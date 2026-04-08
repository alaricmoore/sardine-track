//
//  SyncSettingsView.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject var syncer: HealthSyncer
    @Binding var serverURL: String
    @Binding var apiToken: String
    @Binding var userID: Int

    @State private var backfillDays = 90

    // Notification settings
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("bedtimeReminderHour") private var bedtimeReminderHour = 21
    @AppStorage("bedtimeReminderMinute") private var bedtimeReminderMinute = 0
    @AppStorage("syncHour") private var syncHour = 20
    @AppStorage("flareScoreTrendThreshold") private var flareScoreTrendThreshold = 3.0
    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Settings") {
                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("API Token", text: $apiToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("User ID", value: $userID, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("HealthKit") {
                    Button("Authorize HealthKit") {
                        syncer.requestAuthorization()
                    }
                }

                // Custom visual sync section with logo
                Section {
                    Button(action: {
                        syncer.syncNow(serverURL: serverURL, apiToken: apiToken, userID: userID)
                    }) {
                        HStack(spacing: 16) {
                            Image("sardine_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(syncer.isSyncing ? "Syncing..." : "Sync Health Data")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("Upload to biotracker server")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if syncer.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(syncer.isSyncing || apiToken.isEmpty)
                }

                Section("Last Result") {
                    Text(syncer.lastResult.isEmpty ? "Not synced yet" : syncer.lastResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !lastSyncTimestamp.isEmpty {
                        Text("Last auto-sync: \(formattedSyncTime)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Notifications section
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                NotificationManager.shared.requestAuthorization { _ in }
                            }
                        }

                    if notificationsEnabled {
                        HStack {
                            Text("Bedtime Reminder")
                            Spacer()
                            Picker("Hour", selection: $bedtimeReminderHour) {
                                ForEach(18..<24, id: \.self) { h in
                                    Text("\(h):00").tag(h)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Auto-Sync Target")
                            Spacer()
                            Picker("Hour", selection: $syncHour) {
                                ForEach(17..<23, id: \.self) { h in
                                    Text("\(h):00").tag(h)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack {
                            Text("Trend Alert Threshold")
                            Spacer()
                            TextField("Delta", value: $flareScoreTrendThreshold, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }

                // Automatic Background Sync
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automatic Sync")
                                    .font(.headline)

                                Text("Daily at \(syncHour > 0 ? syncHour : 20):00")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                        }

                        if !lastSyncTimestamp.isEmpty {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Auto-Sync")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formattedSyncTime)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                Text(nextSyncTime)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Divider()

                        // Debug buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                testBackgroundSync()
                            }) {
                                Label("Test Now", systemImage: "play.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(syncer.isSyncing || apiToken.isEmpty)

                            Button(action: {
                                BackgroundSyncTask.scheduleNext()
                            }) {
                                Label("Reschedule", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Background Sync")
                } footer: {
                    Text("Your health data syncs automatically every evening. Change the time in Notifications settings above.")
                        .font(.caption)
                }

                // Backfill Health Data Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backfill Historical Data")
                            .font(.headline)

                        Text("Sync all health metrics from past days to your server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Days to backfill:")
                            Spacer()
                            TextField("Days", value: $backfillDays, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                                .disabled(syncer.isBackfilling)
                        }

                        // Quick presets
                        HStack(spacing: 8) {
                            ForEach([2, 7, 30, 90, 365], id: \.self) { days in
                                Button(action: {
                                    backfillDays = days
                                }) {
                                    Text(days == 2 ? "48h" : days == 7 ? "Week" : days == 30 ? "Month" : days == 90 ? "90d" : "Year")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)
                                .disabled(syncer.isBackfilling)
                            }
                        }

                        if syncer.isBackfilling {
                            VStack(spacing: 8) {
                                ProgressView(value: syncer.backfillProgress)
                                    .progressViewStyle(.linear)

                                Text(syncer.backfillStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(action: {
                            syncer.backfillHealthData(
                                days: backfillDays,
                                serverURL: serverURL,
                                apiToken: apiToken,
                                userID: userID
                            )
                        }) {
                            HStack {
                                Image(systemName: syncer.isBackfilling ? "stop.circle.fill" : "clock.arrow.circlepath")
                                Text(syncer.isBackfilling ? "Backfilling..." : "Start Backfill")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(syncer.isBackfilling || apiToken.isEmpty || backfillDays < 1)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Historical Data")
                } footer: {
                    if !syncer.backfillStatus.isEmpty && !syncer.isBackfilling {
                        Text(syncer.backfillStatus)
                            .font(.caption)
                    } else {
                        Text("Syncs steps, HRV, heart rate, SpO2, wrist temp, sun exposure, and more.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("HealthSync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image("sardine_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
            }
        }
    }

    /// Format the timestamp to a human-readable relative time
    private var formattedSyncTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current

        guard let date = formatter.date(from: lastSyncTimestamp) else {
            return lastSyncTimestamp
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    /// Calculate the next scheduled sync time
    private var nextSyncTime: String {
        let targetHour = syncHour > 0 ? syncHour : 20
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = targetHour
        components.minute = 0

        guard var target = calendar.date(from: components) else {
            return "Next: Unknown"
        }

        // If target is in the past, schedule for tomorrow
        if target < Date() {
            target = calendar.date(byAdding: .day, value: 1, to: target)!
        }

        let interval = target.timeIntervalSinceNow

        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Next: in \(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "Next: in \(hours)h"
        } else {
            return "Next: tomorrow"
        }
    }

    /// Test the background sync flow manually
    private func testBackgroundSync() {
        print("🧪 Testing background sync manually")

        syncer.syncNowSilent(serverURL: serverURL, apiToken: apiToken, userID: userID) { healthSyncSuccess in
            print(healthSyncSuccess ? "✅ Health data synced" : "❌ Health sync failed")

            FlareChecker.shared.fetchStatus(serverURL: serverURL, apiToken: apiToken, userID: userID) { flareStatus in
                if let status = flareStatus {
                    print("✅ Flare status fetched: score \(status.score ?? 0)")

                    // Update timestamp in the same format as BackgroundSyncTask
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd HH:mm"
                    f.timeZone = .current
                    lastSyncTimestamp = f.string(from: Date())
                } else {
                    print("❌ Failed to fetch flare status")
                }
            }
        }
    }
}
