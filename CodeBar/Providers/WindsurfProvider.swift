import Foundation

struct WindsurfProvider: PlatformProvider {
    let platformName = "Windsurf"

    private var apiKey: String?

    private let statusURL = "https://server.self-serve.windsurf.com/exa.seat_management_pb.SeatManagementService/GetUserStatus"

    init() {
        apiKey = Self.findApiKey()
    }

    var isConfigured: Bool {
        apiKey != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let apiKey else {
            throw PlatformError.invalidAPIKey
        }

        guard let url = URL(string: statusURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        // Connect protocol (application/json over HTTP POST)
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        var planType = "Pro"
        var extra: [(label: String, value: String)] = []

        if let planInfo = json["planInfo"] as? [String: Any],
           let name = planInfo["planName"] as? String {
            planType = name
        }

        if let quotas = json["quotas"] as? [[String: Any]] {
            for quota in quotas {
                guard let usedPct = quota["usedPercent"] as? Double,
                      let label = quota["label"] as? String else { continue }

                let resetTimestamp = quota["resetTimestamp"] as? Double ?? 0
                let resetDate = resetTimestamp > 0
                    ? Date(timeIntervalSince1970: resetTimestamp)
                    : Date().addingTimeInterval(24 * 3600)

                let key = label.lowercased().contains("daily") ? "daily" :
                          label.lowercased().contains("weekly") ? "weekly" : label.lowercased()

                items.append(UsageItem(
                    key: key, label: label,
                    used: Int(usedPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        // Fallback: parse usageData if quotas not present
        if items.isEmpty, let usageData = json["usageData"] as? [String: Any] {
            if let dailyPct = usageData["dailyQuotaUsedPercent"] as? Double {
                let resetTs = usageData["dailyResetTimestamp"] as? Double ?? 0
                let resetDate = resetTs > 0 ? Date(timeIntervalSince1970: resetTs) : Date().addingTimeInterval(24 * 3600)
                items.append(UsageItem(
                    key: "daily", label: "Daily quota",
                    used: Int(dailyPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
            if let weeklyPct = usageData["weeklyQuotaUsedPercent"] as? Double {
                let resetTs = usageData["weeklyResetTimestamp"] as? Double ?? 0
                let resetDate = resetTs > 0 ? Date(timeIntervalSince1970: resetTs) : Date().addingTimeInterval(7 * 24 * 3600)
                items.append(UsageItem(
                    key: "weekly", label: "Weekly quota",
                    used: Int(weeklyPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        // Extra usage balance
        if let overageBalance = json["overageBalanceMicros"] as? Int, overageBalance > 0 {
            let dollars = Double(overageBalance) / 1_000_000.0
            extra.append((label: "Extra usage balance", value: String(format: "$%.2f", dollars)))
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "daily", label: "Daily quota",
                used: 0, total: 100, unit: "%",
                resetDate: Date().addingTimeInterval(24 * 3600)
            ))
        }

        return PlatformUsageData(
            platformName: platformName,
            planType: planType,
            items: items,
            extraInfo: extra
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private static func findApiKey() -> String? {
        let dbPaths = [
            NSHomeDirectory() + "/Library/Application Support/Windsurf/User/globalStorage/state.vscdb",
            NSHomeDirectory() + "/Library/Application Support/windsurf-next/User/globalStorage/state.vscdb",
        ]

        for dbPath in dbPaths {
            guard FileManager.default.fileExists(atPath: dbPath) else { continue }

            if let value = SQLiteHelper.readValue(dbPath: dbPath, key: "windsurfAuthStatus") {
                if let data = value.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let apiKey = json["apiKey"] as? String, !apiKey.isEmpty {
                    return apiKey
                }
            }
        }

        return nil
    }
}
