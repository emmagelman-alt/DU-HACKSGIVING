import Foundation
import Observation

/// What the scan page is looking for, in the order shown under the camera.
enum ScanField: CaseIterable {
    case name, dosage, expiration, time, provider

    /// Parser keys that count as finding this field.
    var keys: [String] {
        switch self {
        case .name: ["name"]
        case .dosage: ["strength", "dose"]
        case .expiration: ["expiration"]
        case .time: ["frequency"]
        case .provider: ["prescriber"]
        }
    }
}

/// Collects label text while the bottle turns in front of the camera, or from photos, and decides what
/// each field says.
///
/// The camera reads the label many times a second, and any one reading can be wrong: glare turns
/// QUILLICHEW into QUILLICHI, or text behind the bottle gets read too. So each reading is parsed on its
/// own and counts as one vote per field, and every field shows the value most readings agree on. A field
/// turns green once two readings agree, and a later majority can still correct it.
///
/// Every distinct line is also kept in one pile (saved with the bottle). The pile is parsed as a whole
/// only for fields no single reading has caught, such as a date split across two views of the bottle.
@MainActor
@Observable
final class ScanSession {
    private(set) var lines: [String] = []
    private(set) var label = ParsedLabel()

    /// Readings that must agree before a field counts as found.
    static let agreement = 2

    /// Parser keys that are voted on, in the order they're filled in (dose after strength, so its form wins).
    static let votedKeys = ["name", "strength", "dose", "frequency", "expiration", "prescriber", "patient",
                            "looks", "rx", "quantity", "refills", "pharmacy", "directions"]

    private struct Tally {
        var weight: Int
        let order: Int
        let source: ParsedLabel
    }

    @ObservationIgnored private var votes: [String: [String: Tally]] = [:]
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var pile = ParsedLabel()
    @ObservationIgnored private var pileParsedAt = Date.distantPast
    @ObservationIgnored private var pileDirty = false
    @ObservationIgnored private var pileTask: Task<Void, Never>?
    /// Changes on reset or an on-the-spot pile read, so a background read that finishes later is thrown away.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var readings = 0
    @ObservationIgnored private var lastReading = ""
    @ObservationIgnored private var lastReadingAt = Date.distantPast
    // Details gathered from every reading rather than voted on.
    @ObservationIgnored private var scored = false
    @ObservationIgnored private var imprint = ""
    @ObservationIgnored private var color = ""
    @ObservationIgnored private var fillDate: Date?
    @ObservationIgnored private var instructions: Set<String> = []

    func has(_ field: ScanField) -> Bool { field.keys.contains { label.found.contains($0) } }
    var isComplete: Bool { ScanField.allCases.allSatisfy(has) }
    var foundCount: Int { ScanField.allCases.filter(has).count }

    func reset() {
        lines = []
        label = ParsedLabel()
        votes = [:]
        seen = []
        pile = ParsedLabel()
        pileParsedAt = .distantPast
        pileDirty = false
        pileTask?.cancel()
        pileTask = nil
        generation += 1
        readings = 0
        lastReading = ""
        lastReadingAt = .distantPast
        scored = false
        imprint = ""
        color = ""
        fillDate = nil
        instructions = []
    }

    /// One camera frame's text, top to bottom.
    func add(_ frame: [String], now: Date = Date()) {
        let clean = Self.clean(frame)
        guard !clean.isEmpty else { return }
        addToPile(clean)
        // The camera reports many near-identical frames a second. Counting the same view every time would
        // let one steady misread outvote everything, so an unchanged view counts at most twice a second.
        let key = clean.joined(separator: "\n").uppercased()
        let gap = now.timeIntervalSince(lastReadingAt)
        if gap >= 0.12, key != lastReading || gap >= 0.5 {
            lastReading = key
            lastReadingAt = now
            vote(LabelParser.parse(lines: clean), weight: 1)
        }
        if pileDirty, lines.count < 300, pileTask == nil, now.timeIntervalSince(pileParsedAt) >= 1 {
            parsePileInBackground(now: now)
        }
        rebuild()
    }

    /// One whole still photo's text. A sharp photo read in full counts as two agreeing readings.
    func addPhoto(_ photoLines: [String], now: Date = Date()) {
        let clean = Self.clean(photoLines)
        guard !clean.isEmpty else { return }
        addToPile(clean)
        vote(LabelParser.parse(lines: clean), weight: Self.agreement)
        // Read the pile now, and drop any slower background read of an older pile.
        pileTask?.cancel()
        pileTask = nil
        generation += 1
        parsePile(now: now)
        rebuild()
    }

    // MARK: Voting

    private func vote(_ p: ParsedLabel, weight: Int) {
        readings += 1
        for key in Self.votedKeys where p.found.contains(key) {
            let value = Self.value(of: key, in: p)
            if votes[key]?[value] != nil {
                votes[key]![value]!.weight += weight
            } else {
                votes[key, default: [:]][value] = Tally(weight: weight, order: readings, source: p)
            }
        }
        if p.pillScored { scored = true }
        if imprint.isEmpty { imprint = p.pillImprint }
        if color.isEmpty { color = p.pillColor }
        if fillDate == nil { fillDate = p.fillDate }
        instructions.formUnion(p.instructions)
    }

    /// The winning value for each field. Ties go to the value read first, so the screen doesn't flicker.
    private func rebuild() {
        var l = ParsedLabel()
        for key in Self.votedKeys {
            if let tallies = votes[key], !tallies.isEmpty {
                let best = tallies.values.max { a, b in a.weight != b.weight ? a.weight < b.weight : a.order > b.order }!
                if best.weight >= Self.agreement { Self.copy(key, from: best.source, into: &l) }
            } else if pile.found.contains(key) {
                Self.copy(key, from: pile, into: &l)
            }
        }
        l.pillScored = scored
        if l.pillImprint.isEmpty { l.pillImprint = imprint }
        if l.pillColor.isEmpty { l.pillColor = color }
        l.fillDate = fillDate
        l.instructions = instructions.sorted()
        l.rawText = lines.joined(separator: "\n")
        if l != label { label = l }
    }

    /// What a reading says for one field, as text, so equal readings land in the same tally.
    private static func value(of key: String, in p: ParsedLabel) -> String {
        switch key {
        case "name": p.name.uppercased()
        case "strength": p.strength.uppercased()
        case "dose": "\(p.pillsPerDose) \(p.form)"
        case "frequency":
            "\(p.frequency.rawValue) \(p.timesPerDay) \(p.intervalHours) \(p.minHoursApart) "
                + "\(p.dayParts.map(\.rawValue)) \(p.weekdays)"
        case "expiration": p.expiration.map { "\($0.timeIntervalSince1970)" } ?? ""
        case "prescriber": p.prescriberName.uppercased()
        case "patient": p.patientName.uppercased()
        case "looks": "\(p.pillShape) \(p.pillColor)"
        case "rx": p.rxNumber
        case "quantity": p.quantity.map(String.init) ?? ""
        case "refills": p.refills.map(String.init) ?? ""
        case "pharmacy": p.pharmacy.uppercased()
        case "directions": p.directions.uppercased()
        default: ""
        }
    }

    private static func copy(_ key: String, from p: ParsedLabel, into l: inout ParsedLabel) {
        switch key {
        case "name": l.name = p.name
        case "strength": l.strength = p.strength; l.form = p.form
        case "dose": l.pillsPerDose = p.pillsPerDose; l.form = p.form
        case "frequency":
            l.frequency = p.frequency
            l.timesPerDay = p.timesPerDay
            l.intervalHours = p.intervalHours
            l.minHoursApart = p.minHoursApart
            l.dayParts = p.dayParts
            l.weekdays = p.weekdays
        case "expiration": l.expiration = p.expiration
        case "prescriber": l.prescriberName = p.prescriberName
        case "patient": l.patientName = p.patientName
        case "looks": l.pillShape = p.pillShape; l.pillColor = p.pillColor; l.pillImprint = p.pillImprint
        case "rx": l.rxNumber = p.rxNumber
        case "quantity": l.quantity = p.quantity
        case "refills": l.refills = p.refills
        case "pharmacy": l.pharmacy = p.pharmacy
        case "directions": l.directions = p.directions
        default: return
        }
        l.found.insert(key)
    }

    // MARK: The pile of lines

    private static func clean(_ lines: [String]) -> [String] {
        lines.map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
    }

    /// Places each new line after the line it was seen with, so the pile stays in label order.
    private func addToPile(_ frame: [String]) {
        var anchor: Int?
        for line in frame {
            let key = line.uppercased()
            if seen.contains(key) {
                anchor = lines.firstIndex { $0.uppercased() == key }
                continue
            }
            seen.insert(key)
            let at = min(anchor.map { $0 + 1 } ?? lines.count, lines.count)
            lines.insert(line, at: at)
            anchor = at
            pileDirty = true
        }
    }

    private func parsePile(now: Date) {
        pile = LabelParser.parse(lines: lines)
        pileParsedAt = now
        pileDirty = false
    }

    /// A long pile takes a while to read, so during live scanning it's read off the main thread and the
    /// camera view keeps moving smoothly.
    private func parsePileInBackground(now: Date) {
        let snapshot = lines
        let generation = self.generation
        pileParsedAt = now
        pileDirty = false
        pileTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .utility) { LabelParser.parse(lines: snapshot) }.value
            guard let self, self.generation == generation else { return }
            self.pile = parsed
            self.pileTask = nil
            self.rebuild()
        }
    }
}
