import SwiftData
import SwiftUI

struct PrescriberEditView: View {
    @Bindable var prescriber: Prescriber

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $prescriber.name)
                TextField("Practice or clinic", text: $prescriber.practice)
                TextField("Phone", text: $prescriber.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("Email", text: $prescriber.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section {
                Toggle("When a medication is about to expire", isOn: $prescriber.notifyWhenExpiring)
                Toggle("When a medication is running low", isOn: $prescriber.notifyWhenLow)
            } header: {
                Text("Offer to message them")
            } footer: {
                Text("PillBox writes the message for you. You review it and tap send, so nothing goes out without you.")
            }
            Section("Prescribes") {
                if prescriber.medications.isEmpty { Text("No medications linked yet").foregroundStyle(.secondary) }
                ForEach(prescriber.medications) { med in
                    HStack { PillIcon(colorIndex: med.colorIndex, form: med.form, size: 30); Text(med.displayName) }
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
}

/// A ready-to-send refill request to the prescriber, sent by text or email.
struct PrescriberMessageView: View {
    let message: PrescriberMessage
    @Query private var meds: [Medication]
    @AppStorage("patientName") private var patientName = ""
    @Environment(\.openURL) private var openURL
    @State private var text = ""

    private var med: Medication? { meds.first { $0.id == message.medicationID } }

    var body: some View {
        Form {
            if let med, let p = med.prescriber {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "stethoscope")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            Text([p.practice, p.phone, p.email].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Message") {
                    TextEditor(text: $text).frame(minHeight: 180)
                }
                Section {
                    Button { send(sms: p.phone) } label: {
                        Label("Send as text message", systemImage: "message.fill").font(.headline)
                    }
                    .disabled(p.phone.isEmpty)
                    Button { send(email: p.email, med: med) } label: {
                        Label("Send as email", systemImage: "envelope.fill").font(.headline)
                    }
                    .disabled(p.email.isEmpty)
                } footer: {
                    Text("Opens Messages or Mail with this text filled in. You tap send.")
                }
            } else {
                Text("Add a prescriber to this medication first.")
            }
        }
        .navigationTitle("Refill request")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if text.isEmpty { text = draftText() } }
    }

    private func draftText() -> String {
        guard let med, let p = med.prescriber else { return "" }
        let bottle = med.activeBottles.first
        let who = patientName.isEmpty ? "one of your patients" : patientName
        let rx = bottle.map { $0.rxNumber.isEmpty ? "" : " (Rx #\($0.rxNumber))" } ?? ""
        let detail: String
        switch message.reason {
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
        return "Hello \(p.name),\n\nThis is \(who). \(detail.prefix(1).uppercased() + detail.dropFirst()). Could you please send a new prescription\(pharmacy)?\n\nThank you!"
    }

    private func send(sms phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let body = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(digits)&body=\(body)") { openURL(url) }
    }

    private func send(email: String, med: Medication) {
        let subject = "Refill request: \(med.displayName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(email)?subject=\(subject)&body=\(body)") { openURL(url) }
    }
}
