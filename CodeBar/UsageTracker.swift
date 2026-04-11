import Foundation
import Combine

/// 显示类型
enum UsageDisplayType: String, CaseIterable, Identifiable {
    case billMonth = "账单月"
    case fiveHour = "5小时"
    case week = "周"

    var id: String { rawValue }
}

/// 支持的 platform 类型
enum PlatformType: String, CaseIterable, Identifiable {
    case bailian = "阿里云百炼"
    case zenmux = "ZenMux"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bailian:
            return "cloud.fill"
        case .zenmux:
            return "bolt.fill"
        }
    }

    var shortName: String {
        switch self {
        case .bailian:
            return "百炼"
        case .zenmux:
            return "ZenMux"
        }
    }
}

/// 多平台用量追踪器
@MainActor
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published var platforms: [PlatformType: PlatformUsage] = [:]
    @Published var errorMessages: [PlatformType: String] = [:]
    @Published var isLoading: Bool = false
    @Published var lastRefreshDate: Date = Date()

    // 每个平台的显示类型配置
    @Published var displayTypes: [PlatformType: [UsageDisplayType]] = [.bailian: [.billMonth, .fiveHour, .week], .zenmux: [.billMonth, .fiveHour, .week]] {
        didSet {
            saveDisplayConfig()
        }
    }

    var providers: [PlatformType: PlatformProvider] = [:]
    private var timer: Timer?

    /// 获取所有已配置的平台
    var configuredPlatforms: [PlatformType] {
        PlatformType.allCases.filter { providers[$0]?.isConfigured == true }
    }

    /// 是否有任何平台已配置
    var hasAnyConfig: Bool {
        providers.values.contains { $0.isConfigured }
    }

    /// 是否有任何错误
    var hasErrors: Bool {
        !errorMessages.isEmpty
    }

    /// 获取第一个错误消息（用于简单显示）
    var firstErrorMessage: String? {
        errorMessages.values.first
    }

    init() {
        loadConfig()
        loadDisplayConfig()
        loadFromStorage()
        setupTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 配置管理

    func loadConfig() {
        // 尝试从 Keychain 加载配置
        if let config = loadBailianConfig() {
            providers[.bailian] = BailianProvider(config: config)
            AppLogger.logConfigChange(platform: "百炼", action: "加载配置")
        }

        if let config = loadZenMuxConfig() {
            providers[.zenmux] = ZenMuxProvider(config: config)
            AppLogger.logConfigChange(platform: "ZenMux", action: "加载配置")
        }

        // 迁移旧的 UserDefaults 数据到 Keychain
        migrateFromUserDefaults()
    }

    /// 迁移旧的 UserDefaults 数据到 Keychain（向后兼容）
    private func migrateFromUserDefaults() {
        // 迁移 Bailian 配置
        if KeychainHelper.shared.exists(Constants.bailianConfigKey) == false {
            if let data = UserDefaults.standard.data(forKey: Constants.legacyBailianConfigKey) {
                try? KeychainHelper.shared.save(data, for: Constants.bailianConfigKey)
                UserDefaults.standard.removeObject(forKey: Constants.legacyBailianConfigKey)
                AppLogger.logConfigChange(platform: "百炼", action: "迁移到 Keychain")
            }
        }

        // 迁移 ZenMux 配置
        if KeychainHelper.shared.exists(Constants.zenmuxConfigKey) == false {
            if let data = UserDefaults.standard.data(forKey: Constants.legacyZenmuxConfigKey) {
                try? KeychainHelper.shared.save(data, for: Constants.zenmuxConfigKey)
                UserDefaults.standard.removeObject(forKey: Constants.legacyZenmuxConfigKey)
                AppLogger.logConfigChange(platform: "ZenMux", action: "迁移到 Keychain")
            }
        }
    }

    func saveBailianConfig(cookies: String, secToken: String, region: String = "cn-beijing") {
        let config = BailianConfig(cookies: cookies, secToken: secToken, region: region)
        providers[.bailian] = BailianProvider(config: config)

        // 保存到 Keychain
        do {
            try KeychainHelper.shared.save(config, for: Constants.bailianConfigKey)
            AppLogger.logConfigChange(platform: "百炼", action: "保存配置")
        } catch {
            AppLogger.logError(error)
        }

        // 清除该平台的错误
        errorMessages[.bailian] = nil

        // 刷新用量
        refresh()
    }

    func loadBailianConfig() -> BailianConfig? {
        return KeychainHelper.shared.readIfPresent(BailianConfig.self, for: Constants.bailianConfigKey)
    }

    func saveZenMuxConfig(apiKey: String) {
        let config = ZenMuxConfig(apiKey: apiKey)
        providers[.zenmux] = ZenMuxProvider(config: config)

        // 保存到 Keychain
        do {
            try KeychainHelper.shared.save(config, for: Constants.zenmuxConfigKey)
            AppLogger.logConfigChange(platform: "ZenMux", action: "保存配置")
        } catch {
            AppLogger.logError(error)
        }

        // 清除该平台的错误
        errorMessages[.zenmux] = nil

        // 刷新用量
        refresh()
    }

    func loadZenMuxConfig() -> ZenMuxConfig? {
        return KeychainHelper.shared.readIfPresent(ZenMuxConfig.self, for: Constants.zenmuxConfigKey)
    }

    func clearConfig(for platform: PlatformType) {
        switch platform {
        case .bailian:
            try? KeychainHelper.shared.delete(Constants.bailianConfigKey)
            providers[.bailian] = nil
            platforms[.bailian] = nil
            errorMessages[.bailian] = nil
            AppLogger.logConfigChange(platform: "百炼", action: "清除配置")
        case .zenmux:
            try? KeychainHelper.shared.delete(Constants.zenmuxConfigKey)
            providers[.zenmux] = nil
            platforms[.zenmux] = nil
            errorMessages[.zenmux] = nil
            AppLogger.logConfigChange(platform: "ZenMux", action: "清除配置")
        }
    }

    // MARK: - 显示配置

    private func saveDisplayConfig() {
        let data = displayTypes.mapValues { types in
            types.map { $0.rawValue }
        }
        UserDefaults.standard.set(data, forKey: Constants.displayTypesKey)
    }

    private func loadDisplayConfig() {
        if let data = UserDefaults.standard.dictionary(forKey: Constants.displayTypesKey) as? [String: [String]] {
            for (platformRaw, typesRaw) in data {
                if let platform = PlatformType.allCases.first(where: { $0.rawValue == platformRaw }) {
                    let types = typesRaw.compactMap { UsageDisplayType(rawValue: $0) }
                    if !types.isEmpty {
                        displayTypes[platform] = types
                    }
                }
            }
        }
    }

    func toggleDisplayType(_ type: UsageDisplayType, for platform: PlatformType) {
        if var types = displayTypes[platform] {
            if types.contains(type) {
                types.removeAll { $0 == type }
                if !types.isEmpty {
                    displayTypes[platform] = types
                }
            } else {
                types.append(type)
                displayTypes[platform] = types
            }
        }
    }

    // MARK: - 刷新用量

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessages = [:]

        defer {
            isLoading = false
        }

        for (platform, provider) in providers {
            guard provider.isConfigured else { continue }
            do {
                let usage = try await provider.fetchUsage()
                platforms[platform] = usage
                AppLogger.logUsageUpdate(platform: platform.shortName, used: usage.used, total: usage.total)
            } catch let err as PlatformError {
                errorMessages[platform] = err.errorDescription
                AppLogger.logError(err)
            } catch {
                errorMessages[platform] = error.localizedDescription
                AppLogger.logError(error)
            }
        }

        lastRefreshDate = Date()
        saveToStorage()
    }

    func refresh() {
        Task { @MainActor in
            await refresh()
        }
    }

    // MARK: - 本地存储

    private func saveToStorage() {
        var data: [String: [String: Any]] = [:]
        for (platform, usage) in platforms {
            data[platform.rawValue] = [
                "used": usage.used,
                "total": usage.total,
                "unit": usage.unit,
                "resetDate": usage.resetDate,
                "planType": usage.planType,
                "platformName": usage.platformName,
                "used5Hour": usage.used5Hour,
                "total5Hour": usage.total5Hour,
                "resetDate5Hour": usage.resetDate5Hour,
                "usedWeek": usage.usedWeek,
                "totalWeek": usage.totalWeek,
                "resetDateWeek": usage.resetDateWeek
            ]
        }
        UserDefaults.standard.set(data, forKey: Constants.usageCacheKey)
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.dictionary(forKey: Constants.usageCacheKey) else {
            return
        }

        for (platformName, usageData) in data {
            guard let platform = PlatformType.allCases.first(where: { $0.rawValue == platformName }),
                  let dict = usageData as? [String: Any],
                  let used = dict["used"] as? Int,
                  let total = dict["total"] as? Int,
                  let unit = dict["unit"] as? String,
                  let resetDate = dict["resetDate"] as? Date,
                  let planType = dict["planType"] as? String,
                  let platformNameValue = dict["platformName"] as? String,
                  let used5Hour = dict["used5Hour"] as? Int,
                  let total5Hour = dict["total5Hour"] as? Int,
                  let resetDate5Hour = dict["resetDate5Hour"] as? Date,
                  let usedWeek = dict["usedWeek"] as? Int,
                  let totalWeek = dict["totalWeek"] as? Int,
                  let resetDateWeek = dict["resetDateWeek"] as? Date else {
                continue
            }

            platforms[platform] = PlatformUsage(
                used: used,
                total: total,
                unit: unit,
                resetDate: resetDate,
                planType: planType,
                platformName: platformNameValue,
                used5Hour: used5Hour,
                total5Hour: total5Hour,
                resetDate5Hour: resetDate5Hour,
                usedWeek: usedWeek,
                totalWeek: totalWeek,
                resetDateWeek: resetDateWeek
            )
        }
    }

    private func setupTimer() {
        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        // 基础间隔 60 秒，加上 -5s 到 +5s 的随机浮动，避免触发风控
        let baseInterval: TimeInterval = Constants.refreshInterval
        let randomJitter = TimeInterval.random(in: -Constants.jitterRange...Constants.jitterRange)
        let interval = baseInterval + randomJitter

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
                self?.scheduleNextRefresh()
            }
        }
    }
}