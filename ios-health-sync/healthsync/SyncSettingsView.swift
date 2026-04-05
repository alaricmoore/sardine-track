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
                        Text("Last auto-sync: \(lastSyncTimestamp)")
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
}
