import Foundation

struct ClaudeProvider: PlatformProvider {
    let platformName = "Claude"

    private var accessToken: String?
    private var refreshTokenValue: String?

    private let credentialPath = NSHomeDirectory() + "/.claude/.credentials.json"
    private let oauthRefreshURL = "https://platform.claude.com/v1/oauth/token"
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let usageURL = "https://api.anthropic.com/api/oauth/usage"

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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.networkError(NSError(domain: "", code: -1))
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw PlatformError.invalidAPIKey
            }
            throw PlatformError.unknown("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        var planType = "Pro"

        if let tierName = json["tierName"] as? String {
            planType = tierName
        }

        if let rateLimits = json["rateLimits"] as? [[String: Any]] {
            for limit in rateLimits {
                guard let windowSec = limit["windowSeconds"] as? Int,
                      let usedPct = limit["usedPercent"] as? Double else { continue }

                let totalPct = 100
                let usedInt = Int(usedPct * 100)

                let resetDate = Date().addingTimeInterval(TimeInterval(windowSec))

                if windowSec <= 18000 {
                    items.append(UsageItem(
                        key: "session", label: "Session",
                        used: usedInt, total: totalPct * 100, unit: "%",
                        resetDate: resetDate
                    ))
                } else {
                    items.append(UsageItem(
                        key: "weekly", label: "Weekly",
                        used: usedInt, total: totalPct * 100, unit: "%",
                        resetDate: resetDate
                    ))
                }
            }
        }

        if items.isEmpty {
            if let sessionPct = json["sessionPercent"] as? Double {
                items.append(UsageItem(
                    key: "session", label: "Session",
                    used: Int(sessionPct * 100), total: 10000, unit: "%",
                    resetDate: Date().addingTimeInterval(5 * 3600)
                ))
            }
            if let weeklyPct = json["weeklyPercent"] as? Double {
                items.append(UsageItem(
                    key: "weekly", label: "Weekly",
                    used: Int(weeklyPct * 100), total: 10000, unit: "%",
                    resetDate: Date().addingTimeInterval(7 * 24 * 3600)
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
        let claudeDir = home + "/.claude"
        let credPath = claudeDir + "/.credentials.json"

        if let data = FileManager.default.contents(atPath: credPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let access = json["accessToken"] as? String ?? json["access_token"] as? String
            let refresh = json["refreshToken"] as? String ?? json["refresh_token"] as? String
            if access != nil || refresh != nil {
                return (access, refresh)
            }
        }

        // Only try keychain if Claude Code appears to be installed
        if FileManager.default.fileExists(atPath: claudeDir),
           let keychainToken = KeychainHelper.readExternalItem(service: "Claude Code-credentials") {
            if let data = keychainToken.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let access = json["accessToken"] as? String ?? json["access_token"] as? String
                let refresh = json["refreshToken"] as? String ?? json["refresh_token"] as? String
                return (access, refresh)
            }
            return (keychainToken, nil)
        }

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] {
            return (envToken, nil)
        }

        return (nil, nil)
    }

}
