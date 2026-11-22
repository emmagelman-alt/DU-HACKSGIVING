import AlarmKit
import AppIntents
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

struct DoseAlarmMetadata: AlarmMetadata {
    var slotKey: String
}

/// Schedules the reminders:
/// - an AlarmKit alarm at each dose time (fills the Lock Screen, rings through Silent, shows on Apple Watch)
/// - backup notifications every few minutes afterwards until the dose is confirmed
/// - expiration warnings 30, 14 and 7 days before, and on the day
@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()

    static let doseCategory = "DOSE"
    static let takenAction = "TAKEN"
    static let snoozeAction = "SNOOZE"
    /// Minutes after the dose time when backup reminders repeat.
    static let followUps = [5, 10, 15, 20, 30, 45, 60, 90]

    var alarmsAllowed: Bool { AlarmManager.shared.authorizationState == .authorized }

    /// Which dose each alarm scheduled since launch belongs to, so a ringing alarm can be matched to its dose.
    private var alarmSlots: [UUID: String] = [:]

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let taken = UNNotificationAction(identifier: Self.takenAction, title: "I took them", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze…", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.doseCategory, actions: [taken, snooze], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
    }

    // MARK: - Scheduling

    func rescheduleAll(context: ModelContext) async {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let now = Date()
        let center = UNUserNotificationCenter.current()

        // Clear what we scheduled before, except a test reminder that hasn't gone off yet.
        let testKey = UserDefaults.standard.string(forKey: "testSlotKey")
        let testPending = (UserDefaults.standard.object(forKey: "testFireDate") as? Date).map { $0 > now.addingTimeInterval(-15 * 60) } ?? false
        let keepID = testPending ? testKey.map(Self.alarmID) : nil
        for alarm in (try? AlarmManager.shared.alarms) ?? [] where alarm.id != keepID {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { id in
            if testPending, let testKey, id.hasPrefix("dose-\(testKey)-") { return false }
            return id.hasPrefix("dose-") || id.hasPrefix("exp-") || id.hasPrefix("low-")
        })

        // Doses for today and tomorrow.
        for offset in 0...1 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            for slot in Scheduler.slots(on: day, meds: meds) {
                let status = Scheduler.status(of: slot, logs: logs, now: now)
                let fireDate: Date
                switch status {
                case .taken, .missed: continue
                case .snoozed(let until): fireDate = until
                case .due: fireDate = now.addingTimeInterval(60)
                case .upcoming: fireDate = slot.date
                }
                await scheduleAlarm(for: slot, at: fireDate)
                scheduleNotifications(for: slot, at: fireDate)
            }
        }
        scheduleExpiryWarnings(meds: meds, now: now)
    }

    func scheduleAlarm(for slot: DoseSlot, at date: Date) async {
        guard alarmsAllowed else { return }
        let title = "\(slot.title) · \(slot.timeText)"
        let takenButton = AlarmButton(text: "Taken", textColor: .white, systemImageName: "checkmark.circle.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                            secondaryButton: takenButton, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                            stopButton: AlarmButton(text: "Open", textColor: .white, systemImageName: "pills.fill"),
                                            secondaryButton: takenButton, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: DoseAlarmMetadata(slotKey: slot.key),
            tintColor: slot.dayPart.color
        )
        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: OpenDoseIntent(slotKey: slot.key),
            secondaryIntent: TakenIntent(slotKey: slot.key),
            sound: .default
        )
        alarmSlots[Self.alarmID(slot.key)] = slot.key
        _ = try? await AlarmManager.shared.schedule(id: Self.alarmID(slot.key), configuration: config)
    }

    // MARK: - Ringing alarms

    /// iOS draws a ringing alarm itself: full screen on the Lock Screen, but only a banner at the top when
    /// the phone is unlocked, and apps can't change that. So whenever MEDI is open (including right after
    /// someone taps that banner), it covers its own screen with the full-screen "Time for your meds" page
    /// the moment an alarm starts ringing, instead of waiting for the next check.
    func watchRingingAlarms() async {
        for await alarms in AlarmManager.shared.alarmUpdates {
            let router = AppRouter.shared
            for alarm in alarms where alarm.state == .alerting {
                guard let key = slotKey(forAlarm: alarm.id) else { continue }
                if router.activeSlotKey == nil || router.activeSlotKey == key {
                    router.openTakeScreen(slotKey: key)
                }
                break
            }
        }
    }

    private func slotKey(forAlarm id: UUID) -> String? {
        if let key = alarmSlots[id] { return key }
        // The test reminder is kept across launches without being scheduled again.
        if let test = UserDefaults.standard.string(forKey: "testSlotKey"), Self.alarmID(test) == id { return test }
        return nil
    }

    func scheduleNotifications(for slot: DoseSlot, at date: Date) {
        let center = UNUserNotificationCenter.current()
        let names = slot.meds.map(\.displayName).joined(separator: ", ")
        // When alarms are off, the first notification fires right at the dose time.
        let offsets = (alarmsAllowed ? [] : [0]) + Self.followUps
        for minutes in offsets {
            let fire = date.addingTimeInterval(Double(minutes) * 60)
            guard fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = minutes == 0 ? "Time for your \(slot.title.lowercased())" : "Still waiting: \(slot.title.lowercased())"
            content.body = "\(names). Tap to confirm you took them."
            content.sound = .defaultCritical
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.doseCategory
            content.threadIdentifier = slot.key
            content.userInfo = ["slotKey": slot.key]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let request = UNNotificationRequest(identifier: "dose-\(slot.key)-\(minutes)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
        }
    }

    func cancelReminders(for slotKey: String) {
        try? AlarmManager.shared.cancel(id: Self.alarmID(slotKey))
        try? AlarmManager.shared.stop(id: Self.alarmID(slotKey))
        let ids = ([0] + Self.followUps).map { "dose-\(slotKey)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func scheduleExpiryWarnings(meds: [Medication], now: Date) {
        var requests: [(Date, UNNotificationRequest)] = []
        for med in meds {
            for bottle in med.activeBottles {
                guard let exp = bottle.expirationDate else { continue }
                for daysBefore in [30, 14, 7, 0] {
                    guard let day = Calendar.current.date(byAdding: .day, value: -daysBefore, to: exp) else { continue }
                    let fire = ClockText.date(day, minutes: 9 * 60)
                    guard fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = daysBefore == 0 ? "\(med.displayName) expires today" : "\(med.displayName) expires in \(daysBefore == 30 ? "1 month" : daysBefore == 14 ? "2 weeks" : "1 week")"
                    content.body = daysBefore == 0
                        ? "Don't take pills from this bottle after today. Scan the label of your new bottle in PillBox."
                        : "Plan a refill. Rx #\(bottle.rxNumber.isEmpty ? "—" : bottle.rxNumber)."
                    content.sound = .default
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    requests.append((fire, UNNotificationRequest(identifier: "exp-\(bottle.id.uuidString)-\(daysBefore)", content: content,
                                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))))
                }
            }
        }
        // iOS keeps at most 64 pending notifications; keep the soonest warnings.
        for (_, r) in requests.sorted(by: { $0.0 < $1.0 }).prefix(16) {
            UNUserNotificationCenter.current().add(r)
        }
    }

    /// A test reminder for demos: fires in `seconds`.
    func scheduleTest(context: ModelContext, inSeconds seconds: Double = 60) async {
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let now = Date().addingTimeInterval(seconds)
        let minutes = ClockText.minutes(of: now)
        let part = DayPart.containing(minutes: minutes)
        let partMeds = Scheduler.slots(on: now, meds: meds).filter { $0.dayPart == part }.flatMap(\.meds)
        let slot = DoseSlot(day: Calendar.current.startOfDay(for: now), minutes: minutes,
                            meds: partMeds.isEmpty ? Array(meds.prefix(2)) : partMeds)
        UserDefaults.standard.set(slot.key, forKey: "testSlotKey")
        UserDefaults.standard.set(now, forKey: "testFireDate")
        await scheduleAlarm(for: slot, at: now)
        scheduleNotifications(for: slot, at: now)
    }

    static func alarmID(_ slotKey: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data(slotKey.utf8))
        var bytes = Array(digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Notification delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let key = notification.request.content.userInfo["slotKey"] as? String
        if let key {
            // The app is open: cover the screen with the "Take your meds" screen instead of a small banner.
            await MainActor.run { AppRouter.shared.openTakeScreen(slotKey: key) }
            return [.sound]
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let key = response.notification.request.content.userInfo["slotKey"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case ReminderService.takenAction:
                DoseActions.markTaken(slotKey: key, context: AppModel.container.mainContext)
            case ReminderService.snoozeAction:
                AppRouter.shared.openTakeScreen(slotKey: key, snooze: true)
            default:
                // Tapping or dismissing the notification brings up the confirm screen; it can't be skipped.
                AppRouter.shared.openTakeScreen(slotKey: key)
            }
        }
    }
}

// MARK: - Alarm buttons

/// "Taken" button on the alarm: records the dose without opening the app.
struct TakenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark meds as taken"
    static var openAppWhenRun = false

    @Parameter(title: "Dose") var slotKey: String

    init() {}
    init(slotKey: String) { self.slotKey = slotKey }

    @MainActor
    func perform() async throws -> some IntentResult {
        DoseActions.markTaken(slotKey: slotKey, context: AppModel.container.mainContext)
        return .result()
    }
}

/// Sliding to stop the alarm opens the app on the confirm screen, which can't be closed until the dose
/// is confirmed (or snoozed). On a locked phone iOS asks for Face ID first; if the person doesn't unlock,
/// the screen is waiting the next time the app opens, and backup reminders keep coming until they confirm.
struct OpenDoseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open dose confirmation"
    static var openAppWhenRun = true

    @Parameter(title: "Dose") var slotKey: String

    init() {}
    init(slotKey: String) { self.slotKey = slotKey }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openTakeScreen(slotKey: slotKey)
        return .result()
    }
}
