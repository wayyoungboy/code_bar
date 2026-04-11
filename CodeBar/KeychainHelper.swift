import Foundation
import Security

/// Keychain 操作工具类
/// 用于安全存储敏感凭证（API密钥、cookies等）
final class KeychainHelper {
    static let shared = KeychainHelper()

    private init() {}

    // Keychain 服务标识
    private let service = "com.codebar.app"

    /// 保存数据到 Keychain
    func save(_ data: Data, for key: String) throws {
        // 先尝试删除旧数据
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// 从 Keychain 读取数据
    func read(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    /// 从 Keychain 删除数据
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// 检查是否存在某个 key
    func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        return status == errSecSuccess
    }

    /// 保存 Codable 对象
    func save<T: Codable>(_ object: T, for key: String) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, for: key)
    }

    /// 读取 Codable 对象
    func read<T: Codable>(_ type: T.Type, for key: String) throws -> T {
        let data = try read(for: key)
        return try JSONDecoder().decode(type, from: data)
    }

    /// 尝试读取，失败返回 nil
    func readIfPresent<T: Codable>(_ type: T.Type, for key: String) -> T? {
        try? read(type, for: key)
    }
}

/// Keychain 错误类型
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain 保存失败 (status: \(status))"
        case .readFailed(let status):
            return "Keychain 读取失败 (status: \(status))"
        case .deleteFailed(let status):
            return "Keychain 删除失败 (status: \(status))"
        case .invalidData:
            return "Keychain 数据无效"
        }
    }
}