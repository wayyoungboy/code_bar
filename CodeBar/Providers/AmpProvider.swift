import Foundation

struct AmpProvider: PlatformProvider {
    let platformName = "Amp"

    private var apiKey: String?

    private let apiURL = "https://ampcode.com/api/internal"

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

        guard let url = URL(string: apiURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        let body: [String: Any] = [
            "method": "userDisplayBalanceInfo",
            "params": [String: Any](),
        ]

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        var planType = "Free"
        var extra: [(label: String, value: String)] = []

        // Free tier balance
        if let free = result["free"] as? [String: Any],
           let usedCents = free["usedCents"] as? Int,
           let limitCents = free["limitCents"] as? Int, limitCents > 0 {
            let replenishRate = free["replenishCentsPerHour"] as? Int ?? 0
            items.append(UsageItem(
                key: "free", label: "Free",
                used: usedCents, total: limitCents, unit: "cents",
                resetDate: Date().addingTimeInterval(TimeInterval(max(1, (limitCents - usedCents)) / max(1, replenishRate)) * 3600)
            ))
        }

        // Bonus
        if let bonus = result["bonus"] as? [String: Any],
           let pct = bonus["percentRemaining"] as? Double {
            let daysLeft = bonus["daysRemaining"] as? Int ?? 0
            extra.append((label: "Bonus", value: "\(Int(pct))% (\(daysLeft)d left)"))
        }

        // Credits
        if let credits = result["credits"] as? [String: Any],
           let balanceCents = credits["balanceCents"] as? Int {
            extra.append((label: "Credits", value: String(format: "$%.2f", Double(balanceCents) / 100.0)))
        }

        if let tier = result["planTier"] as? String {
            planType = tier.capitalized
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "free", label: "Free",
                used: 0, total: 100, unit: "%",
                resetDate: Date().addingTimeInterval(3600)
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
        let home = NSHomeDirectory()
        let secretsPath = home + "/.local/share/amp/secrets.json"

        guard let data = FileManager.default.contents(atPath: secretsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["apiKey@https://ampcode.com/"] as? String
    }
}
