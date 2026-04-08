import SwiftUI
import BackgroundTasks

@main
struct HealthSyncApp: App {
    init() {
        BackgroundSyncTask.register()
        NotificationManager.shared.setup()
        NotificationManager.shared.requestAuthorization { _ in }
        BackgroundSyncTask.scheduleNext()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
