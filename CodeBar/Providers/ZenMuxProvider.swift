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
        let validAccounts = config.accounts.filter(\.isValid)
        let invalidAccounts = config.accounts.filter { !$0.isValid }
        guard !validAccounts.isEmpty else {
            throw PlatformError.invalidAPIKey
        }

        var accountBreakdowns = invalidAccounts.map { account in
            AccountUsageData(
                id: account.id,
                alias: account.displayName,
                planType: "错误",
                items: [],
                resetTimeKeys: account.resetTimeKeys,
                errorMessage: "API Key 无效"
            )
        }
        var failures = invalidAccounts.map { (alias: $0.displayName, message: "API Key 无效") }

        await withTaskGroup(of: (ZenMuxAccountConfig, Result<AccountUsageData, Error>).self) { group in
            for account in validAccounts {
                group.addTask {
                    do {
                        let usage = try await fetchAccountUsage(for: account)
                        return (account, .success(usage))
                    } catch {
                        return (account, .failure(error))
                    }
                }
            }

            for await (account, result) in group {
                switch result {
                case .success(let usage):
                    accountBreakdowns.append(usage)
                case .failure(let error):
                    let message = (error as? PlatformError)?.errorDescription ?? error.localizedDescription
                    failures.append((alias: account.displayName, message: message))
                    accountBreakdowns.append(AccountUsageData(
                        id: account.id,
                        alias: account.displayName,
                        planType: "错误",
                        items: [],
                        resetTimeKeys: account.resetTimeKeys,
                        errorMessage: message
                    ))
                }
            }
        }

        let successfulAccounts = accountBreakdowns.filter { $0.errorMessage == nil }
        guard !successfulAccounts.isEmpty else {
            let message = failures.first?.message ?? "所有 ZenMux 账号请求失败"
            throw PlatformError.unknown(message)
        }

        let aggregateItems = aggregateItems(from: successfulAccounts)
        var extra: [(label: String, value: String)] = config.accounts.count == 1
            ? (successfulAccounts.first?.extraInfo ?? [])
            : []
        for failure in failures {
            extra.append((label: "\(failure.alias)失败", value: failure.message))
        }

        accountBreakdowns.sort { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }

        return PlatformUsageData(
            platformName: platformName,
            planType: config.accounts.count == 1 ? (successfulAccounts.first?.planType ?? "ZenMux") : "\(successfulAccounts.count)/\(config.accounts.count) 账号",
            items: aggregateItems,
            extraInfo: extra,
            accountBreakdowns: accountBreakdowns
        )
    }

    private func fetchAccountUsage(for account: ZenMuxAccountConfig) async throws -> AccountUsageData {
        guard let url = URL(string: "\(baseURL)/subscription/detail") else {
            throw PlatformError.unknown("无效的 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(account.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        // 解析 JSON 响应
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let success = rawJSON?["success"] as? Bool, success,
              let responseData = rawJSON?["data"] as? [String: Any] else {
            throw PlatformError.unknown("响应格式错误")
        }

        // 解析配额信息
        guard let quota5Hour = responseData["quota_5_hour"] as? [String: Any],
              let quota7Day = responseData["quota_7_day"] as? [String: Any],
              let planInfo = responseData["plan"] as? [String: Any] else {
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

        let items = [
            UsageItem(key: "5hour", label: "5小时", used: used5Hour, total: total5Hour, unit: "flows", resetDate: resetDate5Hour),
            UsageItem(key: "7day", label: "7天", used: used7Day, total: total7Day, unit: "flows", resetDate: resetDate7Day),
        ].filter { account.displayKeys.contains($0.key) }

        return AccountUsageData(
            id: account.id,
            alias: account.displayName,
            planType: planType.capitalized,
            items: items,
            resetTimeKeys: account.resetTimeKeys,
            extraInfo: extra
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    // MARK: - 辅助方法

    private func aggregateItems(from accounts: [AccountUsageData]) -> [UsageItem] {
        let preferredOrder = ["5hour", "7day"]
        let grouped = Dictionary(grouping: accounts.flatMap(\.items), by: \.key)

        return preferredOrder.compactMap { key in
            guard let items = grouped[key], let first = items.first else { return nil }
            let used = items.reduce(0) { $0 + $1.used }
            let total = items.reduce(0) { $0 + $1.total }
            let resetDate = items.compactMap(\.resetDate).min()
            return UsageItem(
                key: first.key,
                label: first.label,
                used: used,
                total: total,
                unit: first.unit,
                resetDate: resetDate
            )
        }
    }

    private func parseISODate(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
