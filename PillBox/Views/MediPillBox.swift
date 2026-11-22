import SwiftData
import SwiftUI

/// "pillbox base": one compartment per medication, two across. A medication whose bottle
/// expires within one week turns orange, and red only once it has actually expired.
struct MediPillBoxView: View {
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @State private var selected: Medication?

    private var slotCount: Int { max(8, meds.count + meds.count % 2) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.fixed(155), spacing: 20), GridItem(.fixed(155))], spacing: 17) {
                ForEach(0..<slotCount, id: \.self) { i in
                    if i < meds.count {
                        let med = meds[i]
                        Button { selected = med } label: { compartment(med) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(med.displayName)
                            .accessibilityValue([med.pillDescription, MedText.expiryWarning(med)?.spoken ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: ". "))
                    } else {
                        Color.clear
                            .frame(width: 155, height: 155)
                            .mediCard()
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .background(MediBackground())
        .fullScreenCover(item: $selected) { med in
            MedDetailCard(med: med)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private func compartment(_ med: Medication) -> some View {
        let warning = MedText.expiryWarning(med)
        return VStack(spacing: 0) {
            // A line drawing of the pill itself: its shape, score line and imprint from the label.
            PillOutline(med: med, size: 100, fill: Medi.ink.opacity(warning == nil ? 0.12 : 0.2))
                .padding(.top, 10)
            Text(med.name)
                .font(.karla(24))
                .foregroundStyle(Medi.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
            Spacer(minLength: 0)
        }
        .frame(width: 155, height: 155)
        .background {
            // Glass, solid orange when a bottle expires within a week, and solid red once it has expired.
            if let warning { RoundedRectangle(cornerRadius: 32, style: .continuous).fill(warning.fill) }
        }
        .mediCard()
    }
}

/// "pill specific view": the medication's details in one glass card over the blurred pill box.
/// Each detail has a pencil and can be changed here.
struct MedDetailCard: View {
    let med: Medication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("patientName") private var patientName = ""
    @State private var confirmDelete = false
    @State private var contact: RefillRequest?
    @State private var editing: MedField?
    @State private var draft = MedDraft(parsed: ParsedLabel())

    private var expiry: Date? { med.activeBottles.first?.expirationDate ?? med.bottles.compactMap(\.expirationDate).max() }

    var body: some View {
        ZStack {
            Color.white.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            MedInfoCard(rowSpacing: 22, bottomPadding: 31) {
                Button { edit(.name) } label: { MedNameTitle(name: med.name) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to edit")
            } rows: {
                MedEditRow(text: "Dosage: " + MedText.dosage(med)) { edit(.dosage) }
                MedEditRow(text: "Time: " + MedText.times(for: med)) { edit(.time) }
                MedEditRow(text: "Expires: " + MedText.date(expiry),
                           color: MedText.expiryWarning(med)?.text ?? Medi.ink) { edit(.expiration) }
                MedEditRow(text: "Provider: " + (med.prescriber?.name ?? "x")) { edit(.provider) }
            } buttons: {
                MediButton(title: "DELETE MED", style: .stop) { confirmDelete = true }
                MediButton(title: "GO BACK", style: .plain) { dismiss() }
                // Text or Email, with the refill request written and the To field left blank.
                MediButton(title: "CONTACT PROVIDER", style: .plain, fontSize: 20) {
                    contact = PrescriberMessage.suggested(for: med).request(for: med, patientName: patientName)
                }
            }
            .padding(.bottom, 36)
        }
        .sheet(item: $editing, onDismiss: { MedSaver.saveEdits(draft, to: med, context: context) }) { field in
            MedFieldEditor(field: field, draft: $draft)
                .presentationDetents(field == .time || field == .dosage ? [.medium, .large] : [.medium])
        }
        .confirmationDialog("Delete \(med.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This removes it from your pill box, stops its reminders and lists it under Past medications on the Info tab.")
        }
        .refillComposer($contact)
    }

    /// Opens the same editor the confirm page uses, filled in from the saved medication.
    private func edit(_ field: MedField) {
        var d = MedDraft(med: med)
        d.hasExpiration = expiry != nil
        if let expiry { d.expiration = expiry }
        d.prescriberName = med.prescriber?.name ?? ""
        draft = d
        editing = field
    }

    private func delete() {
        HealthProfile.recordStopped(med)
        context.delete(med)
        try? context.save()
        Task { await ReminderService.shared.rescheduleAll(context: context) }
        dismiss()
    }
}

extension PrescriberMessage: Identifiable {
    var id: String { "\(medicationID)-\(reason.rawValue)" }
}

/// How a pill box compartment warns about its bottle's date. Orange means "expires soon, still fine to
/// take"; red is kept for a bottle that has actually expired, so nobody throws out good medicine early.
enum ExpiryWarning {
    case soon, expired

    var fill: Color { self == .expired ? Medi.danger : Medi.warning }
    var text: Color { self == .expired ? Medi.expiringText : Medi.warningText }
    var spoken: String { self == .expired ? "Expired" : "Expiring soon" }
}

extension MedText {
    /// Expires within one week (including today): orange. Past the date: red. Otherwise nil.
    static func expiryWarning(_ med: Medication, now: Date = Date()) -> ExpiryWarning? {
        guard let date = med.activeBottles.first?.expirationDate else { return nil }
        switch ExpiryLevel.level(for: date, now: now) {
        case .expired: return .expired
        case .week, .today: return .soon
        default: return nil
        }
    }
}
