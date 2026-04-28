import Foundation
import Combine
import UserNotifications

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
    @Published var isLoading: Bool = false
    @Published var lastRefreshDate: Date = Date()
    @Published var notificationPermissionGranted: Bool = false

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

    /// 平台是否启用（已配置且未关闭）
    func isPlatformEnabled(_ platform: PlatformType) -> Bool {
        guard providers[platform]?.isConfigured == true else { return false }
        return enabledPlatforms[platform] ?? true
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

    /// ZenMux 通知功能是否启用
    var isZenMuxNoticeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Constants.zenmuxNoticeEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.zenmuxNoticeEnabledKey) }
    }

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        loadConfig()
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

    func loadConfig() {
        let allConfigs = loadAllConfigs()

        if let data = allConfigs[PlatformType.bailian.rawValue],
           let config = try? JSONDecoder().decode(BailianConfig.self, from: data) {
            providers[.bailian] = BailianProvider(config: config)
            AppLogger.logConfigChange(platform: "百炼", action: "加载配置")
        }

        if let data = allConfigs[PlatformType.zenmux.rawValue],
           let config = try? JSONDecoder().decode(ZenMuxConfig.self, from: data) {
            providers[.zenmux] = ZenMuxProvider(config: config)
            AppLogger.logConfigChange(platform: "ZenMux", action: "加载配置")
        }
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
        } catch {
            AppLogger.logError(error)
        }
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
        AppLogger.logConfigChange(platform: "百炼", action: "保存配置")
        errorMessages[.bailian] = nil
        refresh()
    }

    func loadBailianConfig() -> BailianConfig? {
        guard let data = loadAllConfigs()[PlatformType.bailian.rawValue] else { return nil }
        return try? JSONDecoder().decode(BailianConfig.self, from: data)
    }

    func saveZenMuxConfig(apiKey: String) {
        let config = ZenMuxConfig(apiKey: apiKey)
        providers[.zenmux] = ZenMuxProvider(config: config)
        savePlatformConfig(config, for: .zenmux)
        AppLogger.logConfigChange(platform: "ZenMux", action: "保存配置")
        errorMessages[.zenmux] = nil
        refresh()
    }

    func loadZenMuxConfig() -> ZenMuxConfig? {
        guard let data = loadAllConfigs()[PlatformType.zenmux.rawValue] else { return nil }
        return try? JSONDecoder().decode(ZenMuxConfig.self, from: data)
    }

    func clearConfig(for platform: PlatformType) {
        removePlatformConfig(for: platform)
        providers[platform] = nil
        platforms[platform] = nil
        errorMessages[platform] = nil
        AppLogger.logConfigChange(platform: platform.shortName, action: "清除配置")
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
        resetTimeKeys[platform]?.contains(key) == true
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

        defer {
            isLoading = false
        }

        for (platform, provider) in providers {
            guard isPlatformEnabled(platform) else { continue }
            do {
                let usage = try await provider.fetchUsage()
                platforms[platform] = usage
                if platform == .zenmux && isZenMuxNoticeEnabled {
                    checkZenMuxRefreshNotices(usage: usage)
                }
                let firstItem = usage.items.first
                AppLogger.logUsageUpdate(platform: platform.shortName, used: firstItem?.used ?? 0, total: firstItem?.total ?? 0)
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
            data[platform.rawValue] = [
                "platformName": usage.platformName,
                "planType": usage.planType,
                "items": itemsArray,
                "extraInfo": extraArray,
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

            platforms[platform] = PlatformUsageData(
                platformName: platformName,
                planType: planType,
                items: items,
                extraInfo: extraInfo
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationPermissionGranted = granted
                if let error {
                    AppLogger.logError(error)
                }
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
                AppLogger.general.info("通知权限未授权，无法发送测试通知")
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

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.general.error("发送通知失败: \(error.localizedDescription)")
            } else {
                AppLogger.general.info("通知已发送: \(title)")
            }
        }
    }

    private func checkZenMuxRefreshNotices(usage: PlatformUsageData) {
        for item in usage.items {
            guard let cacheKey = noticeCacheKey(for: item.key) else { continue }
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

    private func noticeCacheKey(for itemKey: String) -> String? {
        switch itemKey {
        case "5hour": return Constants.zenmuxNotice5Hour
        case "7day": return Constants.zenmuxNotice7Day
        default: return nil
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