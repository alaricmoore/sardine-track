import Foundation
import HealthKit
import Combine

/// Reads Apple Health data, computes RMSSD from overnight RR intervals,
/// and POSTs everything to the biotracker health-sync API.
class HealthSyncer: ObservableObject {
    private let store = HKHealthStore()

    @Published var lastResult: String = ""
    @Published var isSyncing: Bool = false

    // Backfill state
    @Published var backfillProgress: Double = 0
    @Published var backfillStatus: String = ""
    @Published var isBackfilling: Bool = false

    // All the HealthKit types we want to read
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.appleWalkingSteadiness), // placeholder — see below
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.timeInDaylight),
        ]
        // Heartbeat series for RR intervals → RMSSD
        if let seriesType = HKSeriesType.heartbeat() as? HKObjectType {
            types.insert(seriesType)
        }
        return types
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastResult = "HealthKit not available on this device"
            return
        }
        store.requestAuthorization(toShare: [], read: readTypes) { ok, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.lastResult = "Auth error: \(error.localizedDescription)"
                } else if ok {
                    self.lastResult = "HealthKit authorized"
                }
            }
        }
    }

    func syncNow(serverURL: String, apiToken: String, userID: Int) {
        guard !isSyncing else { return }
        DispatchQueue.main.async { self.isSyncing = true; self.lastResult = "syncing..." }

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let group = DispatchGroup()
        var payload: [String: Any] = [
            "user_id": userID,
            "date": Self.isoDate(today),
        ]

        // Steps — sum for the day
        group.enter()
        querySum(.stepCount, unit: .count(), start: today, end: tomorrow) { val in
            if let v = val { payload["steps"] = v }
            group.leave()
        }

        // HRV (SDNN) — most recent
        group.enter()
        queryMostRecent(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) { val in
            if let v = val { payload["hrv"] = v }
            group.leave()
        }

        // Resting heart rate — most recent
        group.enter()
        queryMostRecent(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())) { val in
            if let v = val { payload["resting_heart_rate"] = v }
            group.leave()
        }

        // Body temperature (BBT delta) — most recent
        group.enter()
        queryMostRecent(.bodyTemperature, unit: .degreeFahrenheit()) { val in
            // Apple stores absolute temp; biotracker wants delta from baseline
            // The iOS app sends the raw value; server could subtract baseline,
            // but for now we send as-is (same as what Shortcuts was doing)
            if let v = val { payload["basal_temp_delta"] = v }
            group.leave()
        }

        // SpO2 — most recent
        group.enter()
        queryMostRecent(.oxygenSaturation, unit: .percent()) { val in
            if let v = val { payload["spo2"] = v * 100.0 } // HealthKit returns 0-1, we want %
            group.leave()
        }

        // Respiratory rate — most recent
        group.enter()
        queryMostRecent(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute())) { val in
            if let v = val { payload["respiratory_rate"] = v }
            group.leave()
        }

        // Time in daylight — sum for the day (minutes)
        group.enter()
        querySum(.timeInDaylight, unit: .minute(), start: today, end: tomorrow) { val in
            if let v = val { payload["sun_exposure_min"] = v }
            group.leave()
        }

        // RMSSD from overnight RR intervals (yesterday 10pm → today 8am)
        group.enter()
        queryRMSSD(start: yesterday.addingTimeInterval(22 * 3600),
                   end: today.addingTimeInterval(8 * 3600)) { val in
            if let v = val { payload["hrv_rmssd"] = v }
            group.leave()
        }

        group.notify(queue: .main) {
            self.postToServer(serverURL: serverURL, apiToken: apiToken, payload: payload)
        }
    }

    // MARK: - HealthKit Queries

    private func querySum(_ typeID: HKQuantityTypeIdentifier, unit: HKUnit,
                          start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        let type = HKQuantityType(typeID)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                       options: .cumulativeSum) { _, stats, _ in
            let val = stats?.sumQuantity()?.doubleValue(for: unit)
            completion(val)
        }
        store.execute(query)
    }

    private func queryMostRecent(_ typeID: HKQuantityTypeIdentifier, unit: HKUnit,
                                  completion: @escaping (Double?) -> Void) {
        let type = HKQuantityType(typeID)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil,
                                   limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
            completion(val)
        }
        store.execute(query)
    }

    private func queryRMSSD(start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let seriesType = HKSeriesType.heartbeat()

        let query = HKSampleQuery(sampleType: seriesType, predicate: predicate,
                                   limit: HKObjectQueryNoLimit,
                                   sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                       ascending: true)]) { [weak self] _, samples, _ in
            guard let self = self, let series = samples as? [HKHeartbeatSeriesSample], !series.isEmpty else {
                completion(nil)
                return
            }

            // Collect all RR intervals from all overnight series
            var allIntervals: [Double] = []
            let rrGroup = DispatchGroup()

            for sample in series {
                rrGroup.enter()
                let rrQuery = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceStart, precededByGap, done, error in
                    if error == nil && !precededByGap {
                        allIntervals.append(timeSinceStart * 1000.0) // convert to ms
                    }
                    if done { rrGroup.leave() }
                }
                self.store.execute(rrQuery)
            }

            rrGroup.notify(queue: .global()) {
                // Compute RMSSD from successive differences
                guard allIntervals.count >= 2 else { completion(nil); return }

                // Convert cumulative timestamps to inter-beat intervals
                var rrDurations: [Double] = []
                for i in 1..<allIntervals.count {
                    let ibi = allIntervals[i] - allIntervals[i - 1]
                    if ibi > 200 && ibi < 2000 { // filter physiological range
                        rrDurations.append(ibi)
                    }
                }

                guard rrDurations.count >= 2 else { completion(nil); return }

                var sumSq: Double = 0
                for i in 1..<rrDurations.count {
                    let diff = rrDurations[i] - rrDurations[i - 1]
                    sumSq += diff * diff
                }
                let rmssd = sqrt(sumSq / Double(rrDurations.count - 1))
                completion((rmssd * 100).rounded() / 100) // round to 2 decimal places
            }
        }
        store.execute(query)
    }

    // MARK: - Backfill

    func backfillRMSSD(serverURL: String, apiToken: String, userID: Int, days: Int) {
        guard !isBackfilling else { return }
        DispatchQueue.main.async {
            self.isBackfilling = true
            self.backfillProgress = 0
            self.backfillStatus = "starting backfill..."
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Build list of dates to process (yesterday back to N days ago)
        var dates: [Date] = []
        for offset in 1...days {
            if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                dates.append(d)
            }
        }

        let total = dates.count
        var processed = 0
        var synced = 0
        var skipped = 0

        func processNext() {
            guard processed < total else {
                DispatchQueue.main.async {
                    self.isBackfilling = false
                    self.backfillProgress = 1.0
                    self.backfillStatus = "done: \(synced) days synced, \(skipped) skipped (no data)"
                }
                return
            }

            let targetDate = dates[processed]
            let dateStr = Self.isoDate(targetDate)
            let prevDay = cal.date(byAdding: .day, value: -1, to: targetDate)!

            // Overnight window: previous day 10pm → target day 8am
            let overnightStart = prevDay.addingTimeInterval(22 * 3600)
            let overnightEnd = targetDate.addingTimeInterval(8 * 3600)

            DispatchQueue.main.async {
                self.backfillStatus = "querying \(dateStr)..."
            }

            queryRMSSD(start: overnightStart, end: overnightEnd) { [weak self] rmssd in
                guard let self = self else { return }

                if let rmssd = rmssd {
                    let payload: [String: Any] = [
                        "user_id": userID,
                        "date": dateStr,
                        "hrv_rmssd": rmssd,
                    ]
                    self.sendPayload(serverURL: serverURL, apiToken: apiToken, payload: payload) { success in
                        if success { synced += 1 } else { skipped += 1 }
                        processed += 1
                        DispatchQueue.main.async {
                            self.backfillProgress = Double(processed) / Double(total)
                            self.backfillStatus = "\(processed)/\(total) — \(synced) synced"
                        }
                        // Delay 0.5s between requests
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                            processNext()
                        }
                    }
                } else {
                    skipped += 1
                    processed += 1
                    DispatchQueue.main.async {
                        self.backfillProgress = Double(processed) / Double(total)
                        self.backfillStatus = "\(processed)/\(total) — \(synced) synced"
                    }
                    // No delay needed when skipping
                    processNext()
                }
            }
        }

        DispatchQueue.global().async {
            processNext()
        }
    }

    // MARK: - Network

    /// Reusable POST that reports success/failure via completion handler.
    private func sendPayload(serverURL: String, apiToken: String,
                             payload: [String: Any],
                             completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(false)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(status == 200)
        }.resume()
    }

    private func postToServer(serverURL: String, apiToken: String, payload: [String: Any]) {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            DispatchQueue.main.async {
                self.lastResult = "invalid server URL"
                self.isSyncing = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSyncing = false

                if let error = error {
                    self.lastResult = "network error: \(error.localizedDescription)"
                    return
                }

                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    if status == 200 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let fields = json["fields_updated"] as? [String] {
                            self.lastResult = "synced \(fields.count) fields: \(fields.joined(separator: ", "))"
                        } else {
                            self.lastResult = "synced (status \(status))"
                        }
                    } else {
                        self.lastResult = "error \(status): \(body)"
                    }
                } else {
                    self.lastResult = "no response (status \(status))"
                }
            }
        }.resume()
    }

    // MARK: - Helpers

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}
