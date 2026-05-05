import Foundation

struct ZaiProvider: PlatformProvider {
    let platformName = "Z.ai"

    private var apiKey: String?

    private let subscriptionURL = "https://api.z.ai/api/biz/subscription/list"
    private let quotaURL = "https://api.z.ai/api/monitor/usage/quota/limit"

    init() {
        apiKey = Self.findApiKey()
    }

    var isConfigured: Bool {
        apiKey != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let apiKey else {
            throw PlatformError.invalidAPIKey
        }

        // Fetch subscription info
        var planType = "Free"
        if let subURL = URL(string: subscriptionURL) {
            var subReq = URLRequest(url: subURL)
            subReq.timeoutInterval = Constants.networkTimeout
            subReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            if let (subData, subResp) = try? await URLSession.shared.data(for: subReq),
               let httpResp = subResp as? HTTPURLResponse, httpResp.statusCode == 200,
               let subJson = try? JSONSerialization.jsonObject(with: subData) as? [String: Any],
               let dataArr = subJson["data"] as? [[String: Any]],
               let first = dataArr.first,
               let productName = first["productName"] as? String {
                planType = productName
            }
        }

        // Fetch quota limits
        guard let url = URL(string: quotaURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let limits = dataObj["limits"] as? [[String: Any]] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []

        for limit in limits {
            guard let limitType = limit["limitType"] as? String,
                  let used = limit["used"] as? Int,
                  let total = limit["limit"] as? Int, total > 0 else { continue }

            let unit = limit["unit"] as? Int ?? 0
            let windowSec = limit["windowSeconds"] as? Int ?? 0
            let resetDate = Date().addingTimeInterval(TimeInterval(windowSec > 0 ? windowSec : 5 * 3600))

            if limitType == "TOKENS_LIMIT" {
                if unit == 3 || windowSec <= 18000 {
                    items.append(UsageItem(
                        key: "session", label: "Session",
                        used: used, total: total, unit: "tokens",
                        resetDate: resetDate
                    ))
                } else {
                    items.append(UsageItem(
                        key: "weekly", label: "Weekly",
                        used: used, total: total, unit: "tokens",
                        resetDate: resetDate
                    ))
                }
            } else if limitType == "TIME_LIMIT" {
                items.append(UsageItem(
                    key: "searches", label: "Web Searches",
                    used: used, total: total, unit: "req",
                    resetDate: Date().addingTimeInterval(30 * 24 * 3600)
                ))
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

    private static func findApiKey() -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["ZAI_API_KEY"] ?? env["GLM_API_KEY"]
    }
}
