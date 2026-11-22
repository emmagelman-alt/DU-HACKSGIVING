import SwiftUI

/// How close a bottle is to its expiration date. Warnings go out at 30, 14 and 7 days, and on the day.
enum ExpiryLevel: Int, Comparable {
    case ok, month, twoWeeks, week, today, expired

    static func < (a: ExpiryLevel, b: ExpiryLevel) -> Bool { a.rawValue < b.rawValue }

    static func days(until date: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func level(for date: Date?, now: Date = Date()) -> ExpiryLevel {
        guard let date else { return .ok }
        let d = days(until: date, now: now)
        switch d {
        case ..<0: return .expired
        case 0: return .today
        case 1...7: return .week
        case 8...14: return .twoWeeks
        case 15...30: return .month
        default: return .ok
        }
    }

    static func text(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "No expiration date" }
        let d = days(until: date, now: now)
        switch d {
        case ..<(-1): return "Expired \(-d) days ago"
        case -1: return "Expired yesterday"
        case 0: return "Expires today"
        case 1: return "Expires tomorrow"
        default: return "Expires in \(d) days"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .month: .yellow
        case .twoWeeks: .orange
        case .week, .today: Color(red: 0.95, green: 0.35, blue: 0.20)
        case .expired: .red
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.seal.fill"
        case .month, .twoWeeks: "clock.badge.exclamationmark.fill"
        case .week, .today: "exclamationmark.triangle.fill"
        case .expired: "xmark.octagon.fill"
        }
    }

    var isWarning: Bool { self != .ok }
}
