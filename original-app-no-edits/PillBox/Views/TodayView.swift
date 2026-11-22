import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query private var logs: [DoseLog]
    @AppStorage("patientName") private var patientName = ""
    @State private var now = Date()

    private var slots: [DoseSlot] { Scheduler.slots(on: now, meds: meds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if meds.isEmpty {
                        emptyState
                    } else {
                        progressCard
                        if let next = nextSlot { nextCard(next) }
                        alertBanner
                        SectionTitle(text: "Today's schedule")
                        ForEach(slots) { slot in
                            let status = Scheduler.status(of: slot, logs: logs, now: now)
                            SlotRow(slot: slot, status: status, onTap: tapAction(slot, status))
                        }
                        let asNeeded = meds.filter { $0.frequency == .asNeeded }
                        if !asNeeded.isEmpty {
                            SectionTitle(text: "As needed")
                            ForEach(asNeeded) { med in
                                HStack { PillIcon(colorIndex: med.colorIndex, form: med.form, size: 32); Text(med.displayName).font(.headline) }.card()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showScanner = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medication")
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(greeting).font(.largeTitle.weight(.bold))
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return patientName.isEmpty ? part : "\(part), \(patientName.split(separator: " ").first.map(String.init) ?? patientName)"
    }

    private var takenCount: Int { slots.filter { if case .taken = Scheduler.status(of: $0, logs: logs, now: now) { true } else { false } }.count }

    private var progressCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: slots.isEmpty ? 0 : CGFloat(takenCount) / CGFloat(slots.count))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(takenCount)/\(slots.count)").font(.headline)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(takenCount == slots.count && !slots.isEmpty ? "All done for today" : "\(takenCount) of \(slots.count) doses taken")
                    .font(.headline)
                Text("\(meds.count) medications · \(slots.flatMap(\.meds).count) pills scheduled today")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var nextSlot: DoseSlot? {
        slots.first { s in
            switch Scheduler.status(of: s, logs: logs, now: now) {
            case .due, .upcoming, .snoozed: true
            default: false
            }
        }
    }

    private func nextCard(_ slot: DoseSlot) -> some View {
        let status = Scheduler.status(of: slot, logs: logs, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(status == .due ? "Due now" : "Next up", systemImage: slot.dayPart.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(relative(slot.date)).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title).font(.title2.weight(.bold))
                Text(slot.timeText).font(.system(size: 44, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            HStack(spacing: -8) {
                ForEach(slot.meds) { med in
                    Image(systemName: "pills.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(PillPalette.color(med.colorIndex), in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                Text(slot.meds.map(\.name).joined(separator: ", "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                    .lineLimit(1)
            }
            Button { router.openTakeScreen(slotKey: slot.key) } label: {
                Text(status == .due ? "Take now" : "Take early")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(slot.dayPart.color)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [slot.dayPart.color, slot.dayPart.color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    @ViewBuilder private var alertBanner: some View {
        let bottles = meds.flatMap(\.activeBottles).filter { ExpiryLevel.level(for: $0.expirationDate).isWarning }
        let worst = bottles.map { ExpiryLevel.level(for: $0.expirationDate) }.max()
        if let worst {
            Button { router.tab = .alerts } label: {
                HStack(spacing: 12) {
                    Image(systemName: worst.symbol).font(.title2).foregroundStyle(worst.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(worst == .expired ? "A bottle has expired" : "\(bottles.count) bottle\(bottles.count == 1 ? "" : "s") expiring soon")
                            .font(.headline)
                        Text(worst == .expired ? "Scan the label of your new bottle" : "Tap to see dates and refill options")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Add your first medication").font(.title2.weight(.bold))
            Text("Take a photo of the label on each bottle. PillBox reads the name, dose, schedule and expiration date for you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { router.showScanner = true } label: {
                Label("Scan a label", systemImage: "camera.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            Button("Load demo medications") { DemoData.seed(into: context) }
                .font(.subheadline)
        }
        .padding(24)
        .card()
        .padding(.top, 20)
    }

    private func tapAction(_ slot: DoseSlot, _ status: SlotStatus) -> (() -> Void)? {
        switch status {
        case .taken: nil
        default: { router.openTakeScreen(slotKey: slot.key) }
        }
    }

    private func relative(_ date: Date) -> String {
        let mins = Int(date.timeIntervalSince(now) / 60)
        if mins <= 0 { return "now" }
        if mins < 60 { return "in \(mins) min" }
        return "in \(mins / 60) hr \(mins % 60) min"
    }
}
