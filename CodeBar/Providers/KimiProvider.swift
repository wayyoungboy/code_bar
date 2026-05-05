import Foundation

struct KimiProvider: PlatformProvider {
    let platformName = "Kimi"

    private var accessToken: String?
    private var refreshTokenValue: String?

    private let oauthRefreshURL = "https://auth.kimi.com/api/oauth/token"
    private let clientId = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private let usageURL = "https://api.kimi.com/coding/v1/usages"

    init() {
        (accessToken, refreshTokenValue) = Self.findCredentials()
    }

    var isConfigured: Bool {
        accessToken != nil || refreshTokenValue != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        var token = accessToken

        if token == nil, let rt = refreshTokenValue {
            let resp = try await OAuthHelper.refreshToken(
                url: oauthRefreshURL,
                clientId: clientId,
                refreshToken: rt
            )
            token = resp.access_token
        }

        guard let token else {
            throw PlatformError.invalidAPIKey
        }

        guard let url = URL(string: usageURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        var planType = "Free"

        if let user = json["user"] as? [String: Any],
           let membership = user["membership"] as? [String: Any],
           let level = membership["level"] as? String {
            planType = level.replacingOccurrences(of: "LEVEL_", with: "").capitalized
        }

        if let limits = json["limits"] as? [[String: Any]] {
            // Sort by window: smallest first (session), largest last (weekly)
            let sorted = limits.sorted { l, r in
                let lw = l["windowSeconds"] as? Int ?? 0
                let rw = r["windowSeconds"] as? Int ?? 0
                return lw < rw
            }

            for (i, limit) in sorted.enumerated() {
                guard let usedPct = limit["usedPercent"] as? Double,
                      let windowSec = limit["windowSeconds"] as? Int else { continue }

                let resetDate = Date().addingTimeInterval(TimeInterval(windowSec))
                let key = i == 0 ? "session" : "weekly"
                let label = i == 0 ? "Session" : "Weekly"

                items.append(UsageItem(
                    key: key, label: label,
                    used: Int(usedPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "session", label: "Session",
                used: 0, total: 100, unit: "%",
                resetDate: Date().addingTimeInterval(5 * 3600)
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

    private static func findCredentials() -> (String?, String?) {
        let home = NSHomeDirectory()
        let credPath = home + "/.kimi/credentials/kimi-code.json"

        guard let data = FileManager.default.contents(atPath: credPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let access = json["access_token"] as? String
        let refresh = json["refresh_token"] as? String

        // Check expiration
        if let expiresAt = json["expires_at"] as? Double {
            if Date().timeIntervalSince1970 > expiresAt && refresh != nil {
                return (nil, refresh)
            }
        }

        return (access, refresh)
    }
}
