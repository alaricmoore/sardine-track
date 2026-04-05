import SwiftUI

struct ContentView: View {
    @StateObject private var syncer = HealthSyncer()

    // Persisted settings
    @AppStorage("serverURL") private var serverURL = "https://<YOUR_SERVER>/api/health-sync"
    @AppStorage("apiToken") private var apiToken = ""
    @AppStorage("userID") private var userID = 1

    @State private var backfillDays: Int = 7

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    TextField("URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    SecureField("API Token", text: $apiToken)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Stepper("User ID: \(userID)", value: $userID, in: 1...99)
                }

                Section(header: Text("Sync")) {
                    Button(action: {
                        syncer.syncNow(serverURL: serverURL,
                                       apiToken: apiToken,
                                       userID: userID)
                    }) {
                        HStack {
                            Text("Sync Now")
                            Spacer()
                            if syncer.isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(apiToken.isEmpty || syncer.isSyncing)
                }

                Section(header: Text("Backfill History")) {
                    Picker("Range", selection: $backfillDays) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                        Text("365 days").tag(365)
                    }
                    Button(action: {
                        syncer.backfillAll(serverURL: serverURL,
                                           apiToken: apiToken,
                                           userID: userID,
                                           days: backfillDays)
                    }) {
                        HStack {
                            Text("Start Backfill")
                            Spacer()
                            if syncer.isBackfilling {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(apiToken.isEmpty || syncer.isBackfilling)

                    if syncer.isBackfilling {
                        ProgressView(value: syncer.backfillProgress)
                        Text(syncer.backfillStatus)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else if !syncer.backfillStatus.isEmpty {
                        Text(syncer.backfillStatus)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Status")) {
                    Text(syncer.lastResult)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section(header: Text("HealthKit")) {
                    Button("Request Permissions") {
                        syncer.requestAuthorization()
                    }
                }

                Section(header: Text("Info")) {
                    Text("Syncs: steps, HRV (SDNN), RMSSD, resting HR, BBT, SpO2, respiratory rate, time in daylight")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("RMSSD is computed from overnight RR intervals (10pm-8am)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Backfill pulls all metrics for each historical day: steps, HRV, RMSSD, resting HR, BBT, SpO2, respiratory rate, daylight")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Tip: add this app to a Shortcuts automation triggered at bedtime for automatic daily sync")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Health Sync")
        }
        .onAppear {
            syncer.requestAuthorization()
        }
    }
}
