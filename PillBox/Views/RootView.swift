import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meds: [Medication]
    @Query private var logs: [DoseLog]
    /// The MEDI welcome screen shows when the app opens with no medications (or with `-screen welcome`).
    @State private var welcomePending = AppModel.launchScreen == nil || AppModel.launchScreen == "welcome"

    private var showWelcome: Bool {
        welcomePending && (meds.isEmpty || AppModel.launchScreen == "welcome")
    }

    var body: some View {
        @Bindable var router = router
        Group {
            if showWelcome {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.35)) { welcomePending = false }
                    Task { await ReminderService.shared.requestPermissions() }
                }
                .transition(.opacity)
            } else {
                Group {
                    switch router.tab {
                    case .today: TodayView()
                    case .add: AddMedView()
                    case .pillBox: MediPillBoxView()
                    case .meds: InfoView()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MediTabBar(tab: $router.tab)
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(item: activeSlot) { slot in
            TakeMedsView(slot: slot)
        }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .sheet(isPresented: $router.showAlerts) { AlertsView() }
        .task {
            SavedDataFixes.run(context: context)
            // On first launch, ask for alarm and notification permission after START, not over the welcome screen.
            if !showWelcome { await ReminderService.shared.requestPermissions() }
            await ReminderService.shared.rescheduleAll(context: context)
            ScreenRoutes.apply(AppModel.launchScreen, context: context)
            checkForDueDose()
        }
        // A dose alarm that starts ringing while MEDI is open covers the screen straight away.
        .task { await ReminderService.shared.watchRingingAlarms() }
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in checkForDueDose() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkForDueDose()
                Task { await ReminderService.shared.rescheduleAll(context: context) }
            }
        }
        // "Scan a new label" buttons elsewhere in the app open the + tab.
        .onChange(of: router.showScanner) { _, open in
            guard open else { return }
            router.showScanner = false
            router.showAlerts = false
            router.showSettings = false
            welcomePending = false
            router.tab = .add
        }
        .onChange(of: meds.count) {
            Task { await ReminderService.shared.rescheduleAll(context: context) }
        }
    }

    private var activeSlot: Binding<DoseSlot?> {
        Binding(
            get: { router.activeSlotKey.flatMap { DoseActions.slot(for: $0, context: context) } },
            set: { router.activeSlotKey = $0?.key }
        )
    }

    /// If a dose is due while the app is open, cover the screen until it's confirmed or snoozed.
    private func checkForDueDose() {
        guard router.activeSlotKey == nil, AppModel.launchScreen == nil else { return }
        // An alarm that was stopped (perhaps on the Lock Screen, without opening the app) comes back first.
        // This also catches test reminders, which aren't at a regular dose time.
        if let key = AppRouter.awaitingSlotKey {
            if let slot = DoseActions.slot(for: key, context: context), Scheduler.status(of: slot, logs: logs) == .due {
                router.openTakeScreen(slotKey: key)
                return
            }
            UserDefaults.standard.removeObject(forKey: AppRouter.awaitingKey)
        }
        let due = Scheduler.slots(on: Date(), meds: meds).first { Scheduler.status(of: $0, logs: logs) == .due }
        if let due { router.openTakeScreen(slotKey: due.key) }
    }
}
