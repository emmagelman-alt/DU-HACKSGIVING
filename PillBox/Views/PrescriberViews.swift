import MessageUI
import SwiftData
import SwiftUI

struct PrescriberEditView: View {
    @Bindable var prescriber: Prescriber

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Name", text: $prescriber.name)
                TextField("Practice or clinic", text: $prescriber.practice)
            }
            Section {
                Toggle("When a medication is about to expire", isOn: $prescriber.notifyWhenExpiring)
                Toggle("When a medication is running low", isOn: $prescriber.notifyWhenLow)
            } header: {
                Text("Offer to message them")
            } footer: {
                Text("MEDI writes the message. You choose Text or Email, add who it goes to, and tap send.")
            }
            Section("Prescribes") {
                if prescriber.medications.isEmpty { Text("No medications linked yet").foregroundStyle(.secondary) }
                ForEach(prescriber.medications) { med in
                    HStack { PillOutline(med: med, size: 36); Text(med.displayName) }
                }
            }
        }
        .navigationTitle(prescriber.name.isEmpty ? "Prescriber" : prescriber.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrescriberMessage: Hashable {
    enum Reason: String, Hashable { case expiring, expired, runningLow, refill }
    var medicationID: UUID
    var reason: Reason

    /// The refill request MEDI writes for this medication.
    func request(for med: Medication, patientName: String) -> RefillRequest {
        RefillRequest(subject: "Refill request: \(med.displayName)",
                      body: Self.body(for: med, reason: reason, patientName: patientName))
    }

    static func body(for med: Medication, reason: Reason, patientName: String) -> String {
        let bottle = med.activeBottles.first
        let who = patientName.trimmingCharacters(in: .whitespaces).isEmpty ? "one of your patients" : patientName
        let rx = bottle.map { $0.rxNumber.isEmpty ? "" : " (Rx #\($0.rxNumber))" } ?? ""
        let detail: String
        switch reason {
        case .expired:
            detail = "my \(med.displayName)\(rx) expired on \(bottle?.expirationDate?.formatted(date: .long, time: .omitted) ?? "a recent date")"
        case .expiring:
            detail = "my \(med.displayName)\(rx) expires on \(bottle?.expirationDate?.formatted(date: .long, time: .omitted) ?? "soon")"
        case .runningLow:
            detail = "I only have \(med.pillsRemaining) pills of \(med.displayName)\(rx) left (about \(Scheduler.daysLeft(med) ?? 0) days)"
        case .refill:
            detail = "I'd like a refill of \(med.displayName)\(rx)"
        }
        let pharmacy = bottle?.pharmacy.isEmpty == false ? " to \(bottle!.pharmacy)" : ""
        let hello = med.prescriber.map { "Hello \($0.name)," } ?? "Hello,"
        return "\(hello)\n\nThis is \(who). \(detail.prefix(1).uppercased() + detail.dropFirst()). Could you please send a new prescription\(pharmacy)?\n\nThank you!"
    }
}

/// A ready-to-send refill request. It goes out with the To field left blank: the person types
/// the provider's number or email themselves, so MEDI never needs to store them.
struct RefillRequest: Identifiable {
    let id = UUID()
    var subject: String
    var body: String
}

extension View {
    /// "Contact provider": asks Text or Email, then opens Apple's message or email screen
    /// with the request written in and no recipient.
    func refillComposer(_ request: Binding<RefillRequest?>) -> some View {
        modifier(RefillComposerModifier(request: request))
    }
}

private struct RefillComposerModifier: ViewModifier {
    @Binding var request: RefillRequest?
    @Environment(\.openURL) private var openURL
    @State private var composing: RefillComposer.Job?
    @State private var unavailable: RefillComposer.Job?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Contact provider", isPresented: asking, titleVisibility: .visible, presenting: request) { r in
                Button("Text") { send(r, by: .text) }
                Button("Email") { send(r, by: .email) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("MEDI writes the refill request. You add who it goes to, then tap send.")
            }
            .sheet(item: $composing) { job in
                RefillComposer(job: job) { composing = nil }
                    .ignoresSafeArea()
            }
            .alert(unavailable?.channel == .email ? "Email isn't set up on this iPhone" : "This iPhone can't send texts",
                   isPresented: Binding(get: { unavailable != nil }, set: { if !$0 { unavailable = nil } }),
                   presenting: unavailable) { job in
                Button("Copy message") { UIPasteboard.general.string = job.request.body }
                Button("OK", role: .cancel) {}
            } message: { _ in
                Text("Copy the message and paste it into any app to send it.")
            }
    }

    private var asking: Binding<Bool> {
        Binding(get: { request != nil }, set: { if !$0 { request = nil } })
    }

    private func send(_ r: RefillRequest, by channel: RefillComposer.Channel) {
        let job = RefillComposer.Job(channel: channel, request: r)
        // Apple's own compose screen when the phone can send; otherwise Messages or Mail itself.
        if job.canCompose {
            composing = job
        } else if let url = job.appURL {
            openURL(url) { opened in if !opened { unavailable = job } }
        } else {
            unavailable = job
        }
    }
}

/// Apple's message or email compose screen, with the body (and email subject) filled in and nobody in To.
struct RefillComposer: UIViewControllerRepresentable {
    enum Channel { case text, email }

    struct Job: Identifiable {
        let id = UUID()
        var channel: Channel
        var request: RefillRequest

        var canCompose: Bool {
            channel == .text ? MFMessageComposeViewController.canSendText() : MFMailComposeViewController.canSendMail()
        }

        /// Messages or Mail opened with the text filled in and no recipient.
        var appURL: URL? {
            let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: safe) ?? "" }
            switch channel {
            case .text: return URL(string: "sms:&body=\(encode(request.body))")
            case .email: return URL(string: "mailto:?subject=\(encode(request.subject))&body=\(encode(request.body))")
            }
        }
    }

    let job: Job
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIViewController {
        switch job.channel {
        case .text:
            let vc = MFMessageComposeViewController()
            vc.recipients = []
            vc.body = job.request.body
            vc.messageComposeDelegate = context.coordinator
            return vc
        case .email:
            let vc = MFMailComposeViewController()
            vc.setToRecipients([])
            vc.setSubject(job.request.subject)
            vc.setMessageBody(job.request.body, isHTML: false)
            vc.mailComposeDelegate = context.coordinator
            return vc
        }
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}

/// A ready-to-send refill request, shown so it can be changed before it goes out by text or email.
struct PrescriberMessageView: View {
    let message: PrescriberMessage
    @Query private var meds: [Medication]
    @AppStorage("patientName") private var patientName = ""
    @State private var text = ""
    @State private var sending: RefillRequest?

    private var med: Medication? { meds.first { $0.id == message.medicationID } }

    var body: some View {
        Form {
            if let med {
                if let p = med.prescriber {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "stethoscope")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 44, height: 44)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading) {
                                Text(p.name).font(.headline)
                                if !p.practice.isEmpty {
                                    Text(p.practice).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Message") {
                    TextEditor(text: $text).frame(minHeight: 180)
                }
                Section {
                    Button {
                        var r = message.request(for: med, patientName: patientName)
                        r.body = text
                        sending = r
                    } label: {
                        Label("Send by text or email", systemImage: "paperplane.fill").font(.headline)
                    }
                } footer: {
                    Text("Opens a text or email with this message filled in. You add who it goes to and tap send.")
                }
            } else {
                Text("This medication was deleted.")
            }
        }
        .navigationTitle("Refill request")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if text.isEmpty, let med { text = PrescriberMessage.body(for: med, reason: message.reason, patientName: patientName) }
        }
        .refillComposer($sending)
    }
}
