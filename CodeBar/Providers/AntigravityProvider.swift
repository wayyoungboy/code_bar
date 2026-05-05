import Foundation

struct AntigravityProvider: PlatformProvider {
    let platformName = "Antigravity"

    private var accessToken: String?
    private var refreshTokenValue: String?
    private var clientId: String = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"

    private let quotaURL = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    init() {
        (accessToken, refreshTokenValue) = Self.findCredentials()
    }

    var isConfigured: Bool {
        accessToken != nil || refreshTokenValue != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        var token = accessToken

        if token == nil, let rt = refreshTokenValue {
            token = try await refreshGoogleToken(refreshToken: rt)
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
        let planType = "Free"
        let resetDate = Date().addingTimeInterval(5 * 3600)

        if let models = json["models"] as? [[String: Any]] {
            for model in models {
                guard let name = model["displayName"] as? String,
                      let quota = model["quota"] as? [String: Any],
                      let usedPct = quota["usedPercent"] as? Double else { continue }

                let key: String
                let label: String
                if name.lowercased().contains("pro") {
                    key = "pro"
                    label = "Gemini Pro"
                } else if name.lowercased().contains("flash") {
                    key = "flash"
                    label = "Gemini Flash"
                } else if name.lowercased().contains("claude") {
                    key = "claude"
                    label = "Claude"
                } else {
                    key = name.lowercased().replacingOccurrences(of: " ", with: "_")
                    label = name
                }

                items.append(UsageItem(
                    key: key, label: label,
                    used: Int(usedPct * 100), total: 10000, unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "pro", label: "Gemini Pro",
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

    private func refreshGoogleToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: tokenURL) else {
            throw PlatformError.unknown("Invalid token URL")
        }

        let body = [
            "grant_type=refresh_token",
            "client_id=\(clientId.urlEncoded())",
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

    private static func findCredentials() -> (String?, String?) {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Antigravity/User/globalStorage/state.vscdb"

        guard FileManager.default.fileExists(atPath: dbPath) else { return (nil, nil) }

        // Try to read OAuth token from SQLite
        if let tokenJson = SQLiteHelper.readValue(dbPath: dbPath, key: "antigravity.oauthToken") {
            if let data = tokenJson.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let access = json["access_token"] as? String
                let refresh = json["refresh_token"] as? String
                return (access, refresh)
            }
        }

        // Try alternative key names
        for key in ["google.oauthToken", "oauthToken", "antigravity.googleOAuthToken"] {
            if let tokenJson = SQLiteHelper.readValue(dbPath: dbPath, key: key) {
                if let data = tokenJson.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let access = json["access_token"] as? String
                    let refresh = json["refresh_token"] as? String
                    if access != nil || refresh != nil {
                        return (access, refresh)
                    }
                }
            }
        }

        return (nil, nil)
    }
}
