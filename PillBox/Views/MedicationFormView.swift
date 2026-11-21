import SwiftData
import SwiftUI

/// Editable copy of a medication + bottle, filled from a scanned label.
struct MedDraft {
    var name = ""
    var strength = ""
    var form = "tablet"
    var pillsPerDose = 1
    var directions = ""
    var frequency: FrequencyKind = .daily
    var timesPerDay = 1
    var intervalHours = 8
    var minHoursApart = 0
    var dayParts: Set<DayPart> = [.morning]
    var useExactTimes = false
    var exactTimes: [Date] = []
    var everyDay = true
    var weekdays: Set<Int> = []
    var instructions = ""

    var hasExpiration = false
    var expiration = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
    var quantity = 30
    var refills = 0
    var rxNumber = ""
    var pharmacy = ""
    var fillDate: Date?
    var labelText = ""

    var prescriberName = ""
    var found: Set<String> = []

    init(parsed p: ParsedLabel) {
        name = p.name
        strength = p.strength
        form = p.form
        pillsPerDose = p.pillsPerDose
        directions = p.directions
        frequency = p.frequency
        timesPerDay = max(1, p.timesPerDay)
        intervalHours = p.intervalHours > 0 ? p.intervalHours : 8
        minHoursApart = p.minHoursApart
        dayParts = Set(p.dayParts.isEmpty ? [.morning] : p.dayParts)
        everyDay = p.weekdays.isEmpty
        weekdays = Set(p.weekdays)
        instructions = p.instructions.joined(separator: " · ")
        hasExpiration = p.expiration != nil
        if let e = p.expiration { expiration = e }
        quantity = p.quantity ?? 30
        refills = p.refills ?? 0
        rxNumber = p.rxNumber
        pharmacy = p.pharmacy
        fillDate = p.fillDate
        labelText = p.rawText
        prescriberName = p.prescriberName
        found = p.found
        exactTimes = defaultExactTimes()
    }

    init(med: Medication) {
        name = med.name
        strength = med.strength
        form = med.form
        pillsPerDose = med.pillsPerDose
        directions = med.directions
        frequency = med.frequency
        timesPerDay = med.timesPerDay
        intervalHours = med.intervalHours > 0 ? med.intervalHours : 8
        minHoursApart = med.minHoursApart
        dayParts = Set(med.dayParts)
        useExactTimes = !med.customTimes.isEmpty
        exactTimes = Scheduler.times(for: med).map { ClockText.date(Date(), minutes: $0) }
        everyDay = med.weekdays.isEmpty
        weekdays = Set(med.weekdays)
        instructions = med.instructions
        found = ["name", "strength", "dose", "frequency", "expiration"]
    }

    func defaultExactTimes() -> [Date] {
        let parts = DayPart.allCases.filter { dayParts.contains($0) }
        return parts.map { ClockText.date(Date(), minutes: DayPartTimes.minutes(for: $0)) }
    }

    func apply(to med: Medication) {
        med.name = name.trimmingCharacters(in: .whitespaces)
        med.strength = strength.trimmingCharacters(in: .whitespaces)
        med.form = form
        med.pillsPerDose = pillsPerDose
        med.directions = directions
        med.frequency = frequency
        med.timesPerDay = frequency == .everyHours ? max(1, 24 / max(1, intervalHours)) : (useExactTimes ? exactTimes.count : timesPerDay)
        med.intervalHours = frequency == .everyHours ? intervalHours : 0
        med.minHoursApart = frequency == .everyHours ? intervalHours : minHoursApart
        med.dayParts = DayPart.allCases.filter { dayParts.contains($0) }
        med.customTimes = useExactTimes && frequency != .asNeeded ? exactTimes.map { ClockText.minutes(of: $0) }.sorted() : []
        med.weekdays = everyDay ? [] : weekdays.sorted()
        med.instructions = instructions
    }

    /// Preview of the times this draft will remind at.
    var previewTimes: [Int] {
        let m = Medication(name: name, strength: strength)
        apply(to: m)
        return Scheduler.times(for: m)
    }
}

struct MedicationFormView: View {
    enum Mode {
        case new(UIImage?)
        case edit(Medication)
    }

    @State var draft: MedDraft
    let mode: Mode
    var onDone: (() -> Void)? = nil
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meds: [Medication]
    @Query private var prescribers: [Prescriber]
    @State private var addToExisting = true
    @State private var showLabelText = false

    private var isNew: Bool { if case .new = mode { true } else { false } }
    private var labelImage: UIImage? { if case .new(let img) = mode { img } else { nil } }

    private var existingMatch: Medication? {
        guard isNew, !draft.name.isEmpty else { return nil }
        return meds.first {
            $0.name.caseInsensitiveCompare(draft.name) == .orderedSame
                && $0.strength.replacingOccurrences(of: " ", with: "").lowercased() == draft.strength.replacingOccurrences(of: " ", with: "").lowercased()
        }
    }

    var body: some View {
        if embedded { form } else { NavigationStack { form } }
    }

    private var form: some View {
        Form {
            if isNew { scanSummary }

            if let match = existingMatch {
                Section {
                    Toggle(isOn: $addToExisting) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Another bottle of \(match.displayName)").font(.headline)
                            Text("Adds this bottle with its own expiration date and keeps one schedule, so you don't get double reminders.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Medication") {
                field("Name", text: $draft.name, key: "name")
                field("Strength", text: $draft.strength, key: "strength", prompt: "e.g. 10 mg")
                Picker("Form", selection: $draft.form) {
                    ForEach(["tablet", "capsule", "softgel", "mL", "drop", "puff", "patch", "pill"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Stepper("Take \(draft.pillsPerDose) per dose", value: $draft.pillsPerDose, in: 1...10)
                    .listRowBackground(missing("dose"))
            }

            if !(isNew && addToExisting && existingMatch != nil) {
                scheduleSection
            }

            if isNew { bottleSection }

            Section("Notes") {
                TextField("e.g. Take with food", text: $draft.instructions, axis: .vertical)
                if !draft.directions.isEmpty {
                    LabeledContent("From the label") { Text(draft.directions).multilineTextAlignment(.trailing) }
                        .font(.footnote)
                }
            }

            if isNew {
                Section("Prescriber (optional)") {
                    TextField("Doctor's name", text: $draft.prescriberName)
                    if !draft.prescriberName.isEmpty, prescribers.contains(where: { $0.name.caseInsensitiveCompare(draft.prescriberName) == .orderedSame }) {
                        Label("Linked to your saved contact", systemImage: "link").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Check the details" : "Edit \(draft.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).fontWeight(.semibold).disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var scanSummary: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                if let labelImage {
                    Image(uiImage: labelImage).resizable().scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 6) {
                    let keys = ["name", "strength", "dose", "frequency", "expiration"]
                    let got = keys.filter { draft.found.contains($0) }.count
                    Label(got == keys.count ? "Label read" : "Some details need checking",
                          systemImage: got == keys.count ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(got == keys.count ? .green : .orange)
                    Text("Found \(got) of \(keys.count) key details. Compare each one with your label before saving. Fields marked in orange weren't found.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !draft.labelText.isEmpty {
                        Button(showLabelText ? "Hide label text" : "Show label text") { showLabelText.toggle() }.font(.footnote)
                    }
                }
            }
            if showLabelText {
                Text(draft.labelText).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("How often", selection: $draft.frequency) {
                Text("Daily").tag(FrequencyKind.daily)
                Text("Every X hours").tag(FrequencyKind.everyHours)
                Text("As needed").tag(FrequencyKind.asNeeded)
            }
            .pickerStyle(.segmented)
            .listRowBackground(missing("frequency"))

            switch draft.frequency {
            case .daily:
                if !draft.useExactTimes {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parts of the day").font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            ForEach(DayPart.allCases) { part in
                                let on = draft.dayParts.contains(part)
                                Button {
                                    if on { draft.dayParts.remove(part) } else { draft.dayParts.insert(part) }
                                    draft.timesPerDay = max(1, draft.dayParts.count)
                                    draft.exactTimes = draft.defaultExactTimes()
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: part.symbol).font(.title3)
                                        Text(part.title).font(.caption2.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .foregroundStyle(on ? .white : part.color)
                                    .background(on ? part.color : part.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper(draft.minHoursApart == 0 ? "No minimum gap" : "Keep \(draft.minHoursApart) hours apart",
                            value: $draft.minHoursApart, in: 0...24)
                }
                Toggle("Set exact times", isOn: $draft.useExactTimes.animation())
                if draft.useExactTimes {
                    ForEach(draft.exactTimes.indices, id: \.self) { i in
                        DatePicker("Dose \(i + 1)", selection: $draft.exactTimes[i], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { draft.exactTimes.remove(atOffsets: $0) }
                    Button("Add a time") { draft.exactTimes.append(ClockText.date(Date(), minutes: 12 * 60)) }
                }
            case .everyHours:
                Stepper("Every \(draft.intervalHours) hours", value: $draft.intervalHours, in: 2...24)
            case .asNeeded:
                Text("No reminders. It will show under \"As needed\" on the Today screen.").font(.footnote).foregroundStyle(.secondary)
            }

            if draft.frequency != .asNeeded {
                Toggle("Every day", isOn: $draft.everyDay)
                if !draft.everyDay {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = draft.weekdays.contains(d)
                            Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                                if on { draft.weekdays.remove(d) } else { draft.weekdays.insert(d) }
                            }
                            .frame(width: 36, height: 36)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("When to take it")
        } footer: {
            let times = draft.previewTimes
            if !times.isEmpty {
                Text("Reminders at " + times.map { ClockText.format(minutes: $0) }.joined(separator: ", "))
            }
        }
    }

    private var bottleSection: some View {
        Section {
            Toggle("Has an expiration date", isOn: $draft.hasExpiration)
                .listRowBackground(missing("expiration"))
            if draft.hasExpiration {
                DatePicker("Expires", selection: $draft.expiration, displayedComponents: .date)
            }
            Stepper("Pills in bottle: \(draft.quantity)", value: $draft.quantity, in: 0...1000, step: 1)
            Stepper("Refills left: \(draft.refills)", value: $draft.refills, in: 0...20)
            field("Rx number", text: $draft.rxNumber, key: "rx")
            field("Pharmacy", text: $draft.pharmacy, key: "pharmacy")
        } header: {
            Text("This bottle")
        } footer: {
            Text("You'll get warnings 1 month, 2 weeks and 1 week before this bottle expires, and on the day.")
        }
    }

    private func field(_ title: String, text: Binding<String>, key: String, prompt: String? = nil) -> some View {
        LabeledContent(title) {
            TextField(prompt ?? title, text: text).multilineTextAlignment(.trailing)
        }
        .listRowBackground(missing(key))
    }

    private func missing(_ key: String) -> Color? {
        isNew && !draft.found.contains(key) ? Color.orange.opacity(0.14) : nil
    }

    private func save() {
        switch mode {
        case .edit(let med):
            draft.apply(to: med)
        case .new(let image):
            let med: Medication
            if let match = existingMatch, addToExisting {
                med = match
            } else {
                med = Medication(name: draft.name, strength: draft.strength)
                med.colorIndex = meds.count
                draft.apply(to: med)
                context.insert(med)
            }
            let bottle = Bottle()
            bottle.expirationDate = draft.hasExpiration ? draft.expiration : nil
            bottle.quantity = draft.quantity
            bottle.pillsRemaining = draft.quantity
            bottle.refills = draft.refills
            bottle.rxNumber = draft.rxNumber
            bottle.pharmacy = draft.pharmacy
            bottle.fillDate = draft.fillDate
            bottle.labelText = draft.labelText
            bottle.labelImage = image?.jpegData(compressionQuality: 0.6)
            bottle.medication = med
            context.insert(bottle)

            let name = draft.prescriberName.trimmingCharacters(in: .whitespaces)
            if med.prescriber == nil, !name.isEmpty {
                if let existing = prescribers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    med.prescriber = existing
                } else {
                    let p = Prescriber(name: name)
                    context.insert(p)
                    med.prescriber = p
                }
            }
        }
        try? context.save()
        Task { await ReminderService.shared.rescheduleAll(context: context) }
        finish()
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }
}
