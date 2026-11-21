import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

// The + tab (Figma "Main tabs UPDATED"): "take scan page" → "confirm info page" → "screen for when
// medication has been added and the user is choosing what to do next".

struct AddMedView: View {
    enum Stage: Equatable { case scan, confirm, added(String) }

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var stage: Stage = .scan
    @State private var draft = MedDraft(parsed: ParsedLabel())
    @State private var labelImage: UIImage?

    var body: some View {
        Group {
            switch stage {
            case .scan:
                TakeScanView { draft, image in
                    self.draft = draft
                    labelImage = image
                    withAnimation(.easeInOut(duration: 0.3)) { stage = .confirm }
                }
            case .confirm:
                ConfirmInfoView(draft: $draft,
                                onAdd: {
                                    let med = MedSaver.save(draft, image: labelImage, context: context)
                                    withAnimation(.easeInOut(duration: 0.3)) { stage = .added(med.name) }
                                },
                                onBack: { withAnimation(.easeInOut(duration: 0.3)) { stage = .scan } })
            case .added(let name):
                MedAddedView(name: name,
                             onAddAnother: { withAnimation(.easeInOut(duration: 0.3)) { stage = .scan } },
                             onDone: { router.tab = .pillBox })
            }
        }
        .transition(.opacity)
        .background {
            // The scan page is grey (#F2F2F2); the confirm and "added" pages keep their soft gradient.
            if stage == .scan {
                Medi.screen.ignoresSafeArea()
            } else {
                LinearGradient(colors: [Medi.welcomeTop, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
        }
    }
}

// MARK: - Take scan page

/// What the scan page is looking for, in the order shown under the camera.
enum ScanField: CaseIterable {
    case name, dosage, expiration, time, provider

    /// Parser keys that count as finding this field.
    var keys: [String] {
        switch self {
        case .name: ["name"]
        case .dosage: ["strength", "dose"]
        case .expiration: ["expiration"]
        case .time: ["frequency"]
        case .provider: ["prescriber"]
        }
    }
}

/// Collects label text as the bottle turns in front of the camera. Each new line is placed next to
/// the lines it was seen with, the whole set is parsed again, and a field is kept once it's found.
@MainActor
@Observable
final class ScanSession {
    private(set) var lines: [String] = []
    private(set) var label = ParsedLabel()
    private var seen: Set<String> = []

    func has(_ field: ScanField) -> Bool { field.keys.contains { label.found.contains($0) } }
    var isComplete: Bool { ScanField.allCases.allSatisfy(has) }
    var foundCount: Int { ScanField.allCases.filter(has).count }

    func reset() {
        lines = []
        seen = []
        label = ParsedLabel()
    }

    /// One camera frame's text, top to bottom.
    func add(_ frame: [String]) {
        var changed = false
        var anchor: Int?
        for raw in frame {
            let line = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard line.count >= 2 else { continue }
            let key = line.uppercased()
            if seen.contains(key) {
                anchor = lines.firstIndex { $0.uppercased() == key }
                continue
            }
            seen.insert(key)
            let at = anchor.map { $0 + 1 } ?? lines.count
            lines.insert(line, at: min(at, lines.count))
            anchor = at
            changed = true
        }
        guard changed, lines.count < 300 else { return }
        absorb(LabelParser.parse(lines: lines))
    }

    /// One whole photo's text. Its lines were already added a few at a time; parsing the photo on its own
    /// as well catches anything that reads better without the other photos' lines mixed in.
    func addPhoto(_ photoLines: [String]) {
        add(photoLines)
        absorb(LabelParser.parse(lines: photoLines))
    }

    /// Keeps the first value found for each field, so a blurry later frame can't undo it.
    private func absorb(_ p: ParsedLabel) {
        var l = label
        func newly(_ key: String) -> Bool { p.found.contains(key) && !l.found.contains(key) }
        if newly("name") { l.name = p.name; l.found.insert("name") }
        if newly("strength") { l.strength = p.strength; l.found.insert("strength") }
        if newly("dose") { l.pillsPerDose = p.pillsPerDose; l.form = p.form; l.found.insert("dose") }
        else if !l.found.contains("dose") { l.form = p.form }
        if newly("frequency") {
            l.frequency = p.frequency
            l.timesPerDay = p.timesPerDay
            l.intervalHours = p.intervalHours
            l.minHoursApart = p.minHoursApart
            l.dayParts = p.dayParts
            l.weekdays = p.weekdays
            l.found.insert("frequency")
        }
        if newly("expiration") { l.expiration = p.expiration; l.found.insert("expiration") }
        if newly("prescriber") { l.prescriberName = p.prescriberName; l.found.insert("prescriber") }
        if newly("patient") { l.patientName = p.patientName; l.found.insert("patient") }
        if newly("looks") {
            l.pillShape = p.pillShape
            l.pillColor = p.pillColor
            l.found.insert("looks")
        }
        // The score line and imprint can be on a different side of the bottle from the shape.
        if p.pillScored { l.pillScored = true }
        if l.pillImprint.isEmpty { l.pillImprint = p.pillImprint }
        if l.pillColor.isEmpty { l.pillColor = p.pillColor }
        if newly("rx") { l.rxNumber = p.rxNumber; l.found.insert("rx") }
        if newly("quantity") { l.quantity = p.quantity; l.found.insert("quantity") }
        if newly("refills") { l.refills = p.refills; l.found.insert("refills") }
        if newly("pharmacy") { l.pharmacy = p.pharmacy; l.found.insert("pharmacy") }
        if newly("directions") { l.directions = p.directions; l.found.insert("directions") }
        if l.fillDate == nil { l.fillDate = p.fillDate }
        l.instructions = Array(Set(l.instructions + p.instructions)).sorted()
        l.rawText = p.rawText
        label = l
    }
}

struct TakeScanView: View {
    var onComplete: (MedDraft, UIImage?) -> Void

    @State private var session = ScanSession()
    @State private var cameraState: CameraState = .checking
    @State private var stillImage: UIImage?
    @State private var replay: Task<Void, Never>?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    /// "Photo 2 of 3" while several photos are being read.
    @State private var photoProgress: (index: Int, count: Int)?
    /// The session came from a built-in sample label, so a real photo should start over.
    @State private var fromSample = false
    @State private var showManualButton = false
    @State private var finished = false

    enum CameraState { case checking, live, unavailable(String) }

    var body: some View {
        VStack(spacing: 16) {
            // "Instructions card"
            Text("Place medication bottle in frame. Slowly rotate until MEDI registers all information.")
                .font(.karla(23))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            cameraArea
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 395.5)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .layoutPriority(-1)

            scannedInfoCard
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await startCamera() }
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showManualButton = true }
        }
        .onChange(of: session.isComplete) { _, done in
            guard done, !finished else { return }
            finished = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                finish()
            }
        }
        .onChange(of: session.foundCount) { old, new in
            if new > old { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        // Several photos of the same bottle (different sides) all count toward one medication.
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 10,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                photoItems = []
                if !images.isEmpty { replayScan(of: images, startOver: fromSample) }
            }
        }
        .onDisappear { replay?.cancel() }
    }

    // MARK: Camera area

    @ViewBuilder private var cameraArea: some View {
        ZStack {
            Color(hex: 0xD9D9D9)
            if let stillImage {
                PanningLabel(image: stillImage)
                    .id(ObjectIdentifier(stillImage))
                    .overlay { if isReading { ScanSweep() } }
            } else {
                switch cameraState {
                case .checking:
                    ProgressView()
                case .live:
                    LiveTextScanner { lines in session.add(lines) }
                case .unavailable(let reason):
                    VStack(spacing: 14) {
                        Text("(camera area)").font(.karla(40))
                        Text(reason)
                            .font(.karla(18))
                            .foregroundStyle(Medi.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        sourceMenu(label: "Try a sample label")
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if stillImage != nil || isLive { sourceMenu(label: nil).padding(12) }
        }
        .overlay(alignment: .topLeading) {
            if let photoProgress, photoProgress.count > 1 {
                Text("Photo \(photoProgress.index) of \(photoProgress.count)")
                    .font(.karla(17, .bold))
                    .foregroundStyle(Medi.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showManualButton || session.foundCount > 0, !session.isComplete {
                VStack(spacing: 8) {
                    // Another side of the bottle can fill in what this photo didn't show.
                    if stillImage != nil, !isReading, !fromSample {
                        overlayButton("Add another photo", symbol: "plus") { showPhotos = true }
                    }
                    overlayButton("Fill in the rest myself") { finish() }
                }
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
    }

    private func overlayButton(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.karla(18, .medium))
            }
            .foregroundStyle(Medi.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A photo is still being read.
    private var isReading: Bool { photoProgress != nil }

    private var isLive: Bool { if case .live = cameraState { true } else { false } }

    /// Photos and the sample labels, for the simulator (no camera) and for trying the flow without a bottle.
    private func sourceMenu(label: String?) -> some View {
        Menu {
            Button { showPhotos = true } label: {
                Label(session.foundCount > 0 && !fromSample ? "Add more photos of this bottle" : "Use photos of a label",
                      systemImage: "photo.on.rectangle")
            }
            if stillImage != nil, DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                // Back to the live camera, keeping everything read so far.
                Button {
                    replay?.cancel()
                    photoProgress = nil
                    stillImage = nil
                    cameraState = .live
                } label: { Label("Use the camera", systemImage: "camera") }
            }
            Section("Sample labels") {
                ForEach(DemoData.sampleLabels, id: \.asset) { sample in
                    Button(sample.title) {
                        if let img = UIImage(named: sample.asset) { replayScan(of: [img], startOver: true, sample: true) }
                    }
                }
            }
        } label: {
            if let label {
                Text(label)
                    .font(.karla(20, .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(Capsule().fill(Medi.goFill))
                    .overlay(Capsule().strokeBorder(Medi.goStroke, lineWidth: 3))
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Medi.ink)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("Scan a photo or a sample label")
            }
        }
    }

    // MARK: "Scanned info card" under the camera

    private var scannedInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldChip(.name, text: session.has(.name) ? session.label.name : "med name", font: .karla(36))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldChip(.dosage, text: "Dosage: " + (session.has(.dosage) ? MedText.dosage(session.label) : "x"))
                    fieldChip(.time, text: "Time: " + (session.has(.time) ? MedText.times(for: session.label) : "x"), lines: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    fieldChip(.expiration, text: "Expiration: " + (session.has(.expiration) ? MedText.date(session.label.expiration) : "x/x/x"))
                    fieldChip(.provider, text: "Provider: " + (session.has(.provider) ? session.label.prescriberName : "x"), lines: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A field turns green once it has been read from the label.
    private func fieldChip(_ field: ScanField, text: String, font: Font = .karla(20), lines: Int = 1) -> some View {
        let done = session.has(field)
        return Text(text)
            .font(font)
            .foregroundStyle(.black)
            .lineLimit(lines)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(done ? Medi.goFill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(done ? Medi.goStroke : .clear, lineWidth: 2))
            .padding(.horizontal, -6)
            .animation(.easeInOut(duration: 0.35), value: done)
            .accessibilityValue(done ? "Scanned" : "Not scanned yet")
    }

    // MARK: Actions

    private func startCamera() async {
        if let asset = AppRouter.shared.scanDemoAsset, let img = UIImage(named: asset) {
            AppRouter.shared.scanDemoAsset = nil
            replayScan(of: [img], startOver: true, sample: true)
        }
        guard DataScannerViewController.isSupported else {
            cameraState = .unavailable("Live scanning needs an iPhone camera. Try a sample label instead.")
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        cameraState = DataScannerViewController.isAvailable
            ? .live
            : .unavailable("Turn on camera access for MEDI in Settings, or try a sample label.")
    }

    /// Reads still photos one after another and feeds each one's lines in a few at a time, as if the
    /// bottle were turning. Everything read so far is kept unless `startOver` is set, so photos of
    /// different sides of one bottle add up to one medication.
    private func replayScan(of images: [UIImage], startOver: Bool, sample: Bool = false) {
        replay?.cancel()
        if startOver { session.reset() }
        fromSample = sample
        finished = false
        stillImage = images.first
        replay = Task {
            let pause: Duration = images.count > 1 ? .milliseconds(180) : .milliseconds(320)
            for (n, image) in images.enumerated() {
                withAnimation {
                    stillImage = image
                    photoProgress = (n + 1, images.count)
                }
                guard let lines = try? await LabelReader.readLines(from: image), !Task.isCancelled else { break }
                for i in lines.indices {
                    try? await Task.sleep(for: pause)
                    if Task.isCancelled { return }
                    withAnimation { session.add(Array(lines[...i])) }
                }
                withAnimation { session.addPhoto(lines) }
                if session.isComplete { break }
            }
            if Task.isCancelled { return }
            withAnimation {
                photoProgress = nil
                if !session.isComplete { showManualButton = true }
            }
        }
    }

    private func finish() {
        replay?.cancel()
        finished = true
        onComplete(MedDraft(parsed: session.label), stillImage)
    }
}

/// A label photo that slides past slowly, like a bottle turning in front of the camera.
private struct PanningLabel: View {
    let image: UIImage
    @State private var atEnd = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = max(geo.size.width, height * image.size.width / max(image.size.height, 1))
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .offset(x: atEnd ? geo.size.width - width : 0)
        }
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 5)) { atEnd = true }
        }
    }
}

/// A bright band that sweeps up and down over a label while it's being read.
private struct ScanSweep: View {
    @State private var down = false
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Medi.goStroke.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
                .offset(y: down ? geo.size.height - 60 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { down = true }
        }
    }
}

/// The live camera, reading text as it moves (VisionKit). Needs a real iPhone.
struct LiveTextScanner: UIViewControllerRepresentable {
    var onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onLines = onLines
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLines: onLines) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onLines: ([String]) -> Void
        init(onLines: @escaping ([String]) -> Void) { self.onLines = onLines }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            send(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            send(allItems)
        }

        private func send(_ items: [RecognizedItem]) {
            let texts: [(y: CGFloat, x: CGFloat, text: String)] = items.compactMap {
                if case .text(let t) = $0 { return (t.bounds.topLeft.y, t.bounds.topLeft.x, t.transcript) }
                return nil
            }
            let ordered = texts.sorted { abs($0.y - $1.y) > 10 ? $0.y < $1.y : $0.x < $1.x }
            onLines(ordered.flatMap { $0.text.components(separatedBy: .newlines) })
        }
    }
}

// MARK: - Confirm info page

struct ConfirmInfoView: View {
    @Binding var draft: MedDraft
    var onAdd: () -> Void
    var onBack: () -> Void
    @State private var editing: MedField?

    var body: some View {
        VStack(spacing: 16) {
            // The name has no pencil in the design, but it can still be tapped to fix a misread.
            Button { editing = .name } label: {
                MedNameCard(name: draft.name.isEmpty ? "med name" : draft.name, faded: draft.name.isEmpty)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double-tap to edit")

            MedDetailsCard(rowSpacing: 24, verticalPadding: 19) {
                row(.dosage, "Dosage: " + MedText.dosage(draft))
                row(.time, "Time: " + MedText.times(draft.previewTimes))
                row(.expiration, "Expires: " + (draft.hasExpiration ? MedText.date(draft.expiration) : "x/x/x"))
                row(.provider, "Provider: " + (draft.prescriberName.isEmpty ? "x" : draft.prescriberName))
            }

            VStack(spacing: 23) {
                MediButton(title: "ADD TO PILLBOX", style: .go, width: 274) { onAdd() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                MediButton(title: "GO BACK", style: .plain, width: 266) { onBack() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $editing) { field in
            MedFieldEditor(field: field, draft: $draft)
                .presentationDetents(field == .time || field == .dosage ? [.medium, .large] : [.medium])
        }
    }

    /// A detail with a pencil; tapping anywhere on the line edits it.
    private func row(_ field: MedField, _ text: String) -> some View {
        Button { editing = field } label: {
            HStack(spacing: 8) {
                MedDetailLine(text: text)
                Image("icon-edit")
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Double-tap to edit")
    }
}

enum MedField: String, Identifiable {
    case name, dosage, time, expiration, provider
    var id: String { rawValue }
}

/// Edits one line of the confirm page.
struct MedFieldEditor: View {
    let field: MedField
    @Binding var draft: MedDraft
    @Environment(\.dismiss) private var dismiss
    private let forms = ["tablet", "capsule", "softgel", "pill", "mL", "puff", "drop", "patch"]

    var body: some View {
        NavigationStack {
            Form {
                switch field {
                case .name:
                    TextField("Medication name", text: $draft.name).textInputAutocapitalization(.words)
                case .dosage:
                    TextField("Strength, e.g. 10 mg", text: $draft.strength)
                    Stepper("\(draft.pillsPerDose) per dose", value: $draft.pillsPerDose, in: 1...10)
                    Picker("Form", selection: $draft.form) {
                        ForEach(forms.contains(draft.form) ? forms : forms + [draft.form], id: \.self) { Text($0) }
                    }
                    Section {
                        pillShapeGrid
                        Toggle("Score line across the middle", isOn: $draft.pillScored)
                        TextField("Letters or numbers on it (optional)", text: $draft.pillImprint)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("What the pill looks like")
                    } footer: {
                        Text("This drawing shows on the pill's compartment in your pill box.")
                    }
                case .time:
                    Section {
                        ForEach(draft.exactTimes.indices, id: \.self) { i in
                            DatePicker("Dose \(i + 1)", selection: $draft.exactTimes[i], displayedComponents: .hourAndMinute)
                        }
                        .onDelete { draft.exactTimes.remove(atOffsets: $0) }
                        Button("Add a time") {
                            let last = draft.exactTimes.last.map { ClockText.minutes(of: $0) } ?? 8 * 60
                            draft.exactTimes.append(ClockText.date(Date(), minutes: min(last + 4 * 60, 22 * 60)))
                        }
                    } footer: {
                        Text("MEDI reminds you at each of these times every day.")
                    }
                case .expiration:
                    DatePicker("Expires", selection: Binding(get: { draft.expiration }, set: { draft.expiration = $0; draft.hasExpiration = true }),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                case .provider:
                    TextField("Doctor's name", text: $draft.prescriberName).textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            // Switch to exact times the first time the schedule is edited, starting from what was read.
            if field == .time, !draft.useExactTimes {
                draft.exactTimes = draft.previewTimes.map { ClockText.date(Date(), minutes: $0) }
                if draft.exactTimes.isEmpty { draft.exactTimes = [ClockText.date(Date(), minutes: 8 * 60)] }
                draft.frequency = .daily
                draft.useExactTimes = true
            }
        }
    }

    /// Every shape as a small line drawing; the chosen one is outlined.
    private var pillShapeGrid: some View {
        let current = PillShape.resolve(shape: draft.pillShape, form: draft.form)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(PillShape.pickable) { shape in
                Button { draft.pillShape = shape.rawValue } label: {
                    VStack(spacing: 2) {
                        PillOutline(shape: shape, scored: draft.pillScored && shape == current,
                                    imprint: shape == current ? draft.pillImprint.uppercased() : "", size: 54)
                        Text(shape.title).font(.karla(13)).foregroundStyle(Medi.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(shape == current ? Medi.compartment : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(shape == current ? Medi.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shape.title)
                .accessibilityAddTraits(shape == current ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch field {
        case .name: "Name"
        case .dosage: "Dosage"
        case .time: "Time"
        case .expiration: "Expiration date"
        case .provider: "Provider"
        }
    }
}

// MARK: - Added page

struct MedAddedView: View {
    let name: String
    var onAddAnother: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Medi.goFill)
                .overlay(Circle().strokeBorder(Medi.goStroke, lineWidth: 4))
                .overlay(Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Color(hex: 0x5BA832)))
                .frame(width: 63, height: 60)
                .accessibilityHidden(true)
            Text("\(name)\nAdded to\npillbox")
                .font(.karla(48))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineSpacing(-4)
                .minimumScaleFactor(0.6)
                .frame(width: 320)
                .padding(.top, 2)
            VStack(spacing: 19) {
                MediButton(title: "Add another", style: .plain, width: 266, action: onAddAnother)
                MediButton(title: "DONE", style: .plain, width: 266, action: onDone)
            }
            .padding(.top, 40)
        }
        .padding(.top, 29)
        .padding(.bottom, 50)
        .frame(width: 330)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Saving

@MainActor
enum MedSaver {
    /// Saves a new bottle. A bottle of a medication that's already in the pill box joins it (same schedule).
    @discardableResult
    static func save(_ draft: MedDraft, image: UIImage?, context: ModelContext) -> Medication {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let prescribers = (try? context.fetch(FetchDescriptor<Prescriber>())) ?? []
        let squash = { (s: String) in s.replacingOccurrences(of: " ", with: "").lowercased() }
        let name = draft.name.trimmingCharacters(in: .whitespaces)

        let med: Medication
        if let match = meds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && squash($0.strength) == squash(draft.strength) }) {
            med = match
            // A newer label can say what the pill looks like when the first one didn't.
            if !draft.pillShape.isEmpty { draft.applyLooks(to: med) }
        } else {
            med = Medication(name: name, strength: draft.strength)
            med.colorIndex = meds.count
            draft.apply(to: med)
            context.insert(med)
        }

        let bottle = Bottle()
        bottle.expirationDate = draft.hasExpiration ? draft.expiration : nil
        bottle.quantity = draft.quantity
        bottle.pillsRemaining = draft.quantity
        bottle.refills = draft.refills
        bottle.rxNumber = draft.rxNumber
        bottle.pharmacy = draft.pharmacy
        bottle.fillDate = draft.fillDate
        bottle.labelText = draft.labelText
        bottle.labelImage = image?.jpegData(compressionQuality: 0.6)
        bottle.medication = med
        context.insert(bottle)

        let doctor = draft.prescriberName.trimmingCharacters(in: .whitespaces)
        if med.prescriber == nil, !doctor.isEmpty {
            if let existing = prescribers.first(where: { $0.name.caseInsensitiveCompare(doctor) == .orderedSame }) {
                med.prescriber = existing
            } else {
                let p = Prescriber(name: doctor)
                context.insert(p)
                med.prescriber = p
            }
        }
        // The label says whose bottle it is: fill in the name on the Info tab if it's still blank.
        // (A name the person typed themselves is never replaced.)
        let patient = draft.patientName.trimmingCharacters(in: .whitespaces)
        let saved = UserDefaults.standard.string(forKey: "patientName")?.trimmingCharacters(in: .whitespaces) ?? ""
        if !patient.isEmpty, saved.isEmpty {
            UserDefaults.standard.set(patient, forKey: "patientName")
        }

        try? context.save()
        Task { await ReminderService.shared.rescheduleAll(context: context) }
        return med
    }
}
