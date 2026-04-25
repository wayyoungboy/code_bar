import Foundation

/// ZenMux 平台用量提供者
struct ZenMuxProvider: PlatformProvider {
    let platformName = "ZenMux"
    private let config: ZenMuxConfig
    private let baseURL = "https://zenmux.ai/api/v1/management"

    init(config: ZenMuxConfig) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let url = URL(string: "\(baseURL)/subscription/detail") else {
            throw PlatformError.unknown("无效的 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // 使用安全的日志记录
        AppLogger.logRequest(url: url.absoluteString, method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
        }

        AppLogger.logResponse(url: url.absoluteString, statusCode: httpResponse.statusCode)

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw PlatformError.invalidAPIKey
        case 429:
            throw PlatformError.rateLimited
        default:
            throw PlatformError.unknown("HTTP \(httpResponse.statusCode)")
        }

        // 解析 JSON 响应
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let success = rawJSON?["success"] as? Bool, success,
              let responseData = rawJSON?["data"] as? [String: Any] else {
            AppLogger.logParseError(message: "响应格式错误")
            throw PlatformError.unknown("响应格式错误")
        }

        // 解析配额信息
        guard let quota5Hour = responseData["quota_5_hour"] as? [String: Any],
              let quota7Day = responseData["quota_7_day"] as? [String: Any],
              let planInfo = responseData["plan"] as? [String: Any] else {
            AppLogger.logParseError(message: "配额数据缺失")
            throw PlatformError.unknown("配额数据缺失")
        }

        // 5 小时配额
        let total5Hour = quota5Hour["max_flows"] as? Int ?? 0
        let used5Hour = Int(quota5Hour["used_flows"] as? Double ?? 0)
        let reset5HourStr = quota5Hour["resets_at"] as? String ?? ""
        let resetDate5Hour = parseISODate(reset5HourStr) ?? Date().addingTimeInterval(5 * 3600)

        // 7 天配额
        let total7Day = quota7Day["max_flows"] as? Int ?? 0
        let used7Day = Int(quota7Day["used_flows"] as? Double ?? 0)
        let reset7DayStr = quota7Day["resets_at"] as? String ?? ""
        let resetDate7Day = parseISODate(reset7DayStr) ?? Date().addingTimeInterval(7 * 24 * 3600)

        let planType = planInfo["tier"] as? String ?? "Unknown"
        let planAmount = planInfo["amount_usd"] as? Double ?? 0
        let planInterval = planInfo["interval"] as? String ?? ""
        let expiresAtStr = planInfo["expires_at"] as? String ?? ""

        let accountStatus = responseData["account_status"] as? String ?? ""
        let baseUsdPerFlow = responseData["base_usd_per_flow"] as? Double ?? 0
        let effectiveUsdPerFlow = responseData["effective_usd_per_flow"] as? Double ?? 0

        let used5HourUsd = quota5Hour["used_value_usd"] as? Double ?? 0
        let max5HourUsd = quota5Hour["max_value_usd"] as? Double ?? 0
        let used7DayUsd = quota7Day["used_value_usd"] as? Double ?? 0
        let max7DayUsd = quota7Day["max_value_usd"] as? Double ?? 0

        let monthlyMaxFlows = (responseData["quota_monthly"] as? [String: Any])?["max_flows"] as? Int ?? 0
        let monthlyMaxUsd = (responseData["quota_monthly"] as? [String: Any])?["max_value_usd"] as? Double ?? 0

        var extra: [(label: String, value: String)] = []
        extra.append((label: "账户状态", value: accountStatus))
        extra.append((label: "套餐", value: "\(planType.capitalized) $\(String(format: "%.0f", planAmount))/\(planInterval)"))
        if let expiresAt = parseISODate(expiresAtStr) {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            extra.append((label: "到期时间", value: fmt.string(from: expiresAt)))
        }
        extra.append((label: "单价", value: "$\(String(format: "%.4f", effectiveUsdPerFlow))/flow"))
        if baseUsdPerFlow != effectiveUsdPerFlow {
            extra.append((label: "原价", value: "$\(String(format: "%.4f", baseUsdPerFlow))/flow"))
        }
        extra.append((label: "5小时费用", value: "$\(String(format: "%.2f", used5HourUsd)) / $\(String(format: "%.2f", max5HourUsd))"))
        extra.append((label: "7天费用", value: "$\(String(format: "%.2f", used7DayUsd)) / $\(String(format: "%.2f", max7DayUsd))"))
        extra.append((label: "月配额", value: "\(monthlyMaxFlows) flows ($\(String(format: "%.2f", monthlyMaxUsd)))"))

        return PlatformUsageData(
            platformName: platformName,
            planType: planType.capitalized,
            items: [
                UsageItem(key: "5hour", label: "5小时", used: used5Hour, total: total5Hour, unit: "flows", resetDate: resetDate5Hour),
                UsageItem(key: "7day", label: "7天", used: used7Day, total: total7Day, unit: "flows", resetDate: resetDate7Day),
            ],
            extraInfo: extra
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    // MARK: - 辅助方法

    private func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}