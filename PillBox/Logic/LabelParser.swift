import Foundation

/// Everything we try to pull off a pharmacy label. Fields we could not find stay nil/empty
/// so the review screen can highlight them for the person to fill in.
struct ParsedLabel: Equatable {
    var name: String = ""
    var strength: String = ""
    var form: String = "tablet"
    var pillsPerDose: Int = 1
    var directions: String = ""
    var frequency: FrequencyKind = .daily
    var timesPerDay: Int = 1
    var intervalHours: Int = 0
    var minHoursApart: Int = 0
    var dayParts: [DayPart] = []
    var weekdays: [Int] = []
    var instructions: [String] = []
    var expiration: Date?
    var fillDate: Date?
    var quantity: Int?
    var refills: Int?
    var rxNumber: String = ""
    var pharmacy: String = ""
    var prescriberName: String = ""
    /// Whose bottle it is ("Jordan Rivera").
    var patientName: String = ""
    /// What one pill looks like, from a line like "DESCRIPTION: PINK ROUND TABLET, SCORED, IMPRINT 10".
    var pillShape: String = ""
    var pillScored: Bool = false
    var pillImprint: String = ""
    var pillColor: String = ""
    var rawText: String = ""

    /// Which of the important fields were found on the label.
    var found: Set<String> = []
}

enum LabelParser {
    static func parse(lines rawLines: [String], today: Date = Date()) -> ParsedLabel {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // Text recognition sometimes reads "/" in dates as "|" or "\\".
        let upperLines = lines.map {
            $0.uppercased().replacingOccurrences(of: #"(?<=\d)\s*[|\\]\s*(?=\d)"#, with: "/", options: .regularExpression)
        }
        let upper = upperLines.joined(separator: "\n")
        var r = ParsedLabel()
        r.rawText = lines.joined(separator: "\n")

        // Rx number
        if let m = first(#"\bRX\s*(?:#|NO\.?|NUMBER)?\s*:?\s*#?\s*([0-9][0-9\-]{4,})"#, in: upper) {
            r.rxNumber = m[1]; r.found.insert("rx")
        }
        // Quantity
        if let m = first(#"\bQ(?:TY|UANTITY)\.?\s*:?\s*(\d{1,4})"#, in: upper), let q = Int(m[1]) {
            r.quantity = q; r.found.insert("quantity")
        }
        // Refills
        if upper.range(of: #"\bNO\s+REFILLS?\b"#, options: .regularExpression) != nil {
            r.refills = 0; r.found.insert("refills")
        } else if let m = first(#"\bREFILLS?\s*(?:LEFT|REMAINING)?\s*:?\s*(\d+|NONE|NO)\b"#, in: upper) {
            r.refills = Int(m[1]) ?? 0; r.found.insert("refills")
        }
        // Expiration ("EXP", "DISCARD AFTER", "USE BY", "BEYOND USE DATE")
        let expKeyword = #"(?:EXP(?:IRES|IRATION)?(?:\s*DATE)?|DISCARD\s*(?:AFTER|BY|ON)?|USE\s*(?:BY|BEFORE)|BEYOND\s*USE(?:\s*DATE)?|BUD)\.?\s*:?\s*"#
        if let d = date(after: expKeyword, in: upper, endOfMonth: true),
           d > Calendar.current.date(byAdding: .year, value: -3, to: today)! {
            r.expiration = d; r.found.insert("expiration")
        }
        // Fill date
        let fillKeyword = #"(?:DATE\s*FILLED|FILL(?:ED)?\s*DATE|FILLED|DATE)\s*:?\s*"#
        if let d = date(after: fillKeyword, in: upper, endOfMonth: false), d != r.expiration {
            r.fillDate = d
        }
        // Prescriber
        if let m = first(#"(?:\bDR\.?\s+|\bDOCTOR\s*:?\s*|PRESCRIBER\s*:?\s*|PRESCRIBED\s+BY\s*:?\s*)([A-Z][A-Z.'\- ]{2,40}?)(?:,?\s*(?:MD|M\.D\.|DO|NP|PA)\b|$|\n)"#, in: upper) {
            let name = m[1].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                r.prescriberName = "Dr. " + titleCase(name.replacingOccurrences(of: "DR. ", with: ""))
                r.found.insert("prescriber")
            }
        }
        // Pharmacy
        let chains = ["CVS", "WALGREENS", "RITE AID", "WALMART", "KROGER", "TARGET", "COSTCO", "PUBLIX", "SAFEWAY", "GIANT EAGLE"]
        if let i = upperLines.firstIndex(where: { l in l.contains("PHARMACY") || chains.contains(where: { l.contains($0) }) }) {
            r.pharmacy = titleCase(lines[i]); r.found.insert("pharmacy")
        }

        // Directions: the "TAKE ..." sentence, which can wrap over a few lines
        let verbs = #"^(TAKE|GIVE|USE|APPLY|INHALE|PLACE|INSTILL|CHEW|DISSOLVE|INJECT|SPRAY|INSERT|DISSOLVE)\b"#
        if let start = upperLines.firstIndex(where: { $0.range(of: verbs, options: .regularExpression) != nil }) {
            var parts = [upperLines[start]]
            var i = start + 1
            while i < upperLines.count, parts.count < 4, !isFieldLine(upperLines[i]) {
                parts.append(upperLines[i]); i += 1
            }
            r.directions = sentenceCase(parts.joined(separator: " "))
            r.found.insert("directions")
        }
        let dir = r.directions.isEmpty ? upper : r.directions.uppercased()
        parseDose(dir, into: &r)
        parseFrequency(dir, into: &r)
        parseInstructions(upper, into: &r)
        parsePillLooks(upperLines, into: &r)

        // Name + strength, then the patient (whose name is printed above the drug)
        let drugLine = parseNameAndStrength(lines: lines, upperLines: upperLines, into: &r)
        parsePatient(upperLines, drugLine: drugLine, into: &r)
        return r
    }

    // MARK: - Pieces

    private static func isFieldLine(_ l: String) -> Bool {
        l.range(of: #"^(RX|QTY|QUANTITY|REFILL|EXP|DISCARD|USE BY|USE BEFORE|DR\.?\s|DOCTOR|PRESCRIB|DATE|FILLED|ORIG|MFG|NDC|PHARMACY|CAUTION|WARNING|DESCRIPTION|IMPRINT|PATIENT)"#, options: .regularExpression) != nil
            || l.range(of: #"\d+(\.\d+)?\s*(MG|MCG|IU)\b"#, options: .regularExpression) != nil && !l.hasPrefix("TAKE")
    }

    private static let numberWords: [String: Int] = ["ONE": 1, "TWO": 2, "THREE": 3, "FOUR": 4, "FIVE": 5, "A": 1, "AN": 1, "HALF": 1, "1/2": 1]

    private static func parseDose(_ dir: String, into r: inout ParsedLabel) {
        let forms = #"(TABLETS?|TABS?|CAPSULES?|CAPS?|PILLS?|PUFFS?|DROPS?|SPRAYS?|ML|TEASPOONS?|PATCH(?:ES)?|SOFTGELS?|GUMMIES|GUMMY)"#
        if let m = first(#"\b(?:TAKE|GIVE|CHEW|USE|INHALE|INSTILL|DISSOLVE)\s+(ONE|TWO|THREE|FOUR|FIVE|HALF|A|AN|1/2|\d+)\s*(?:\(\s*\d+\s*\))?\s*"# + forms, in: dir) {
            r.pillsPerDose = Int(m[1]) ?? numberWords[m[1]] ?? 1
            r.form = normalizeForm(m[2])
            r.found.insert("dose")
        }
    }

    private static func normalizeForm(_ f: String) -> String {
        switch f {
        case let s where s.hasPrefix("TAB"): "tablet"
        case let s where s.hasPrefix("CAP"): "capsule"
        case let s where s.hasPrefix("PUFF"): "puff"
        case let s where s.hasPrefix("DROP"): "drop"
        case let s where s.hasPrefix("SPRAY"): "spray"
        case let s where s.hasPrefix("SOFTGEL"): "softgel"
        case let s where s.hasPrefix("GUMM"): "gummy"
        case let s where s.hasPrefix("PATCH"): "patch"
        case "ML": "mL"
        case let s where s.hasPrefix("TEASPOON"): "teaspoon"
        default: "pill"
        }
    }

    private static func parseFrequency(_ dir: String, into r: inout ParsedLabel) {
        var parts: [DayPart] = []
        if dir.range(of: #"\b(MORNING|BREAKFAST|IN THE AM|EVERY AM|A\.M\.)\b"#, options: .regularExpression) != nil { parts.append(.morning) }
        if dir.range(of: #"\b(NOON|LUNCH|AFTERNOON|MIDDAY)\b"#, options: .regularExpression) != nil { parts.append(.afternoon) }
        if dir.range(of: #"\b(EVENING|DINNER|SUPPER|IN THE PM|EVERY PM|P\.M\.)\b"#, options: .regularExpression) != nil { parts.append(.evening) }
        if dir.range(of: #"\b(BEDTIME|AT NIGHT|NIGHTLY|EVERY NIGHT|HS|AT HOUR OF SLEEP)\b"#, options: .regularExpression) != nil { parts.append(.night) }
        r.dayParts = DayPart.allCases.filter { parts.contains($0) }

        if let m = first(#"\bEVERY\s+(\d{1,2})\s*(?:TO\s*\d{1,2}\s*|-\s*\d{1,2}\s*)?HOURS?\b"#, in: dir) ?? first(#"\bQ\s?(\d{1,2})\s?H\b"#, in: dir),
           let h = Int(m[1]), h > 0, h <= 24 {
            if h == 24 { r.timesPerDay = 1 } else {
                r.frequency = .everyHours
                r.intervalHours = h
                r.timesPerDay = max(1, 24 / h)
            }
            r.minHoursApart = h
            r.found.insert("frequency")
        } else if dir.range(of: #"\b(FOUR TIMES|4 TIMES|QID)\b"#, options: .regularExpression) != nil {
            r.timesPerDay = 4; r.found.insert("frequency")
        } else if dir.range(of: #"\b(THREE TIMES|3 TIMES|TID)\b"#, options: .regularExpression) != nil {
            r.timesPerDay = 3; r.found.insert("frequency")
        } else if dir.range(of: #"\b(TWICE|TWO TIMES|2 TIMES|BID)\b"#, options: .regularExpression) != nil {
            r.timesPerDay = 2; r.found.insert("frequency")
        } else if dir.range(of: #"\b(ONCE A WEEK|ONCE WEEKLY|EVERY WEEK|WEEKLY)\b"#, options: .regularExpression) != nil {
            r.timesPerDay = 1
            let days = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
            if let i = days.firstIndex(where: { dir.contains($0) }) { r.weekdays = [i + 1] }
            else { r.weekdays = [Calendar.current.component(.weekday, from: Date())] }
            r.found.insert("frequency")
        } else if dir.range(of: #"\b(ONCE|DAILY|EVERY DAY|EACH DAY|QD|EVERY MORNING|EVERY NIGHT|NIGHTLY|AT BEDTIME)\b"#, options: .regularExpression) != nil {
            r.timesPerDay = max(1, r.dayParts.count); r.found.insert("frequency")
        } else if !r.dayParts.isEmpty {
            r.timesPerDay = r.dayParts.count; r.found.insert("frequency")
        }
        // "Every 6 hours as needed" = no fixed reminders, but keep the minimum gap.
        if dir.range(of: #"\b(AS NEEDED|PRN|IF NEEDED)\b"#, options: .regularExpression) != nil {
            r.frequency = .asNeeded; r.found.insert("frequency")
        }
        if let m = first(#"\b(\d{1,2})\s*HOURS?\s*APART\b"#, in: dir), let h = Int(m[1]) { r.minHoursApart = h }
        if r.frequency == .daily, r.dayParts.count < r.timesPerDay {
            r.dayParts = Scheduler.defaultParts(timesPerDay: r.timesPerDay)
        }
    }

    private static func parseInstructions(_ text: String, into r: inout ParsedLabel) {
        let notes: [(String, String)] = [
            (#"WITH (FOOD|MEALS?|A MEAL)"#, "Take with food"),
            (#"EMPTY STOMACH"#, "Take on an empty stomach"),
            (#"FULL GLASS OF WATER|WITH WATER"#, "Take with a full glass of water"),
            (#"DO NOT CRUSH|SWALLOW WHOLE"#, "Swallow whole"),
            (#"DROWSINESS|DROWSY"#, "May cause drowsiness"),
            (#"ALCOHOL"#, "Avoid alcohol"),
            (#"UNTIL (ALL )?GONE|FINISH ALL|COMPLETE(LY)? FINISH"#, "Finish the whole course"),
            (#"GRAPEFRUIT"#, "Avoid grapefruit"),
            (#"SUNLIGHT|SUN EXPOSURE"#, "Avoid too much sunlight")
        ]
        r.instructions = notes.compactMap { text.range(of: $0.0, options: .regularExpression) != nil ? $0.1 : nil }
    }

    // MARK: What the pill looks like

    private static let colorWords = ["OFF-WHITE", "WHITE", "YELLOW", "ORANGE", "PINK", "RED", "PEACH", "LIGHT BLUE", "BLUE",
                                     "GREEN", "PURPLE", "LAVENDER", "BROWN", "TAN", "GRAY", "GREY", "BLACK", "BEIGE",
                                     "CREAM", "MAROON", "TURQUOISE", "GOLD", "CLEAR"]

    /// Shape words on labels, most specific first ("capsule-shaped" is a tablet, not a capsule).
    private static let shapeWords: [(pattern: String, shape: String)] = [
        (#"\bCAPSULE[\s-]*SHAPED?\b|\bCAPLETS?\b|\bOBLONG\b|\bBULLET\b"#, "oblong"),
        (#"\bSOFT[\s-]*GELS?\b|\bGELCAPS?\b|\bLIQUI[\s-]*GELS?\b"#, "softgel"),
        (#"\bROUND\b|\bCIRCULAR\b"#, "round"),
        (#"\bOVAL\b|\bELLIPTICAL\b|\bEGG[\s-]*SHAPED\b"#, "oval"),
        (#"\bDIAMOND\b"#, "diamond"),
        (#"\bTRIANG(LE|ULAR)\b|\b3[\s-]*SIDED\b"#, "triangle"),
        (#"\bSQUARE\b"#, "square"),
        (#"\bRECTANG(LE|ULAR)\b"#, "rectangle"),
        (#"\bPENTAGON(AL)?\b|\b5[\s-]*SIDED\b"#, "pentagon"),
        (#"\bHEXAGON(AL)?\b|\b6[\s-]*SIDED\b"#, "hexagon"),
        (#"\bOCTAGON(AL)?\b|\b8[\s-]*SIDED\b"#, "octagon"),
        (#"\bCAPSULES?\b"#, "capsule")
    ]

    /// Reads the pill description that many pharmacies print, e.g.
    /// "DESCRIPTION: PINK ROUND TABLET, SCORED, IMPRINT 10" or "THIS MEDICINE IS A WHITE, OVAL TABLET".
    private static func parsePillLooks(_ upperLines: [String], into r: inout ParsedLabel) {
        let colors = colorWords.map { "\\b\($0)\\b" }.joined(separator: "|")
        let anyShape = shapeWords.dropLast().map(\.pattern).joined(separator: "|")
        // Only lines that describe the pill, so "TAKE ONE CAPSULE" doesn't count as a description.
        let described = upperLines.filter { l in
            l.range(of: #"\b(DESCRIPTION|DESCR|SHAPE|IMPRINT(ED)?|MARKINGS?|(MEDICINE|MEDICATION|PILL|TABLET|CAPSULE) IS (A|AN))\b"#,
                    options: .regularExpression) != nil
                || (l.range(of: colors, options: .regularExpression) != nil && l.range(of: anyShape, options: .regularExpression) != nil)
        }
        guard !described.isEmpty else { return }
        let text = described.joined(separator: " ")

        if let shape = shapeWords.first(where: { text.range(of: $0.pattern, options: .regularExpression) != nil })?.shape {
            r.pillShape = shape
        }
        r.pillScored = text.range(of: #"\b(SCORED|SCORE LINE|BISECTED|BREAK LINE)\b"#, options: .regularExpression) != nil
        let found = colorWords.compactMap { c -> (String.Index, String)? in
            text.range(of: "\\b\(c)\\b", options: .regularExpression).map { ($0.lowerBound, c) }
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
        .filter { c in c != "WHITE" || !text.contains("OFF-WHITE") }
        r.pillColor = Array(found.prefix(2)).joined(separator: " and ").lowercased()
        if let m = first(#"\bIMPRINT(?:ED)?(?:\s+WITH)?\s*:?\s*["']?([A-Z0-9][A-Z0-9 \-/]{0,20})"#, in: text) {
            let imprint = m[1]
                .replacingOccurrences(of: #"\s+(ON|AND|SCORED|BOTH|ONE|THE)\b.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            if !imprint.isEmpty { r.pillImprint = String(imprint.prefix(8)).trimmingCharacters(in: .whitespaces) }
        }
        if !r.pillShape.isEmpty { r.found.insert("looks") }
    }

    // MARK: Patient

    /// Words that are never part of a person's name on a label.
    private static let notNameWords: Set<String> = Set([
        "DR", "MD", "DO", "NP", "PA", "PHARMACY", "PHARMACIST", "DRUG", "DRUGS", "STORE", "STREET", "ST", "AVE", "AVENUE",
        "ROAD", "RD", "BLVD", "SUITE", "TAKE", "GIVE", "USE", "APPLY", "BY", "MOUTH", "DAILY", "ONCE", "TWICE", "WITH",
        "WITHOUT", "MEALS", "MEAL", "FOOD", "WATER", "UNTIL", "ALL", "GONE", "AVOID", "JUICE", "EMPTY", "STOMACH", "MORNING",
        "EVENING", "NIGHT", "BEDTIME", "AT", "IN", "THE", "ON", "AN", "A", "OF", "FOR", "AND", "OR", "TO", "EVERY", "HOURS",
        "HOUR", "AS", "NEEDED", "TABLET", "TABLETS", "CAPSULE", "CAPSULES", "SOFTGEL", "SOFTGELS", "PILL", "PILLS", "QTY",
        "REFILL", "REFILLS", "NO", "NONE", "EXP", "EXPIRES", "DISCARD", "AFTER", "DATE", "FILLED", "RX", "MFG", "NDC",
        "GENERIC", "SUBSTITUTED", "CAUTION", "WARNING", "FEDERAL", "LAW", "KEEP", "REACH", "CHILDREN", "SHAKE", "WELL",
        "NOT", "CRUSH", "CHEW", "SWALLOW", "WHOLE", "MAY", "CAUSE", "DROWSINESS", "ALCOHOL", "SUNLIGHT", "DESCRIPTION",
        "IMPRINT", "ORAL", "HCL", "ER", "XR", "CVS", "WALGREENS", "RITE", "AID", "WALMART", "KROGER", "TARGET", "COSTCO",
        "PUBLIX", "SAFEWAY", "GIANT", "EAGLE", "HEALTH", "CARE", "CLINIC", "MEDICAL", "CENTER", "HOSPITAL", "FAMILY",
        "MEDICINE", "ONLY", "BEFORE", "BEYOND", "PATIENT", "INFORMATION", "QUESTIONS", "CALL", "PHONE", "TEL", "FAX",
        "INC", "LLC", "CORP", "VITAMIN", "DOSE", "DOSES", "DAYS", "WEEK", "WEEKLY", "LEFT", "REMAINING"
    ]).union(colorWords)

    /// "PATIENT: JORDAN RIVERA" anywhere, otherwise a plain two-to-four-word name printed above the drug name.
    private static func parsePatient(_ upperLines: [String], drugLine: Int?, into r: inout ParsedLabel) {
        let labelled = upperLines.lazy.compactMap { l -> String? in
            guard let m = first(#"^(?:PATIENT(?:\s+NAME)?|PT(?:\s+NAME)?|NAME|FOR)\s*[:\-]\s*(.+)$"#, in: l) else { return nil }
            return personName(m[1])
        }.first
        // Without a labelled name, only trust lines above the drug name, so directions can't be mistaken for one.
        let plain = drugLine.flatMap { idx in upperLines[..<idx].lazy.compactMap { personName($0) }.first }
        guard let name = labelled ?? plain,
              name.caseInsensitiveCompare(r.prescriberName.replacingOccurrences(of: "Dr. ", with: "")) != .orderedSame else { return }
        r.patientName = name
        r.found.insert("patient")
    }

    /// "JORDAN RIVERA" or "RIVERA, JORDAN" → "Jordan Rivera"; anything else → nil.
    private static func personName(_ raw: String) -> String? {
        var s = raw.replacingOccurrences(of: #"\s+(DOB|D\.O\.B\.?|BORN|BIRTH)\b.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".:;-")))
        guard (5...36).contains(s.count),
              s.range(of: #"^[A-Z][A-Z'.\-]*(?:,?\s+[A-Z][A-Z'.\-]*){1,3}$"#, options: .regularExpression) != nil else { return nil }
        let words = s.replacingOccurrences(of: ",", with: " ").split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".'-")) }
        guard words.filter({ $0.count >= 2 }).count >= 2,
              !words.contains(where: { notNameWords.contains($0) }),
              !KnownDrugs.names.contains(where: { s.contains($0) }) else { return nil }
        if let comma = s.firstIndex(of: ",") {
            let last = s[..<comma].trimmingCharacters(in: .whitespaces)
            let rest = s[s.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            s = rest + " " + last
        }
        return titleCase(s)
    }

    // MARK: Name and strength

    /// Returns the index of the line with the drug name, if one was found.
    @discardableResult
    private static func parseNameAndStrength(lines: [String], upperLines: [String], into r: inout ParsedLabel) -> Int? {
        let strengthRx = #"(\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?)\s*(MG|MCG|G|ML|%|UNITS?|IU)\b"#
        let all = upperLines.joined(separator: "\n")
        let known = KnownDrugs.names.first { all.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }

        // Prefer the line with a known drug name, otherwise the first line with a strength that isn't directions.
        let candidate = upperLines.firstIndex { l in
            if let known, l.contains(known) { return true }
            return false
        } ?? upperLines.firstIndex { l in
            l.range(of: strengthRx, options: .regularExpression) != nil && !l.hasPrefix("TAKE") && !l.hasPrefix("QTY") && !l.hasPrefix("RX")
        }
        guard let idx = candidate else { return nil }
        let line = upperLines[idx]

        if let m = first(strengthRx, in: line) {
            let unit = m[2] == "MG" || m[2] == "MCG" || m[2] == "G" || m[2] == "ML" ? m[2].lowercased() : m[2]
            r.strength = "\(m[1].replacingOccurrences(of: " ", with: "")) \(unit == "ml" ? "mL" : unit)"
            r.found.insert("strength")
        } else if idx + 1 < upperLines.count, let m = first(strengthRx, in: upperLines[idx + 1]) {
            r.strength = "\(m[1]) \(m[2].lowercased())"
            r.found.insert("strength")
        }

        if let known {
            r.name = titleCase(known)
        } else {
            // Words before the strength, e.g. "LISINOPRIL 10 MG TABLET" -> "Lisinopril"
            let beforeStrength = line.components(separatedBy: CharacterSet.decimalDigits).first ?? line
            let cleaned = beforeStrength
                .replacingOccurrences(of: #"\b(TABLETS?|TABS?|CAPSULES?|CAPS?|ORAL|HCL|ER|XR)\b"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            r.name = titleCase(cleaned.isEmpty && idx > 0 ? upperLines[idx - 1] : cleaned)
        }
        if !r.name.isEmpty { r.found.insert("name") }
        if line.range(of: #"\bCAP(SULE)?S?\b"#, options: .regularExpression) != nil, !r.found.contains("dose") { r.form = "capsule" }
        if line.range(of: #"\bTAB(LET)?S?\b"#, options: .regularExpression) != nil, !r.found.contains("dose") { r.form = "tablet" }
        return idx
    }

    // MARK: - Dates

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Finds a date right after a keyword: 11/30/2027, 11-30-27, 11/2027, NOV 2027, NOV 30 2027.
    static func date(after keyword: String, in text: String, endOfMonth: Bool) -> Date? {
        let numeric = keyword + #"(\d{1,2})\s*[/\-.]\s*(\d{1,4})(?:\s*[/\-.]\s*(\d{2,4})|\s+(\d{4})\b)?"#
        if let m = first(numeric, in: text) {
            let a = Int(m[1]) ?? 0, b = Int(m[2]) ?? 0
            let yearText = m[3].isEmpty ? m[4] : m[3]
            if !yearText.isEmpty, let y = Int(yearText) {
                return makeDate(year: y, month: a, day: b)
            }
            // Month and year only: valid through the end of that month.
            return makeDate(year: b, month: a, day: endOfMonth ? 0 : 1)
        }
        let worded = keyword + #"(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s*(\d{1,2})?,?\s*(\d{4}|\d{2})"#
        if let m = first(worded, in: text), let mi = months.firstIndex(of: String(m[1].prefix(3))), let y = Int(m[3]) {
            return makeDate(year: y, month: mi + 1, day: Int(m[2]) ?? (endOfMonth ? 0 : 1))
        }
        return nil
    }

    /// day 0 = last day of the month.
    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month) else { return nil }
        let y = year < 100 ? 2000 + year : year
        guard (2000...2100).contains(y) else { return nil }
        var c = DateComponents(year: y, month: month, day: max(1, day))
        if day == 0 {
            c.month = month + 1; c.day = 0
            let cal = Calendar(identifier: .gregorian)
            c.day = 1
            guard let first = cal.date(from: c) else { return nil }
            return cal.date(byAdding: .day, value: -1, to: first)
        }
        guard day <= 31 else { return nil }
        return Calendar(identifier: .gregorian).date(from: c)
    }

    // MARK: - Helpers

    /// Returns capture groups (index 0 = whole match). Missing groups are "".
    static func first(_ pattern: String, in text: String) -> [String]? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func titleCase(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { w in
            let small = ["of", "and", "the", "for"]
            return small.contains(String(w)) ? String(w) : w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }

    static func sentenceCase(_ s: String) -> String {
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

enum KnownDrugs {
    /// Common generic names, used to pick out the medication name and to help text recognition.
    static let names: [String] = [
        "ATORVASTATIN", "LISINOPRIL", "LEVOTHYROXINE", "METFORMIN", "AMLODIPINE", "METOPROLOL", "OMEPRAZOLE",
        "SIMVASTATIN", "LOSARTAN", "ALBUTEROL", "GABAPENTIN", "HYDROCHLOROTHIAZIDE", "SERTRALINE", "FUROSEMIDE",
        "ACETAMINOPHEN", "AMOXICILLIN", "ALPRAZOLAM", "ATENOLOL", "CITALOPRAM", "ESCITALOPRAM", "MONTELUKAST",
        "ROSUVASTATIN", "PRAVASTATIN", "TRAMADOL", "BUPROPION", "FLUOXETINE", "TRAZODONE", "CARVEDILOL",
        "PREDNISONE", "PANTOPRAZOLE", "WARFARIN", "CLOPIDOGREL", "IBUPROFEN", "MELOXICAM", "CYCLOBENZAPRINE",
        "ZOLPIDEM", "DULOXETINE", "VENLAFAXINE", "LAMOTRIGINE", "CLONAZEPAM", "LORAZEPAM", "PROPRANOLOL",
        "SPIRONOLACTONE", "GLIPIZIDE", "INSULIN", "TAMSULOSIN", "FINASTERIDE", "DOXYCYCLINE", "AZITHROMYCIN",
        "CEPHALEXIN", "CIPROFLOXACIN", "CETIRIZINE", "LORATADINE", "FAMOTIDINE", "ONDANSETRON", "ESOMEPRAZOLE",
        "ARIPIPRAZOLE", "QUETIAPINE", "RISPERIDONE", "METHYLPHENIDATE", "AMPHETAMINE", "LITHIUM", "TOPIRAMATE",
        "VALSARTAN", "DILTIAZEM", "APIXABAN", "RIVAROXABAN", "SITAGLIPTIN", "EMPAGLIFLOZIN", "ALLOPURINOL",
        "COLCHICINE", "HYDROXYZINE", "BENZONATATE", "NAPROXEN", "OXYCODONE", "HYDROCODONE", "VITAMIN D3",
        "FOLIC ACID", "POTASSIUM CHLORIDE", "ESTRADIOL", "NORETHINDRONE", "SUMATRIPTAN", "BACLOFEN"
    ]
}
