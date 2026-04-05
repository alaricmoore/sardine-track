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
    @Published var isBackfilling: Bool = false
    @Published var backfillProgress: Double = 0.0
    @Published var backfillStatus: String = ""

    // All the HealthKit types we want to read
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.appleWalkingSteadiness),
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.timeInDaylight),
            HKQuantityType(.appleSleepingWristTemperature), // Wrist temperature
        ]
        // Heartbeat series for RR intervals → RMSSD
        types.insert(HKSeriesType.heartbeat())
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

        // HRV (SDNN) — daily average
        group.enter()
        queryAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: today, end: tomorrow) { val in
            if let v = val { payload["hrv"] = v }
            group.leave()
        }

        // Resting heart rate — daily average
        group.enter()
        queryAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: today, end: tomorrow) { val in
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

        // Wrist temperature — daily average (Celsius relative change)
        group.enter()
        queryAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: today, end: tomorrow) { val in
            if let v = val { payload["wrist_temp"] = v }
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

    private func queryAverage(_ typeID: HKQuantityTypeIdentifier, unit: HKUnit,
                              start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        let type = HKQuantityType(typeID)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                       options: .discreteAverage) { _, stats, _ in
            let val = stats?.averageQuantity()?.doubleValue(for: unit)
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

    // MARK: - Silent Sync (for background tasks and Shortcuts)

    /// Sync today's data without updating @Published UI state.
    /// Calls completion(true) on success, completion(false) on failure.
    func syncNowSilent(serverURL: String, apiToken: String, userID: Int, completion: @escaping (Bool) -> Void) {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let group = DispatchGroup()
        var payload: [String: Any] = [
            "user_id": userID,
            "date": Self.isoDate(today),
        ]

        group.enter()
        querySum(.stepCount, unit: .count(), start: today, end: tomorrow) { val in
            if let v = val { payload["steps"] = v }
            group.leave()
        }

        group.enter()
        queryAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: today, end: tomorrow) { val in
            if let v = val { payload["hrv"] = v }
            group.leave()
        }

        group.enter()
        queryAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: today, end: tomorrow) { val in
            if let v = val { payload["resting_heart_rate"] = v }
            group.leave()
        }

        group.enter()
        queryMostRecent(.bodyTemperature, unit: .degreeFahrenheit()) { val in
            if let v = val { payload["basal_temp_delta"] = v }
            group.leave()
        }

        group.enter()
        queryMostRecent(.oxygenSaturation, unit: .percent()) { val in
            if let v = val { payload["spo2"] = v * 100.0 }
            group.leave()
        }

        group.enter()
        queryMostRecent(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute())) { val in
            if let v = val { payload["respiratory_rate"] = v }
            group.leave()
        }

        group.enter()
        querySum(.timeInDaylight, unit: .minute(), start: today, end: tomorrow) { val in
            if let v = val { payload["sun_exposure_min"] = v }
            group.leave()
        }

        group.enter()
        queryAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: today, end: tomorrow) { val in
            if let v = val { payload["wrist_temp"] = v }
            group.leave()
        }

        group.enter()
        queryRMSSD(start: yesterday.addingTimeInterval(22 * 3600),
                   end: today.addingTimeInterval(8 * 3600)) { val in
            if let v = val { payload["hrv_rmssd"] = v }
            group.leave()
        }

        group.notify(queue: .global()) {
            self.sendPayload(serverURL: serverURL, apiToken: apiToken, payload: payload, completion: completion)
        }
    }

    // MARK: - Network

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
                        // Parse fields_updated from response
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

    // MARK: - Backfill
    
    func backfillHealthData(days: Int, serverURL: String, apiToken: String, userID: Int) {
        guard !isBackfilling else { return }
        
        DispatchQueue.main.async {
            self.isBackfilling = true
            self.backfillProgress = 0.0
            self.backfillStatus = "Starting backfill for \(days) days..."
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Process days in reverse chronological order (most recent first)
        var datesToProcess: [Date] = []
        for daysAgo in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) {
                datesToProcess.append(date)
            }
        }
        
        // Process one day at a time sequentially
        processNextBackfillDay(
            dates: datesToProcess,
            index: 0,
            serverURL: serverURL,
            apiToken: apiToken,
            userID: userID,
            successCount: 0,
            skipCount: 0
        )
    }
    
    private func processNextBackfillDay(
        dates: [Date],
        index: Int,
        serverURL: String,
        apiToken: String,
        userID: Int,
        successCount: Int,
        skipCount: Int
    ) {
        // Check if we're done
        guard index < dates.count else {
            DispatchQueue.main.async {
                self.isBackfilling = false
                self.backfillProgress = 1.0
                self.backfillStatus = "Completed! Synced \(successCount) days, skipped \(skipCount) (no data)"
            }
            return
        }
        
        let date = dates[index]
        let progress = Double(index) / Double(dates.count)
        
        DispatchQueue.main.async {
            self.backfillProgress = progress
            self.backfillStatus = "Processing \(Self.isoDate(date)) (\(index + 1)/\(dates.count))..."
        }
        
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        
        // For overnight data (RMSSD): previous day 10pm → this day 8am
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else {
            // Skip and continue
            processNextBackfillDay(
                dates: dates,
                index: index + 1,
                serverURL: serverURL,
                apiToken: apiToken,
                userID: userID,
                successCount: successCount,
                skipCount: skipCount + 1
            )
            return
        }
        
        let overnightStart = previousDay.addingTimeInterval(22 * 3600) // 10pm
        let overnightEnd = date.addingTimeInterval(8 * 3600) // 8am
        
        // Query ALL metrics for this day (same as syncNow but for historical date)
        let group = DispatchGroup()
        var payload: [String: Any] = [
            "user_id": userID,
            "date": Self.isoDate(date),
        ]
        
        // Steps — sum for the day
        group.enter()
        querySum(.stepCount, unit: .count(), start: date, end: tomorrow) { val in
            if let v = val { payload["steps"] = v }
            group.leave()
        }
        
        // HRV (SDNN) — daily average
        group.enter()
        queryAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: date, end: tomorrow) { val in
            if let v = val { payload["hrv"] = v }
            group.leave()
        }
        
        // Resting heart rate — daily average
        group.enter()
        queryAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: date, end: tomorrow) { val in
            if let v = val { payload["resting_heart_rate"] = v }
            group.leave()
        }
        
        // Body temperature (BBT delta) — most recent
        group.enter()
        queryMostRecent(.bodyTemperature, unit: .degreeFahrenheit()) { val in
            if let v = val { payload["basal_temp_delta"] = v }
            group.leave()
        }
        
        // SpO2 — most recent
        group.enter()
        queryMostRecent(.oxygenSaturation, unit: .percent()) { val in
            if let v = val { payload["spo2"] = v * 100.0 }
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
        querySum(.timeInDaylight, unit: .minute(), start: date, end: tomorrow) { val in
            if let v = val { payload["sun_exposure_min"] = v }
            group.leave()
        }
        
        // Wrist temperature — daily average (Celsius relative change)
        group.enter()
        queryAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: date, end: tomorrow) { val in
            if let v = val { payload["wrist_temp"] = v }
            group.leave()
        }
        
        // RMSSD from overnight RR intervals
        group.enter()
        queryRMSSD(start: overnightStart, end: overnightEnd) { val in
            if let v = val { payload["hrv_rmssd"] = v }
            group.leave()
        }
        
        // Wait for all queries to complete
        group.notify(queue: .global()) { [weak self] in
            guard let self = self else { return }
            
            // If we got at least one metric (more than just user_id and date), send it
            let hasData = payload.count > 2
            
            if hasData {
                // Send to server
                self.sendPayload(serverURL: serverURL, apiToken: apiToken, payload: payload) { success in
                    // Wait 0.5s to avoid overwhelming the server, then process next day
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        self.processNextBackfillDay(
                            dates: dates,
                            index: index + 1,
                            serverURL: serverURL,
                            apiToken: apiToken,
                            userID: userID,
                            successCount: success ? successCount + 1 : successCount,
                            skipCount: success ? skipCount : skipCount + 1
                        )
                    }
                }
            } else {
                // No data for this day, skip it (no delay needed)
                self.processNextBackfillDay(
                    dates: dates,
                    index: index + 1,
                    serverURL: serverURL,
                    apiToken: apiToken,
                    userID: userID,
                    successCount: successCount,
                    skipCount: skipCount + 1
                )
            }
        }
    }
    
    private func sendPayload(serverURL: String, apiToken: String, payload: [String: Any], completion: @escaping (Bool) -> Void) {
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
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = (error == nil && status == 200)
            completion(success)
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
