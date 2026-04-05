//
//  SyncHealthIntent.swift
//  healthsync
//
//  Created by Alaric Moore on 3/30/26.
//

import AppIntents
import Foundation

struct SyncHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Health Data"
    static var description = IntentDescription("Syncs your health data to the biotracker server")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Read settings from UserDefaults (same keys as @AppStorage in ContentView)
        let defaults = UserDefaults.standard
        let serverURL = defaults.string(forKey: "serverURL") ?? "https://<YOUR_SERVER>/api/health-sync"
        let apiToken = defaults.string(forKey: "apiToken") ?? ""
        let userID = defaults.integer(forKey: "userID")
        
        // Validate we have an API token
        guard !apiToken.isEmpty else {
            return .result(dialog: "Please set your API token in the HealthSync app first.")
        }
        
        // Create a syncer and perform the sync
        let syncer = HealthSyncer()
        
        // We need to wait for the sync to complete
        return try await withCheckedThrowingContinuation { continuation in
            // Subscribe to the syncer's result
            var cancellable: Any?
            cancellable = syncer.$lastResult.sink { result in
                // Wait until we get a non-empty result that isn't "syncing..."
                if !result.isEmpty && result != "syncing..." {
                    // Clean up the subscription
                    _ = cancellable
                    continuation.resume(returning: .result(dialog: "\(result)"))
                }
            }
            
            // Trigger the sync
            syncer.syncNow(serverURL: serverURL, apiToken: apiToken, userID: userID)
        }
    }
}

struct HealthSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncHealthIntent(),
            phrases: [
                "Sync my health data with \(.applicationName)",
                "Run health sync in \(.applicationName)",
                "Update my health data in \(.applicationName)"
            ],
            shortTitle: "Sync Health",
            systemImageName: "heart.circle.fill"
        )
    }
}
