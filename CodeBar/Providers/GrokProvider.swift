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
              let config = root["config"] as? [String: Any] else {
            throw GrokSubscriptionError.invalidResponse
        }
        let period = config["currentPeriod"] as? [String: Any]
        let periodType = period?["type"] as? String
        let parsedEnd = parseDate(period?["end"] as? String ?? config["billingPeriodEnd"] as? String)
        let parsedPeriodStart = parseDate(period?["start"] as? String)
        let parsedPeriodEnd = parseDate(period?["end"] as? String)
        let hasCompleteTypedPeriod: Bool = {
            guard let kind = periodKind(periodType),
                  let start = parsedPeriodStart,
                  let end = parsedPeriodEnd,
                  start < end else { return false }
            _ = kind
            return true
        }()

        let percent: Double
        let inferredZero: Bool
        if let value = config["creditUsagePercent"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else { throw GrokSubscriptionError.invalidResponse }
            percent = max(0, min(100, number.doubleValue))
            inferredZero = false
        } else if hasCompleteTypedPeriod {
            // proto3 JSON omits zero scalars after a period reset.
            percent = 0
            inferredZero = true
        } else {
            throw GrokSubscriptionError.invalidResponse
        }

        let reset = parsedEnd
        let label = quotaLabel(periodType)
        let tier = (config["subscriptionTier"] as? String ?? root["subscriptionTier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var extraInfo: [(label: String, value: String)] = [
            (label: "数据来源", value: "Grok 订阅接口（官方 CLI 同源，非公开稳定 API）"),
            (label: "额度范围", value: "订阅共享池，不是 xAI API 余额，也不是 Grok Bot 用量"),
            (label: "刷新方式", value: "直接查询订阅额度，自动刷新 OAuth"),
            (label: "Grok 同步时间", value: formatter.string(from: Date())),
            (label: "刷新状态", value: "订阅用量已更新"),
        ]
        if let cycle = periodKind(periodType) {
            extraInfo.append((label: "计费周期", value: cycle == .weekly ? "周" : "月"))
        } else {
            extraInfo.append((label: "计费周期", value: "未返回周期类型，按当前周期显示"))
        }
        if inferredZero {
            extraInfo.append((label: "用量说明", value: "本周期用量为 0%（接口省略零值），这是查询成功而不是失败"))
        }
        extraInfo.append(contentsOf: productLines(config["productUsage"]))
        if let prepaid = optionalPositiveCents(config["prepaidBalance"]) {
            extraInfo.append((label: "额外预付余额", value: formatUSD(cents: prepaid)))
        }
        if let onDemand = onDemandLine(used: config["onDemandUsed"], cap: config["onDemandCap"]) {
            extraInfo.append(onDemand)
        }
        return PlatformUsageData(
            platformName: "Grok", planType: tier?.isEmpty == false ? tier! : "Grok 订阅",
            items: [UsageItem(
                key: "grok.weekly",
                label: label,
                used: Int(percent.rounded()),
                total: 100,
                unit: "%",
                resetDate: reset,
                usedAmount: percent,
                totalAmount: 100
            )],
            extraInfo: extraInfo
        )
    }

    private enum PeriodKind { case weekly, monthly }

    private static func periodKind(_ raw: String?) -> PeriodKind? {
        switch raw {
        case "USAGE_PERIOD_TYPE_WEEKLY": return .weekly
        case "USAGE_PERIOD_TYPE_MONTHLY": return .monthly
        default: return nil
        }
    }

    private static func quotaLabel(_ raw: String?) -> String {
        switch periodKind(raw) {
        case .weekly: return "周额度"
        case .monthly: return "月额度"
        case nil: return "当前周期额度"
        }
    }

    private static func productLines(_ raw: Any?) -> [(label: String, value: String)] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        var lines: [(label: String, value: String)] = []
        for row in rows {
            guard let name = (row["product"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            if let value = row["usagePercent"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite else { continue }
                let percent = max(0, min(100, number.doubleValue))
                lines.append((label: "产品用量 · \(displayProduct(name))", value: formatPercent(percent)))
            } else {
                // Named products without usagePercent are shown as unknown, not invented 0%.
                lines.append((label: "产品用量 · \(displayProduct(name))", value: "无数据"))
            }
        }
        return lines
    }

    private static func displayProduct(_ raw: String) -> String {
        switch raw {
        case "GrokBuild": return "Grok Build"
        case "GrokChat": return "Grok Chat"
        case "GrokImagine": return "Grok Imagine"
        case "GrokVoice": return "Grok Voice"
        case "GrokTasks": return "Grok Tasks"
        case "Api", "API": return "API"
        default: return raw
        }
    }

    /// Show prepaid only when the field is present and the amount is greater than zero.
    private static func optionalPositiveCents(_ raw: Any?) -> Int64? {
        guard let cents = centsValue(raw), cents > 0 else { return nil }
        return cents
    }

    private static func onDemandLine(used: Any?, cap: Any?) -> (label: String, value: String)? {
        let usedCents = centsValue(used)
        let capCents = centsValue(cap)
        let hasUsed = usedCents.map { $0 > 0 } ?? false
        let hasCap = capCents.map { $0 > 0 } ?? false
        guard hasUsed || hasCap else { return nil }
        let usedText = formatUSD(cents: usedCents ?? 0)
        if hasCap {
            return (label: "按需用量", value: "\(usedText) / \(formatUSD(cents: capCents!))")
        }
        return (label: "按需用量", value: usedText)
    }

    private static func centsValue(_ raw: Any?) -> Int64? {
        guard let raw else { return nil }
        if let object = raw as? [String: Any] {
            if object.isEmpty { return 0 }
            if let value = object["val"] {
                return int64Value(value)
            }
            return nil
        }
        return int64Value(raw)
    }

    private static func int64Value(_ raw: Any) -> Int64? {
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let value = number.doubleValue
            guard value.isFinite, value == value.rounded() else { return nil }
            return number.int64Value
        }
        if let text = raw as? String, let value = Int64(text) { return value }
        return nil
    }

    private static func formatUSD(cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "$0.00"
    }

    static func formatPercent(_ value: Double) -> String {
        if value.isFinite, abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f%%", value.rounded())
        }
        return String(format: "%.1f%%", value)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }
    }
}

enum GrokUsageStatus {
    static let lastSuccessRefreshValue = "上次成功结果（旧缓存），不是本次查询"

    static func markAsLastSuccessCache(_ usage: PlatformUsageData) -> PlatformUsageData {
        var extra = usage.extraInfo
        var replaced = false
        extra = extra.map { item in
            guard item.label == "刷新状态" else { return item }
            replaced = true
            return (label: item.label, value: lastSuccessRefreshValue)
        }
        if !replaced {
            extra.append((label: "刷新状态", value: lastSuccessRefreshValue))
        }
        var retained = usage
        retained.extraInfo = extra
        return retained
    }

    static func retainedFailureMessage(base: String, previous: PlatformUsageData, now: Date = Date()) -> String {
        var text = base
        text += "。已保留上次成功结果，可能不是当前用量"
        if let reset = previous.items.first(where: { $0.key == "grok.weekly" })?.resetDate, reset <= now {
            text += "。上次周期已结束，请勿当作当前额度"
        }
        return text
    }
}
