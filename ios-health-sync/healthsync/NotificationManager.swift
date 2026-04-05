//
//  NotificationManager.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // Category identifiers
    static let bedtimeLogCategory = "BEDTIME_LOG"
    static let medDoseCategory = "MED_DOSE"
    static let flareThresholdCategory = "FLARE_THRESHOLD"
    static let flareTrendCategory = "FLARE_TREND"

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register notification categories
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Self.bedtimeLogCategory, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.medDoseCategory, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.flareThresholdCategory, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.flareTrendCategory, actions: [], intentIdentifiers: []),
        ]
        center.setNotificationCategories(categories)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted)
        }
    }

    // MARK: - Bedtime Log Reminder

    func scheduleBedtimeReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()

        // Remove existing bedtime reminders
        center.removePendingNotificationRequests(withIdentifiers: ["bedtime_log_daily"])

        let content = UNMutableNotificationContent()
        content.title = "Time to log"
        content.body = "How was today?"
        content.sound = .default
        content.categoryIdentifier = Self.bedtimeLogCategory

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "bedtime_log_daily", content: content, trigger: trigger)

        center.add(request)
    }

    // MARK: - Medication Dose Reminders

    func scheduleDoseReminders(doses: [DoseReminder]) {
        let center = UNUserNotificationCenter.current()

        // Remove all existing dose reminders
        center.getPendingNotificationRequests { requests in
            let doseIDs = requests
                .filter { $0.content.categoryIdentifier == Self.medDoseCategory }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: doseIDs)

            // Schedule new ones
            for dose in doses {
                let content = UNMutableNotificationContent()
                content.title = "Medication Reminder"
                content.body = "Time for \(dose.doseLabel) \(dose.drugName)"
                content.sound = .default
                content.categoryIdentifier = Self.medDoseCategory

                // Parse scheduled_time "HH:MM"
                let parts = dose.scheduledTime.split(separator: ":")
                guard parts.count == 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1]) else { continue }

                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute

                // Schedule for tomorrow (doses are fetched during evening sync)
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                let tomorrowComps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                dateComponents.year = tomorrowComps.year
                dateComponents.month = tomorrowComps.month
                dateComponents.day = tomorrowComps.day

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "med_dose_\(dose.id)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    // MARK: - Flare Alerts

    func scheduleFlareThresholdAlert(score: Double, maxScore: Double) {
        let lastDate = UserDefaults.standard.string(forKey: "lastFlareAlertDate") ?? ""
        let today = Self.todayString()
        guard lastDate != today else { return } // Already alerted today

        let content = UNMutableNotificationContent()
        content.title = "Flare Risk Elevated"
        content.body = "Flare risk is elevated \u{2014} score \(String(format: "%.1f", score))/\(String(format: "%.0f", maxScore)). Take it easy tomorrow."
        content.sound = .default
        content.categoryIdentifier = Self.flareThresholdCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "flare_threshold_\(today)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(today, forKey: "lastFlareAlertDate")
    }

    func scheduleFlareTrendAlert(delta: Double) {
        let lastDate = UserDefaults.standard.string(forKey: "lastTrendAlertDate") ?? ""
        let today = Self.todayString()
        guard lastDate != today else { return }

        let content = UNMutableNotificationContent()
        content.title = "Risk Score Rising"
        content.body = "Risk score jumped +\(String(format: "%.1f", delta)) today \u{2014} watch for flare signals."
        content.sound = .default
        content.categoryIdentifier = Self.flareTrendCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "flare_trend_\(today)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(today, forKey: "lastTrendAlertDate")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        if category == Self.bedtimeLogCategory || category == Self.medDoseCategory {
            NotificationCenter.default.post(name: .openLogTab, object: nil)
        }
        completionHandler()
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }
}

// MARK: - Notification name for tab navigation

extension Notification.Name {
    static let openLogTab = Notification.Name("openLogTab")
}
