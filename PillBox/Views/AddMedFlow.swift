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
        .background(MediBackground())
    }
}

// MARK: - Take scan page

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
                .foregroundStyle(Medi.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(22)
                .mediCard(cornerRadius: 20)

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
            // A moment more of reading lets the votes settle (and catches the pill count) before moving on.
            Task {
                try? await Task.sleep(for: .milliseconds(1300))
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
            Medi.well
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
                    .foregroundStyle(Medi.ink)
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
                    .foregroundStyle(Medi.ink)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(Capsule().fill(Medi.accent))
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
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mediCard(cornerRadius: 20)
    }

    /// A field turns green once it has been read from the label.
    private func fieldChip(_ field: ScanField, text: String, font: Font = .karla(20), lines: Int = 1) -> some View {
        let done = session.has(field)
        return Text(text)
            .font(font)
            .foregroundStyle(Medi.ink)
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
            recognizedDataTypes: [.text(languages: ["en-US"])],
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
        MedInfoCard(rowSpacing: 24, bottomPadding: 28) {
            // The name has no pencil in the design, but it can still be tapped to fix a misread.
            Button { editing = .name } label: {
                MedNameTitle(name: draft.name.isEmpty ? "med name" : draft.name, faded: draft.name.isEmpty)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double-tap to edit")
        } rows: {
            MedEditRow(text: "Dosage: " + MedText.dosage(draft)) { editing = .dosage }
            MedEditRow(text: "Time: " + MedText.times(for: draft)) { editing = .time }
            MedEditRow(text: "Expires: " + (draft.hasExpiration ? MedText.date(draft.expiration) : "x/x/x")) { editing = .expiration }
            MedEditRow(text: "Provider: " + (draft.prescriberName.isEmpty ? "x" : draft.prescriberName)) { editing = .provider }
        } buttons: {
            MediButton(title: "ADD TO PILLBOX", style: .go, width: 306) { onAdd() }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            MediButton(title: "GO BACK", style: .plain, width: 306) { onBack() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $editing) { field in
            MedFieldEditor(field: field, draft: $draft)
                .presentationDetents(field == .time || field == .dosage ? [.medium, .large] : [.medium])
        }
    }
}

enum MedField: String, Identifiable {
    case name, dosage, time, expiration, provider
    var id: String { rawValue }
}

/// Edits one line of the confirm page or of a saved medication's card.
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
                    timeEditor
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
            guard field == .time, startMode == nil else { return }
            startMode = timeMode.wrappedValue
            // Show the parts of the day the reminders actually fall in.
            if startMode == .parts { timeMode.wrappedValue = .parts }
        }
    }

    // MARK: Time

    /// Parts of the day (no exact time), exact clock times, or the label's own rule.
    enum TimeMode: Hashable { case parts, exact, interval, asNeeded }

    @State private var startMode: TimeMode?

    @ViewBuilder private var timeEditor: some View {
        Section {
            Picker("Remind me", selection: timeMode) {
                Text("Part of day").tag(TimeMode.parts)
                Text("Exact time").tag(TimeMode.exact)
                if startMode == .interval { Text("Every \(draft.intervalHours) h").tag(TimeMode.interval) }
                if startMode == .asNeeded { Text("As needed").tag(TimeMode.asNeeded) }
            }
            .pickerStyle(.segmented)
        }
        switch timeMode.wrappedValue {
        case .parts:
            Section {
                dayPartGrid
            } footer: {
                let parts = DayPart.allCases.filter(draft.dayParts.contains)
                let times = parts.map { "\(MedText.time(DayPartTimes.minutes(for: $0))) (\($0.title.lowercased()))" }
                Text("Reminders ring at \(ListFormatter.localizedString(byJoining: times)). You can change these times in Settings.")
            }
        case .exact:
            Section {
                ForEach(draft.exactTimes.indices, id: \.self) { i in
                    DatePicker("Dose \(i + 1)", selection: $draft.exactTimes[i], displayedComponents: .hourAndMinute)
                }
                .onDelete { if draft.exactTimes.count > 1 { draft.exactTimes.remove(atOffsets: $0) } }
                Button("Add a time") {
                    let last = draft.exactTimes.last.map { ClockText.minutes(of: $0) } ?? 8 * 60
                    draft.exactTimes.append(ClockText.date(Date(), minutes: min(last + 4 * 60, 22 * 60)))
                }
            } footer: {
                Text("MEDI reminds you at each of these times every day.")
            }
        case .interval:
            Section {
                Stepper("Every \(draft.intervalHours) hours", value: $draft.intervalHours, in: 2...24)
            } footer: {
                Text("From the label. MEDI spaces the doses through the day.")
            }
        case .asNeeded:
            Section {
                Text("No reminders. Take it when you need it.")
            }
        }
    }

    private var timeMode: Binding<TimeMode> {
        Binding(get: {
            if draft.useExactTimes { return .exact }
            switch draft.frequency {
            case .daily: return .parts
            case .everyHours: return .interval
            case .asNeeded: return .asNeeded
            }
        }, set: { mode in
            // Start from wherever the reminders fall now.
            let current = draft.previewTimes
            switch mode {
            case .parts:
                let parts = Set(current.map(DayPart.containing))
                draft.dayParts = parts.isEmpty ? [.morning] : parts
                draft.timesPerDay = draft.dayParts.count
                draft.useExactTimes = false
                draft.frequency = .daily
            case .exact:
                if !draft.useExactTimes {
                    draft.exactTimes = (current.isEmpty ? [8 * 60] : current).map { ClockText.date(Date(), minutes: $0) }
                }
                draft.useExactTimes = true
                draft.frequency = .daily
            case .interval:
                draft.useExactTimes = false
                draft.frequency = .everyHours
            case .asNeeded:
                draft.useExactTimes = false
                draft.frequency = .asNeeded
            }
        })
    }

    /// Morning, Afternoon, Evening and Night; pick one or more.
    private var dayPartGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(DayPart.allCases) { part in
                let on = draft.dayParts.contains(part)
                Button {
                    if on {
                        if draft.dayParts.count > 1 { draft.dayParts.remove(part) }
                    } else {
                        draft.dayParts.insert(part)
                    }
                    draft.timesPerDay = draft.dayParts.count
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: part.symbol)
                        Text(part.title).font(.karla(19, .semibold))
                    }
                    .foregroundStyle(Medi.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(on ? Medi.selected : Medi.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(part.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
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
                    .background(shape == current ? Medi.well : .clear, in: RoundedRectangle(cornerRadius: 12))
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
                .fill(Medi.addedFill)
                .overlay(Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Medi.addedTick))
                .frame(width: 63, height: 60)
                .accessibilityHidden(true)
            Text("\(name)\nAdded to\npillbox")
                .font(.karla(48))
                .foregroundStyle(Medi.ink)
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
        .mediCard()
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
    /// Saves changes made with the pencils on a saved medication's card ("pill specific view").
    static func saveEdits(_ draft: MedDraft, to med: Medication, context: ModelContext) {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft.apply(to: med)
        // The date shown on the card is the current bottle's.
        let bottle = med.activeBottles.first
            ?? med.bottles.max { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }
        if draft.hasExpiration { bottle?.expirationDate = draft.expiration }

        let doctor = draft.prescriberName.trimmingCharacters(in: .whitespaces)
        if !doctor.isEmpty, med.prescriber?.name.caseInsensitiveCompare(doctor) != .orderedSame {
            let prescribers = (try? context.fetch(FetchDescriptor<Prescriber>())) ?? []
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
    }
}
