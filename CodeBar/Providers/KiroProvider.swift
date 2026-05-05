import Foundation

struct KiroProvider: PlatformProvider {
    let platformName = "Kiro"

    private var accessToken: String?
    private var region: String?

    private let refreshURL = "https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken"

    init() {
        let creds = Self.findCredentials()
        accessToken = creds.token
        region = creds.region
    }

    var isConfigured: Bool {
        accessToken != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let accessToken else {
            throw PlatformError.invalidAPIKey
        }

        let apiRegion = region ?? "us-east-1"
        let usageURL = "https://q.\(apiRegion).amazonaws.com/getUsageLimits"

        guard let url = URL(string: usageURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        var planType = "Free"

        if let subscriptionInfo = json["subscriptionInfo"] as? [String: Any],
           let title = subscriptionInfo["subscriptionTitle"] as? String {
            planType = title
        }

        if let limits = json["usageLimits"] as? [[String: Any]] {
            for limit in limits {
                guard let limitType = limit["limitType"] as? String,
                      let used = limit["used"] as? Int,
                      let total = limit["limit"] as? Int else { continue }

                if limitType == "AGENTIC_REQUEST" {
                    let isBonus = limit["isBonus"] as? Bool ?? false
                    let resetDate = Date().addingTimeInterval(30 * 24 * 3600)

                    items.append(UsageItem(
                        key: isBonus ? "bonus" : "credits",
                        label: isBonus ? "Bonus Credits" : "Credits",
                        used: used, total: total, unit: "req",
                        resetDate: resetDate
                    ))
                }
            }
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "credits", label: "Credits",
                used: 0, total: 100, unit: "req",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
            ))
        }

        return PlatformUsageData(
            platformName: platformName,
            planType: planType,
            items: items
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private static func findCredentials() -> (token: String?, region: String?) {
        let home = NSHomeDirectory()

        // Read token from AWS SSO cache
        let tokenPath = home + "/.aws/sso/cache/kiro-auth-token.json"
        var token: String?

        if let data = FileManager.default.contents(atPath: tokenPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            token = json["accessToken"] as? String
        }

        // Read region from profile
        var region: String?
        let profilePath = home + "/Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json"
        if let data = FileManager.default.contents(atPath: profilePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arn = json["profileArn"] as? String {
            // Extract region from ARN: arn:aws:codewhisperer:us-east-1:...
            let parts = arn.components(separatedBy: ":")
            if parts.count >= 4 {
                region = parts[3]
            }
        }

        return (token, region)
    }
}
