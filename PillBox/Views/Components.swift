import SwiftUI

struct PillIcon: View {
    var colorIndex: Int
    var form: String = "tablet"
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(PillPalette.color(colorIndex).opacity(0.18))
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(PillPalette.color(colorIndex))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch form {
        case "capsule", "softgel": "pill.fill"
        case "drop": "drop.fill"
        case "puff": "lungs.fill"
        case "mL", "teaspoon": "cross.vial.fill"
        default: "pills.fill"
        }
    }
}

struct Chip: View {
    var text: String
    var symbol: String? = nil
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: Capsule())
    }
}

struct StatusChip: View {
    var status: SlotStatus

    var body: some View {
        switch status {
        case .taken: Chip(text: "Taken", symbol: "checkmark.circle.fill", color: .green)
        case .snoozed(let d): Chip(text: "Snoozed · \(d.formatted(date: .omitted, time: .shortened))", symbol: "zzz", color: .indigo)
        case .due: Chip(text: "Due now", symbol: "bell.fill", color: .orange)
        case .upcoming: Chip(text: "Upcoming", symbol: "clock", color: .secondary)
        case .missed: Chip(text: "Missed", symbol: "exclamationmark.circle.fill", color: .red)
        }
    }
}

struct ExpiryChip: View {
    var date: Date?

    var body: some View {
        let level = ExpiryLevel.level(for: date)
        Chip(text: ExpiryLevel.text(for: date), symbol: level.symbol, color: level == .ok ? .green : level.color)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// One dose time in a list: time, meds, and whether it was taken.
struct SlotRow: View {
    var slot: DoseSlot
    var status: SlotStatus
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    Image(systemName: slot.dayPart.symbol)
                        .font(.title3)
                        .foregroundStyle(slot.dayPart.color)
                        .frame(width: 40, height: 40)
                        .background(slot.dayPart.color.opacity(0.15), in: Circle())
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.timeText).font(.headline)
                            Text(slot.dayPart.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusChip(status: status)
                    }
                    ForEach(slot.meds) { med in
                        HStack(spacing: 10) {
                            PillIcon(colorIndex: med.colorIndex, form: med.form, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(med.displayName).font(.subheadline.weight(.semibold))
                                Text(med.doseText + (med.instructions.isEmpty ? "" : " · \(med.instructions.lowercased())"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .opacity(isTaken ? 0.55 : 1)
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var isTaken: Bool { if case .taken = status { true } else { false } }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text).font(.title3.weight(.bold)).padding(.top, 6)
    }
}
