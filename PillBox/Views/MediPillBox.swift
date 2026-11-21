import SwiftData
import SwiftUI

/// "pillbox base": one compartment per medication, two across. A medication whose bottle
/// expires within one week (or has expired) turns red ("pillbox with expiring meds").
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
                            .accessibilityValue(MedText.isExpiringSoon(med) ? "Expiring soon" : "")
                    } else {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Medi.compartment.opacity(0.55))
                            .frame(width: 155, height: 155)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .background(LinearGradient(colors: [Medi.welcomeTop, .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .fullScreenCover(item: $selected) { med in
            MedDetailCard(med: med)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private func compartment(_ med: Medication) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Medi.pill)
                .frame(width: 40, height: 87)
                .padding(.top, 23)
            Text(med.name)
                .font(.karla(24))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
                .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .frame(width: 155, height: 155)
        .background(MedText.isExpiringSoon(med) ? Medi.stopStroke : Medi.compartment,
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

/// "pill specific view": the medication's details over the blurred pill box.
struct MedDetailCard: View {
    let med: Medication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var message: PrescriberMessage?

    private var expiry: Date? { med.activeBottles.first?.expirationDate ?? med.bottles.compactMap(\.expirationDate).max() }

    var body: some View {
        ZStack {
            Color(hex: 0xD9D9D9).opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                MedNameCard(name: med.name)
                MedDetailsCard(rowSpacing: 22, verticalPadding: 18) {
                    MedDetailLine(text: "Dosage: " + MedText.dosage(med))
                    MedDetailLine(text: "Time: " + MedText.times(for: med))
                    MedDetailLine(text: "Expires: " + MedText.date(expiry),
                                  color: MedText.isExpiringSoon(med) ? Medi.expiringText : .black)
                    MedDetailLine(text: "Provider: " + (med.prescriber?.name ?? "x"))
                }
                VStack(spacing: 23) {
                    MediButton(title: "DELETE MED", style: .stop) { confirmDelete = true }
                    MediButton(title: "GO BACK", style: .plain) { dismiss() }
                    MediButton(title: "CONTACT PROVIDER", style: .plain, fontSize: 20) { message = contactMessage }
                }
            }
            .padding(.bottom, 60)
        }
        .confirmationDialog("Delete \(med.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This removes it from your pill box, stops its reminders and lists it under Past medications on the Info tab.")
        }
        .sheet(item: $message) { msg in
            NavigationStack {
                PrescriberMessageView(message: msg)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { message = nil } } }
            }
        }
    }

    private var contactMessage: PrescriberMessage { .suggested(for: med) }

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

extension MedText {
    /// Expires within one week (or already expired): the compartment turns red.
    static func isExpiringSoon(_ med: Medication) -> Bool {
        guard let date = med.activeBottles.first?.expirationDate else { return false }
        return ExpiryLevel.level(for: date) >= .week
    }
}
