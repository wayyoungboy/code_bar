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

    func fetchUsage() async throws -> PlatformUsage {
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
              let quotaMonthly = responseData["quota_monthly"] as? [String: Any],
              let planInfo = responseData["plan"] as? [String: Any] else {
            AppLogger.logParseError(message: "配额数据缺失")
            throw PlatformError.unknown("配额数据缺失")
        }

        // 提取月度配额
        let totalMonthly = quotaMonthly["max_flows"] as? Int ?? 0
        let usedMonthlyRaw = quotaMonthly["used_flows"] as? Double ?? 0

        // 提取 5 小时配额
        let used5HourRaw = quota5Hour["used_flows"] as? Double ?? 0
        let total5Hour = quota5Hour["max_flows"] as? Int ?? 0
        let reset5HourStr = quota5Hour["resets_at"] as? String ?? ""

        // 提取 7 天配额
        let used7DayRaw = quota7Day["used_flows"] as? Double ?? 0
        let total7Day = quota7Day["max_flows"] as? Int ?? 0
        let reset7DayStr = quota7Day["resets_at"] as? String ?? ""

        // API 返回的 usage_percentage
        let usage5HourPercent = quota5Hour["usage_percentage"] as? Double ?? 0
        let usage7DayPercent = quota7Day["usage_percentage"] as? Double ?? 0

        // 计算已用量
        let used5Hour: Int
        if used5HourRaw > 0 {
            used5Hour = Int(used5HourRaw)
        } else if usage5HourPercent > 0, total5Hour > 0 {
            used5Hour = Int(Double(total5Hour) * usage5HourPercent)
        } else {
            used5Hour = 0
        }

        let used7Day: Int
        if used7DayRaw > 0 {
            used7Day = Int(used7DayRaw)
        } else if usage7DayPercent > 0, total7Day > 0 {
            used7Day = Int(Double(total7Day) * usage7DayPercent)
        } else {
            used7Day = 0
        }

        // 月度已用
        let usedMonthly: Int
        if usedMonthlyRaw > 0 {
            usedMonthly = Int(usedMonthlyRaw)
        } else {
            usedMonthly = used7Day
        }

        // 解析时间
        let resetDate = Date().addingTimeInterval(30 * 24 * 3600)
        let resetDate5Hour = parseISODate(reset5HourStr) ?? Date().addingTimeInterval(5 * 3600)
        let resetDate7Day = parseISODate(reset7DayStr) ?? Date().addingTimeInterval(7 * 24 * 3600)

        // 计划类型
        let planType = planInfo["tier"] as? String ?? "Unknown"

        return PlatformUsage(
            used: usedMonthly,
            total: totalMonthly,
            unit: "flows",
            resetDate: resetDate,
            planType: planType.capitalized,
            platformName: platformName,
            used5Hour: used5Hour,
            total5Hour: total5Hour,
            resetDate5Hour: resetDate5Hour,
            usedWeek: used7Day,
            totalWeek: total7Day,
            resetDateWeek: resetDate7Day
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