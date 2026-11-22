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
        if let name = prescriber(in: upper, lines: upperLines) {
            r.prescriberName = name
            r.found.insert("prescriber")
        }
        // Pharmacy
        let chains = ["CVS", "WALGREENS", "RITE AID", "WALMART", "KROGER", "TARGET", "COSTCO", "PUBLIX", "SAFEWAY", "GIANT EAGLE"]
        if let i = upperLines.firstIndex(where: { l in l.contains("PHARMACY") || chains.contains(where: { l.contains($0) }) }) {
            r.pharmacy = titleCase(lines[i]); r.found.insert("pharmacy")
        }

        // Directions: the "TAKE ..." sentence, which can wrap over a few lines. The camera sometimes joins
        // it to the line beside it ("TAB CHEW 2 TABLETS BY"), so the verb can also start partway along.
        if let directions = findDirections(upperLines) {
            r.directions = sentenceCase(directions)
            r.found.insert("directions")
        }
        // The dose and the times come from the directions only. Without them, only lines that talk about
        // dosing count, so a stray "night" elsewhere in view can't add a reminder.
        let dir = r.directions.isEmpty
            ? upperLines.filter { has(dosingWords, $0) && !has(#"\b(MAX(IMUM)?|DOSE)\b"#, $0) }.joined(separator: " ")
            : r.directions.uppercased()
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
        l.range(of: #"^(RX|QTY|QUANTITY|REFILL|EXP|DISCARD|USE BY|USE BEFORE|DR\.?\s|DOCTOR|PRESCRIB|PRE?SC?R?I?BE?R\b|PRES(C|CR)?\s*[.:]|PHYSICIAN|PROVIDER|DATE|FILLED|ORIG|MFG|NDC|PHARMACY|CAUTION|WARNING|DESCRIPTION|IMPRINT|PATIENT)"#, options: .regularExpression) != nil
            || l.range(of: #"\d+(\.\d+)?\s*(MG|MCG|IU)\b"#, options: .regularExpression) != nil && !l.hasPrefix("TAKE")
    }

    private static let verbs = "TAKE|GIVE|USE|APPLY|INHALE|PLACE|INSTILL|CHEW|DISSOLVE|INJECT|SPRAY|INSERT"
    private static let dosingWords = #"\b(BY MOUTH|ONCE|TWICE|DAILY|TIMES|EVERY|HOURS?|AS NEEDED|BEDTIME|AT NIGHT|NIGHTLY|IN THE MORNING|IN THE EVENING|EACH DAY|PER DAY|WEEKLY)\b"#

    /// "CHEW 2 TABLETS BY / MOUTH ONCE DAILY IN / THE MORNING. MAX / DAILY DOSE: 2" →
    /// "CHEW 2 TABLETS BY MOUTH ONCE DAILY IN THE MORNING." (the maximum is a limit, not a dose).
    static func findDirections(_ upperLines: [String]) -> String? {
        let atStart = "^(\(verbs))\\b"
        let inside = "\\b(\(verbs))\\s+(\\d|ONE|TWO|THREE|FOUR|HALF|A|AN|AS|BY|EVERY|IN|INTO|ON)\\b"
        var start: (line: Int, text: String)?
        if let i = upperLines.firstIndex(where: { has(atStart, $0) }) {
            start = (i, upperLines[i])
        } else if let i = upperLines.firstIndex(where: { has(inside, $0) }),
                  let m = regex(inside)?.firstMatch(in: upperLines[i], range: NSRange(upperLines[i].startIndex..., in: upperLines[i])),
                  let range = Range(m.range, in: upperLines[i]) {
            start = (i, String(upperLines[i][range.lowerBound...]))
        }
        guard let start else { return nil }
        var parts = [start.text]
        var i = start.line + 1
        while i < upperLines.count, parts.count < 4, !isFieldLine(upperLines[i]) {
            parts.append(upperLines[i]); i += 1
        }
        let text = parts.joined(separator: " ")
            .replacingOccurrences(of: #"\s*\b(MAX(IMUM)?|DO NOT EXCEED|NOT TO EXCEED)\b.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return text.count >= 6 ? text : nil
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
        if dir.range(of: #"\b(BEDTIME|AT NIGHT|NIGHTLY|EVERY NIGHT|QHS|AT HOUR OF SLEEP)\b"#, options: .regularExpression) != nil { parts.append(.night) }
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

    // MARK: Prescriber

    /// The word printed before the prescriber's name. Pharmacies shorten it in many ways:
    /// PRESCRIBER, PRSCRBR, PRSCBR, PRESCRBR, PRESCR:, PRES:, PRESCRIBED BY, DOCTOR:, PHYSICIAN:, PROVIDER:.
    /// The name may be on the same line or the next one.
    private static let prescriberLabel =
        #"(?:\bPRESCRIBED\s+BY|\bPRESCRIBING\s+(?:DR|DOCTOR|PHYSICIAN|PROVIDER)|\bPRE?SC?R?I?BE?R\b|\bPRE?S(?:CR?)?(?=\s*[.:#])|\b(?:DOCTOR|PHYSICIAN|PROVIDER)(?=\s*:))[\s.:;#\-]*(?:DR\.?\s+)?([A-Z][A-Z.,'\- ]{1,48})"#

    /// "DR. SMITH" or "DR JOHN SMITH": the name must be on the same line, so a street ("OAK DR")
    /// never picks up the line after it.
    private static let doctorPrefix = #"\bDR(?:[.:][ \t]*|[ \t]+)([A-Z][A-Z.,'\- ]{1,48})"#

    /// A line that is only a first and last name and a credential: "JOHN SMITH, MD".
    /// (A bare "PA" isn't enough here: "PITTSBURGH, PA" is a city.)
    private static let nameWithCredential = #"^[A-Z][A-Z.'\-]*,?\s+[A-Z][A-Z.,'\- ]{1,36}?,?\s+(?:M\.?D|D\.?O|NP|FNP|APRN|CNP|PA-C)\.?$"#

    /// Doctors get "Dr."; nurse practitioners and physician assistants keep their credential instead.
    private static let credentialRx = #",?\s+(M\.?D|D\.?O|DDS|DMD|DPM|OD|NP|FNP|APRN|CNP|PA-?C?)\.?$"#
    private static let nonDoctorCredentials: Set<String> = ["NP", "FNP", "APRN", "CNP", "PA", "PA-C", "PAC"]

    static func prescriber(in upper: String, lines upperLines: [String]) -> String? {
        for pattern in [prescriberLabel, doctorPrefix] {
            for m in matches(pattern, in: upper) {
                if let name = prescriberName(m[1]) { return name }
            }
        }
        for line in upperLines where first(nameWithCredential, in: line) != nil {
            if let name = prescriberName(line) { return name }
        }
        return nil
    }

    /// "SMITH, JOHN MD   QTY: 30" → "Dr. John Smith"; "LEE, KIM NP" → "Kim Lee, NP"; anything that isn't a name → nil.
    private static func prescriberName(_ raw: String) -> String? {
        // Stop at another field printed on the same line, or a run of spaces between columns.
        var s = raw.replacingOccurrences(of: #"(\s{3,}|\s+\b(QTY|QUANTITY|REFILLS?|RX|DATE|FILLED|EXP|NDC|MFG|ORIG|DISCARD|PH|PHONE|TEL|FAX|NPI|DEA|DAW)\b).*$"#,
                                         with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",;:-")))
        s = s.replacingOccurrences(of: #"^DR\.?\s+"#, with: "", options: .regularExpression)
        var credential = ""
        if let m = first(credentialRx, in: s) {
            credential = m[1].replacingOccurrences(of: ".", with: "")
            s = s.replacingOccurrences(of: credentialRx, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
        }
        // "SMITH, JOHN A" → "JOHN A SMITH"
        if let comma = s.firstIndex(of: ",") {
            let last = s[..<comma].trimmingCharacters(in: .whitespaces)
            let rest = s[s.index(after: comma)...].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
            guard !rest.contains(",") else { return nil }
            s = rest.isEmpty ? last : rest + " " + last
        }
        let words = s.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".'-")) }
        guard (1...4).contains(words.count), s.count <= 40,
              words.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || "'-.".contains($0) } }),   // O'BRIEN, SMITH-JONES
              words.contains(where: { $0.count >= 2 }),
              // Single letters are initials ("MARIA A GARCIA"), even though "A" is a word on labels.
              !words.contains(where: { $0.count > 1 && (notNameWords.contains($0) || prescriberNotNameWords.contains($0)) })
        else { return nil }
        let name = titleCase(s)
        if nonDoctorCredentials.contains(credential) {
            return name + ", " + (credential == "PAC" ? "PA-C" : credential)
        }
        return "Dr. " + name
    }

    /// Words from warnings that can follow "DOCTOR" or "PRESCRIBER" but are never a name.
    private static let prescriberNotNameWords: Set<String> = [
        "IF", "YOU", "YOUR", "IS", "ARE", "BE", "HAVE", "HAS", "PLEASE", "ASK", "TELL", "CONTACT", "INFORMATION",
        "INSTRUCTIONS", "DIRECTED", "ORDERS", "OFFICE", "SIGNATURE", "INITIALS", "USE"
    ]

    /// The prescriber's name without "Dr." or a credential, for comparing with the patient's name.
    private static func bareName(_ prescriber: String) -> String {
        prescriber.replacingOccurrences(of: #"^Dr\.\s+|,\s+[A-Z\-]+$"#, with: "", options: .regularExpression)
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
              name.caseInsensitiveCompare(bareName(r.prescriberName)) != .orderedSame else { return }
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
              !KnownDrugs.containsExact(s) else { return nil }
        if let comma = s.firstIndex(of: ",") {
            let last = s[..<comma].trimmingCharacters(in: .whitespaces)
            let rest = s[s.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            s = rest + " " + last
        }
        return titleCase(s)
    }

    // MARK: Name and strength

    private static let strengthRx = #"(\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?)\s*(MG|MCG|GM|G|ML|%|UNITS?|IU)\b"#

    /// Words printed beside a drug's strength: its form and release type.
    private static let formWords = #"\b(TABS?|TABLETS?|CAPS?|CAPSULES?|CHEW|CHEWABLE|ER|XR|XL|SR|CR|LA|ODT|EC|EXTENDED|DELAYED|RELEASE|ORAL|SUSP(ENSION)?|SOLUTION|SOLN|SYRUP|LIQUID|INHALER|CREAM|OINTMENT|PATCH|SOFTGELS?|GELCAPS?|DROPS|INJ(ECTION)?|PEN|HCL)\b"#

    /// Lines that are never the drug line: directions, counts, dates, limits and warnings.
    private static let notDrugLine = #"^(TAKE|GIVE|USE|APPLY|INHALE|PLACE|INSTILL|CHEW|DISSOLVE|INJECT|SPRAY|INSERT|QTY|QUANTITY|RX|REFILLS?|DATE|FILLED|EXP|DISCARD|NDC|MFG)\b|\b(BY MOUTH|DAILY|MAX(IMUM)?|DOSE|DO NOT|AVOID|WARNING|CAUTION|MAY CAUSE|IF YOU|CALL|ASK|TIMES|EVERY|HOURS)\b"#

    /// "30 MG" → ("30", "mg", strong). Grams count for little on their own: a stray "8 G" in view is
    /// far more often noise than a dose.
    private static func strength(in line: String) -> (amount: String, unit: String, strong: Bool)? {
        guard let m = first(strengthRx, in: line) else { return nil }
        let unit: String
        switch m[2] {
        case "MG", "MCG": unit = m[2].lowercased()
        case "G", "GM": unit = "g"
        case "ML": unit = "mL"
        default: unit = m[2]
        }
        return (m[1].replacingOccurrences(of: " ", with: ""), unit, unit != "g")
    }

    /// Picks the drug line by score rather than taking the first line with a number, so text read from
    /// behind the bottle can't win: a real unit (mg, mcg, mL) counts most, then a form word on or under
    /// it ("CHEW TAB"), then a known drug name on it or the line above.
    /// Returns the index of the line with the drug name, if one was found.
    @discardableResult
    private static func parseNameAndStrength(lines: [String], upperLines: [String], into r: inout ParsedLabel) -> Int? {
        let usable = upperLines.map { !has(notDrugLine, $0) }
        let known = upperLines.indices.map { usable[$0] ? KnownDrugs.match(in: upperLines[$0]) : nil }
        let strengths = upperLines.indices.map { usable[$0] ? strength(in: upperLines[$0]) : nil }

        var best: (line: Int, score: Int)?
        for i in upperLines.indices {
            guard let s = strengths[i] else { continue }
            var score = s.strong ? 4 : 1
            let formBelow = i + 1 < upperLines.count && usable[i + 1] && has(formWords, upperLines[i + 1])
            if has(formWords, upperLines[i]) || formBelow { score += 2 }
            if known[i] != nil || (i > 0 && known[i - 1] != nil) { score += 4 }
            if score >= 3, score > (best?.score ?? 0) { best = (i, score) }
        }

        var nameLine: Int?
        if let b = best, let s = strengths[b.line] {
            r.strength = "\(s.amount) \(s.unit)"
            r.found.insert("strength")
            if let k = known[b.line] {
                r.name = k.name; nameLine = b.line
            } else if b.line > 0, let k = known[b.line - 1] {
                r.name = k.name; nameLine = b.line - 1
            } else {
                // Words before the strength ("LISINOPRIL 10 MG TABLET"), or the line above when the
                // strength starts its own line ("QUILLICHEW ER" / "30 MG CHEW").
                let before = cleanDrugName(upperLines[b.line].components(separatedBy: .decimalDigits).first ?? "")
                if before.count >= 3 {
                    r.name = drugCase(before); nameLine = b.line
                } else if b.line > 0, usable[b.line - 1], !isFieldLine(upperLines[b.line - 1]) {
                    let above = cleanDrugName(upperLines[b.line - 1])
                    if above.count >= 3, above.split(separator: " ").count <= 4 {
                        r.name = drugCase(above); nameLine = b.line - 1
                    }
                }
            }
        } else if let i = known.firstIndex(where: { $0 != nil }), let k = known[i] {
            // A known name with no believable strength in view yet.
            r.name = k.name; nameLine = i
        }
        if !r.name.isEmpty { r.found.insert("name") }
        if let line = best.map({ upperLines[$0.line] }), !r.found.contains("dose") {
            if has(#"\bCAP(SULE)?S?\b"#, line) { r.form = "capsule" }
            if has(#"\bTAB(LET)?S?\b"#, line) { r.form = "tablet" }
        }
        return nameLine
    }

    /// "SERTRALINE HCL TABLET" → "SERTRALINE"; release words like ER stay, since they name the product.
    private static func cleanDrugName(_ s: String) -> String {
        s.replacingOccurrences(of: #"\b(TABLETS?|TABS?|CAPSULES?|CAPS?|ORAL|HCL|CHEWABLE|CHEW|SOLUTION|SUSPENSION)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^A-Z\- ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-")))
    }

    /// "QUILLICHEW ER" → "Quillichew ER": title case, with release words kept in capitals.
    static func drugCase(_ s: String) -> String {
        titleCase(s).split(separator: " ").map { w in
            KnownDrugs.suffixes.contains(w.uppercased()) ? w.uppercased() : String(w)
        }.joined(separator: " ")
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

    /// Compiled patterns, kept because the camera parses several times a second.
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]
    private static let compiledLock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression? {
        compiledLock.lock()
        defer { compiledLock.unlock() }
        if let rx = compiled[pattern] { return rx }
        let rx = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        compiled[pattern] = rx
        return rx
    }

    static func has(_ pattern: String, _ text: String) -> Bool {
        regex(pattern)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Returns capture groups (index 0 = whole match). Missing groups are "".
    static func first(_ pattern: String, in text: String) -> [String]? {
        guard let rx = regex(pattern),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// Every match of `pattern`, each as [whole match, group 1, ...].
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let rx = regex(pattern) else { return [] }
        return rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    /// "SMITH-JONES" → "Smith-Jones", "O'BRIEN" → "O'Brien" (but "WALGREEN'S" → "Walgreen's").
    static func titleCase(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { w in
            let small = ["of", "and", "the", "for"]
            if small.contains(String(w)) { return String(w) }
            var out = ""
            var upNext = true
            for (i, c) in w.enumerated() {
                out += upNext ? c.uppercased() : String(c)
                upNext = c == "-" || (c == "'" && i == 1)
            }
            return out
        }.joined(separator: " ")
    }

    static func sentenceCase(_ s: String) -> String {
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
