import Foundation
import SwiftUI

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
    static let popoverWidth: CGFloat = 420

    /// Island 收起状态宽度
    static let islandClosedWidth: CGFloat = 210

    /// Island 刘海左侧延伸宽度
    static let islandClosedLeftExtensionWidth: CGFloat = 160

    /// Island 收起状态高度
    static let islandClosedHeight: CGFloat = 36

    /// Island 展开状态宽度
    static let islandOpenedWidth: CGFloat = 500

    /// Island 展开状态最大高度
    static let islandOpenedMaximumHeight: CGFloat = 620

    /// 设置窗口宽度
    static let settingsWindowWidth: CGFloat = 520

    /// 设置窗口高度
    static let settingsWindowHeight: CGFloat = 620

    /// 状态栏图标尺寸
    static let statusBarIconSize: CGFloat = 13

    /// 帮助窗口宽度
    static let helpWindowWidth: CGFloat = 450

    /// 帮助窗口高度
    static let helpWindowHeight: CGFloat = 400

    // MARK: - File storage keys
    /// 统一平台配置存储键（所有平台共用一个条目）
    static let platformConfigsKey = "PlatformConfigs"

    /// 监控模块配置存储键
    static let monitorModulesKey = "MonitorModules"

    // MARK: - 其他键名
    /// 用量数据缓存键
    static let usageCacheKey = "PlatformUsage"

    /// 显示类型配置键
    static let displayTypesKey = "PlatformDisplayTypes"

    /// 平台启用状态键
    static let enabledPlatformsKey = "PlatformEnabled"

    /// 重置时间显示配置键
    static let resetTimeKeysKey = "PlatformResetTimeKeys"

    /// 菜单栏多模块展示模式键
    static let menuBarDisplayModeKey = "MenuBarDisplayMode"

    /// 面板样式配置键
    static let presentationModeKey = "CodeBarPresentationMode"

    // MARK: - 通知
    /// ZenMux 5 小时额度刷新通知缓存键
    static let zenmuxNotice5Hour = "code_bar_zenmux_notice_time_5_hour"

    /// ZenMux 7 天额度刷新通知缓存键
    static let zenmuxNotice7Day = "code_bar_zenmux_notice_time_7_day"

    /// ZenMux 通知功能启用状态键
    static let zenmuxNoticeEnabledKey = "code_bar_zenmux_notice_enabled"

    /// 版本更新提醒启用状态键
    static let updateCheckEnabledKey = "code_bar_update_check_enabled"
}

extension Color {
    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgbValue: UInt64 = 0
        guard stripped.count == 6, Scanner(string: stripped).scanHexInt64(&rgbValue) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
