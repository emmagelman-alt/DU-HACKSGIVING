import Foundation
import SwiftData
import SwiftUI

enum AppModel {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([Medication.self, Bottle.self, Prescriber.self, DoseLog.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemory")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open the PillBox database: \(error)")
        }
    }()

    static var launchScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum AppTab: Hashable { case today, pillBox, meds, alerts }

/// App-wide navigation state, so alarms and notifications can open the right screen.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .today
    /// The dose time shown full-screen on the "Take your meds" screen.
    var activeSlotKey: String?
    var showSnoozeOnOpen = false
    var showScanner = false
    var showSettings = false
    /// Sample label to read automatically when the scanner opens (demo and screenshots).
    var scanDemoAsset: String?
    var medsPath = NavigationPath()

    func openTakeScreen(slotKey: String, snooze: Bool = false) {
        showSnoozeOnOpen = snooze
        activeSlotKey = slotKey
    }
}

/// Shared actions used by screens, alarms and notifications.
@MainActor
enum DoseActions {
    static func markTaken(slotKey: String, context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<DoseLog>(predicate: #Predicate { $0.slotKey == slotKey }))) ?? []
        guard existing.isEmpty else { return }
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var ids: [UUID] = []
        if let (day, minutes) = Scheduler.parse(key: slotKey),
           let slot = Scheduler.slots(on: day, meds: meds).first(where: { $0.minutes == minutes }) {
            for med in slot.meds {
                ids.append(med.id)
                // Count pills down from the bottle that expires first.
                var toTake = med.pillsPerDose
                for bottle in med.activeBottles where toTake > 0 {
                    let used = min(toTake, bottle.pillsRemaining)
                    bottle.pillsRemaining -= used
                    toTake -= used
                }
            }
        }
        context.insert(DoseLog(slotKey: slotKey, medicationIDs: ids))
        SnoozeStore.set(slotKey, until: nil)
        try? context.save()
        ReminderService.shared.cancelReminders(for: slotKey)
        if AppRouter.shared.activeSlotKey == slotKey { AppRouter.shared.activeSlotKey = nil }
    }

    static func snooze(slotKey: String, until date: Date, context: ModelContext) {
        SnoozeStore.set(slotKey, until: date)
        Task { await ReminderService.shared.rescheduleAll(context: context) }
        if AppRouter.shared.activeSlotKey == slotKey { AppRouter.shared.activeSlotKey = nil }
    }

    static func slot(for key: String, context: ModelContext) -> DoseSlot? {
        guard let (day, minutes) = Scheduler.parse(key: key) else { return nil }
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let slots = Scheduler.slots(on: day, meds: meds)
        if let exact = slots.first(where: { $0.minutes == minutes }) { return exact }
        // A test reminder at an unusual time: show that part of the day's meds.
        let part = DayPart.containing(minutes: minutes)
        let partMeds = slots.filter { $0.dayPart == part }.flatMap(\.meds)
        let chosen = partMeds.isEmpty ? Array(meds.prefix(2)) : partMeds
        return chosen.isEmpty ? nil : DoseSlot(day: day, minutes: minutes, meds: chosen)
    }
}
