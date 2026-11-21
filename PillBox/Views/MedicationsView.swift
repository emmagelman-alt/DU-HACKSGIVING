import SwiftData
import SwiftUI

struct MedicationsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query(sort: \Prescriber.name) private var prescribers: [Prescriber]

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.medsPath) {
            List {
                Section {
                    ForEach(meds) { med in
                        NavigationLink(value: med) { MedRow(med: med) }
                    }
                    Button { router.showScanner = true } label: {
                        Label("Scan a new label", systemImage: "camera.viewfinder").font(.body.weight(.semibold))
                    }
                } header: {
                    Text("\(meds.count) medications")
                } footer: {
                    Text("Scan every bottle's own label, even for the same medicine, so PillBox can track each bottle's expiration date.")
                }

                Section("Prescribers") {
                    ForEach(prescribers) { p in
                        NavigationLink(value: p) {
                            HStack(spacing: 12) {
                                Image(systemName: "stethoscope")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .background(Color.accentColor.opacity(0.12), in: Circle())
                                VStack(alignment: .leading) {
                                    Text(p.name).font(.headline)
                                    Text(p.practice.isEmpty ? "\(p.medications.count) medications" : p.practice)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        let p = Prescriber(name: "New prescriber")
                        context.insert(p)
                        router.medsPath.append(p)
                    } label: {
                        Label("Add a prescriber", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showScanner = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medication")
                }
            }
            .navigationDestination(for: Medication.self) { MedicationDetailView(med: $0) }
            .navigationDestination(for: Prescriber.self) { PrescriberEditView(prescriber: $0) }
            .navigationDestination(for: PrescriberMessage.self) { PrescriberMessageView(message: $0) }
        }
    }
}

struct MedRow: View {
    let med: Medication

    var body: some View {
        HStack(spacing: 14) {
            PillIcon(colorIndex: med.colorIndex, form: med.form, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(med.displayName).font(.headline)
                Text("\(med.doseText) · \(Scheduler.summary(for: med))")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    let soonest = med.activeBottles.first?.expirationDate
                    if ExpiryLevel.level(for: soonest).isWarning { ExpiryChip(date: soonest) }
                    if let days = Scheduler.daysLeft(med), days <= 7 {
                        Chip(text: "\(med.pillsRemaining) left", symbol: "exclamationmark.circle", color: .orange)
                    }
                    if med.activeBottles.count > 1 {
                        Chip(text: "\(med.activeBottles.count) bottles", symbol: "square.stack.fill", color: .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
