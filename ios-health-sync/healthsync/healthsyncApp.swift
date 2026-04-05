//
//  healthsyncApp.swift
//  healthsync
//
//  Created by Alaric Moore on 3/29/26.
//

import SwiftUI
import BackgroundTasks

@main
struct healthsyncApp: App {
    init() {
        // Register background sync task
        BackgroundSyncTask.register()

        // Set up notification manager
        NotificationManager.shared.setup()

        // Request notification permission on first launch
        NotificationManager.shared.requestAuthorization { _ in }

        // Schedule the first background sync
        BackgroundSyncTask.scheduleNextSync()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
