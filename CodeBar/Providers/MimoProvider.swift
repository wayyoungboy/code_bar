import Foundation

/// 小米 MiMo 平台用量提供者
struct MimoProvider: PlatformProvider {
    let platformName = "小米 MiMo"
    private let config: MimoConfig
    private let baseURL = "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"

    init(config: MimoConfig) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let url = URL(string: baseURL) else {
            throw PlatformError.unknown("无效的 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        request.setValue("api-platform_serviceToken=\"\(config.serviceToken)\"; userId=\(config.userId)", forHTTPHeaderField: "cookie")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
        }

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

        guard let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "MimoProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法解析 JSON"]))
        }

        let code = rawJSON["code"] as? Int ?? -1
        if code != 0 {
            let message = rawJSON["message"] as? String ?? "未知错误"
            throw PlatformError.unknown(message)
        }

        guard let dataDict = rawJSON["data"] as? [String: Any] else {
            throw PlatformError.unknown("响应缺少 data 字段")
        }

        var items: [UsageItem] = []

        // 下月1号作为重置时间锚点
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let resetDate = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))!

        // 解析总用量
        if let usage = dataDict["usage"] as? [String: Any],
           let usageItems = usage["items"] as? [[String: Any]] {
            for item in usageItems {
                guard let name = item["name"] as? String else { continue }
                let used = Int(item["used"] as? Double ?? 0)
                let limit = Int(item["limit"] as? Double ?? 0)
                // 跳过 limit 为 0 的补偿项
                if limit == 0 { continue }
                let label = name == "plan_total_token" ? "总用量" : name
                items.append(UsageItem(key: name, label: label, used: used, total: limit, unit: "tokens", resetDate: resetDate))
            }
        }

        // 解析月用量
        if let monthUsage = dataDict["monthUsage"] as? [String: Any],
           let monthItems = monthUsage["items"] as? [[String: Any]] {
            for item in monthItems {
                guard let name = item["name"] as? String else { continue }
                let used = Int(item["used"] as? Double ?? 0)
                let limit = Int(item["limit"] as? Double ?? 0)
                if limit == 0 { continue }
                let label = name == "month_total_token" ? "月用量" : name
                items.append(UsageItem(key: name, label: label, used: used, total: limit, unit: "tokens", resetDate: resetDate))
            }
        }

        if items.isEmpty {
            throw PlatformError.unknown("无用量数据")
        }

        return PlatformUsageData(
            platformName: platformName,
            planType: "MiMo",
            items: items
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }
}
