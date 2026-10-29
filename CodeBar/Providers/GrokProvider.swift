import Foundation
import CoreFoundation

/// Fetches the signed-in Grok subscription directly; no CLI process or workspace is used.
struct GrokProvider: PlatformProvider {
    let platformName = "Grok"
    private let config: GrokConfig
    private let client: any GrokSubscriptionFetching

    init(config: GrokConfig = GrokConfig(), client: any GrokSubscriptionFetching = GrokSubscriptionClient.shared) {
        self.config = config
        self.client = client
    }

    var isConfigured: Bool {
        config.isValid && FileManager.default.fileExists(atPath: authURL.path)
    }

    func fetchUsage() async throws -> PlatformUsageData {
        let data = try await client.fetch(authURL: authURL, proxyURL: config.proxyURL)
        return try Self.makeUsage(from: data)
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private var authURL: URL {
        let custom = config.homeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = ProcessInfo.processInfo.environment["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let home: URL
        if let path = custom, !path.isEmpty {
            home = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else if let path = environment, !path.isEmpty {
            home = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
        }
        return home.appendingPathComponent("auth.json")
    }

#if CODEBAR_BEHAVIOR_TESTS
    static func testUsage(from data: Data) throws -> PlatformUsageData { try makeUsage(from: data) }
#endif

    private static func makeUsage(from data: Data) throws -> PlatformUsageData {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = root["config"] as? [String: Any],
              let number = config["creditUsagePercent"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw GrokSubscriptionError.invalidResponse
        }
        let percent = max(0, min(100, number.doubleValue))
        let period = config["currentPeriod"] as? [String: Any]
        let reset = parseDate(period?["end"] as? String ?? config["billingPeriodEnd"] as? String)
        let tier = (config["subscriptionTier"] as? String ?? root["subscriptionTier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return PlatformUsageData(
            platformName: "Grok", planType: tier?.isEmpty == false ? tier! : "Grok 订阅",
            items: [UsageItem(key: "grok.weekly", label: "周额度", used: Int(percent.rounded()), total: 100, unit: "%", resetDate: reset)],
            extraInfo: [
                (label: "数据来源", value: "Grok 订阅接口"),
                (label: "刷新方式", value: "直接查询订阅额度，自动刷新 OAuth"),
                (label: "Grok 同步时间", value: formatter.string(from: Date())),
                (label: "刷新状态", value: "订阅用量已更新"),
            ]
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }
    }
}
