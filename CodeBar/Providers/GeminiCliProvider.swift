import Foundation

struct GeminiCliProvider: PlatformProvider {
    let platformName = "Gemini"

    private var accessToken: String?
    private var refreshTokenValue: String?
    private var clientId: String?
    private var clientSecret: String?

    private let quotaURL = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    init() {
        let creds = Self.findCredentials()
        accessToken = creds.access
        refreshTokenValue = creds.refresh
        clientId = creds.clientId
        clientSecret = creds.clientSecret
    }

    var isConfigured: Bool {
        accessToken != nil || refreshTokenValue != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        var token = accessToken

        if let rt = refreshTokenValue, let cid = clientId, let cs = clientSecret {
            if token == nil {
                let resp = try await refreshGoogleToken(refreshToken: rt, clientId: cid, clientSecret: cs)
                token = resp
            }
        }

        guard let token else {
            throw PlatformError.invalidAPIKey
        }

        guard let url = URL(string: quotaURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        let planType = (json["tier"] as? String) ?? "Free"
        let resetDate = Date().addingTimeInterval(5 * 3600)

        if let models = json["modelQuota"] as? [[String: Any]] {
            for model in models {
                guard let name = model["modelName"] as? String,
                      let usedPct = model["usedPercent"] as? Double else { continue }

                let key: String
                let label: String
                if name.lowercased().contains("pro") {
                    key = "pro"
                    label = "Pro"
                } else if name.lowercased().contains("flash") {
                    key = "flash"
                    label = "Flash"
                } else {
                    key = name.lowercased()
                    label = name
                }

                items.append(UsageItem(
                    key: key, label: label,
                    used: Int(usedPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        // Fallback: try quotaUsage
        if items.isEmpty, let quotaUsage = json["quotaUsage"] as? [String: Any] {
            if let proPct = quotaUsage["proPercent"] as? Double {
                items.append(UsageItem(
                    key: "pro", label: "Pro",
                    used: Int(proPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
            if let flashPct = quotaUsage["flashPercent"] as? Double {
                items.append(UsageItem(
                    key: "flash", label: "Flash",
                    used: Int(flashPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "pro", label: "Pro",
                used: 0, total: 100, unit: "%",
                resetDate: resetDate
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

    private func refreshGoogleToken(refreshToken: String, clientId: String, clientSecret: String) async throws -> String {
        guard let url = URL(string: tokenURL) else {
            throw PlatformError.unknown("Invalid token URL")
        }

        let body = [
            "grant_type=refresh_token",
            "client_id=\(clientId.urlEncoded())",
            "client_secret=\(clientSecret.urlEncoded())",
            "refresh_token=\(refreshToken.urlEncoded())",
        ].joined(separator: "&")

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }
        return token
    }

    private static func findCredentials() -> (access: String?, refresh: String?, clientId: String?, clientSecret: String?) {
        let home = NSHomeDirectory()
        let oauthPath = home + "/.gemini/oauth_creds.json"

        // Check settings first
        let settingsPath = home + "/.gemini/settings.json"
        if let settingsData = FileManager.default.contents(atPath: settingsPath),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let authType = settings["authType"] as? String,
           authType != "oauth-personal" {
            return (nil, nil, nil, nil)
        }

        var access: String?
        var refresh: String?

        if let data = FileManager.default.contents(atPath: oauthPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            access = json["access_token"] as? String
            refresh = json["refresh_token"] as? String
        }

        // Find client credentials from installed gemini-cli
        let (clientId, clientSecret) = findGeminiClientCredentials()

        if access != nil || refresh != nil {
            return (access, refresh, clientId, clientSecret)
        }

        return (nil, nil, nil, nil)
    }

    private static func findGeminiClientCredentials() -> (String?, String?) {
        let home = NSHomeDirectory()
        let searchPaths = [
            home + "/.bun/install/global/node_modules/@anthropic-ai/gemini-cli",
            home + "/.bun/install/global/node_modules/@anthropic-ai/gemini",
            "/opt/homebrew/lib/node_modules/@anthropic-ai/gemini-cli",
            "/usr/local/lib/node_modules/@anthropic-ai/gemini-cli",
        ]

        for basePath in searchPaths {
            let credFile = basePath + "/dist/client_credentials.json"
            if let data = FileManager.default.contents(atPath: credFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let cid = json["client_id"] as? String
                let cs = json["client_secret"] as? String
                if cid != nil { return (cid, cs) }
            }
        }

        return (nil, nil)
    }
}
