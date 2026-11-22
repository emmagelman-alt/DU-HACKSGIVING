import Foundation
import SwiftData

enum FrequencyKind: String, Codable, CaseIterable, Identifiable {
    case daily, everyHours, asNeeded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: "Times per day"
        case .everyHours: "Every few hours"
        case .asNeeded: "As needed"
        }
    }
}

/// One medication the person takes, with its schedule.
/// Each physical bottle of it is a separate `Bottle`, so two bottles of the same
/// medication can have different expiration dates.
@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var strength: String = ""
    var form: String = "tablet"
    var pillsPerDose: Int = 1
    var directions: String = ""
    var frequencyRaw: String = FrequencyKind.daily.rawValue
    var timesPerDay: Int = 1
    var intervalHours: Int = 0
    /// Minimum hours between two doses (0 = no rule).
    var minHoursApart: Int = 0
    var dayPartsRaw: [String] = [DayPart.morning.rawValue]
    /// Exact times in minutes after midnight. Empty = use the day-part times.
    var customTimes: [Int] = []
    /// Calendar weekdays (1 = Sunday). Empty = every day.
    var weekdays: [Int] = []
    var instructions: String = ""
    var colorIndex: Int = 0
    var createdAt: Date = Date()
    var prescriber: Prescriber?
    @Relationship(deleteRule: .cascade, inverse: \Bottle.medication)
    var bottles: [Bottle] = []

    init(name: String, strength: String) {
        self.name = name
        self.strength = strength
    }

    var frequency: FrequencyKind {
        get { FrequencyKind(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var dayParts: [DayPart] {
        get { DayPart.allCases.filter { dayPartsRaw.contains($0.rawValue) } }
        set { dayPartsRaw = newValue.map(\.rawValue) }
    }

    var displayName: String { strength.isEmpty ? name : "\(name) \(strength)" }

    var doseText: String {
        let unit = form.isEmpty ? "pill" : form
        return "\(pillsPerDose) \(pillsPerDose == 1 ? unit : unit + "s")"
    }

    var activeBottles: [Bottle] {
        bottles.filter { !$0.isFinished }.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }

    var pillsRemaining: Int { activeBottles.reduce(0) { $0 + $1.pillsRemaining } }
}

/// One physical bottle, read from its own label.
@Model
final class Bottle {
    var id: UUID = UUID()
    var medication: Medication?
    var expirationDate: Date?
    var fillDate: Date?
    var quantity: Int = 0
    var pillsRemaining: Int = 0
    var refills: Int = 0
    var rxNumber: String = ""
    var pharmacy: String = ""
    var labelText: String = ""
    @Attribute(.externalStorage) var labelImage: Data?
    var addedAt: Date = Date()
    /// Used up, thrown away, or replaced by a new bottle.
    var isFinished: Bool = false

    init() {}
}

/// The doctor or other practitioner who prescribes a medication.
@Model
final class Prescriber {
    var id: UUID = UUID()
    var name: String = ""
    var practice: String = ""
    var phone: String = ""
    var email: String = ""
    var notifyWhenExpiring: Bool = true
    var notifyWhenLow: Bool = true
    @Relationship(inverse: \Medication.prescriber)
    var medications: [Medication] = []

    init(name: String) { self.name = name }
}

/// A record that the person confirmed taking the meds for one dose time.
@Model
final class DoseLog {
    var slotKey: String = ""
    var medicationIDs: [UUID] = []
    var takenAt: Date = Date()

    init(slotKey: String, medicationIDs: [UUID], takenAt: Date = Date()) {
        self.slotKey = slotKey
        self.medicationIDs = medicationIDs
        self.takenAt = takenAt
    }
}
