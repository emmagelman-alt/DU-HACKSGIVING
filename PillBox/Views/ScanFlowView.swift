import PhotosUI
import SwiftData
import SwiftUI

/// Add a medication: photo of the label → read it on the phone → review and save.
struct ScanFlowView: View {
    enum Step { case choose, reading(UIImage), review(MedDraft, UIImage?) }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var error: String?

    init(startAt step: Step = .choose) { _step = State(initialValue: step) }

    private var isReviewing: Bool { if case .review = step { true } else { false } }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: chooser
                case .reading(let image): ReadingView(image: image)
                case .review(let draft, let image): MedicationFormView(draft: draft, mode: .new(image), onDone: { dismiss() }, embedded: true)
                }
            }
            .toolbar {
                if !isReviewing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await read(image)
                }
            }
        }
        .task {
            if let asset = AppRouter.shared.scanDemoAsset, let img = UIImage(named: asset) {
                AppRouter.shared.scanDemoAsset = nil
                await read(img)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await read(image) } }.ignoresSafeArea()
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(height: 190)
                    VStack(spacing: 10) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Color.accentColor)
                        Text("Name · Dose · When to take · Expiration")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 8) {
                    Text("Scan a medication label").font(.title.weight(.bold))
                    Text("Take a photo of the pharmacy label. Every bottle needs its own photo, even for the same medicine, so each expiration date is tracked.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    Button { showCamera = true } label: {
                        Label("Take a photo", systemImage: "camera.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Upload from Photos", systemImage: "photo.on.rectangle").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        ForEach(DemoData.sampleLabels, id: \.asset) { sample in
                            Button(sample.title) {
                                if let img = UIImage(named: sample.asset) { Task { await read(img) } }
                            }
                        }
                    } label: {
                        Label("Try a sample label", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                    }
                    Button("Enter details by hand") { step = .review(MedDraft(parsed: ParsedLabel()), nil) }
                        .font(.subheadline)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 10) {
                    tip("sun.max", "Use bright, even light and avoid glare.")
                    tip("rotate.3d", "Turn the bottle so the whole label faces the camera.")
                    tip("lock.shield", "Labels are read on your phone. Photos are never uploaded.")
                }
                .card()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Add medication")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
    }

    @MainActor
    private func read(_ image: UIImage) async {
        step = .reading(image)
        do {
            let lines = try await LabelReader.readLines(from: image)
            try? await Task.sleep(for: .milliseconds(600))
            let parsed = LabelParser.parse(lines: lines)
            step = .review(MedDraft(parsed: parsed), image)
        } catch {
            self.error = "Couldn't read that photo. Try again or enter the details by hand."
            step = .choose
        }
    }
}

struct ReadingView: View {
    let image: UIImage
    @State private var scan = false

    var body: some View {
        VStack(spacing: 24) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: scan ? .bottom : .top) {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Color.accentColor.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: 40)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxHeight: 360)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: scan)
            ProgressView()
            Text("Reading label…").font(.title3.weight(.semibold))
            Text("Finding the name, dose, schedule and expiration date").foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .onAppear { scan = true }
        .navigationTitle("Reading label")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
