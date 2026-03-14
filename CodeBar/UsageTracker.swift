import Foundation
import Combine

/// 支持的 platform 类型
enum PlatformType: String, CaseIterable, Identifiable {
    case bailian = "阿里云百炼"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bailian:
            return "cloud.fill"
        }
    }
}

/// 多平台用量追踪器
class UsageTracker: ObservableObject {
    @Published var platforms: [PlatformType: PlatformUsage] = [:]
    @Published var selectedPlatform: PlatformType = .bailian
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isConfigured: Bool = false
    @Published var lastRefreshDate: Date = Date()

    // 显示类型配置
    @Published var displayTypes: [UsageDisplayType] = [.billMonth] {
        didSet {
            saveDisplayConfig()
            resetRotationIndex()
        }
    }
    @Published var currentDisplayIndex: Int = 0

    enum UsageDisplayType: String, CaseIterable, Identifiable {
        case billMonth = "账单月"
        case fiveHour = "5 小时"
        case week = "周"

        var id: String { rawValue }
    }

    private var providers: [PlatformType: PlatformProvider] = [:]
    private var timer: Timer?
    private var rotationTimer: Timer?

    var currentUsage: PlatformUsage? {
        platforms[selectedPlatform]
    }

    // 根据当前显示类型返回对应的用量数据
    var currentDisplayUsage: (used: Int, total: Int, percent: Double, resetDate: Date, label: String)? {
        guard let usage = currentUsage else { return nil }
        guard !displayTypes.isEmpty else { return nil }

        // 确保索引有效
        let safeIndex = currentDisplayIndex % displayTypes.count
        let displayType = displayTypes[safeIndex]

        switch displayType {
        case .billMonth:
            return (usage.used, usage.total, usage.usagePercent, usage.resetDate, "账单月")
        case .fiveHour:
            return (usage.used5Hour, usage.total5Hour, usage.used5HourPercent, usage.resetDate5Hour, "5 小时")
        case .week:
            return (usage.usedWeek, usage.totalWeek, usage.usedWeekPercent, usage.resetDateWeek, "周")
        }
    }

    var usagePercent: Double {
        currentUsage?.usagePercent ?? 0
    }

    var isLowUsage: Bool {
        (currentUsage?.usagePercent ?? 0) > 80
    }

    init() {
        loadConfig()
        loadDisplayConfig()
        loadFromStorage()
        setupTimer()
        setupRotationTimer()
    }

    // MARK: - 配置管理

    func loadConfig() {
        // 加载百炼配置
        if let config = loadBailianConfig() {
            providers[.bailian] = BailianProvider(config: config)
            isConfigured = config.isValid
        } else {
            isConfigured = false
        }
    }

    func saveBailianConfig(cookies: String, secToken: String, region: String = "cn-beijing") {
        let config = BailianConfig(cookies: cookies, secToken: secToken, region: region)
        providers[.bailian] = BailianProvider(config: config)
        isConfigured = config.isValid

        // 保存到 UserDefaults
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "BailianConfig")
        }

        // 立即刷新用量
        refresh()
    }

    func loadBailianConfig() -> BailianConfig? {
        guard let data = UserDefaults.standard.data(forKey: "BailianConfig") else {
            return nil
        }
        return try? JSONDecoder().decode(BailianConfig.self, from: data)
    }

    // MARK: - 显示配置

    private func saveDisplayConfig() {
        let types = displayTypes.map { $0.rawValue }
        UserDefaults.standard.set(types, forKey: "UsageDisplayTypes")
    }

    private func loadDisplayConfig() {
        if let types = UserDefaults.standard.array(forKey: "UsageDisplayTypes") as? [String] {
            displayTypes = types.compactMap { UsageDisplayType(rawValue: $0) }
        }
        if displayTypes.isEmpty {
            displayTypes = [.billMonth]
        }
    }

    private func resetRotationIndex() {
        currentDisplayIndex = 0
    }

    private func setupRotationTimer() {
        // 每 5 秒滚动一次显示
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 只有在多种显示类型时才滚动
            if self.displayTypes.count > 1 {
                self.currentDisplayIndex = (self.currentDisplayIndex + 1) % self.displayTypes.count
            }
        }
    }

    // MARK: - 刷新用量

    @MainActor
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        for (platform, provider) in providers {
            do {
                let usage = try await provider.fetchUsage()
                platforms[platform] = usage
            } catch let error as PlatformError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
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
                "used5Hour": usage.used5Hour,
                "total5Hour": usage.total5Hour,
                "resetDate5Hour": usage.resetDate5Hour,
                "usedWeek": usage.usedWeek,
                "totalWeek": usage.totalWeek,
                "resetDateWeek": usage.resetDateWeek
            ]
        }
        UserDefaults.standard.set(data, forKey: "PlatformUsage")
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.dictionary(forKey: "PlatformUsage") else {
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
                platformName: platformName,
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
        let baseInterval: TimeInterval = 60.0
        let randomJitter = TimeInterval.random(in: -5.0...5.0)
        let interval = baseInterval + randomJitter

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
                self?.scheduleNextRefresh()
            }
        }
    }
}
