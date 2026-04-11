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

/// 平台用量数据
struct PlatformUsage {
    let used: Int
    let total: Int
    let unit: String
    let resetDate: Date
    let planType: String
    let platformName: String

    // 5 小时周期用量
    let used5Hour: Int
    let total5Hour: Int
    let resetDate5Hour: Date

    // 周周期用量
    let usedWeek: Int
    let totalWeek: Int
    let resetDateWeek: Date

    var remaining: Int {
        return total - used
    }

    var usagePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    var used5HourPercent: Double {
        guard total5Hour > 0 else { return 0 }
        return Double(used5Hour) / Double(total5Hour) * 100
    }

    var usedWeekPercent: Double {
        guard totalWeek > 0 else { return 0 }
        return Double(usedWeek) / Double(totalWeek) * 100
    }
}

/// 平台提供者协议
protocol PlatformProvider {
    var platformName: String { get }
    var isConfigured: Bool { get }

    /// 获取用量信息
    func fetchUsage() async throws -> PlatformUsage

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
    var apiKey: String

    var isValid: Bool {
        !apiKey.isEmpty && apiKey.count >= 20  // 基本长度检查
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "zenmux_api_key"
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
