import SwiftData
import SwiftUI

struct MedicationDetailView: View {
    @Bindable var med: Medication
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PillIcon(colorIndex: med.colorIndex, form: med.form, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.name).font(.title2.weight(.bold))
                        Text("\(med.strength) · \(med.doseText) per dose").foregroundStyle(.secondary)
                        Text(Scheduler.summary(for: med)).font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                let times = Scheduler.times(for: med)
                if times.isEmpty {
                    Text("Take only when needed").foregroundStyle(.secondary)
                }
                ForEach(times, id: \.self) { t in
                    let part = DayPart.containing(minutes: t)
                    HStack {
                        Image(systemName: part.symbol).foregroundStyle(part.color).frame(width: 28)
                        Text(ClockText.format(minutes: t)).font(.headline)
                        Spacer()
                        Text(part.title).foregroundStyle(.secondary)
                    }
                }
                if med.minHoursApart > 0 {
                    Label("Doses kept at least \(med.minHoursApart) hours apart", systemImage: "arrow.left.and.right")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button { editing = true } label: { Label("Change times", systemImage: "clock.arrow.circlepath") }
            } header: {
                Text("When to take it")
            }

            if !med.instructions.isEmpty || !med.directions.isEmpty {
                Section("Directions") {
                    if !med.directions.isEmpty { Text(med.directions) }
                    if !med.instructions.isEmpty {
                        Label(med.instructions, systemImage: "info.circle.fill").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                ForEach(med.bottles.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }) { bottle in
                    BottleRow(bottle: bottle)
                        .swipeActions {
                            Button(bottle.isFinished ? "Restore" : "Finished") { bottle.isFinished.toggle() }
                                .tint(bottle.isFinished ? .blue : .gray)
                        }
                }
                Button { router.showScanner = true } label: { Label("Scan a new bottle", systemImage: "camera.viewfinder") }
            } header: {
                Text("Bottles · \(med.pillsRemaining) pills left")
            } footer: {
                if let days = Scheduler.daysLeft(med) { Text("About \(days) days of medication left at your current schedule.") }
            }

            Section("Prescriber") {
                if let p = med.prescriber {
                    NavigationLink(value: p) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text([p.practice, p.phone].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(value: PrescriberMessage(medicationID: med.id, reason: reason)) {
                        Label("Ask \(p.name) for a refill", systemImage: "paperplane.fill")
                    }
                } else {
                    Button {
                        let p = Prescriber(name: "New prescriber")
                        context.insert(p)
                        med.prescriber = p
                        router.medsPath.append(p)
                    } label: { Label("Add the prescriber's contact", systemImage: "person.crop.circle.badge.plus") }
                }
            }

            Section {
                Button("Delete medication", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(med.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { MedicationFormView(draft: MedDraft(med: med), mode: .edit(med)) }
        .confirmationDialog("Delete \(med.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(med)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("This removes its reminders and all its bottles.")
        }
    }

    private var reason: PrescriberMessage.Reason {
        let level = ExpiryLevel.level(for: med.activeBottles.first?.expirationDate)
        if level >= .week { return .expiring }
        if let d = Scheduler.daysLeft(med), d <= 7 { return .runningLow }
        return level.isWarning ? .expiring : .refill
    }
}

struct BottleRow: View {
    let bottle: Bottle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = bottle.labelImage, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text.image").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 48)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(bottle.rxNumber.isEmpty ? "Bottle" : "Rx #\(bottle.rxNumber)").font(.subheadline.weight(.semibold))
                if bottle.isFinished {
                    Chip(text: "Finished", symbol: "archivebox", color: .secondary)
                } else {
                    ExpiryChip(date: bottle.expirationDate)
                }
                Text([
                    bottle.expirationDate.map { "Exp. \($0.formatted(date: .abbreviated, time: .omitted))" },
                    bottle.quantity > 0 ? "\(bottle.pillsRemaining) of \(bottle.quantity) left" : nil,
                    bottle.pharmacy.isEmpty ? nil : bottle.pharmacy
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(bottle.isFinished ? 0.5 : 1)
    }
}
