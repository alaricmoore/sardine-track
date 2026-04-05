//
//  BackgroundSyncTask.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import Foundation
import BackgroundTasks

enum BackgroundSyncTask {
    static let identifier = "com.biotracking.healthsync.daily"

    /// Register the background task handler. Call once at app launch.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
    }

    /// Schedule the next background sync around the configured hour.
    static func scheduleNextSync() {
        let syncHour = UserDefaults.standard.integer(forKey: "syncHour")
        let targetHour = syncHour > 0 ? syncHour : 20

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = targetHour
        components.minute = 0

        guard let target = calendar.date(from: components) else { return }
        let earliestDate = target < Date() ? target.addingTimeInterval(86400) : target

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestDate
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Handle the background task execution.
    static func handle(task: BGAppRefreshTask) {
        // Schedule next run immediately so it's always queued
        scheduleNextSync()

        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        let userID = UserDefaults.standard.integer(forKey: "userID")

        guard !serverURL.isEmpty, !apiToken.isEmpty, userID > 0 else {
            task.setTaskCompleted(success: false)
            return
        }

        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Step 1: Sync health data silently
        let syncer = HealthSyncer()
        syncer.syncNowSilent(serverURL: serverURL, apiToken: apiToken, userID: userID) { syncSuccess in

            // Step 2: Fetch flare status
            FlareChecker.shared.fetchStatus(serverURL: serverURL, apiToken: apiToken, userID: userID) { status in

                let notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")

                if let status = status, status.ok, notificationsEnabled {
                    let trendThreshold = UserDefaults.standard.double(forKey: "flareScoreTrendThreshold")
                    let effectiveThreshold = trendThreshold > 0 ? trendThreshold : 3.0

                    if let eval = FlareChecker.shared.evaluate(status: status, trendThreshold: effectiveThreshold) {
                        // Step 3: Schedule flare alerts
                        if eval.thresholdCrossed {
                            NotificationManager.shared.scheduleFlareThresholdAlert(
                                score: eval.score, maxScore: eval.maxScore
                            )
                        }
                        if eval.trendAlert {
                            NotificationManager.shared.scheduleFlareTrendAlert(delta: eval.scoreDelta)
                        }

                        // Step 4: Schedule med dose reminders for tomorrow
                        if !eval.dosesDue.isEmpty {
                            NotificationManager.shared.scheduleDoseReminders(doses: eval.dosesDue)
                        }
                    }
                }

                // Step 5: Schedule bedtime reminder
                if notificationsEnabled {
                    let hour = UserDefaults.standard.integer(forKey: "bedtimeReminderHour")
                    let minute = UserDefaults.standard.integer(forKey: "bedtimeReminderMinute")
                    NotificationManager.shared.scheduleBedtimeReminder(
                        hour: hour > 0 ? hour : 21, minute: minute
                    )
                }

                // Step 6: Record sync timestamp
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                f.timeZone = .current
                UserDefaults.standard.set(f.string(from: Date()), forKey: "lastSyncTimestamp")

                task.setTaskCompleted(success: syncSuccess)
            }
        }
    }
}
