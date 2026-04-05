//
//  FlareChecker.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import Foundation

// MARK: - Models

struct FlareStatus: Codable {
    let ok: Bool
    let date: String?
    let score: Double?
    let weightedScore: Double?
    let maxScore: Double?
    let threshold: Double?
    let predictedFlare: Bool?
    let riskLevel: String?
    let riskColor: String?
    let scoreDelta: Double?
    let deltaDirection: String?
    let factors: [FlareStatusFactor]?
    let dosesDue: [DoseReminder]?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case ok, date, score, threshold, factors, reason
        case weightedScore = "weighted_score"
        case maxScore = "max_score"
        case predictedFlare = "predicted_flare"
        case riskLevel = "risk_level"
        case riskColor = "risk_color"
        case scoreDelta = "score_delta"
        case deltaDirection = "delta_direction"
        case dosesDue = "doses_due"
    }
}

struct FlareStatusFactor: Codable {
    let name: String
    let points: Double
    let color: String
}

struct DoseReminder: Codable {
    let id: Int
    let drugName: String
    let doseLabel: String
    let scheduledTime: String
    let taken: Bool

    enum CodingKeys: String, CodingKey {
        case id, taken
        case drugName = "drug_name"
        case doseLabel = "dose_label"
        case scheduledTime = "scheduled_time"
    }
}

// MARK: - FlareChecker

class FlareChecker {
    static let shared = FlareChecker()
    private init() {}

    /// Fetch flare status from the API.
    /// Derives base URL from the stored health-sync endpoint.
    func fetchStatus(serverURL: String, apiToken: String, userID: Int, completion: @escaping (FlareStatus?) -> Void) {
        let baseURL = serverURL.replacingOccurrences(of: "/api/health-sync", with: "")
        guard let url = URL(string: "\(baseURL)/api/flare-status?user_id=\(userID)") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                completion(nil)
                return
            }

            let decoder = JSONDecoder()
            let status = try? decoder.decode(FlareStatus.self, from: data)
            completion(status)
        }.resume()
    }

    /// Evaluate whether alert conditions are met.
    struct AlertEvaluation {
        let thresholdCrossed: Bool
        let trendAlert: Bool
        let score: Double
        let maxScore: Double
        let scoreDelta: Double
        let dosesDue: [DoseReminder]
    }

    func evaluate(status: FlareStatus, trendThreshold: Double = 3.0) -> AlertEvaluation? {
        guard status.ok, let score = status.score, let maxScore = status.maxScore else {
            return nil
        }

        return AlertEvaluation(
            thresholdCrossed: status.predictedFlare ?? false,
            trendAlert: (status.scoreDelta ?? 0) >= trendThreshold,
            score: score,
            maxScore: maxScore,
            scoreDelta: status.scoreDelta ?? 0,
            dosesDue: status.dosesDue ?? []
        )
    }
}
