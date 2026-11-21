import SwiftData
import SwiftUI

/// Expired and expiring bottles, and meds that are running low.
struct AlertsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.name) private var meds: [Medication]

    private var bottles: [(Medication, Bottle)] {
        meds.flatMap { m in m.activeBottles.map { (m, $0) } }
            .sorted { ($0.1.expirationDate ?? .distantFuture) < ($1.1.expirationDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                let expired = bottles.filter { ExpiryLevel.level(for: $0.1.expirationDate) == .expired }
                let soon = bottles.filter { let l = ExpiryLevel.level(for: $0.1.expirationDate); return l.isWarning && l != .expired }
                let low = meds.filter { (Scheduler.daysLeft($0) ?? 99) <= 7 }

                if expired.isEmpty && soon.isEmpty && low.isEmpty {
                    Section {
                        Label("Everything is in date and well stocked.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }

                if !expired.isEmpty {
                    Section {
                        ForEach(expired, id: \.1.id) { med, bottle in
                            alertRow(med: med, bottle: bottle, reason: .expired)
                        }
                    } header: {
                        Label("Expired — don't take these", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    } footer: {
                        Text("Scan the label of your new bottle to confirm you have a fresh supply.")
                    }
                }

                if !soon.isEmpty {
                    Section("Expiring soon") {
                        ForEach(soon, id: \.1.id) { med, bottle in
                            alertRow(med: med, bottle: bottle, reason: .expiring)
                        }
                    }
                }

                if !low.isEmpty {
                    Section("Running low") {
                        ForEach(low) { med in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    PillIcon(colorIndex: med.colorIndex, form: med.form, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(med.displayName).font(.headline)
                                        Text("\(med.pillsRemaining) pills left · about \(Scheduler.daysLeft(med) ?? 0) days").font(.subheadline).foregroundStyle(.orange)
                                    }
                                }
                                if med.prescriber != nil {
                                    NavigationLink(value: PrescriberMessage(medicationID: med.id, reason: .runningLow)) {
                                        Label("Ask \(med.prescriber!.name) for a refill", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("How expiration warnings work") {
                    timeline
                }
            }
            .navigationTitle("Alerts")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: PrescriberMessage.self) { PrescriberMessageView(message: $0) }
        }
    }

    private func alertRow(med: Medication, bottle: Bottle, reason: PrescriberMessage.Reason) -> some View {
        let level = ExpiryLevel.level(for: bottle.expirationDate)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: level.symbol)
                    .font(.title3)
                    .foregroundStyle(level.color)
                    .frame(width: 40, height: 40)
                    .background(level.color.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.displayName).font(.headline)
                    Text(ExpiryLevel.text(for: bottle.expirationDate)).font(.subheadline.weight(.semibold)).foregroundStyle(level.color)
                    Text("Rx #\(bottle.rxNumber) · exp. \(bottle.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button { router.showScanner = true } label: {
                    Label("Scan new bottle", systemImage: "camera.viewfinder").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(level == .expired ? .red : .accentColor)
                if let p = med.prescriber {
                    NavigationLink(value: PrescriberMessage(medicationID: med.id, reason: reason)) {
                        Text("Message \(p.name)").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var timeline: some View {
        HStack(spacing: 0) {
            ForEach([("1 month", ExpiryLevel.month), ("2 weeks", .twoWeeks), ("1 week", .week), ("Day of", .today)], id: \.0) { item in
                VStack(spacing: 6) {
                    Circle().fill(item.1.color).frame(width: 14, height: 14)
                    Text(item.0).font(.caption.weight(.semibold))
                    Text("before").font(.caption2).foregroundStyle(.secondary).opacity(item.0 == "Day of" ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .background(alignment: .top) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 2).padding(.horizontal, 40).padding(.top, 12)
        }
    }
}
