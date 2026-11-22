import Foundation
import SwiftUI

/// The four parts of the day that a pill box is divided into.
/// Times are stored as "minutes after midnight" (0...1439).
enum DayPart: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning, afternoon, evening, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    var shortTitle: String {
        switch self {
        case .morning: "AM"
        case .afternoon: "Noon"
        case .evening: "PM"
        case .night: "Bed"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: Color(red: 0.98, green: 0.62, blue: 0.20)
        case .afternoon: Color(red: 0.20, green: 0.62, blue: 0.95)
        case .evening: Color(red: 0.62, green: 0.38, blue: 0.90)
        case .night: Color(red: 0.25, green: 0.30, blue: 0.62)
        }
    }

    /// Default reminder time for this part of the day.
    var defaultMinutes: Int {
        switch self {
        case .morning: 8 * 60
        case .afternoon: 13 * 60
        case .evening: 18 * 60
        case .night: 21 * 60 + 30
        }
    }

    /// The window this part of the day covers. Snoozing can never go past `endMinutes`.
    var startMinutes: Int {
        switch self {
        case .morning: 5 * 60
        case .afternoon: 12 * 60
        case .evening: 17 * 60
        case .night: 21 * 60
        }
    }

    /// Last minute (inclusive) that still belongs to this part of the day.
    var endMinutes: Int {
        switch self {
        case .morning: 11 * 60 + 59
        case .afternoon: 16 * 60 + 59
        case .evening: 20 * 60 + 59
        case .night: 23 * 60 + 59
        }
    }

    /// Which part of the day a clock time falls in. Early hours (before 5 AM) count as night.
    static func containing(minutes: Int) -> DayPart {
        switch minutes {
        case 300..<720: .morning
        case 720..<1020: .afternoon
        case 1020..<1260: .evening
        default: .night
        }
    }
}

enum ClockText {
    /// "8:00 AM" for 480.
    static func format(minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, h < 12 ? "AM" : "PM")
    }

    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(_ day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}
