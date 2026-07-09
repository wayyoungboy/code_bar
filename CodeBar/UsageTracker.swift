import Foundation
import Combine
import UserNotifications

/// 支持的 platform 类型
enum PlatformType: String, CaseIterable, Identifiable, Codable {
    case bailian = "阿里云百炼"
    case zenmux = "ZenMux"
    case mimo = "小米 MiMo"
    case codex = "Codex"
    case gemini = "Gemini"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bailian: return "cloud.fill"
        case .zenmux: return "sparkles"
        case .mimo: return "m.circle.fill"
        case .codex: return "circle.hexagongrid.fill"
        case .gemini: return "sparkles"
        }
    }

    var logoAssetName: String? {
        switch self {
        case .bailian: return nil
        case .zenmux: return "ZenMuxLogo"
        case .mimo: return "XiaomiLogo"
        case .codex: return "CodexLogo"
        case .gemini: return "GeminiLogo"
        }
    }

    var usesOriginalLogoColor: Bool {
        switch self {
        case .mimo, .gemini: return true
        default: return false
        }
    }

    var shortName: String {
        switch self {
        case .bailian: return "百炼"
        case .zenmux: return "ZenMux"
        case .mimo: return "MiMo"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var brandColor: String {
        switch self {
        case .bailian: return "#0070FF"
        case .zenmux: return "#8B5CF6"
        case .mimo: return "#FF6900"
        case .codex: return "#10A37F"
        case .gemini: return "#4285F4"
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case independent
    case rotating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .independent: return "独立"
        case .rotating: return "轮播"
        }
    }

    var description: String {
        switch self {
        case .independent: return "每个模块创建一个独立 bar 栏状态项"
        case .rotating: return "多个模块共用一个状态项，按顺序自动切换"
        }
    }
}

/// 多平台用量追踪器
@MainActor
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    private let notificationDelegate = NotificationDelegate()

    @Published var platforms: [PlatformType: PlatformUsageData] = [:]
    @Published var errorMessages: [PlatformType: String] = [:]
    @Published var modules: [MonitorModule] = []
    @Published var moduleUsages: [String: PlatformUsageData] = [:]
    @Published var moduleErrors: [String: String] = [:]
    @Published var isLoading: Bool = false
    @Published var lastRefreshDate: Date = Date()
    @Published var notificationPermissionGranted: Bool = false
    @Published var menuBarDisplayMode: MenuBarDisplayMode = MenuBarDisplayMode(
        rawValue: UserDefaults.standard.string(forKey: Constants.menuBarDisplayModeKey) ?? ""
    ) ?? .independent {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Constants.menuBarDisplayModeKey)
            NotificationCenter.default.post(name: .moduleStatusItemsChanged, object: nil)
        }
    }

    // 每个平台的启用状态
    @Published var enabledPlatforms: [PlatformType: Bool] = [:] {
        didSet {
            saveEnabledConfig()
        }
    }

    // 每个平台的重置时间显示配置（存储需要显示重置时间的 item key）
    @Published var resetTimeKeys: [PlatformType: [String]] = [:] {
        didSet {
            saveResetTimeConfig()
        }
    }

    // 每个平台的显示类型配置（存储 UsageItem 的 key）
    @Published var displayTypes: [PlatformType: [String]] = [:] {
        didSet {
            saveDisplayConfig()
        }
    }

    var providers: [PlatformType: PlatformProvider] = [:]
    private var timer: Timer?

    /// 平台是否启用（必须用户手动开启）
    func isPlatformEnabled(_ platform: PlatformType) -> Bool {
        guard providers[platform]?.isConfigured == true else { return false }
        return enabledPlatforms[platform] ?? false
    }

    /// 获取所有已启用的平台
    var configuredPlatforms: [PlatformType] {
        PlatformType.allCases.filter { isPlatformEnabled($0) }
    }

    /// 是否有任何平台已启用
    var hasAnyConfig: Bool {
        PlatformType.allCases.contains { isPlatformEnabled($0) }
    }

    /// 是否有任何错误
    var hasErrors: Bool {
        !errorMessages.isEmpty
    }

    /// 获取第一个错误消息（用于简单显示）
    var firstErrorMessage: String? {
        errorMessages.values.first
    }

    /// 额度刷新通知总开关
    var isQuotaRefreshNoticeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Constants.zenmuxNoticeEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.zenmuxNoticeEnabledKey) }
    }

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        loadModules()
        loadEnabledConfig()
        loadResetTimeConfig()
        loadDisplayConfig()
        loadFromStorage()
        setupTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 配置管理

    var sortedModules: [MonitorModule] {
        modules.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var detailModules: [MonitorModule] {
        sortedModules.filter(\.showInDetail)
    }

    var menuBarModules: [MonitorModule] {
        sortedModules.filter { $0.isMonitoringEnabled && $0.showInMenuBar && $0.isValid }
    }

    var hasAnyModule: Bool {
        !modules.isEmpty
    }

    func canAddModule(for platform: PlatformType, excluding moduleID: String? = nil) -> Bool {
        if platform == .zenmux {
            return true
        }
        return !modules.contains { module in
            module.id != moduleID && module.platform == platform
        }
    }

    func addModule(_ module: MonitorModule) {
        guard canAddModule(for: module.platform) else { return }
        var newModule = module
        if !modules.contains(where: { $0.id == module.id }) {
            newModule.sortOrder = modules.count
        }
        modules.append(newModule)
        normalizeModuleOrder()
        saveModules()
        refresh()
    }

    func updateModule(_ module: MonitorModule) {
        guard let index = modules.firstIndex(where: { $0.id == module.id }) else { return }
        guard canAddModule(for: module.platform, excluding: module.id) else { return }
        modules[index] = module
        normalizeModuleOrder()
        saveModules()
        refresh()
    }

    func updateModule(id: String, mutate: (inout MonitorModule) -> Void) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        mutate(&modules[index])
        normalizeModuleOrder()
        saveModules()
        refresh()
    }

    func updateModuleDisplayState(id: String, mutate: (inout MonitorModule) -> Void) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        mutate(&modules[index])
        saveModules(notifyStatusItemsChanged: false)
    }

    func deleteModule(_ module: MonitorModule) {
        modules.removeAll { $0.id == module.id }
        moduleUsages[module.id] = nil
        moduleErrors[module.id] = nil
        normalizeModuleOrder()
        saveModules()
        refresh()
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        var sorted = sortedModules
        sorted.move(fromOffsets: source, toOffset: destination)
        for index in sorted.indices {
            if let originalIndex = modules.firstIndex(where: { $0.id == sorted[index].id }) {
                modules[originalIndex].sortOrder = index
            }
        }
        saveModules()
        NotificationCenter.default.post(name: .moduleStatusItemsChanged, object: nil)
    }

    func displayKeys(for module: MonitorModule) -> [String] {
        if !module.displayKeys.isEmpty {
            return module.displayKeys
        }
        return moduleUsages[module.id]?.items.map(\.key) ?? []
    }

    func isResetTimeEnabled(_ key: String, for module: MonitorModule) -> Bool {
        module.resetTimeKeys.contains(key)
    }

    private func loadModules() {
        guard let data = try? KeychainHelper.shared.read(for: Constants.monitorModulesKey),
              let decoded = try? JSONDecoder().decode([MonitorModule].self, from: data) else {
            modules = []
            return
        }
        modules = decoded
        normalizeModuleOrder()
    }

    private func saveModules(notifyStatusItemsChanged: Bool = true) {
        do {
            let data = try JSONEncoder().encode(modules)
            try KeychainHelper.shared.save(data, for: Constants.monitorModulesKey)
            if notifyStatusItemsChanged {
                NotificationCenter.default.post(name: .moduleStatusItemsChanged, object: nil)
            }
        } catch {}
    }

    private func normalizeModuleOrder() {
        let sorted = sortedModules
        for index in sorted.indices {
            if let originalIndex = modules.firstIndex(where: { $0.id == sorted[index].id }) {
                modules[originalIndex].sortOrder = index
            }
        }
    }

    private func provider(for module: MonitorModule) -> PlatformProvider? {
        switch module.config {
        case .bailian(let config):
            return BailianProvider(config: config)
        case .zenmux:
            let account = ModuleProviderConfiguration.zenMuxAccount(for: module)
            return ZenMuxProvider(config: ZenMuxConfig(accounts: [account]))
        case .mimo(let config):
            return MimoProvider(config: config)
        case .codex(let config):
            return CodexProvider(config: config)
        case .gemini(let config):
            return GeminiProvider(config: config)
        }
    }

    func loadConfig() {
        let allConfigs = loadAllConfigs()

        if let data = allConfigs[PlatformType.bailian.rawValue],
           let config = try? JSONDecoder().decode(BailianConfig.self, from: data) {
            providers[.bailian] = BailianProvider(config: config)
        }

        if let data = allConfigs[PlatformType.zenmux.rawValue],
           let config = try? JSONDecoder().decode(ZenMuxConfig.self, from: data) {
            providers[.zenmux] = ZenMuxProvider(config: config)
        }

        if let data = allConfigs[PlatformType.mimo.rawValue],
           let config = try? JSONDecoder().decode(MimoConfig.self, from: data) {
            providers[.mimo] = MimoProvider(config: config)
        }

        let codexConfig = allConfigs[PlatformType.codex.rawValue]
            .flatMap { try? JSONDecoder().decode(CodexConfig.self, from: $0) } ?? CodexConfig()
        providers[.codex] = CodexProvider(config: codexConfig)

        let geminiConfig = allConfigs[PlatformType.gemini.rawValue]
            .flatMap { try? JSONDecoder().decode(GeminiConfig.self, from: $0) } ?? GeminiConfig()
        providers[.gemini] = GeminiProvider(config: geminiConfig)
    }

    private func loadAllConfigs() -> [String: Data] {
        guard let data = try? KeychainHelper.shared.read(for: Constants.platformConfigsKey),
              let dict = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveAllConfigs(_ configs: [String: Data]) {
        do {
            let data = try JSONEncoder().encode(configs)
            try KeychainHelper.shared.save(data, for: Constants.platformConfigsKey)
        } catch {}
    }

    private func savePlatformConfig<T: Codable>(_ config: T, for platform: PlatformType) {
        var allConfigs = loadAllConfigs()
        if let data = try? JSONEncoder().encode(config) {
            allConfigs[platform.rawValue] = data
            saveAllConfigs(allConfigs)
        }
    }

    private func removePlatformConfig(for platform: PlatformType) {
        var allConfigs = loadAllConfigs()
        allConfigs.removeValue(forKey: platform.rawValue)
        if allConfigs.isEmpty {
            try? KeychainHelper.shared.delete(Constants.platformConfigsKey)
        } else {
            saveAllConfigs(allConfigs)
        }
    }

    func saveBailianConfig(cookies: String, secToken: String, region: String = "cn-beijing") {
        let config = BailianConfig(cookies: cookies, secToken: secToken, region: region)
        providers[.bailian] = BailianProvider(config: config)
        savePlatformConfig(config, for: .bailian)
        errorMessages[.bailian] = nil
        refresh()
    }

    func loadBailianConfig() -> BailianConfig? {
        guard let data = loadAllConfigs()[PlatformType.bailian.rawValue] else { return nil }
        return try? JSONDecoder().decode(BailianConfig.self, from: data)
    }

    func saveZenMuxConfig(_ config: ZenMuxConfig) {
        providers[.zenmux] = ZenMuxProvider(config: config)
        savePlatformConfig(config, for: .zenmux)
        errorMessages[.zenmux] = nil
        refresh()
    }

    func loadZenMuxConfig() -> ZenMuxConfig? {
        guard let data = loadAllConfigs()[PlatformType.zenmux.rawValue] else { return nil }
        return try? JSONDecoder().decode(ZenMuxConfig.self, from: data)
    }

    func saveMimoConfig(serviceToken: String, userId: String) {
        let config = MimoConfig(serviceToken: serviceToken, userId: userId)
        providers[.mimo] = MimoProvider(config: config)
        savePlatformConfig(config, for: .mimo)
        errorMessages[.mimo] = nil
        refresh()
    }

    func loadMimoConfig() -> MimoConfig? {
        guard let data = loadAllConfigs()[PlatformType.mimo.rawValue] else { return nil }
        return try? JSONDecoder().decode(MimoConfig.self, from: data)
    }

    func saveCodexProxyURL(_ proxyURL: String?) {
        let trimmed = proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = CodexConfig(proxyURL: trimmed?.isEmpty == true ? nil : trimmed)
        providers[.codex] = CodexProvider(config: config)
        savePlatformConfig(config, for: .codex)
        errorMessages[.codex] = nil
        refresh()
    }

    func loadCodexConfig() -> CodexConfig? {
        guard let data = loadAllConfigs()[PlatformType.codex.rawValue] else { return nil }
        return try? JSONDecoder().decode(CodexConfig.self, from: data)
    }

    func saveGeminiProxyURL(_ proxyURL: String?) {
        let trimmed = proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = GeminiConfig(proxyURL: trimmed?.isEmpty == true ? nil : trimmed)
        providers[.gemini] = GeminiProvider(config: config)
        savePlatformConfig(config, for: .gemini)
        errorMessages[.gemini] = nil
        refresh()
    }

    func loadGeminiConfig() -> GeminiConfig? {
        guard let data = loadAllConfigs()[PlatformType.gemini.rawValue] else { return nil }
        return try? JSONDecoder().decode(GeminiConfig.self, from: data)
    }

    func clearConfig(for platform: PlatformType) {
        removePlatformConfig(for: platform)
        if platform == .codex {
            providers[.codex] = CodexProvider()
        } else if platform == .gemini {
            providers[.gemini] = GeminiProvider()
        } else {
            providers[platform] = nil
        }
        platforms[platform] = nil
        errorMessages[platform] = nil
    }

    // MARK: - 启用配置

    private func saveEnabledConfig() {
        var data: [String: Bool] = [:]
        for (platform, enabled) in enabledPlatforms {
            data[platform.rawValue] = enabled
        }
        UserDefaults.standard.set(data, forKey: Constants.enabledPlatformsKey)
    }

    private func loadEnabledConfig() {
        if let data = UserDefaults.standard.dictionary(forKey: Constants.enabledPlatformsKey) as? [String: Bool] {
            for (platformRaw, enabled) in data {
                if let platform = PlatformType.allCases.first(where: { $0.rawValue == platformRaw }) {
                    enabledPlatforms[platform] = enabled
                }
            }
        }
    }

    // MARK: - 显示配置

    /// 获取平台的显示 key 列表，未配置时返回该平台所有 item key
    func displayKeys(for platform: PlatformType) -> [String] {
        if platform == .zenmux {
            return platforms[platform]?.items.map(\.key) ?? []
        }
        if let keys = displayTypes[platform], !keys.isEmpty {
            return keys
        }
        return platforms[platform]?.items.map(\.key) ?? []
    }

    private func saveDisplayConfig() {
        var data: [String: [String]] = [:]
        for (platform, keys) in displayTypes {
            data[platform.rawValue] = keys
        }
        UserDefaults.standard.set(data, forKey: Constants.displayTypesKey)
    }

    private func loadDisplayConfig() {
        if let data = UserDefaults.standard.dictionary(forKey: Constants.displayTypesKey) as? [String: [String]] {
            for (platformRaw, keys) in data {
                if let platform = PlatformType.allCases.first(where: { $0.rawValue == platformRaw }) {
                    if !keys.isEmpty {
                        displayTypes[platform] = keys
                    }
                }
            }
        }
    }

    func toggleDisplayType(_ key: String, for platform: PlatformType) {
        var keys = displayTypes[platform] ?? platforms[platform]?.items.map(\.key) ?? []
        if keys.contains(key) {
            keys.removeAll { $0 == key }
        } else {
            keys.append(key)
        }
        if keys.isEmpty {
            keys = platforms[platform]?.items.map(\.key) ?? []
        }
        displayTypes[platform] = keys
    }

    // MARK: - 重置时间配置

    func isResetTimeEnabled(_ key: String, for platform: PlatformType) -> Bool {
        if platform == .zenmux {
            return loadZenMuxConfig()?.accounts.contains { account in
                account.displayKeys.contains(key) && account.resetTimeKeys.contains(key)
            } == true
        }
        return resetTimeKeys[platform]?.contains(key) == true
    }

    func toggleResetTime(_ key: String, for platform: PlatformType) {
        var keys = resetTimeKeys[platform] ?? []
        if keys.contains(key) {
            keys.removeAll { $0 == key }
        } else {
            keys.append(key)
        }
        resetTimeKeys[platform] = keys
    }

    private func saveResetTimeConfig() {
        var data: [String: [String]] = [:]
        for (platform, keys) in resetTimeKeys {
            data[platform.rawValue] = keys
        }
        UserDefaults.standard.set(data, forKey: Constants.resetTimeKeysKey)
    }

    private func loadResetTimeConfig() {
        if let data = UserDefaults.standard.dictionary(forKey: Constants.resetTimeKeysKey) as? [String: [String]] {
            for (platformRaw, keys) in data {
                if let platform = PlatformType.allCases.first(where: { $0.rawValue == platformRaw }) {
                    resetTimeKeys[platform] = keys
                }
            }
        }
    }

    // MARK: - 刷新用量

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessages = [:]
        moduleErrors = [:]

        defer {
            isLoading = false
        }

        if !modules.isEmpty {
            await refreshModules()
            lastRefreshDate = Date()
            NotificationCenter.default.post(name: .usageDataUpdated, object: nil)
            return
        }

        for (platform, provider) in providers {
            guard isPlatformEnabled(platform) else { continue }
            do {
                let usage = try await provider.fetchUsage()
                platforms[platform] = usage
                if platform == .zenmux && isQuotaRefreshNoticeEnabled {
                    checkZenMuxRefreshNotices(usage: usage)
                }
            } catch let err as PlatformError {
                errorMessages[platform] = err.errorDescription
                if platform == .zenmux {
                    platforms[platform] = nil
                }
            } catch {
                errorMessages[platform] = error.localizedDescription
                if platform == .zenmux {
                    platforms[platform] = nil
                }
            }
        }

        lastRefreshDate = Date()
        saveToStorage()
        NotificationCenter.default.post(name: .usageDataUpdated, object: nil)
    }

    private func refreshModules() async {
        for module in sortedModules {
            guard module.isMonitoringEnabled else {
                moduleUsages[module.id] = nil
                continue
            }
            guard module.isValid, let provider = provider(for: module) else {
                moduleUsages[module.id] = nil
                moduleErrors[module.id] = "配置无效"
                continue
            }

            do {
                var usage = try await provider.fetchUsage()
                usage = ModuleUsageStorage.usageForModuleCache(from: usage, module: module)
                moduleUsages[module.id] = usage
                if module.platform == .zenmux && isQuotaRefreshNoticeEnabled && module.isNotificationEnabled {
                    checkZenMuxRefreshNotices(usage: usage, moduleID: module.id)
                }
            } catch let err as PlatformError {
                moduleUsages[module.id] = nil
                moduleErrors[module.id] = err.errorDescription
            } catch {
                moduleUsages[module.id] = nil
                moduleErrors[module.id] = error.localizedDescription
            }
        }
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
            let itemsArray = usage.items.map { item -> [String: Any] in
                [
                    "key": item.key,
                    "label": item.label,
                    "used": item.used,
                    "total": item.total,
                    "unit": item.unit,
                    "resetDate": item.resetDate,
                ]
            }
            let extraArray = usage.extraInfo.map { info -> [String: String] in
                ["label": info.label, "value": info.value]
            }
            let accountArray = usage.accountBreakdowns.map { account -> [String: Any] in
                let accountItems = account.items.map { item -> [String: Any] in
                    [
                        "key": item.key,
                        "label": item.label,
                        "used": item.used,
                        "total": item.total,
                        "unit": item.unit,
                        "resetDate": item.resetDate,
                    ]
                }
                let accountExtra = account.extraInfo.map { info -> [String: String] in
                    ["label": info.label, "value": info.value]
                }
                var accountDict: [String: Any] = [
                    "id": account.id,
                    "alias": account.alias,
                    "planType": account.planType,
                    "items": accountItems,
                    "resetTimeKeys": account.resetTimeKeys,
                    "extraInfo": accountExtra,
                ]
                if let errorMessage = account.errorMessage {
                    accountDict["errorMessage"] = errorMessage
                }
                return accountDict
            }
            data[platform.rawValue] = [
                "platformName": usage.platformName,
                "planType": usage.planType,
                "items": itemsArray,
                "extraInfo": extraArray,
                "accountBreakdowns": accountArray,
            ]
        }
        UserDefaults.standard.set(data, forKey: Constants.usageCacheKey)
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.dictionary(forKey: Constants.usageCacheKey) else {
            return
        }

        for (platformRaw, usageData) in data {
            guard let platform = PlatformType.allCases.first(where: { $0.rawValue == platformRaw }),
                  let dict = usageData as? [String: Any],
                  let platformName = dict["platformName"] as? String,
                  let planType = dict["planType"] as? String,
                  let itemsArray = dict["items"] as? [[String: Any]] else {
                continue
            }

            let items = itemsArray.compactMap { itemDict -> UsageItem? in
                guard let key = itemDict["key"] as? String,
                      let label = itemDict["label"] as? String,
                      let used = itemDict["used"] as? Int,
                      let total = itemDict["total"] as? Int,
                      let unit = itemDict["unit"] as? String,
                      let resetDate = itemDict["resetDate"] as? Date else {
                    return nil
                }
                return UsageItem(key: key, label: label, used: used, total: total, unit: unit, resetDate: resetDate)
            }

            var extraInfo: [(label: String, value: String)] = []
            if let extraArray = dict["extraInfo"] as? [[String: String]] {
                extraInfo = extraArray.compactMap { d in
                    guard let label = d["label"], let value = d["value"] else { return nil }
                    return (label: label, value: value)
                }
            }

            var accountBreakdowns: [AccountUsageData] = []
            if let accountArray = dict["accountBreakdowns"] as? [[String: Any]] {
                accountBreakdowns = accountArray.compactMap { accountDict in
                    guard let id = accountDict["id"] as? String,
                          let alias = accountDict["alias"] as? String,
                          let accountPlanType = accountDict["planType"] as? String,
                          let accountItemsArray = accountDict["items"] as? [[String: Any]] else {
                        return nil
                    }

                    let accountItems = accountItemsArray.compactMap { itemDict -> UsageItem? in
                        guard let key = itemDict["key"] as? String,
                              let label = itemDict["label"] as? String,
                              let used = itemDict["used"] as? Int,
                              let total = itemDict["total"] as? Int,
                              let unit = itemDict["unit"] as? String,
                              let resetDate = itemDict["resetDate"] as? Date else {
                            return nil
                        }
                        return UsageItem(key: key, label: label, used: used, total: total, unit: unit, resetDate: resetDate)
                    }

                    var accountExtra: [(label: String, value: String)] = []
                    if let accountExtraArray = accountDict["extraInfo"] as? [[String: String]] {
                        accountExtra = accountExtraArray.compactMap { d in
                            guard let label = d["label"], let value = d["value"] else { return nil }
                            return (label: label, value: value)
                        }
                    }

                    return AccountUsageData(
                        id: id,
                        alias: alias,
                        planType: accountPlanType,
                        items: accountItems,
                        resetTimeKeys: accountDict["resetTimeKeys"] as? [String] ?? [],
                        extraInfo: accountExtra,
                        errorMessage: accountDict["errorMessage"] as? String
                    )
                }
            }

            platforms[platform] = PlatformUsageData(
                platformName: platformName,
                planType: planType,
                items: items,
                extraInfo: extraInfo,
                accountBreakdowns: accountBreakdowns
            )
        }
    }

    // MARK: - 通知

    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = granted
            }
        }
    }

    func sendTestNotice() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var authorized = settings.authorizationStatus == .authorized

            if !authorized {
                let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorized = granted == true
                notificationPermissionGranted = authorized
            }

            guard authorized else {
                return
            }

            sendNotice(title: "CodeBar 测试通知", body: "如果你看到这条消息，说明通知功能正常工作")
        }
    }

    private func sendNotice(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func checkZenMuxRefreshNotices(usage: PlatformUsageData, moduleID: String? = nil) {
        for item in usage.items {
            guard let cacheKey = noticeCacheKey(for: item.key, moduleID: moduleID) else { continue }
            let newResetDate = item.resetDate

            // resetDate 变化超过 1 小时才算真正进入新周期
            let isSignificantChange: Bool
            if let oldResetDate = UserDefaults.standard.object(forKey: cacheKey) as? Date {
                isSignificantChange = abs(oldResetDate.timeIntervalSince(newResetDate)) >= 3600
            } else {
                isSignificantChange = true
            }

            if isSignificantChange {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                formatter.unitsStyle = .abbreviated
                let remaining = formatter.string(from: Date(), to: newResetDate) ?? ""

                sendNotice(
                    title: "\(usage.platformName) 额度已刷新",
                    body: "\(item.label) 已重置，下次刷新在 \(remaining) 后"
                )
            }

            // 缓存始终更新，保持最新状态
            UserDefaults.standard.set(newResetDate, forKey: cacheKey)
        }
    }

    private func noticeCacheKey(for itemKey: String, moduleID: String? = nil) -> String? {
        let baseKey: String
        switch itemKey {
        case "5hour":
            baseKey = Constants.zenmuxNotice5Hour
        case "7day":
            baseKey = Constants.zenmuxNotice7Day
        default:
            return nil
        }
        guard let moduleID else { return baseKey }
        return "\(baseKey)_\(moduleID)"
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
