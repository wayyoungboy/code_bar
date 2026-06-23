import Foundation

/// 平台错误
enum PlatformError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case parseError(Error)
    case rateLimited
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key 无效"
        case .networkError(let error):
            return "网络错误：\(error.localizedDescription)"
        case .parseError(let error):
            return "解析错误：\(error.localizedDescription)"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .unknown(let message):
            return message
        }
    }
}

/// 单个配额条目
struct UsageItem {
    let key: String
    let label: String
    let used: Int
    let total: Int
    let unit: String
    let resetDate: Date

    var percent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

/// 单账号用量数据（用于支持同平台多账号明细）
struct AccountUsageData: Identifiable {
    let id: String
    let alias: String
    let planType: String
    let items: [UsageItem]
    let resetTimeKeys: [String]
    var extraInfo: [(label: String, value: String)] = []
    var errorMessage: String?
}

/// 平台用量数据
struct PlatformUsageData {
    let platformName: String
    let planType: String
    let items: [UsageItem]
    var extraInfo: [(label: String, value: String)] = []
    var accountBreakdowns: [AccountUsageData] = []
}

enum DetailUsagePresentation {
    static func items(from usage: PlatformUsageData, module: MonitorModule) -> [UsageItem] {
        usage.items
    }

    static func resetDate(for item: UsageItem, module: MonitorModule) -> Date? {
        item.resetDate
    }
}

enum ModuleUsageStorage {
    static func usageForModuleCache(from usage: PlatformUsageData, module: MonitorModule) -> PlatformUsageData {
        PlatformUsageData(
            platformName: module.displayName,
            planType: usage.planType,
            items: usage.items,
            extraInfo: usage.extraInfo,
            accountBreakdowns: usage.accountBreakdowns
        )
    }
}

enum ModuleProviderConfiguration {
    static func zenMuxAccount(for module: MonitorModule) -> ZenMuxAccountConfig {
        guard case .zenmux(var account) = module.config else {
            return ZenMuxAccountConfig()
        }
        account.displayKeys = ZenMuxAccountConfig.defaultDisplayKeys
        account.resetTimeKeys = module.resetTimeKeys
        return account
    }
}

enum MonitorModuleConfig: Codable {
    case bailian(BailianConfig)
    case zenmux(ZenMuxAccountConfig)
    case mimo(MimoConfig)
    case codex(CodexConfig)
    case gemini(GeminiConfig)

    private enum CodingKeys: String, CodingKey {
        case type
        case bailian
        case zenmux
        case mimo
        case codex
        case gemini
    }

    var platform: PlatformType {
        switch self {
        case .bailian: return .bailian
        case .zenmux: return .zenmux
        case .mimo: return .mimo
        case .codex: return .codex
        case .gemini: return .gemini
        }
    }

    var isValid: Bool {
        switch self {
        case .bailian(let config):
            return config.isValid
        case .zenmux(let account):
            return account.isValid
        case .mimo(let config):
            return config.isValid
        case .codex(let config):
            return config.isValid
        case .gemini(let config):
            return config.isValid
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PlatformType.self, forKey: .type)
        switch type {
        case .bailian:
            self = .bailian(try container.decode(BailianConfig.self, forKey: .bailian))
        case .zenmux:
            self = .zenmux(try container.decode(ZenMuxAccountConfig.self, forKey: .zenmux))
        case .mimo:
            self = .mimo(try container.decode(MimoConfig.self, forKey: .mimo))
        case .codex:
            self = .codex(try container.decode(CodexConfig.self, forKey: .codex))
        case .gemini:
            self = .gemini(try container.decode(GeminiConfig.self, forKey: .gemini))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .type)
        switch self {
        case .bailian(let config):
            try container.encode(config, forKey: .bailian)
        case .zenmux(let account):
            try container.encode(account, forKey: .zenmux)
        case .mimo(let config):
            try container.encode(config, forKey: .mimo)
        case .codex(let config):
            try container.encode(config, forKey: .codex)
        case .gemini(let config):
            try container.encode(config, forKey: .gemini)
        }
    }
}

struct MonitorModule: Codable, Identifiable {
    var id: String
    var alias: String
    var config: MonitorModuleConfig
    var isMonitoringEnabled: Bool
    var showInMenuBar: Bool
    var showInDetail: Bool
    var isNotificationEnabled: Bool
    var displayKeys: [String]
    var resetTimeKeys: [String]
    var isCollapsed: Bool
    var percentDisplayMode: UsagePercentDisplayMode
    var sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case alias
        case config
        case isMonitoringEnabled
        case showInMenuBar
        case showInDetail
        case isNotificationEnabled
        case displayKeys
        case resetTimeKeys
        case isCollapsed
        case percentDisplayMode
        case sortOrder
    }

    init(
        id: String = UUID().uuidString,
        alias: String,
        config: MonitorModuleConfig,
        isMonitoringEnabled: Bool = true,
        showInMenuBar: Bool = true,
        showInDetail: Bool = true,
        isNotificationEnabled: Bool = true,
        displayKeys: [String] = [],
        resetTimeKeys: [String] = [],
        isCollapsed: Bool = false,
        percentDisplayMode: UsagePercentDisplayMode = .used,
        sortOrder: Int
    ) {
        self.id = id
        self.alias = alias
        self.config = config
        self.isMonitoringEnabled = isMonitoringEnabled
        self.showInMenuBar = showInMenuBar
        self.showInDetail = showInDetail
        self.isNotificationEnabled = isNotificationEnabled
        self.displayKeys = displayKeys
        self.resetTimeKeys = resetTimeKeys
        self.isCollapsed = isCollapsed
        self.percentDisplayMode = percentDisplayMode
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        alias = try container.decode(String.self, forKey: .alias)
        config = try container.decode(MonitorModuleConfig.self, forKey: .config)
        isMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMonitoringEnabled) ?? true
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        showInDetail = try container.decodeIfPresent(Bool.self, forKey: .showInDetail) ?? true
        isNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isNotificationEnabled) ?? true
        displayKeys = try container.decodeIfPresent([String].self, forKey: .displayKeys) ?? []
        resetTimeKeys = try container.decodeIfPresent([String].self, forKey: .resetTimeKeys) ?? []
        isCollapsed = Self.decodeBoolIfPresent(container, forKey: .isCollapsed) ?? false
        percentDisplayMode = (try? container.decodeIfPresent(UsagePercentDisplayMode.self, forKey: .percentDisplayMode)) ?? .used
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(alias, forKey: .alias)
        try container.encode(config, forKey: .config)
        try container.encode(isMonitoringEnabled, forKey: .isMonitoringEnabled)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(showInDetail, forKey: .showInDetail)
        try container.encode(isNotificationEnabled, forKey: .isNotificationEnabled)
        try container.encode(displayKeys, forKey: .displayKeys)
        try container.encode(resetTimeKeys, forKey: .resetTimeKeys)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(percentDisplayMode, forKey: .percentDisplayMode)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    var platform: PlatformType {
        config.platform
    }

    var aliasDisplayName: String? {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var editorAlias: String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if case .zenmux(let account) = config {
            return account.alias
        }
        return alias
    }

    var editorDisplayKeys: [String] {
        if !displayKeys.isEmpty {
            return displayKeys
        }
        if case .zenmux(let account) = config {
            return account.displayKeys
        }
        return displayKeys
    }

    var editorResetTimeKeys: [String] {
        if !resetTimeKeys.isEmpty {
            return resetTimeKeys
        }
        if case .zenmux(let account) = config {
            return account.resetTimeKeys
        }
        return resetTimeKeys
    }

    var displayName: String {
        if let aliasDisplayName {
            return "\(platform.shortName) · \(aliasDisplayName)"
        }
        return platform.shortName
    }

    var isValid: Bool {
        config.isValid
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
}

enum UsagePercentDisplayMode: String, CaseIterable, Codable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .used: return "已用"
        case .remaining: return "剩余"
        }
    }

    func value(for item: UsageItem) -> Int {
        switch self {
        case .used:
            return item.used
        case .remaining:
            return max(item.total - item.used, 0)
        }
    }

    func percent(for item: UsageItem) -> Double {
        switch self {
        case .used:
            return item.percent
        case .remaining:
            return max(0, min(100, 100 - item.percent))
        }
    }

    func isNearLimit(_ item: UsageItem) -> Bool {
        switch self {
        case .used:
            return item.percent > 80
        case .remaining:
            return percent(for: item) < 20
        }
    }
}

enum UsageStatusFormatting {
    static func compactPercentText(for item: UsageItem, displayMode: UsagePercentDisplayMode) -> String {
        let prefix = displayMode == .remaining ? "剩" : ""
        return "\(prefix)\(String(format: "%.0f%%", displayMode.percent(for: item)))"
    }
}

/// 平台提供者协议
protocol PlatformProvider {
    var platformName: String { get }
    var isConfigured: Bool { get }

    /// 获取用量信息
    func fetchUsage() async throws -> PlatformUsageData

    /// 验证配置是否有效
    func validateConfig() async throws -> Bool
}

/// 平台配置
protocol PlatformConfig {
    var platform: PlatformType { get }
    var isValid: Bool { get }
}

/// 百炼平台配置
struct BailianConfig: PlatformConfig, Codable {
    let platform: PlatformType = .bailian
    var cookies: String
    var secToken: String
    var region: String = "cn-beijing"

    var isValid: Bool {
        !cookies.isEmpty && !secToken.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case cookies = "bailian_cookies"
        case secToken = "bailian_sec_token"
        case region = "bailian_region"
    }
}

/// ZenMux 平台配置
struct ZenMuxConfig: PlatformConfig, Codable {
    let platform: PlatformType = .zenmux
    var accounts: [ZenMuxAccountConfig]

    init(accounts: [ZenMuxAccountConfig] = []) {
        self.accounts = accounts
    }

    var isValid: Bool {
        accounts.contains(where: \.isValid)
    }

    enum CodingKeys: String, CodingKey {
        case accounts = "zenmux_accounts"
    }
}

struct ZenMuxAccountConfig: Codable, Identifiable, Equatable {
    var id: String
    var alias: String
    var apiKey: String
    var displayKeys: [String]
    var resetTimeKeys: [String]

    init(
        id: String = UUID().uuidString,
        alias: String = "",
        apiKey: String = "",
        displayKeys: [String] = ZenMuxAccountConfig.defaultDisplayKeys,
        resetTimeKeys: [String] = []
    ) {
        self.id = id
        self.alias = alias
        self.apiKey = apiKey
        self.displayKeys = displayKeys
        self.resetTimeKeys = resetTimeKeys
    }

    static let defaultDisplayKeys = ["5hour", "7day"]

    var isValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && apiKey.count >= 20
    }

    var displayName: String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名账号" : trimmed
    }
}

enum ModuleEditorConfigFactory {
    static func zenMuxConfig(
        alias: String,
        apiKey: String,
        displayKeys: [String],
        resetTimeKeys: [String]
    ) -> MonitorModuleConfig {
        .zenmux(ZenMuxAccountConfig(
            alias: alias,
            apiKey: apiKey,
            displayKeys: displayKeys,
            resetTimeKeys: resetTimeKeys
        ))
    }
}

/// 小米 MiMo 平台配置
struct MimoConfig: PlatformConfig, Codable {
    let platform: PlatformType = .mimo
    var serviceToken: String
    var userId: String

    var isValid: Bool {
        !serviceToken.isEmpty && !userId.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case serviceToken = "mimo_service_token"
        case userId = "mimo_user_id"
    }
}

/// Codex CLI / ChatGPT OAuth 用量配置
struct CodexConfig: PlatformConfig, Codable {
    let platform: PlatformType = .codex
    var proxyURL: String?

    init(proxyURL: String? = nil) {
        self.proxyURL = proxyURL
    }

    var isValid: Bool {
        true
    }

    enum CodingKeys: String, CodingKey {
        case proxyURL = "codex_proxy_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proxyURL = try container.decodeIfPresent(String.self, forKey: .proxyURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(proxyURL, forKey: .proxyURL)
    }
}

/// Gemini CLI / Code Assist OAuth 用量配置
struct GeminiConfig: PlatformConfig, Codable {
    let platform: PlatformType = .gemini
    var proxyURL: String?

    init(proxyURL: String? = nil) {
        self.proxyURL = proxyURL
    }

    var isValid: Bool {
        true
    }

    enum CodingKeys: String, CodingKey {
        case proxyURL = "gemini_proxy_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proxyURL = try container.decodeIfPresent(String.self, forKey: .proxyURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(proxyURL, forKey: .proxyURL)
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
