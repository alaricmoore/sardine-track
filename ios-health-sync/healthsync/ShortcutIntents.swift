//
//  ShortcutIntents.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import AppIntents
import Foundation

// MARK: - Open Biotracker Log

struct OpenBioTrackerLog: AppIntent {
    static var title: LocalizedStringResource = "Open Biotracker Log"
    static var description = IntentDescription("Opens the biotracker daily log page")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .openLogTab, object: nil)
        return .result()
    }
}

// MARK: - Sync Health Data

struct SyncHealthData: AppIntent {
    static var title: LocalizedStringResource = "Sync Biotracker"
    static var description = IntentDescription("Syncs today's health data to the biotracker")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        let userID = UserDefaults.standard.integer(forKey: "userID")

        guard !serverURL.isEmpty, !apiToken.isEmpty, userID > 0 else {
            return .result(value: "Sync failed — configure server settings first")
        }

        let success = await withCheckedContinuation { continuation in
            let syncer = HealthSyncer()
            syncer.syncNowSilent(serverURL: serverURL, apiToken: apiToken, userID: userID) { ok in
                continuation.resume(returning: ok)
            }
        }

        return .result(value: success ? "Sync complete" : "Sync failed — check Tailscale")
    }
}

// MARK: - App Shortcuts Provider

struct BioTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBioTrackerLog(),
            phrases: ["Open \(.applicationName) log"],
            shortTitle: "Open Log",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SyncHealthData(),
            phrases: ["Sync \(.applicationName)"],
            shortTitle: "Sync",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
