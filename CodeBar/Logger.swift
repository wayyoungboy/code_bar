import OSLog

/// 应用日志工具
/// 使用 OSLog 提供结构化日志，避免 print 语句泄露敏感数据
struct AppLogger {
    /// 日志子系统
    private static let subsystem = "com.codebar.app"

    // MARK: - 日志分类

    /// 通用日志
    static let general = Logger(subsystem: subsystem, category: "general")

    /// 网络请求日志
    static let network = Logger(subsystem: subsystem, category: "network")

    /// 数据解析日志
    static let parsing = Logger(subsystem: subsystem, category: "parsing")

    /// 错误日志
    static let error = Logger(subsystem: subsystem, category: "error")

    /// 配置日志
    static let config = Logger(subsystem: subsystem, category: "config")

    // MARK: - 便捷方法

    /// 记录网络请求（不含敏感数据）
    static func logRequest(url: String, method: String) {
        network.info("📤 请求: \(method) \(url)")
    }

    /// 记录网络响应状态
    static func logResponse(url: String, statusCode: Int) {
        network.info("📥 响应: \(url) - HTTP \(statusCode)")
    }

    /// 记录解析错误（不含完整响应内容）
    static func logParseError(message: String) {
        parsing.error("❌ 解析失败: \(message)")
    }

    /// 记录配置变更
    static func logConfigChange(platform: String, action: String) {
        config.info("⚙️ \(platform): \(action)")
    }

    /// 记录错误
    static func logError(_ err: Error) {
        error.error("❌ 错误: \(err.localizedDescription)")
    }

    /// 记录用量数据更新
    static func logUsageUpdate(platform: String, used: Int, total: Int) {
        general.info("📊 \(platform): 已用 \(used) / 总计 \(total)")
    }
}