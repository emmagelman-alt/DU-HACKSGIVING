import SwiftData
import SwiftUI

@main
struct PillBoxApp: App {
    @State private var router = AppRouter.shared

    init() {
        ReminderService.shared.configure()
        if ProcessInfo.processInfo.arguments.contains("-seedDemoData") {
            DemoData.seed(into: AppModel.container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .tint(Color("AccentColor"))
                // The MEDI redesign is light only.
                .preferredColorScheme(.light)
        }
        .modelContainer(AppModel.container)
    }
}
