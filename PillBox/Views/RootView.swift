import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meds: [Medication]
    @Query private var logs: [DoseLog]

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) { TodayView() }
            Tab("Pill Box", systemImage: "square.grid.3x3.fill", value: AppTab.pillBox) { PillBoxView() }
            Tab("Meds", systemImage: "pills.fill", value: AppTab.meds) { MedicationsView() }
            Tab("Alerts", systemImage: "bell.badge.fill", value: AppTab.alerts) { AlertsView() }
                .badge(alertCount)
        }
        .fullScreenCover(item: activeSlot) { slot in
            TakeMedsView(slot: slot)
        }
        .sheet(isPresented: $router.showScanner) { ScanFlowView() }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .task {
            await ReminderService.shared.requestPermissions()
            await ReminderService.shared.rescheduleAll(context: context)
            ScreenRoutes.apply(AppModel.launchScreen, context: context)
            checkForDueDose()
        }
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in checkForDueDose() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkForDueDose()
                Task { await ReminderService.shared.rescheduleAll(context: context) }
            }
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

    private var alertCount: Int {
        let bottleWarnings = meds.flatMap(\.activeBottles).filter { ExpiryLevel.level(for: $0.expirationDate) >= .week }.count
        let low = meds.filter { (Scheduler.daysLeft($0) ?? 99) <= 7 }.count
        return bottleWarnings + low
    }

    /// If a dose is due while the app is open, cover the screen until it's confirmed or snoozed.
    private func checkForDueDose() {
        guard router.activeSlotKey == nil, AppModel.launchScreen == nil else { return }
        let due = Scheduler.slots(on: Date(), meds: meds).first { Scheduler.status(of: $0, logs: logs) == .due }
        if let due { router.openTakeScreen(slotKey: due.key) }
    }
}
