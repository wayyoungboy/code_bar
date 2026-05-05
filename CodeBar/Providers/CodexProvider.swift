import Foundation

struct CodexProvider: PlatformProvider {
    let platformName = "Codex"

    private var accessToken: String?
    private var refreshTokenValue: String?
    private var accountId: String?

    private let oauthRefreshURL = "https://auth.openai.com/oauth/token"
    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let usageURL = "https://chatgpt.com/backend-api/wham/usage"

    init() {
        (accessToken, refreshTokenValue, accountId) = Self.findCredentials()
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
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
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

                let usedInt = Int(usedPct * 100)
                let resetDate = Date().addingTimeInterval(TimeInterval(windowSec))

                if windowSec <= 18000 {
                    items.append(UsageItem(
                        key: "session", label: "Session",
                        used: usedInt, total: 10000, unit: "%",
                        resetDate: resetDate
                    ))
                } else {
                    items.append(UsageItem(
                        key: "weekly", label: "Weekly",
                        used: usedInt, total: 10000, unit: "%",
                        resetDate: resetDate
                    ))
                }
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

    private static func findCredentials() -> (String?, String?, String?) {
        let home = NSHomeDirectory()
        let paths = [
            home + "/.config/codex/auth.json",
            home + "/.codex/auth.json",
        ]

        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            let customPath = (codexHome as NSString).appendingPathComponent("auth.json")
            if let result = readAuthFile(customPath) { return result }
        }

        var hasCodexDir = false
        for path in paths {
            if let result = readAuthFile(path) { return result }
            let dir = (path as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: dir) { hasCodexDir = true }
        }

        // Only try keychain if Codex config directory exists
        if hasCodexDir,
           let keychainData = KeychainHelper.readExternalItem(service: "Codex Auth") {
            if let data = keychainData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let access = json["access_token"] as? String
                let refresh = json["refresh_token"] as? String
                let account = json["account_id"] as? String
                return (access, refresh, account)
            }
        }

        return (nil, nil, nil)
    }

    private static func readAuthFile(_ path: String) -> (String?, String?, String?)? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let access = json["access_token"] as? String
        let refresh = json["refresh_token"] as? String
        let account = json["account_id"] as? String
        if access != nil || refresh != nil {
            return (access, refresh, account)
        }
        return nil
    }

}
