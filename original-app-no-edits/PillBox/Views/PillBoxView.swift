import SwiftData
import SwiftUI

/// A week-long pill organizer: days across, parts of the day down.
struct PillBoxView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query private var logs: [DoseLog]
    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: weekOffset * 7 - 3, to: today)!
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekHeader
                    organizer
                    legend
                    SectionTitle(text: selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    let slots = Scheduler.slots(on: selectedDay, meds: meds)
                    if slots.isEmpty {
                        Text("No scheduled meds this day.").foregroundStyle(.secondary).card()
                    }
                    ForEach(slots) { slot in
                        let status = Scheduler.status(of: slot, logs: logs)
                        SlotRow(slot: slot, status: status, onTap: Calendar.current.isDateInToday(slot.day) && status != .upcoming
                                ? { router.openTakeScreen(slotKey: slot.key) } : nil)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pill Box")
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").font(.headline) }
                .accessibilityLabel("Previous week")
            Spacer()
            Text("\(days.first!.formatted(.dateTime.month(.abbreviated).day())) – \(days.last!.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.headline)
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").font(.headline) }
                .accessibilityLabel("Next week")
        }
        .padding(.horizontal, 4)
    }

    private var organizer: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 26, height: 1)
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    Button { selectedDay = day } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(day.formatted(.dateTime.day()))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isSelected ? .white : isToday ? Color.accentColor : .primary)
                                .frame(width: 30, height: 30)
                                .background(isSelected ? Color.accentColor : .clear, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(DayPart.allCases) { part in
                GridRow {
                    Image(systemName: part.symbol)
                        .font(.footnote)
                        .foregroundStyle(part.color)
                        .frame(width: 26)
                    ForEach(days, id: \.self) { day in
                        compartment(day: day, part: part)
                            .onTapGesture { selectedDay = day }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func compartment(day: Date, part: DayPart) -> some View {
        let slots = Scheduler.slots(on: day, meds: meds).filter { $0.dayPart == part }
        let statuses = slots.map { Scheduler.status(of: $0, logs: logs) }
        let pills = slots.flatMap(\.meds)
        let allTaken = !slots.isEmpty && statuses.allSatisfy { if case .taken = $0 { true } else { false } }
        let anyMissed = statuses.contains(.missed)
        let anyDue = statuses.contains(.due)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(slots.isEmpty ? Color(.tertiarySystemFill).opacity(0.5)
                      : allTaken ? Color.green.opacity(0.18)
                      : anyMissed ? Color.red.opacity(0.15)
                      : part.color.opacity(0.16))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(anyDue ? Color.orange : isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 2)
            if allTaken {
                Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(.green)
            } else if anyMissed {
                Image(systemName: "xmark").font(.caption.weight(.heavy)).foregroundStyle(.red)
            } else if !pills.isEmpty {
                // Little pills in the compartment, one per medication.
                LazyVGrid(columns: [GridItem(.fixed(9), spacing: 3), GridItem(.fixed(9), spacing: 3)], spacing: 3) {
                    ForEach(Array(pills.prefix(4).enumerated()), id: \.offset) { _, med in
                        Capsule().fill(PillPalette.color(med.colorIndex)).frame(width: 9, height: 6)
                    }
                }
            }
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel("\(part.title), \(pills.count) meds, \(allTaken ? "taken" : anyMissed ? "missed" : "not taken yet")")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Color.green.opacity(0.5), "Taken")
            legendItem(Color.red.opacity(0.4), "Missed")
            legendItem(Color.orange, "Due now")
            legendItem(Color.secondary.opacity(0.3), "Upcoming")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10); Text(text) }
    }
}
