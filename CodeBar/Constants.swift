import Foundation

/// 应用配置常量
struct Constants {
    // MARK: - 时间间隔
    /// 数据刷新间隔（秒）
    static let refreshInterval: Double = 60.0

    /// 刷新间隔抖动范围（秒）
    static let jitterRange: Double = 5.0

    /// 菜单栏平台轮换间隔（秒）
    static let rotationInterval: Double = 5.0

    // MARK: - 网络配置
    /// 网络请求超时时间（秒）
    static let networkTimeout: Double = 30.0

    // MARK: - UI 尺寸
    /// 弹出窗口宽度
    static let popoverWidth: CGFloat = 360

    /// 弹出窗口内容最大高度
    static let popoverMaxHeight: CGFloat = 450

    /// 设置窗口宽度
    static let settingsWindowWidth: CGFloat = 520

    /// 设置窗口高度
    static let settingsWindowHeight: CGFloat = 620

    /// 帮助窗口宽度
    static let helpWindowWidth: CGFloat = 450

    /// 帮助窗口高度
    static let helpWindowHeight: CGFloat = 400

    // MARK: - Keychain 键名
    /// Bailian 配置存储键
    static let bailianConfigKey = "BailianConfig"

    /// ZenMux 配置存储键
    static let zenmuxConfigKey = "ZenMuxConfig"

    /// 旧版 UserDefaults Bailian 键（用于迁移）
    static let legacyBailianConfigKey = "BailianConfig"

    /// 旧版 UserDefaults ZenMux 键（用于迁移）
    static let legacyZenmuxConfigKey = "ZenMuxConfig"

    // MARK: - 其他键名
    /// 用量数据缓存键
    static let usageCacheKey = "PlatformUsage"

    /// 显示类型配置键
    static let displayTypesKey = "PlatformDisplayTypes"
}