import Foundation

/// Gemini CLI / Code Assist OAuth 订阅额度提供者
struct GeminiProvider: PlatformProvider {
    let platformName = "Gemini"
    private let config: GeminiConfig
    private let loadCodeAssistURL = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private let retrieveUserQuotaURL = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    init(config: GeminiConfig = GeminiConfig()) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid && readCredentials().accessToken != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        let credentials = readCredentials()
        guard var accessToken = credentials.accessToken else {
            throw PlatformError.unknown(credentials.message ?? "未找到 Gemini CLI OAuth 凭据")
        }

        if credentials.isExpired, let refreshToken = credentials.refreshToken {
            accessToken = try await refreshAccessToken(refreshToken)
        }

        let projectID = try await loadCodeAssistProjectID(accessToken: accessToken)
        let quota = try await retrieveUserQuota(accessToken: accessToken, projectID: projectID)
        let items = makeUsageItems(from: quota)
        guard !items.isEmpty else {
            throw PlatformError.unknown("无 Gemini 额度数据")
        }

        var extra: [(label: String, value: String)] = [
            (label: "凭据来源", value: credentials.source.displayName),
        ]
        if let projectID, !projectID.isEmpty {
            extra.append((label: "Code Assist Project", value: projectID))
        }

        return PlatformUsageData(
            platformName: platformName,
            planType: "Code Assist",
            items: items,
            extraInfo: extra
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private func loadCodeAssistProjectID(accessToken: String) async throws -> String? {
        guard let url = URL(string: loadCodeAssistURL) else {
            throw PlatformError.unknown("无效的 Gemini loadCodeAssist URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideType": "GEMINI_CLI",
                "pluginType": "GEMINI",
            ],
        ])

        let data = try await send(request, context: "loadCodeAssist")
        let response = try JSONDecoder().decode(GeminiLoadCodeAssistResponse.self, from: data)
        return response.cloudaicompanionProject?.projectID
    }

    private func retrieveUserQuota(accessToken: String, projectID: String?) async throws -> GeminiQuotaResponse {
        guard let url = URL(string: retrieveUserQuotaURL) else {
            throw PlatformError.unknown("无效的 Gemini retrieveUserQuota URL")
        }

        var body: [String: Any] = [:]
        if let projectID, !projectID.isEmpty {
            body["project"] = projectID
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request, context: "retrieveUserQuota")
        return try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)
    }

    private func send(_ request: URLRequest, context: String) async throws -> Data {
        let session = try makeSession()
        AppLogger.logRequest(url: request.url?.absoluteString ?? context, method: request.httpMethod ?? "GET")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
        }

        AppLogger.logResponse(url: request.url?.absoluteString ?? context, statusCode: httpResponse.statusCode)

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw PlatformError.invalidAPIKey
        case 429:
            throw PlatformError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.unknown("\(context) HTTP \(httpResponse.statusCode): \(body)")
        }
    }

    private func makeUsageItems(from response: GeminiQuotaResponse) -> [UsageItem] {
        var bucketsByCategory: [String: GeminiBucket] = [:]

        for bucket in response.buckets ?? [] {
            let category = categoryKey(for: bucket.modelID ?? "unknown")
            let remaining = max(0, min(1, bucket.remainingFraction ?? 1))
            if let existing = bucketsByCategory[category], existing.remaining <= remaining {
                continue
            }
            bucketsByCategory[category] = GeminiBucket(
                remaining: remaining,
                resetTime: bucket.resetTime
            )
        }

        return ["gemini_pro", "gemini_flash", "gemini_flash_lite"].compactMap { key in
            guard let bucket = bucketsByCategory[key] else { return nil }
            let used = max(0, min(100, Int(((1 - bucket.remaining) * 100).rounded())))
            return UsageItem(
                key: key,
                label: label(for: key),
                used: used,
                total: 100,
                unit: "%",
                resetDate: parseResetDate(bucket.resetTime) ?? Date().addingTimeInterval(24 * 3_600)
            )
        }
    }

    private func categoryKey(for modelID: String) -> String {
        let lowercased = modelID.lowercased()
        if lowercased.contains("flash-lite") {
            return "gemini_flash_lite"
        }
        if lowercased.contains("flash") {
            return "gemini_flash"
        }
        if lowercased.contains("pro") {
            return "gemini_pro"
        }
        return stableKey(from: modelID)
    }

    private func label(for key: String) -> String {
        switch key {
        case "gemini_pro": return "Pro"
        case "gemini_flash": return "Flash"
        case "gemini_flash_lite": return "Flash Lite"
        default: return key
        }
    }

    private func stableKey(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
    }

    private func parseResetDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        guard let url = URL(string: tokenURL) else {
            throw PlatformError.unknown("无效的 OAuth token URL")
        }
        let oauthClient = try readOAuthClientCredentials()

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: oauthClient.clientID),
            URLQueryItem(name: "client_secret", value: oauthClient.clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try await send(request, context: "refreshGeminiToken")
        let response = try JSONDecoder().decode(GeminiTokenRefreshResponse.self, from: data)
        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw PlatformError.unknown("Gemini OAuth 刷新结果缺少 access_token")
        }
        return accessToken
    }

    private func readOAuthClientCredentials() throws -> GeminiOAuthClientCredentials {
        let environment = ProcessInfo.processInfo.environment
        if let clientID = environment["GEMINI_OAUTH_CLIENT_ID"], !clientID.isEmpty,
           let clientSecret = environment["GEMINI_OAUTH_CLIENT_SECRET"], !clientSecret.isEmpty {
            return GeminiOAuthClientCredentials(clientID: clientID, clientSecret: clientSecret)
        }

        for directory in geminiCLIBundleDirectories() {
            if let credentials = readOAuthClientCredentials(fromBundleDirectory: directory) {
                return credentials
            }
        }

        throw PlatformError.unknown("Gemini access_token 已过期，但无法读取 Gemini CLI OAuth client 配置。请确认已安装 Gemini CLI，或重新运行 Gemini CLI 登录刷新凭据。")
    }

    private func geminiCLIBundleDirectories() -> [URL] {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var directories: [URL] = []

        if let bundlePath = environment["GEMINI_CLI_BUNDLE_PATH"], !bundlePath.isEmpty {
            directories.append(URL(fileURLWithPath: bundlePath, isDirectory: true))
        }

        for binaryPath in ["/usr/local/bin/gemini", "/opt/homebrew/bin/gemini"] {
            let binaryURL = URL(fileURLWithPath: binaryPath)
            guard fileManager.fileExists(atPath: binaryURL.path) else { continue }
            let resolvedURL = resolveSymlink(binaryURL)
            directories.append(resolvedURL.deletingLastPathComponent())
        }

        return Array(Set(directories.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
    }

    private func resolveSymlink(_ url: URL) -> URL {
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
    }

    private func readOAuthClientCredentials(fromBundleDirectory directory: URL) -> GeminiOAuthClientCredentials? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "js",
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let credentials = parseOAuthClientCredentials(fromJavaScript: content) else {
                continue
            }
            return credentials
        }
        return nil
    }

    private func parseOAuthClientCredentials(fromJavaScript content: String) -> GeminiOAuthClientCredentials? {
        guard let clientID = firstJavaScriptString(named: "OAUTH_CLIENT_ID", in: content),
              let clientSecret = firstJavaScriptString(named: "OAUTH_CLIENT_SECRET", in: content) else {
            return nil
        }
        return GeminiOAuthClientCredentials(clientID: clientID, clientSecret: clientSecret)
    }

    private func firstJavaScriptString(named variableName: String, in content: String) -> String? {
        let pattern = #"var\s+\#(NSRegularExpression.escapedPattern(for: variableName))\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private func readCredentials() -> GeminiCredentials {
        if let keychainContent = KeychainHelper.readExternalItem(service: "gemini-cli-oauth", account: "main-account"),
           let credentials = parseKeychainCredentialsJSON(keychainContent) {
            return credentials
        }

        let authPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
            .appendingPathComponent("oauth_creds.json")

        guard FileManager.default.fileExists(atPath: authPath.path) else {
            return GeminiCredentials(
                accessToken: nil,
                refreshToken: nil,
                source: .file,
                isExpired: false,
                message: "未找到 Gemini CLI OAuth 凭据，请先使用 Gemini CLI 登录 Google"
            )
        }

        do {
            let content = try String(contentsOf: authPath, encoding: .utf8)
            if let credentials = parseFileCredentialsJSON(content) {
                return credentials
            }
            return GeminiCredentials(
                accessToken: nil,
                refreshToken: nil,
                source: .file,
                isExpired: false,
                message: "Gemini oauth_creds.json 格式无效"
            )
        } catch {
            return GeminiCredentials(
                accessToken: nil,
                refreshToken: nil,
                source: .file,
                isExpired: false,
                message: "读取 Gemini oauth_creds.json 失败：\(error.localizedDescription)"
            )
        }
    }

    private func parseKeychainCredentialsJSON(_ content: String) -> GeminiCredentials? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONDecoder().decode(GeminiKeychainCredentials.self, from: data) else {
            return parseFileCredentialsJSON(content)
        }

        guard let accessToken = json.token.accessToken, !accessToken.isEmpty else {
            return GeminiCredentials(
                accessToken: nil,
                refreshToken: json.token.refreshToken,
                source: .keychain,
                isExpired: false,
                message: "Gemini Keychain accessToken 缺失"
            )
        }

        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: json.token.refreshToken,
            source: .keychain,
            isExpired: isExpired(expiryMilliseconds: json.token.expiresAt),
            message: nil
        )
    }

    private func parseFileCredentialsJSON(_ content: String) -> GeminiCredentials? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONDecoder().decode(GeminiFileCredentials.self, from: data) else {
            return nil
        }

        guard let accessToken = json.accessToken, !accessToken.isEmpty else {
            return GeminiCredentials(
                accessToken: nil,
                refreshToken: json.refreshToken,
                source: .file,
                isExpired: false,
                message: "Gemini OAuth access_token 缺失"
            )
        }

        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: json.refreshToken,
            source: .file,
            isExpired: isExpired(expiryMilliseconds: json.expiryDate),
            message: nil
        )
    }

    private func isExpired(expiryMilliseconds: Int64?) -> Bool {
        guard let expiryMilliseconds else { return false }
        return expiryMilliseconds < Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func makeSession() throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.networkTimeout
        configuration.timeoutIntervalForResource = Constants.networkTimeout

        guard let rawProxyURL = config.proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawProxyURL.isEmpty else {
            return URLSession(configuration: configuration)
        }

        guard let proxyURL = URL(string: rawProxyURL),
              let scheme = proxyURL.scheme?.lowercased(),
              let host = proxyURL.host,
              let port = proxyURL.port else {
            throw PlatformError.unknown("Gemini 代理地址无效，请使用 http://host:port 或 socks5://host:port")
        }

        switch scheme {
        case "http", "https":
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case "socks", "socks5":
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        default:
            throw PlatformError.unknown("Gemini 代理协议不支持：\(scheme)")
        }

        return URLSession(configuration: configuration)
    }

    private struct GeminiBucket {
        let remaining: Double
        let resetTime: String?
    }

    private struct GeminiOAuthClientCredentials {
        let clientID: String
        let clientSecret: String
    }

    private struct GeminiCredentials {
        enum Source {
            case keychain
            case file

            var displayName: String {
                switch self {
                case .keychain: return "Keychain"
                case .file: return "~/.gemini/oauth_creds.json"
                }
            }
        }

        let accessToken: String?
        let refreshToken: String?
        let source: Source
        let isExpired: Bool
        let message: String?
    }

    private struct GeminiFileCredentials: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiryDate: Int64?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiryDate = "expiry_date"
        }
    }

    private struct GeminiKeychainCredentials: Decodable {
        let token: GeminiKeychainToken
    }

    private struct GeminiKeychainToken: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Int64?
    }

    private struct GeminiTokenRefreshResponse: Decodable {
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct GeminiLoadCodeAssistResponse: Decodable {
        let cloudaicompanionProject: GeminiProjectReference?
    }

    private struct GeminiProjectReference: Decodable {
        let projectID: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                projectID = string
                return
            }
            let object = try container.decode(GeminiProjectObject.self)
            projectID = object.id ?? object.projectID
        }
    }

    private struct GeminiProjectObject: Decodable {
        let id: String?
        let projectID: String?

        enum CodingKeys: String, CodingKey {
            case id
            case projectID = "projectId"
        }
    }

    private struct GeminiQuotaResponse: Decodable {
        let buckets: [GeminiBucketInfo]?
    }

    private struct GeminiBucketInfo: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelID: String?

        enum CodingKeys: String, CodingKey {
            case remainingFraction
            case resetTime
            case modelID = "modelId"
        }
    }
}
