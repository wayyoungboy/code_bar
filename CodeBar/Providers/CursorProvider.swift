import Foundation

struct CursorProvider: PlatformProvider {
    let platformName = "Cursor"

    private var accessToken: String?
    private var refreshTokenValue: String?

    private let oauthRefreshURL = "https://api2.cursor.sh/oauth/token"
    private let clientId = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private let usageURL = "https://www.cursor.com/api/usage"

    init() {
        (accessToken, refreshTokenValue) = Self.findCredentials()
    }

    var isConfigured: Bool {
        accessToken != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        var token = accessToken

        if token == nil, let rt = refreshTokenValue {
            let resp = try await OAuthHelper.refreshToken(
                url: oauthRefreshURL,
                clientId: clientId,
                refreshToken: rt,
                extraParams: ["grant_type": "refresh_token"]
            )
            token = resp.access_token
        }

        guard let token else {
            throw PlatformError.invalidAPIKey
        }

        // Try REST usage API with cookie auth
        guard let url = URL(string: usageURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")

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

        if let membershipType = json["membershipType"] as? String {
            planType = membershipType.capitalized
        }

        // Parse usage items from different fields
        if let premiumUsage = json["numRequestsTotal"] as? Int,
           let premiumLimit = json["numRequestsLimit"] as? Int, premiumLimit > 0 {
            items.append(UsageItem(
                key: "requests", label: "Requests",
                used: premiumUsage, total: premiumLimit, unit: "req",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
            ))
        }

        // GPT-4 / Premium model usage
        if let gpt4Usage = json["numRequestsMade"] as? Int,
           let gpt4Limit = json["maxRequestUsage"] as? Int, gpt4Limit > 0 {
            items.append(UsageItem(
                key: "premium", label: "Premium",
                used: gpt4Usage, total: gpt4Limit, unit: "req",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
            ))
        }

        // Credits / spending
        if let currentSpend = json["currentSpend"] as? Double,
           let spendLimit = json["hardLimit"] as? Double, spendLimit > 0 {
            let usedCents = Int(currentSpend * 100)
            let totalCents = Int(spendLimit * 100)
            items.append(UsageItem(
                key: "credits", label: "Credits",
                used: usedCents, total: totalCents, unit: "$",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
            ))
            extra.append((label: "Usage", value: String(format: "$%.2f / $%.2f", currentSpend, spendLimit)))
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "status", label: "Status",
                used: 0, total: 100, unit: "%",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
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

    private static func findCredentials() -> (String?, String?) {
        let home = NSHomeDirectory()
        let dbPaths = [
            home + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            home + "/Library/Application Support/cursor/User/globalStorage/state.vscdb",
        ]

        var cursorInstalled = false
        for dbPath in dbPaths {
            guard FileManager.default.fileExists(atPath: dbPath) else { continue }
            cursorInstalled = true

            if let tokenJson = SQLiteHelper.readValue(dbPath: dbPath, key: "cursorAuth/accessToken") {
                return (tokenJson, nil)
            }
        }

        // Only try keychain if Cursor is installed but DB had no token
        if cursorInstalled,
           let token = KeychainHelper.readExternalItem(service: "cursor-access-token") {
            let refresh = KeychainHelper.readExternalItem(service: "cursor-refresh-token")
            return (token, refresh)
        }

        return (nil, nil)
    }

}
