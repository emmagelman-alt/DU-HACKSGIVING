import Foundation
import SwiftData

/// The person's preferred time for each part of the day (Settings screen).
enum DayPartTimes {
    static func minutes(for part: DayPart) -> Int {
        let stored = UserDefaults.standard.object(forKey: key(part)) as? Int
        return stored ?? part.defaultMinutes
    }

    static func set(_ minutes: Int, for part: DayPart) {
        UserDefaults.standard.set(minutes, forKey: key(part))
    }

    private static func key(_ part: DayPart) -> String { "time.\(part.rawValue)" }
}

/// All the meds due at one time on one day — one compartment of the pill box.
struct DoseSlot: Identifiable, Hashable {
    let day: Date
    let minutes: Int
    let meds: [Medication]

    var id: String { key }
    var key: String { Scheduler.key(day: day, minutes: minutes) }
    var dayPart: DayPart { DayPart.containing(minutes: minutes) }
    var date: Date { ClockText.date(day, minutes: minutes) }
    var timeText: String { ClockText.format(minutes: minutes) }
    var title: String { "\(dayPart.title) meds" }

    static func == (a: DoseSlot, b: DoseSlot) -> Bool { a.key == b.key && a.meds.map(\.id) == b.meds.map(\.id) }
    func hash(into h: inout Hasher) { h.combine(key) }
}

enum SlotStatus: Equatable {
    case taken(Date)
    case snoozed(Date)
    case due
    case upcoming
    case missed

    var label: String {
        switch self {
        case .taken: "Taken"
        case .snoozed(let d): "Snoozed to \(ClockText.format(minutes: ClockText.minutes(of: d)))"
        case .due: "Due now"
        case .upcoming: "Upcoming"
        case .missed: "Missed"
        }
    }
}

enum Scheduler {
    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(day: Date, minutes: Int) -> String {
        "\(keyFormatter.string(from: day))@\(String(format: "%04d", (minutes / 60) * 100 + minutes % 60))"
    }

    /// Parses a slot key back into (day, minutes).
    static func parse(key: String) -> (Date, Int)? {
        let parts = key.split(separator: "@")
        guard parts.count == 2, let day = keyFormatter.date(from: String(parts[0])), let hhmm = Int(parts[1]) else { return nil }
        return (Calendar.current.startOfDay(for: day), (hhmm / 100) * 60 + hhmm % 100)
    }

    static func defaultParts(timesPerDay n: Int) -> [DayPart] {
        switch n {
        case ..<2: [.morning]
        case 2: [.morning, .evening]
        case 3: [.morning, .afternoon, .evening]
        default: DayPart.allCases
        }
    }

    /// Spreads "every N hours" doses across waking hours (roughly 6 AM – 11:30 PM).
    static func intervalTimes(hours h: Int) -> [Int] {
        guard h > 0 else { return [DayPartTimes.minutes(for: .morning)] }
        let step = h * 60
        let lastAllowed = 23 * 60 + 30
        let maxFit = (lastAllowed - 6 * 60) / step + 1
        let n = max(1, min(24 / h, maxFit))
        let start = max(5 * 60, min(DayPartTimes.minutes(for: .morning), lastAllowed - (n - 1) * step))
        return (0..<n).map { start + $0 * step }
    }

    /// Pushes doses later when they are closer together than the medication allows.
    static func enforceGap(_ times: [Int], hours: Int) -> [Int] {
        guard hours > 0 else { return times }
        var out: [Int] = []
        for t in times.sorted() {
            if let last = out.last, t - last < hours * 60 {
                let pushed = last + hours * 60
                if pushed <= 23 * 60 + 59 { out.append(pushed) }
            } else {
                out.append(t)
            }
        }
        return out
    }

    /// Times of day (minutes after midnight) this medication is taken.
    static func times(for med: Medication) -> [Int] {
        if med.frequency == .asNeeded { return [] }
        if !med.customTimes.isEmpty { return Array(Set(med.customTimes)).sorted() }
        if med.frequency == .everyHours, med.intervalHours > 0 {
            return intervalTimes(hours: med.intervalHours)
        }
        var parts = med.dayParts
        if parts.count < max(1, med.timesPerDay) {
            parts = defaultParts(timesPerDay: med.timesPerDay)
        }
        let times = parts.map { DayPartTimes.minutes(for: $0) }
        return enforceGap(times, hours: med.minHoursApart)
    }

    static func takesOn(_ med: Medication, day: Date) -> Bool {
        guard !med.weekdays.isEmpty else { return true }
        return med.weekdays.contains(Calendar.current.component(.weekday, from: day))
    }

    static func slots(on day: Date, meds: [Medication]) -> [DoseSlot] {
        let start = Calendar.current.startOfDay(for: day)
        var byTime: [Int: [Medication]] = [:]
        for med in meds where takesOn(med, day: start) {
            for t in times(for: med) { byTime[t, default: []].append(med) }
        }
        return byTime.keys.sorted().map { t in
            DoseSlot(day: start, minutes: t, meds: byTime[t]!.sorted { $0.name < $1.name })
        }
    }

    static func status(of slot: DoseSlot, logs: [DoseLog], now: Date = Date()) -> SlotStatus {
        if let log = logs.first(where: { $0.slotKey == slot.key }) { return .taken(log.takenAt) }
        if let until = SnoozeStore.until(slot.key), until > now { return .snoozed(until) }
        if slot.date > now { return .upcoming }
        let endOfPart = ClockText.date(slot.day, minutes: slot.dayPart.endMinutes).addingTimeInterval(59)
        let endOfDay = Calendar.current.startOfDay(for: slot.day).addingTimeInterval(86_400)
        return now > max(endOfPart, slot.date.addingTimeInterval(3 * 3600)) || now >= endOfDay ? .missed : .due
    }

    /// How many days of pills are left, based on how many the schedule uses per day.
    static func daysLeft(_ med: Medication) -> Int? {
        let perDay = times(for: med).count * max(1, med.pillsPerDose)
        guard perDay > 0 else { return nil }
        return med.pillsRemaining / perDay
    }

    static func summary(for med: Medication) -> String {
        switch med.frequency {
        case .asNeeded: return "As needed"
        case .everyHours: return "Every \(med.intervalHours) hours"
        case .daily:
            let n = times(for: med).count
            let base = switch n { case 1: "Once a day"; case 2: "Twice a day"; default: "\(n) times a day" }
            if !med.weekdays.isEmpty {
                let names = Calendar.current.shortWeekdaySymbols
                return "\(base) · " + med.weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
            }
            return base
        }
    }
}

/// Snoozed dose times, kept in UserDefaults so alarms and the app agree.
enum SnoozeStore {
    private static let key = "snoozes"

    static func until(_ slotKey: String) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return all[slotKey].map { Date(timeIntervalSince1970: $0) }
    }

    static func set(_ slotKey: String, until date: Date?) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        all[slotKey] = date?.timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Snooze choices for a dose. They never leave its part of the day or the same day.
    static func options(for slot: DoseSlot, now: Date = Date()) -> (base: Date, presets: [Int], latest: Date) {
        // Snoozing a dose opened early counts from the dose time, not from now.
        let base = max(now, slot.date)
        let endOfPart = ClockText.date(slot.day, minutes: slot.dayPart.endMinutes)
        let endOfDay = ClockText.date(slot.day, minutes: 23 * 60 + 59)
        // If the part of the day is already over, allow one short final snooze (still the same day).
        let latest = base < endOfPart ? endOfPart : min(endOfDay, base.addingTimeInterval(15 * 60))
        let presets = [10, 15, 30, 60].filter { base.addingTimeInterval(Double($0) * 60) <= latest }
        return (base, presets, latest)
    }
}
