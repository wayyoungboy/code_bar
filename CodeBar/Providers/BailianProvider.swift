import Foundation

/// 百炼平台用量提供者
struct BailianProvider: PlatformProvider {
    let platformName = "阿里云百炼"
    private let config: BailianConfig
    private let baseURL = "https://bailian-cs.console.aliyun.com"

    // 存储上次的 feTraceId，用于保持会话一致性
    private static var cachedTraceId: String?

    init(config: BailianConfig) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid
    }

    func fetchUsage() async throws -> PlatformUsage {
        guard let url = URL(string: buildURL()) else {
            throw PlatformError.unknown("无效的 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "accept-language")
        request.setValue("https://bailian.console.aliyun.com", forHTTPHeaderField: "origin")
        request.setValue(buildReferer(), forHTTPHeaderField: "referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        request.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue(cookies: config.cookies)

        let body = buildRequestBody()
        request.httpBody = body.data(using: .utf8)

        #if DEBUG
        print("🌐 请求 URL: \(url)")
        print("📦 请求体：\(body)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 响应：\(jsonString)")
        }
        #endif

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

        // 先用 JSONSerialization 解析原始数据，便于调试
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // 检查响应 code
        if let code = rawJSON?["code"] as? String, code != "200" {
            let message = rawJSON?["message"] as? String ?? "未知错误"
            throw PlatformError.unknown(message)
        }

        // 手动解析嵌套结构 - 真实结构是：data.DataV2.data.data.codingPlanInstanceInfos
        guard let dataDict = rawJSON?["data"] as? [String: Any],
              let dataV2 = dataDict["DataV2"] as? [String: Any],
              let dataV2Data = dataV2["data"] as? [String: Any],
              let dataContent = dataV2Data["data"] as? [String: Any],
              let instances = dataContent["codingPlanInstanceInfos"] as? [[String: Any]],
              let firstInstance = instances.first,
              let quotaInfo = firstInstance["codingPlanQuotaInfo"] as? [String: Any] else {
            print("❌ 解析失败 - 原始响应：")
            if let jsonData = try? JSONSerialization.data(withJSONObject: rawJSON ?? [:], options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
            throw PlatformError.unknown("无用量数据 - 响应结构不匹配")
        }

        // 从字典中提取用量数据
        guard let used = quotaInfo["perBillMonthUsedQuota"] as? Int,
              let total = quotaInfo["perBillMonthTotalQuota"] as? Int,
              let resetTimeMs = quotaInfo["perBillMonthQuotaNextRefreshTime"] as? Int64,
              let used5Hour = quotaInfo["per5HourUsedQuota"] as? Int,
              let total5Hour = quotaInfo["per5HourTotalQuota"] as? Int,
              let resetTime5HourMs = quotaInfo["per5HourQuotaNextRefreshTime"] as? Int64,
              let usedWeek = quotaInfo["perWeekUsedQuota"] as? Int,
              let totalWeek = quotaInfo["perWeekTotalQuota"] as? Int,
              let resetTimeWeekMs = quotaInfo["perWeekQuotaNextRefreshTime"] as? Int64 else {
            print("❌ 用量数据提取失败 - quotaInfo:")
            print(quotaInfo)
            throw PlatformError.unknown("用量数据字段缺失")
        }

        let planType = firstInstance["instanceName"] as? String ?? "Unknown"
        let resetTime = resetTimeMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(resetTimeMs / 1000))
            : Date().addingTimeInterval(7 * 24 * 3600)
        let resetTime5Hour = resetTime5HourMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(resetTime5HourMs / 1000))
            : Date().addingTimeInterval(5 * 3600)
        let resetTimeWeek = resetTimeWeekMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(resetTimeWeekMs / 1000))
            : Date().addingTimeInterval(7 * 24 * 3600)

        return PlatformUsage(
            used: used,
            total: total,
            unit: "tokens",
            resetDate: resetTime,
            planType: planType,
            platformName: platformName,
            used5Hour: used5Hour,
            total5Hour: total5Hour,
            resetDate5Hour: resetTime5Hour,
            usedWeek: usedWeek,
            totalWeek: totalWeek,
            resetDateWeek: resetTimeWeek
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    // MARK: - 请求构建

    private func buildURL() -> String {
        "\(baseURL)/data/api.json?action=BroadScopeAspnGateway&product=sfm_bailian&api=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2&_v=undefined&region=\(config.region)"
    }

    private func buildReferer() -> String {
        "https://bailian.console.aliyun.com/\(config.region)/?tab=coding-plan"
    }

    private func buildRequestBody() -> String {
        // 使用或创建 traceId
        if Self.cachedTraceId == nil {
            Self.cachedTraceId = UUID().uuidString
        }

        let params = """
        {"Api":"zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2","V":"1.0","Data":{"queryCodingPlanInstanceInfoRequest":{"commodityCode":"sfm_codingplan_public_cn","onlyLatestOne":true},"cornerstoneParam":{"feTraceId":"\(Self.cachedTraceId ?? UUID().uuidString)","feURL":"\(buildReferer())","protocol":"V2","console":"ONE_CONSOLE","productCode":"p_efm","switchAgent":11603654,"switchUserType":3,"domain":"bailian.console.aliyun.com","consoleSite":"BAILIAN_ALIYUN","xsp_lang":"zh-CN","X-Anonymous-Id":"anonymous"}}}
        """

        return "params=\(params.urlEncoded())&region=\(config.region)&sec_token=\(config.secToken)"
    }
}

// MARK: - 辅助扩展

extension String {
    func urlEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

extension URLRequest {
    mutating func setValue(cookies: String) {
        setValue(cookies, forHTTPHeaderField: "cookie")
    }
}

// MARK: - API 响应模型

struct BailianAPIResponse: Codable {
    let code: String
    let message: String?
    let data: BailianResponseData?
    let successResponse: Bool?
}

struct BailianResponseData: Codable {
    let DataV2: DataV2Response?
    let success: Bool?
}

struct DataV2Response: Codable {
    let data: DataV2Data?
    let ret: [String]?
}

struct DataV2Data: Codable {
    let codingPlanInstanceInfos: [CodingPlanInfo]?
    let userId: String?
}

struct CodingPlanInfo: Codable {
    let codingPlanQuotaInfo: CodingPlanQuotaInfo?
    let instanceId: String?
    let instanceName: String?
    let instanceType: String?
    let remainingDays: Int?
    let chargeType: String?
    let status: String?
}

struct CodingPlanQuotaInfo: Codable {
    let perBillMonthUsedQuota: Int       // 账单周期已用
    let perBillMonthTotalQuota: Int      // 账单周期总额度
    let perBillMonthQuotaNextRefreshTime: Int64  // 账单周期重置时间 (毫秒)

    let per5HourUsedQuota: Int           // 5 小时周期已用
    let per5HourTotalQuota: Int          // 5 小时周期总额度
    let per5HourQuotaNextRefreshTime: Int64  // 5 小时周期重置时间 (毫秒)

    let perWeekUsedQuota: Int            // 周周期已用
    let perWeekTotalQuota: Int           // 周周期总额度
    let perWeekQuotaNextRefreshTime: Int64  // 周周期重置时间 (毫秒)
}
