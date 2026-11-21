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
        .background(LinearGradient(colors: [Medi.welcomeTop, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
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
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showManualButton = false
    @State private var finished = false

    enum CameraState { case checking, live, unavailable(String) }

    var body: some View {
        VStack(spacing: 0) {
            Text("Place medication bottle in frame. Slowly rotate until MEDI registers all information.")
                .font(.karla(24))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .frame(width: 345)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            cameraArea
                .frame(width: 322)
                .frame(maxHeight: 494)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.top, 16)
                .layoutPriority(-1)

            fieldList
                .frame(width: 322, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 10)
        }
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
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    replayScan(of: image)
                }
                photoItem = nil
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
                    .overlay { ScanSweep() }
            } else {
                switch cameraState {
                case .checking:
                    ProgressView()
                case .live:
                    LiveTextScanner { lines in session.add(lines) }
                case .unavailable(let reason):
                    VStack(spacing: 14) {
                        Text("(camera area)").font(.karla(32))
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
        .overlay(alignment: .bottom) {
            if showManualButton || session.foundCount > 0, !session.isComplete {
                Button("Fill in the rest myself") { finish() }
                    .font(.karla(18, .medium))
                    .foregroundStyle(Medi.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }

    private var isLive: Bool { if case .live = cameraState { true } else { false } }

    /// Photos and the sample labels, for the simulator (no camera) and for trying the flow without a bottle.
    private func sourceMenu(label: String?) -> some View {
        Menu {
            Button { showPhotos = true } label: { Label("Use a photo of a label", systemImage: "photo.on.rectangle") }
            Section("Sample labels") {
                ForEach(DemoData.sampleLabels, id: \.asset) { sample in
                    Button(sample.title) {
                        if let img = UIImage(named: sample.asset) { replayScan(of: img) }
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

    // MARK: Fields under the camera

    private var fieldList: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldChip(.name, text: session.has(.name) ? session.label.name : "med name", font: .karla(36))
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldChip(.dosage, text: "Dosage: " + (session.has(.dosage) ? MedText.dosage(session.label) : "x"))
                    fieldChip(.time, text: "Time: " + (session.has(.time) ? MedText.times(for: session.label) : "x"))
                }
                .frame(width: 138, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    fieldChip(.expiration, text: "Expiration: " + (session.has(.expiration) ? MedText.date(session.label.expiration) : "x/x/x"))
                    fieldChip(.provider, text: "Provider: " + (session.has(.provider) ? session.label.prescriberName : "x"), lines: 2)
                }
            }
        }
    }

    /// A field turns green once it has been read from the label.
    private func fieldChip(_ field: ScanField, text: String, font: Font = .karla(24), lines: Int = 1) -> some View {
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
            replayScan(of: img)
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

    /// Reads a still photo, then feeds its lines in a few at a time, as if the bottle were turning.
    private func replayScan(of image: UIImage) {
        replay?.cancel()
        session.reset()
        finished = false
        stillImage = image
        replay = Task {
            guard let lines = try? await LabelReader.readLines(from: image), !Task.isCancelled else { return }
            for i in lines.indices {
                try? await Task.sleep(for: .milliseconds(320))
                if Task.isCancelled { return }
                withAnimation { session.add(Array(lines[...i])) }
            }
            if !session.isComplete { withAnimation { showManualButton = true } }
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
            VStack(alignment: .leading, spacing: 0) {
                row(.name, draft.name.isEmpty ? "med name" : draft.name, font: .karla(48), faded: draft.name.isEmpty)
                    .padding(.bottom, 14)
                row(.dosage, "Dosage: " + MedText.dosage(draft))
                row(.time, "Time: " + MedText.times(draft.previewTimes))
                row(.expiration, "Expires: " + (draft.hasExpiration ? MedText.date(draft.expiration) : "x/x/x"))
                row(.provider, "Provider: " + (draft.prescriberName.isEmpty ? "x" : draft.prescriberName))
                VStack(spacing: 23) {
                    MediButton(title: "ADD TO PILLBOX", style: .go, width: 274) { onAdd() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    MediButton(title: "GO BACK", style: .plain, width: 266) { onBack() }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 19)
            }
            .padding(.top, 31)
            .padding(.bottom, 40)
            .padding(.horizontal, 24)
            .frame(width: 330)
            .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            Text("Tap any detail to change it.")
                .font(.karla(18))
                .foregroundStyle(Medi.inkSecondary)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $editing) { field in
            MedFieldEditor(field: field, draft: $draft)
                .presentationDetents(field == .time ? [.medium, .large] : [.medium])
        }
    }

    private func row(_ field: MedField, _ text: String, font: Font = .karla(40), faded: Bool = false) -> some View {
        Button { editing = field } label: {
            Text(text)
                .font(font)
                .foregroundStyle(faded ? Medi.inkSecondary : .black)
                .lineLimit(field == .name ? 2 : 1)
                .minimumScaleFactor(0.45)
                .padding(.leading, 13)
                .frame(maxWidth: .infinity, minHeight: field == .name ? 56 : 46, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        try? context.save()
        Task { await ReminderService.shared.rescheduleAll(context: context) }
        return med
    }
}
