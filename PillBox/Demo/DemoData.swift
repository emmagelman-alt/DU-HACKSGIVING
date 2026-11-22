import SwiftData
import UIKit

/// Demo medications for showing the app. Dates are relative to today so warnings always appear.
@MainActor
enum DemoData {
    static var sampleLabels: [SampleLabel] { SampleLabel.all }

    static func wipe(_ context: ModelContext) {
        try? context.delete(model: DoseLog.self)
        try? context.delete(model: Bottle.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: Prescriber.self)
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "snoozes")
        UserDefaults.standard.removeObject(forKey: HealthProfile.key)
    }

    static func seed(into context: ModelContext) {
        wipe(context)
        UserDefaults.standard.set("Jordan Rivera", forKey: "patientName")
        typealias Item = HealthProfile.Item
        HealthProfile(
            birthDate: Calendar.current.date(from: DateComponents(year: 1948, month: 3, day: 4)),
            insurancePlan: "Medicare",
            insuranceDetail: "Part A and Part B",
            memberID: "1EG4-TE5-MK72",
            conditions: [Item(title: "Type 2 diabetes"), Item(title: "High cholesterol"), Item(title: "High blood pressure")],
            allergies: [Item(title: "Sulfa drugs", detail: "Rash and swelling")],
            pastMeds: [Item(title: "Simvastatin 20 mg", detail: "Stopped 2024")]
        ).save()
        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }

        let chen = Prescriber(name: "Dr. Sarah Chen")
        chen.practice = "Riverside Family Medicine"
        chen.phone = "(412) 555-0186"
        chen.email = "schen@riversidefm.example"
        let patel = Prescriber(name: "Dr. Marcus Patel")
        patel.practice = "Allegheny Endocrine Associates"
        patel.phone = "(412) 555-0123"
        patel.email = "mpatel@alleghenyendo.example"
        context.insert(chen)
        context.insert(patel)

        func bottle(_ med: Medication, asset: String, rx: String, exp: Date, qty: Int, left: Int, refills: Int, pharmacy: String = "Main Street Pharmacy") {
            let b = Bottle()
            b.expirationDate = exp
            b.quantity = qty
            b.pillsRemaining = left
            b.refills = refills
            b.rxNumber = rx
            b.pharmacy = pharmacy
            b.labelImage = UIImage(named: asset)?.jpegData(compressionQuality: 0.7)
            b.labelText = SampleLabel.all.first { $0.asset == asset }?.fullText.joined(separator: "\n") ?? ""
            b.medication = med
            context.insert(b)
        }

        let lisinopril = Medication(name: "Lisinopril", strength: "10 mg")
        lisinopril.directions = "Take one tablet by mouth once daily in the morning"
        lisinopril.dayParts = [.morning]
        lisinopril.colorIndex = 0
        lisinopril.pillShape = "round"; lisinopril.pillScored = true; lisinopril.pillImprint = "10"; lisinopril.pillColor = "pink"
        lisinopril.prescriber = chen
        context.insert(lisinopril)
        bottle(lisinopril, asset: "label-lisinopril", rx: "6043921", exp: day(25), qty: 30, left: 22, refills: 2)

        let metformin = Medication(name: "Metformin", strength: "500 mg")
        metformin.directions = "Take 1 tablet by mouth twice daily with meals"
        metformin.timesPerDay = 2
        metformin.dayParts = [.morning, .evening]
        metformin.instructions = "Take with food"
        metformin.colorIndex = 1
        metformin.pillShape = "oblong"; metformin.pillImprint = "500"; metformin.pillColor = "white"
        metformin.prescriber = patel
        context.insert(metformin)
        bottle(metformin, asset: "label-metformin-a", rx: "6043977", exp: day(5), qty: 60, left: 8, refills: 0)
        bottle(metformin, asset: "label-metformin-b", rx: "6051140", exp: day(310), qty: 60, left: 60, refills: 5)

        let amoxicillin = Medication(name: "Amoxicillin", strength: "500 mg")
        amoxicillin.form = "capsule"
        amoxicillin.directions = "Take 1 capsule by mouth every 8 hours until all gone"
        amoxicillin.frequency = .everyHours
        amoxicillin.intervalHours = 8
        amoxicillin.minHoursApart = 8
        amoxicillin.timesPerDay = 3
        amoxicillin.dayParts = []
        amoxicillin.colorIndex = 2
        amoxicillin.pillShape = "capsule"; amoxicillin.pillColor = "pink and red"
        amoxicillin.prescriber = chen
        context.insert(amoxicillin)
        bottle(amoxicillin, asset: "label-amoxicillin", rx: "7781204", exp: day(12), qty: 30, left: 24, refills: 0, pharmacy: "Corner Drug Pharmacy")

        let atorvastatin = Medication(name: "Atorvastatin", strength: "20 mg")
        atorvastatin.directions = "Take one tablet by mouth at bedtime"
        atorvastatin.dayParts = [.night]
        atorvastatin.instructions = "Avoid grapefruit"
        atorvastatin.colorIndex = 4
        atorvastatin.pillShape = "oval"; atorvastatin.pillImprint = "20"; atorvastatin.pillColor = "white"
        atorvastatin.prescriber = chen
        context.insert(atorvastatin)
        bottle(atorvastatin, asset: "label-atorvastatin", rx: "5998310", exp: day(-3), qty: 90, left: 6, refills: 1)

        let vitaminD = Medication(name: "Vitamin D3", strength: "1000 IU")
        vitaminD.form = "softgel"
        vitaminD.directions = "Take 1 softgel by mouth daily with food"
        vitaminD.customTimes = [9 * 60 + 15]   // an exact time the person chose
        vitaminD.instructions = "Take with food"
        vitaminD.colorIndex = 3
        vitaminD.pillShape = "softgel"; vitaminD.pillColor = "yellow"
        vitaminD.prescriber = chen
        context.insert(vitaminD)
        bottle(vitaminD, asset: "label-vitamind", rx: "6012255", exp: day(480), qty: 120, left: 74, refills: 3)

        try? context.save()

        // History: every dose up to now was taken, except one missed dose three nights ago.
        let meds = [lisinopril, metformin, amoxicillin, atorvastatin, vitaminD]
        let now = Date()
        for offset in -6...0 {
            for slot in Scheduler.slots(on: day(offset), meds: meds) where slot.date < now.addingTimeInterval(-15 * 60) {
                if offset == -3 && slot.dayPart == .night && slot.meds.contains(where: { $0 === atorvastatin }) { continue }
                context.insert(DoseLog(slotKey: slot.key, medicationIDs: slot.meds.map(\.id),
                                       takenAt: slot.date.addingTimeInterval(Double.random(in: 60...900))))
            }
        }
        try? context.save()
    }
}

/// Opens a specific screen at launch (`-screen <name>`), used to take screenshots for design work.
@MainActor
enum ScreenRoutes {
    static func apply(_ screen: String?, context: ModelContext) {
        guard let screen else { return }
        let router = AppRouter.shared
        let meds = (try? context.fetch(FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let prescribers = (try? context.fetch(FetchDescriptor<Prescriber>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let nextSlot = Scheduler.slots(on: Date(), meds: meds).first { Scheduler.status(of: $0, logs: logs) != .missed && !isTaken($0, logs) }
            ?? Scheduler.slots(on: Date().addingTimeInterval(86_400), meds: meds).first

        switch screen {
        case "pillbox": router.tab = .pillBox
        case "meds": router.tab = .meds
        case "med":
            router.tab = .meds
            if let m = meds.first(where: { $0.name == "Metformin" }) { router.medsPath.append(m) }
        case "prescriber":
            router.tab = .meds
            if let p = prescribers.first(where: { $0.name.contains("Chen") }) { router.medsPath.append(p) }
        case "message":
            router.tab = .meds
            if let m = meds.first(where: { $0.name == "Atorvastatin" }) {
                router.medsPath.append(m)
                router.medsPath.append(PrescriberMessage(medicationID: m.id, reason: .expired))
            }
        case "alerts": router.showAlerts = true
        case "scan": router.showScanner = true
        case "review":
            router.scanDemoAsset = "label-levothyroxine"
            router.showScanner = true
        case "take": if let s = nextSlot { router.openTakeScreen(slotKey: s.key) }
        case "snooze": if let s = nextSlot { router.openTakeScreen(slotKey: s.key, snooze: true) }
        case "settings": router.showSettings = true
        case "empty": DemoData.wipe(context)
        default: break
        }
    }

    private static func isTaken(_ slot: DoseSlot, _ logs: [DoseLog]) -> Bool {
        if case .taken = Scheduler.status(of: slot, logs: logs) { return true }
        return false
    }
}
