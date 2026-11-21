import SwiftData
import SwiftUI

/// The person's own health details for the Info tab. Kept on the phone only, as JSON in UserDefaults.
/// (The name stays in `patientName`, which Settings and the refill message also use.)
struct HealthProfile: Codable, Equatable {
    struct Item: Codable, Hashable, Identifiable {
        var id = UUID()
        var title = ""
        var detail = ""
    }

    static let key = "healthProfile"

    var birthDate: Date?
    var insurancePlan = ""
    var insuranceDetail = ""
    var memberID = ""
    var conditions: [Item] = []
    var allergies: [Item] = []
    var pastMeds: [Item] = []
    var emergencyName = ""
    var emergencyRelation = ""
    var emergencyPhone = ""

    static func decode(_ data: Data) -> HealthProfile {
        (try? JSONDecoder().decode(HealthProfile.self, from: data)) ?? HealthProfile()
    }

    static var current: HealthProfile { decode(UserDefaults.standard.data(forKey: key) ?? Data()) }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func update(_ change: (inout HealthProfile) -> Void) {
        var profile = current
        change(&profile)
        profile.save()
    }

    /// A deleted medication moves to "Past medications".
    static func recordStopped(_ med: Medication, on date: Date = Date()) {
        update { profile in
            profile.pastMeds.removeAll { $0.title == med.displayName }
            profile.pastMeds.insert(Item(title: med.displayName,
                                         detail: "Stopped " + date.formatted(.dateTime.month(.wide).year())), at: 0)
        }
    }
}

/// "07 Info": who the person is, insurance, conditions, allergies, medications, providers,
/// pharmacy and emergency contact, in one scrolling page.
struct InfoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query(sort: \Prescriber.name) private var prescribers: [Prescriber]
    @AppStorage("patientName") private var patientName = ""
    @AppStorage(HealthProfile.key) private var profileData = Data()
    @State private var editing = false
    @State private var selectedMed: Medication?

    private var profile: HealthProfile { HealthProfile.decode(profileData) }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.medsPath) {
            ScrollView {
                VStack(spacing: 20) {
                    meCard
                    insuranceCard
                    InfoCard(title: "Conditions") { itemRows(profile.conditions) }
                        .editable { editing = true }
                    InfoCard(title: "Allergies", outlined: true) { itemRows(profile.allergies, empty: "None added") }
                        .editable { editing = true }
                    medicationsCard
                    InfoCard(title: "Past medications") { itemRows(profile.pastMeds, empty: "None yet") }
                        .editable { editing = true }
                    providersCard
                    pharmacyCard
                    emergencyCard
                    moreCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 20)
            }
            // Keeps scrolled cards from showing behind the clock and battery.
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Medi.screen) }
            .background(Medi.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Medication.self) { MedicationDetailView(med: $0) }
            .navigationDestination(for: Prescriber.self) { PrescriberEditView(prescriber: $0) }
            .navigationDestination(for: PrescriberMessage.self) { PrescriberMessageView(message: $0) }
        }
        .sheet(isPresented: $editing) { ProfileEditView() }
        .fullScreenCover(item: $selectedMed) { med in
            MedDetailCard(med: med)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: Cards

    private var meCard: some View {
        Button { editing = true } label: {
            HStack(spacing: 16) {
                InitialsCircle(name: patientName, size: 72, fontSize: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(patientName.isEmpty ? "Add your name" : patientName)
                        .font(.karla(26, .bold))
                        .foregroundStyle(Medi.ink)
                    Text(profile.birthDate.map { "Born " + $0.formatted(date: .long, time: .omitted) } ?? "Tap to add your details")
                        .font(.karla(18))
                        .foregroundStyle(Medi.inkSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit your details")
    }

    private var insuranceCard: some View {
        let p = profile
        return InfoCard(title: "Insurance") {
            if p.insurancePlan.isEmpty && p.memberID.isEmpty {
                InfoRow(title: "Not added yet", first: true, muted: true)
            }
            if !p.insurancePlan.isEmpty {
                InfoRow(title: p.insurancePlan, detail: p.insuranceDetail, first: true)
            }
            if !p.memberID.isEmpty {
                InfoRow(title: "Member ID", detail: p.memberID, first: p.insurancePlan.isEmpty)
            }
        }
        .editable { editing = true }
    }

    private var medicationsCard: some View {
        InfoCard(title: "Current medications") {
            if meds.isEmpty {
                Button { router.tab = .add } label: {
                    InfoRow(title: "None yet. Tap + to scan a bottle.", first: true, muted: true)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(meds.enumerated()), id: \.element.id) { i, med in
                Button { selectedMed = med } label: {
                    InfoRow(title: med.displayName, detail: Self.medDetail(med), first: i == 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var providersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Providers")
                .font(.karla(24, .bold))
                .foregroundStyle(Medi.ink)
            if prescribers.isEmpty {
                Text("Not added yet")
                    .font(.karla(21, .semibold))
                    .foregroundStyle(Medi.inkSecondary)
            }
            ForEach(prescribers) { p in
                HStack(spacing: 14) {
                    NavigationLink(value: p) {
                        HStack(spacing: 14) {
                            InitialsCircle(name: p.name, size: 52, fontSize: 20)
                            Text(p.name)
                                .font(.karla(21, .semibold))
                                .foregroundStyle(Medi.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let message = PrescriberMessage.suggested(for: p) {
                        Button { router.medsPath.append(message) } label: {
                            HStack(spacing: 8) {
                                Image("icon-msg")
                                Text("Message").font(.karla(17, .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Medi.selected, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Message \(p.name)")
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var pharmacyCard: some View {
        // Every pharmacy on a bottle, the one that fills the most medications first.
        var counts: [String: Int] = [:]
        for med in meds {
            for name in Set(med.activeBottles.map { $0.pharmacy.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        let pharmacies = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return InfoCard(title: "Pharmacy") {
            if pharmacies.isEmpty { InfoRow(title: "Not added yet", first: true, muted: true) }
            ForEach(Array(pharmacies.enumerated()), id: \.element) { i, name in
                InfoRow(title: name, first: i == 0)
            }
        }
    }

    private var emergencyCard: some View {
        let p = profile
        return VStack(alignment: .leading, spacing: 14) {
            Text("Emergency contact")
                .font(.karla(24, .bold))
                .foregroundStyle(Medi.ink)
            Button { editing = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.emergencyName.isEmpty ? "Not added yet" : p.emergencyName)
                        .font(.karla(21, .semibold))
                        .foregroundStyle(p.emergencyName.isEmpty ? Medi.inkSecondary : Medi.ink)
                    if !p.emergencyRelation.isEmpty {
                        Text(p.emergencyRelation).font(.karla(17)).foregroundStyle(Medi.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your emergency contact")

            let digits = p.emergencyPhone.filter { "0123456789+".contains($0) }
            Button {
                if digits.isEmpty { editing = true } else if let url = URL(string: "tel:\(digits)") { openURL(url) }
            } label: {
                HStack(spacing: 10) {
                    if !digits.isEmpty { Image("icon-phone") }
                    Text(digits.isEmpty ? "Add a contact" : "Call").font(.karla(22, .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Medi.selected, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(digits.isEmpty ? "Add an emergency contact" : "Call \(p.emergencyName)")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Not in the Figma frame: the old Info tab's settings and alerts need a home.
    private var moreCard: some View {
        InfoCard(title: "More") {
            Button { editing = true } label: { InfoRow(title: "Edit my info", first: true, chevron: true) }
            Button {
                let p = Prescriber(name: "New provider")
                context.insert(p)
                router.medsPath.append(p)
            } label: { InfoRow(title: "Add a provider", chevron: true) }
            Button { router.showAlerts = true } label: { InfoRow(title: "Alerts", chevron: true) }
            Button { router.showSettings = true } label: { InfoRow(title: "Settings", chevron: true) }
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    @ViewBuilder private func itemRows(_ items: [HealthProfile.Item], empty: String = "Not added yet") -> some View {
        if items.isEmpty { InfoRow(title: empty, first: true, muted: true) }
        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            InfoRow(title: item.title, detail: item.detail, first: i == 0)
        }
    }

    /// "1 tablet, take with food"
    static func medDetail(_ med: Medication) -> String {
        let notes = med.instructions
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).lowercased() + $0.dropFirst() }
        return ([med.doseText] + notes).joined(separator: ", ")
    }
}

/// A white Info section: a bold title over rows split by thin lines. Allergies get a black outline.
private struct InfoCard<Content: View>: View {
    let title: String
    var outlined = false
    @ViewBuilder var content: Content

    var body: some View {
        let border: CGFloat = outlined ? 2.5 : 0
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.karla(24, .bold))
                .foregroundStyle(Medi.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.top, 20 + border)
        .padding(.horizontal, 20 + border)
        .padding(.bottom, 8 + border)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if outlined {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Medi.ink, lineWidth: border)
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    var detail = ""
    var first = false
    var muted = false
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.karla(21, .semibold))
                    .foregroundStyle(muted ? Medi.inkSecondary : Medi.ink)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.karla(17))
                        .foregroundStyle(Medi.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Medi.inkSecondary)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color(hex: 0xE0E0E0)).frame(height: 1.5) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The whole card opens the editor (buttons inside it still work on their own).
    func editable(_ action: @escaping () -> Void) -> some View {
        contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit")
    }
}

/// White initials on a dark circle ("JR", "SC" for Dr. Sarah Chen).
struct InitialsCircle: View {
    let name: String
    let size: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Group {
            let letters = Self.initials(name)
            if letters.isEmpty {
                Image(systemName: "person.fill").font(.system(size: fontSize))
            } else {
                Text(letters).font(.karla(fontSize, .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Medi.selected, in: Circle())
        .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "Dr.", with: "")
            .split(separator: " ")
            .filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return "" }
        let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
        return (String(first) + last).uppercased()
    }
}

/// Edits everything on the Info tab that isn't a medication or a provider.
struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("patientName") private var patientName = ""
    @State private var name = ""
    @State private var draft = HealthProfile()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name).textContentType(.name)
                    Toggle("Birthday", isOn: hasBirthday)
                    if draft.birthDate != nil {
                        DatePicker("Born", selection: birthday, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section("Insurance") {
                    TextField("Plan, for example Medicare", text: $draft.insurancePlan)
                    TextField("Coverage, for example Part A and Part B", text: $draft.insuranceDetail)
                    TextField("Member ID", text: $draft.memberID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                itemSection("Conditions", items: $draft.conditions, titleHint: "Condition",
                            detailHint: "Note (optional)", add: "Add a condition")
                itemSection("Allergies", items: $draft.allergies, titleHint: "Allergy",
                            detailHint: "Reaction (optional)", add: "Add an allergy")
                itemSection("Past medications", items: $draft.pastMeds, titleHint: "Medication",
                            detailHint: "When you stopped (optional)", add: "Add a past medication")
                Section("Emergency contact") {
                    TextField("Name", text: $draft.emergencyName)
                    TextField("Relationship, for example Son", text: $draft.emergencyRelation)
                    TextField("Phone", text: $draft.emergencyPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }
            .navigationTitle("My info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .onAppear {
            guard !loaded else { return }
            name = patientName
            draft = .current
            loaded = true
        }
    }

    private static let defaultBirthday = Calendar.current.date(from: DateComponents(year: 1950, month: 1, day: 1)) ?? Date()

    private var hasBirthday: Binding<Bool> {
        Binding(get: { draft.birthDate != nil },
                set: { draft.birthDate = $0 ? (draft.birthDate ?? Self.defaultBirthday) : nil })
    }

    private var birthday: Binding<Date> {
        Binding(get: { draft.birthDate ?? Self.defaultBirthday }, set: { draft.birthDate = $0 })
    }

    private func itemSection(_ title: String, items: Binding<[HealthProfile.Item]>, titleHint: String,
                             detailHint: String, add: String) -> some View {
        Section(title) {
            ForEach(items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField(titleHint, text: $item.title).font(.headline)
                    TextField(detailHint, text: $item.detail).foregroundStyle(.secondary)
                }
            }
            .onDelete { items.wrappedValue.remove(atOffsets: $0) }
            Button { items.wrappedValue.append(HealthProfile.Item()) } label: {
                Label(add, systemImage: "plus.circle.fill")
            }
        }
    }

    private func save() {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func clean(_ list: [HealthProfile.Item]) -> [HealthProfile.Item] {
            list.map { item in
                var item = item
                item.title = clean(item.title)
                item.detail = clean(item.detail)
                return item
            }
            .filter { !$0.title.isEmpty }
        }
        var p = draft
        p.insurancePlan = clean(p.insurancePlan)
        p.insuranceDetail = clean(p.insuranceDetail)
        p.memberID = clean(p.memberID)
        p.conditions = clean(p.conditions)
        p.allergies = clean(p.allergies)
        p.pastMeds = clean(p.pastMeds)
        p.emergencyName = clean(p.emergencyName)
        p.emergencyRelation = clean(p.emergencyRelation)
        p.emergencyPhone = clean(p.emergencyPhone)
        p.save()
        patientName = clean(name)
        dismiss()
    }
}

extension PrescriberMessage {
    /// The most useful message to send about a medication: expired, expiring, running low, or a plain refill.
    static func suggested(for med: Medication) -> PrescriberMessage {
        let expiry = med.activeBottles.first?.expirationDate ?? med.bottles.compactMap(\.expirationDate).max()
        let level = ExpiryLevel.level(for: expiry)
        let reason: Reason
        if level == .expired { reason = .expired }
        else if level.isWarning { reason = .expiring }
        else if let days = Scheduler.daysLeft(med), days <= 7 { reason = .runningLow }
        else { reason = .refill }
        return PrescriberMessage(medicationID: med.id, reason: reason)
    }

    /// For a provider: the message about whichever of their medications needs it most.
    static func suggested(for prescriber: Prescriber) -> PrescriberMessage? {
        let order: [Reason] = [.expired, .expiring, .runningLow, .refill]
        return prescriber.medications
            .sorted { $0.name < $1.name }
            .map { suggested(for: $0) }
            .min { order.firstIndex(of: $0.reason)! < order.firstIndex(of: $1.reason)! }
    }
}
