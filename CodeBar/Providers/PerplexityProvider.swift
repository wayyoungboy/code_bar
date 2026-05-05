import Foundation

struct PerplexityProvider: PlatformProvider {
    let platformName = "Perplexity"

    private var bearerToken: String?

    private let rateLimitURL = "https://www.perplexity.ai/rest/rate-limit/all"

    init() {
        bearerToken = Self.findToken()
    }

    var isConfigured: Bool {
        bearerToken != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let bearerToken else {
            throw PlatformError.invalidAPIKey
        }

        guard let url = URL(string: rateLimitURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

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

        let resetDate = Date().addingTimeInterval(24 * 3600)

        // Parse rate limits
        if let rateLimits = json["rateLimits"] as? [String: Any] {
            if let queries = rateLimits["queries"] as? [String: Any],
               let remaining = queries["remaining"] as? Int,
               let total = queries["limit"] as? Int {
                items.append(UsageItem(
                    key: "queries", label: "Queries",
                    used: total - remaining, total: total, unit: "req",
                    resetDate: resetDate
                ))
            }

            if let deepResearch = rateLimits["deepResearch"] as? [String: Any],
               let remaining = deepResearch["remaining"] as? Int,
               let total = deepResearch["limit"] as? Int {
                extra.append((label: "Deep Research", value: "\(remaining) / \(total) remaining"))
            }

            if let labs = rateLimits["labs"] as? [String: Any],
               let remaining = labs["remaining"] as? Int,
               let total = labs["limit"] as? Int {
                extra.append((label: "Labs", value: "\(remaining) / \(total) remaining"))
            }
        }

        // API credits
        if let apiCredits = json["apiCredits"] as? [String: Any],
           let balance = apiCredits["balance"] as? Double,
           let limit = apiCredits["limit"] as? Double, limit > 0 {
            let usedCents = Int((limit - balance) * 100)
            let totalCents = Int(limit * 100)
            items.insert(UsageItem(
                key: "credits", label: "API credits",
                used: usedCents, total: totalCents, unit: "$",
                resetDate: Date().addingTimeInterval(30 * 24 * 3600)
            ), at: 0)
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "queries", label: "Queries",
                used: 0, total: 100, unit: "req",
                resetDate: resetDate
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

    private static func findToken() -> String? {
        // Try to extract from Perplexity macOS app cache
        let cachePath = NSHomeDirectory() + "/Library/Containers/ai.perplexity.mac/Data/Library/Caches/ai.perplexity.mac/Cache.db"

        guard FileManager.default.fileExists(atPath: cachePath) else { return nil }

        let rows = SQLiteHelper.query(
            dbPath: cachePath,
            sql: "SELECT request FROM cfurl_cache_response WHERE request LIKE '%perplexity.ai%' AND request LIKE '%Bearer%' LIMIT 10"
        )

        for row in rows {
            guard let requestHex = row["request"] else { continue }
            // Try to extract Bearer token from the cached request data
            if let token = extractBearerToken(from: requestHex) {
                return token
            }
        }

        return nil
    }

    private static func extractBearerToken(from hexOrText: String) -> String? {
        let searchTarget = "Bearer "
        if let range = hexOrText.range(of: searchTarget) {
            let afterBearer = hexOrText[range.upperBound...]
            let token = afterBearer.prefix(while: { !$0.isWhitespace && $0 != "\"" && $0 != "\r" && $0 != "\n" })
            if token.count > 20 {
                return String(token)
            }
        }
        return nil
    }
}
