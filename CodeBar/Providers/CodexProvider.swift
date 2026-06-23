import Foundation

private final class CodexKeychainCredentialCache {
    static let shared = CodexKeychainCredentialCache()

    private let lock = NSLock()
    private var didRead = false
    private var cachedContent: String?

    private init() {}

    func readCodexAuth() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if didRead {
            return cachedContent
        }

        cachedContent = KeychainHelper.readExternalItem(service: "Codex Auth")
        didRead = true
        return cachedContent
    }
}

/// Codex CLI / ChatGPT OAuth 订阅额度提供者
struct CodexProvider: PlatformProvider {
    let platformName = "Codex"
    private let config: CodexConfig
    private let usageURL = "https://chatgpt.com/backend-api/wham/usage"

    init(config: CodexConfig = CodexConfig()) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid && readCredentials().accessToken != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        let credentials = readCredentials()
        guard let accessToken = credentials.accessToken else {
            throw PlatformError.unknown(credentials.message ?? "未找到 Codex CLI ChatGPT OAuth 凭据")
        }

        guard let url = URL(string: usageURL) else {
            throw PlatformError.unknown("无效的 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        AppLogger.logRequest(url: url.absoluteString, method: "GET")

        let session = try makeSession()
        let (data, response) = try await session.data(for: request)
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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.unknown("HTTP \(httpResponse.statusCode): \(body)")
        }

        let usageResponse: CodexUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw PlatformError.parseError(error)
        }

        let items = makeUsageItems(from: usageResponse)
        guard !items.isEmpty else {
            throw PlatformError.unknown("无 Codex 额度数据")
        }

        var extra: [(label: String, value: String)] = []
        let planType = displayPlanType(from: usageResponse.planType)
        if let rawPlanType = usageResponse.planType, !rawPlanType.isEmpty {
            extra.append((label: "套餐", value: planType))
        }
        extra.append((label: "凭据来源", value: credentials.source.displayName))
        if let accountID = credentials.accountID, !accountID.isEmpty {
            extra.append((label: "账号 ID", value: accountID))
        }
        if credentials.isStale {
            extra.append((label: "提示", value: "Token 可能已超过 8 天未刷新"))
        }
        appendAdditionalInfo(from: usageResponse, to: &extra)

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

#if CODEBAR_BEHAVIOR_TESTS
    static func testUsageItems(from json: String) throws -> [UsageItem] {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        return CodexProvider().makeUsageItems(from: response)
    }
#endif

    private func makeUsageItems(from response: CodexUsageResponse) -> [UsageItem] {
        var items: [UsageItem] = []

        if let rateLimit = response.rateLimit {
            items.append(contentsOf: [
                rateLimit.primaryWindow.flatMap { makeUsageItem(from: $0, fallbackSeconds: 18_000) },
                rateLimit.secondaryWindow.flatMap { makeUsageItem(from: $0, fallbackSeconds: 604_800) },
            ].compactMap { $0 })
        }

        for additionalLimit in response.additionalRateLimits ?? [] {
            guard let rateLimit = additionalLimit.rateLimit else { continue }
            let keyPrefix = "additional-\(stableKey(from: additionalLimit.limitName ?? additionalLimit.meteredFeature ?? "limit"))"
            let labelPrefix = additionalLimit.limitName ?? additionalLimit.meteredFeature ?? "额外额度"
            items.append(contentsOf: [
                rateLimit.primaryWindow.flatMap { makeUsageItem(from: $0, keyPrefix: keyPrefix, labelPrefix: labelPrefix) },
                rateLimit.secondaryWindow.flatMap { makeUsageItem(from: $0, keyPrefix: keyPrefix, labelPrefix: labelPrefix) },
            ].compactMap { $0 })
        }

        return items
    }

    private func makeUsageItem(
        from window: CodexRateLimitWindow,
        keyPrefix: String? = nil,
        labelPrefix: String? = nil,
        fallbackSeconds: Int? = nil
    ) -> UsageItem? {
        guard let usedPercent = window.usedPercent else { return nil }
        let used = max(0, min(100, Int(usedPercent.rounded())))
        guard let seconds = window.limitWindowSeconds ?? fallbackSeconds else { return nil }
        let resetDate = window.resetAt
            .flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date().addingTimeInterval(TimeInterval(max(window.resetAfterSeconds ?? seconds, 0)))
        let baseKey = tierKey(for: seconds)
        let baseLabel = tierLabel(for: seconds)

        return UsageItem(
            key: keyPrefix.map { "\($0)-\(baseKey)" } ?? baseKey,
            label: labelPrefix.map { "\($0) \(baseLabel)" } ?? baseLabel,
            used: used,
            total: 100,
            unit: "%",
            resetDate: resetDate
        )
    }

    private func tierKey(for seconds: Int) -> String {
        switch seconds {
        case 18_000: return "5hour"
        case 604_800: return "7day"
        default:
            let hours = seconds / 3_600
            if hours >= 24 {
                return "\(hours / 24)day"
            }
            return "\(max(hours, 1))hour"
        }
    }

    private func tierLabel(for seconds: Int) -> String {
        switch seconds {
        case 18_000: return "5小时"
        case 604_800: return "7天"
        default:
            let hours = seconds / 3_600
            if hours >= 24 {
                return "\(hours / 24)天"
            }
            return "\(max(hours, 1))小时"
        }
    }

    private func stableKey(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func displayPlanType(from rawPlanType: String?) -> String {
        guard let rawPlanType = rawPlanType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlanType.isEmpty else {
            return "订阅额度"
        }

        switch rawPlanType.lowercased() {
        case "free":
            return "Free"
        case "plus":
            return "Plus"
        case "pro":
            return "Pro"
        case "team":
            return "Team"
        case "enterprise":
            return "Enterprise"
        default:
            return rawPlanType
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private func appendAdditionalInfo(from response: CodexUsageResponse, to extra: inout [(label: String, value: String)]) {
        if let credits = response.credits {
            extra.append((label: "Credits", value: credits.summary))
        }
        if let spendControl = response.spendControl {
            extra.append((label: "消费限制", value: spendControl.summary))
        }
        if let resetCredits = response.rateLimitResetCredits?.availableCount {
            extra.append((label: "可用重置次数", value: "\(resetCredits)"))
        }
        if let reachedType = response.rateLimitReachedType, !reachedType.isEmpty {
            extra.append((label: "限制类型", value: reachedType))
        }
    }

    private func readCredentials() -> CodexCredentials {
        let authPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")

        if FileManager.default.fileExists(atPath: authPath.path) {
            do {
                let content = try String(contentsOf: authPath, encoding: .utf8)
                if let credentials = parseCredentialsJSON(content, source: .file), credentials.accessToken != nil {
                    return credentials
                }
            } catch {
                return CodexCredentials(
                    accessToken: nil,
                    accountID: nil,
                    source: .file,
                    isStale: false,
                    message: "读取 Codex auth.json 失败：\(error.localizedDescription)"
                )
            }
        }

        if let keychainContent = CodexKeychainCredentialCache.shared.readCodexAuth(),
           let credentials = parseCredentialsJSON(keychainContent, source: .keychain) {
            return credentials
        }

        return CodexCredentials(
            accessToken: nil,
            accountID: nil,
            source: .file,
            isStale: false,
            message: "未找到可用的 Codex ChatGPT OAuth 凭据，请先使用 Codex CLI 登录 ChatGPT"
        )
    }

    private func makeSession() throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.networkTimeout
        configuration.timeoutIntervalForResource = Constants.networkTimeout

        guard let rawProxyURL = config.proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawProxyURL.isEmpty else {
            return URLSession(configuration: configuration)
        }

        guard let proxyURL = URL(string: rawProxyURL),
              let scheme = proxyURL.scheme?.lowercased(),
              let host = proxyURL.host,
              let port = proxyURL.port else {
            throw PlatformError.unknown("Codex 代理地址无效，请使用 http://host:port 或 socks5://host:port")
        }

        switch scheme {
        case "http", "https":
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case "socks", "socks5":
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        default:
            throw PlatformError.unknown("Codex 代理协议不支持：\(scheme)")
        }

        return URLSession(configuration: configuration)
    }

    private func parseCredentialsJSON(_ content: String, source: CodexCredentials.Source) -> CodexCredentials? {
        guard let data = content.data(using: .utf8),
              let auth = try? JSONDecoder().decode(CodexAuthJSON.self, from: data) else {
            return nil
        }

        guard auth.authMode == "chatgpt" else {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                source: source,
                isStale: false,
                message: "Codex 当前不是 ChatGPT OAuth 模式"
            )
        }

        let accountID = auth.tokens?.accountID ?? auth.openAIAccountID ?? auth.accountID

        guard let token = auth.tokens?.accessToken, !token.isEmpty else {
            return CodexCredentials(
                accessToken: nil,
                accountID: accountID,
                source: source,
                isStale: false,
                message: "Codex OAuth access_token 缺失"
            )
        }

        return CodexCredentials(
            accessToken: token,
            accountID: accountID,
            source: source,
            isStale: isTokenStale(lastRefresh: auth.lastRefresh),
            message: nil
        )
    }

    private func isTokenStale(lastRefresh: String?) -> Bool {
        guard let lastRefresh,
              let date = ISO8601DateFormatter().date(from: lastRefresh) else {
            return false
        }
        return Date().timeIntervalSince(date) > 8 * 24 * 3_600
    }

    private static func decodeStringIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    private static func decodeIntIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            if let intValue = Int(value) {
                return intValue
            }
            if let doubleValue = Double(value) {
                return Int(doubleValue.rounded())
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return Int(date.timeIntervalSince1970)
            }
        }
        return nil
    }

    private static func decodeDoubleIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: ""))
        }
        return nil
    }

    private static func decodeBoolIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        return nil
    }

    private struct CodexCredentials {
        enum Source {
            case keychain
            case file

            var displayName: String {
                switch self {
                case .keychain: return "Keychain"
                case .file: return "~/.codex/auth.json"
                }
            }
        }

        let accessToken: String?
        let accountID: String?
        let source: Source
        let isStale: Bool
        let message: String?
    }

    private struct CodexAuthJSON: Decodable {
        let authMode: String?
        let tokens: CodexTokens?
        let lastRefresh: String?
        let openAIAccountID: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
            case lastRefresh = "last_refresh"
            case openAIAccountID = "openai_account_id"
            case accountID = "account_id"
        }
    }

    private struct CodexTokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }

    private struct CodexUsageResponse: Decodable {
        let userID: String?
        let accountID: String?
        let email: String?
        let planType: String?
        let rateLimit: CodexRateLimit?
        let codeReviewRateLimit: CodexRateLimit?
        let additionalRateLimits: [CodexAdditionalRateLimit]?
        let credits: CodexCredits?
        let spendControl: CodexSpendControl?
        let rateLimitReachedType: String?
        let promo: String?
        let referralBeacon: String?
        let rateLimitResetCredits: CodexRateLimitResetCredits?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case accountID = "account_id"
            case email
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case codeReviewRateLimit = "code_review_rate_limit"
            case additionalRateLimits = "additional_rate_limits"
            case credits
            case spendControl = "spend_control"
            case rateLimitReachedType = "rate_limit_reached_type"
            case promo
            case referralBeacon = "referral_beacon"
            case rateLimitResetCredits = "rate_limit_reset_credits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            userID = CodexProvider.decodeStringIfPresent(container, forKey: .userID)
            accountID = CodexProvider.decodeStringIfPresent(container, forKey: .accountID)
            email = CodexProvider.decodeStringIfPresent(container, forKey: .email)
            planType = CodexProvider.decodeStringIfPresent(container, forKey: .planType)
            rateLimit = try? container.decodeIfPresent(CodexRateLimit.self, forKey: .rateLimit)
            codeReviewRateLimit = try? container.decodeIfPresent(CodexRateLimit.self, forKey: .codeReviewRateLimit)
            additionalRateLimits = try? container.decodeIfPresent([CodexAdditionalRateLimit].self, forKey: .additionalRateLimits)
            credits = try? container.decodeIfPresent(CodexCredits.self, forKey: .credits)
            spendControl = try? container.decodeIfPresent(CodexSpendControl.self, forKey: .spendControl)
            rateLimitReachedType = CodexProvider.decodeStringIfPresent(container, forKey: .rateLimitReachedType)
            promo = CodexProvider.decodeStringIfPresent(container, forKey: .promo)
            referralBeacon = CodexProvider.decodeStringIfPresent(container, forKey: .referralBeacon)
            rateLimitResetCredits = try? container.decodeIfPresent(CodexRateLimitResetCredits.self, forKey: .rateLimitResetCredits)
        }
    }

    private struct CodexAdditionalRateLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: CodexRateLimit?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            limitName = CodexProvider.decodeStringIfPresent(container, forKey: .limitName)
            meteredFeature = CodexProvider.decodeStringIfPresent(container, forKey: .meteredFeature)
            rateLimit = try? container.decodeIfPresent(CodexRateLimit.self, forKey: .rateLimit)
        }
    }

    private struct CodexRateLimit: Decodable {
        let primaryWindow: CodexRateLimitWindow?
        let secondaryWindow: CodexRateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primaryWindow = try? container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .primaryWindow)
            secondaryWindow = try? container.decodeIfPresent(CodexRateLimitWindow.self, forKey: .secondaryWindow)
        }
    }

    private struct CodexRateLimitWindow: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case remainingPercent = "remaining_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let usedPercent = CodexProvider.decodeDoubleIfPresent(container, forKey: .usedPercent) {
                self.usedPercent = usedPercent
            } else if let remainingPercent = CodexProvider.decodeDoubleIfPresent(container, forKey: .remainingPercent) {
                self.usedPercent = 100 - remainingPercent
            } else {
                self.usedPercent = nil
            }
            limitWindowSeconds = CodexProvider.decodeIntIfPresent(container, forKey: .limitWindowSeconds)
            resetAfterSeconds = CodexProvider.decodeIntIfPresent(container, forKey: .resetAfterSeconds)
            resetAt = CodexProvider.decodeIntIfPresent(container, forKey: .resetAt)
        }
    }

    private struct CodexCredits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let overageLimitReached: Bool?
        let balance: String?
        let approxLocalMessages: [Int]?
        let approxCloudMessages: [Int]?

        var summary: String {
            if unlimited == true { return "Unlimited" }
            if hasCredits == true {
                return "余额 \(balance ?? "0")"
            }
            return overageLimitReached == true ? "已达上限" : "无可用余额"
        }

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case overageLimitReached = "overage_limit_reached"
            case balance
            case approxLocalMessages = "approx_local_messages"
            case approxCloudMessages = "approx_cloud_messages"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = CodexProvider.decodeBoolIfPresent(container, forKey: .hasCredits)
            unlimited = CodexProvider.decodeBoolIfPresent(container, forKey: .unlimited)
            overageLimitReached = CodexProvider.decodeBoolIfPresent(container, forKey: .overageLimitReached)
            balance = CodexProvider.decodeStringIfPresent(container, forKey: .balance)
            approxLocalMessages = try? container.decodeIfPresent([Int].self, forKey: .approxLocalMessages)
            approxCloudMessages = try? container.decodeIfPresent([Int].self, forKey: .approxCloudMessages)
        }
    }

    private struct CodexSpendControl: Decodable {
        let reached: Bool?
        let individualLimit: Double?

        var summary: String {
            if reached == true { return "已达到限制" }
            if let individualLimit {
                return "限制 \(individualLimit)"
            }
            return "未达到限制"
        }

        enum CodingKeys: String, CodingKey {
            case reached
            case individualLimit = "individual_limit"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reached = CodexProvider.decodeBoolIfPresent(container, forKey: .reached)
            individualLimit = CodexProvider.decodeDoubleIfPresent(container, forKey: .individualLimit)
        }
    }

    private struct CodexRateLimitResetCredits: Decodable {
        let availableCount: Int?

        enum CodingKeys: String, CodingKey {
            case availableCount = "available_count"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            availableCount = CodexProvider.decodeIntIfPresent(container, forKey: .availableCount)
        }
    }
}
