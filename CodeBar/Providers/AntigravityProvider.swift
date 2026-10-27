import Foundation
import Darwin

/// Antigravity 平台用量提供者
/// 支持探测本机运行中的 Antigravity 桌面端 Language Server、环境变量连接以及 agy CLI。
struct AntigravityProvider: PlatformProvider {
    let platformName = "Antigravity"
    private let config: AntigravityConfig

    private static let endpointPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let userStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    // 缓存上次探测成功的端点，加速后续轮询
    private static var cachedEndpoint: ResolvedEndpoint?

    init(config: AntigravityConfig = AntigravityConfig()) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid
    }

    struct ResolvedEndpoint: Equatable {
        let scheme: String
        let host: String
        let port: Int
        let csrfToken: String

        var quotaURL: URL? {
            URL(string: "\(scheme)://\(host):\(port)\(AntigravityProvider.endpointPath)")
        }

        var userStatusURL: URL? {
            URL(string: "\(scheme)://\(host):\(port)\(AntigravityProvider.userStatusPath)")
        }
    }

    func fetchUsage() async throws -> PlatformUsageData {
        let proxy = try ModuleProxyConfiguration.parse(config.proxyURL)
        if proxy != nil || config.cliPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return try await fetchFromCLI()
        }
        var desktopError: Error?
        // 1. 尝试通过已知或自动探测的本地 Language Server 获取
        do {
            let endpoint = try await resolveEndpoint()
            do {
                let usage = try await fetchFromLocalServer(endpoint: endpoint)
                Self.cachedEndpoint = endpoint
                return usage
            } catch {
                desktopError = error
                // 如果缓存的端点失效，清除缓存再试一次探测
                Self.cachedEndpoint = nil
                if let freshEndpoint = try? await discoverLocalEndpoint(), freshEndpoint != endpoint {
                    if let usage = try? await fetchFromLocalServer(endpoint: freshEndpoint) {
                        Self.cachedEndpoint = freshEndpoint
                        return usage
                    }
                }
            }
        } catch {
            desktopError = error
        }

        // 2. 尝试通过 agy CLI 获取
        do {
            return try await fetchFromCLI()
        } catch {
            let detail = desktopError?.localizedDescription ?? "本地端点不可用"
            throw PlatformError.unknown("Antigravity 桌面端：\(detail)；CLI：\(error.localizedDescription)")
        }
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    // MARK: - 本地 Language Server 通信

    private func resolveEndpoint() async throws -> ResolvedEndpoint {
        // 优先检查用户自定义配置
        if let customHost = config.hostAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !customHost.isEmpty {
            let token = config.csrfToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return try parseEndpoint(customHost, csrfToken: token)
        }

        // 检查环境配置（由 Antigravity 宿主注入）
        let env = ProcessInfo.processInfo.environment
        if let envAddr = env["ANTIGRAVITY_LS_ADDRESS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envAddr.isEmpty {
            let token = env["ANTIGRAVITY_CSRF_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? config.csrfToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return try parseEndpoint(envAddr, csrfToken: token)
        }

        // 检查内存缓存
        if let cached = Self.cachedEndpoint {
            return cached
        }

        // 自动探测本地运行中的进程
        return try await discoverLocalEndpoint()
    }

    private func discoverLocalEndpoint() async throws -> ResolvedEndpoint {
        let (pid, csrfToken) = try await findLanguageServerProcess()
        let ports = try await findListeningPorts(pid: pid)

        guard !ports.isEmpty else {
            throw PlatformError.unknown("找到 Antigravity 进程 (PID \(pid))，但未检测到监听端口")
        }

        // 尝试探测哪个端口有效（优先尝试 HTTP，再尝试 HTTPS）
        for port in ports {
            for scheme in ["http", "https"] {
                let candidate = ResolvedEndpoint(scheme: scheme, host: "127.0.0.1", port: port, csrfToken: csrfToken)
                if (try? await testEndpoint(candidate)) == true {
                    return candidate
                }
            }
        }

        throw PlatformError.unknown("未能连接到 Antigravity 本地端口 (\(ports.map(String.init).joined(separator: ", ")))")
    }

    private func testEndpoint(_ endpoint: ResolvedEndpoint) async throws -> Bool {
        guard let url = endpoint.quotaURL else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.csrfToken.isEmpty {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        request.httpBody = Data("{}".utf8)

        let session = makeLocalSession()
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            let parsed = try JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data)
            return parsed.response?.groups != nil
        } catch {
            return false
        }
    }

    private func fetchFromLocalServer(endpoint: ResolvedEndpoint) async throws -> PlatformUsageData {
        guard let url = endpoint.quotaURL else {
            throw PlatformError.unknown("无效的 Antigravity 配额接口地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.csrfToken.isEmpty {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        request.httpBody = Data("{}".utf8)

        let session = makeLocalSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
        }

        guard httpResponse.statusCode == 200 else {
            throw PlatformError.unknown("Antigravity 接口返回 HTTP \(httpResponse.statusCode)")
        }

        let quotaResponse = try JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data)
        guard let groups = quotaResponse.response?.groups, !groups.isEmpty else {
            throw PlatformError.unknown("Antigravity 返回的配额组为空")
        }

        let userStatus = await fetchUserStatus(endpoint: endpoint, session: session)
        return makePlatformUsageData(
            groups: groups,
            userStatus: userStatus,
            sourceDescription: "本地端点 (\(endpoint.scheme)://\(endpoint.host):\(endpoint.port))"
        )
    }

    private func fetchUserStatus(endpoint: ResolvedEndpoint, session: URLSession) async -> AntigravityUserStatusResponse? {
        guard let url = endpoint.userStatusURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !endpoint.csrfToken.isEmpty {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        request.httpBody = Data("{}".utf8)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        return try? JSONDecoder().decode(AntigravityUserStatusResponse.self, from: data)
    }

    // MARK: - agy CLI 支持

    private func fetchFromCLI(timeout: TimeInterval = 15) async throws -> PlatformUsageData {
        guard let cliURL = findCLIExecutable() else {
            throw PlatformError.unknown("未找到 agy CLI 可执行文件")
        }

        let result = try await runCommand(
            executable: cliURL,
            arguments: ["-p", "/usage", "--output-format", "json"],
            timeout: timeout,
            environment: try ModuleProxyConfiguration.environment(proxyURL: config.proxyURL, inheriting: ProcessInfo.processInfo.environment),
            workingDirectory: try CodeBarFileStore.shared.cliWorkingDirectory(for: "agy")
        )
        guard result.status == 0 else {
            throw PlatformError.unknown("agy /usage 执行失败（退出码 \(result.status)），请确认 CLI 已登录")
        }
        let data = result.data
        guard !data.isEmpty else {
            throw PlatformError.unknown("agy CLI 输出为空")
        }

        // 解析 CLI JSON 输出
        if let cliReport = try? JSONDecoder().decode(AntigravityCLIReport.self, from: data),
           cliReport.status == nil || cliReport.status?.uppercased() == "SUCCESS",
           let groups = cliReport.command?.data?.response?.groups, !groups.isEmpty {
            return makePlatformUsageData(groups: groups, userStatus: nil, sourceDescription: "agy CLI (/usage)")
        }

        if let directResponse = try? JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data),
           let groups = directResponse.response?.groups, !groups.isEmpty {
            return makePlatformUsageData(groups: groups, userStatus: nil, sourceDescription: "agy CLI")
        }

        throw PlatformError.unknown("无法解析 agy CLI 输出")
    }

    private func findCLIExecutable() -> URL? {
        if let custom = config.cliPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            return nil
        }

        let env = ProcessInfo.processInfo.environment
        if let envPath = env["ANTIGRAVITY_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envPath.isEmpty {
            let url = URL(fileURLWithPath: envPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathCandidates = (env["PATH"] ?? "").split(separator: ":").map { "\($0)/agy" }
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            home.appendingPathComponent(".local/bin/agy").path,
            home.appendingPathComponent(".antigravity/bin/agy").path,
            home.appendingPathComponent(".gemini/antigravity/bin/agy").path,
            home.appendingPathComponent(".antigravity/antigravity/bin/agy").path,
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    // MARK: - 辅助进程发现与端口提取

    private func findLanguageServerProcess() async throws -> (pid: Int, csrfToken: String) {
        let result = try await runCommand(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-ax", "-o", "pid=,command="],
            timeout: 3
        )
        guard result.status == 0, let output = String(data: result.data, encoding: .utf8) else {
            throw PlatformError.unknown("读取进程列表失败")
        }

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().contains("antigravity") else { continue }

            let scanner = Scanner(string: trimmed)
            guard let pid = scanner.scanInt() else { continue }

            let rest = trimmed[scanner.currentIndex...]
            guard let executable = rest.split(separator: " ").first else { continue }
            let name = URL(fileURLWithPath: String(executable)).lastPathComponent
            guard name == "language_server" || name.hasPrefix("language_server_") else { continue }
            var csrfToken = ""
            if let tokenRange = rest.range(of: "--csrf_token") {
                let after = rest[tokenRange.upperBound...].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "=")))
                let tokenParts = after.split(separator: " ")
                if let first = tokenParts.first {
                    csrfToken = String(first)
                }
            }

            return (pid, csrfToken)
        }

        throw PlatformError.unknown("未检测到运行中的 Antigravity language_server 进程")
    }

    private func findListeningPorts(pid: Int) async throws -> [Int] {
        let result = try await runCommand(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-n", "-P"],
            timeout: 3
        )
        guard let output = String(data: result.data, encoding: .utf8) else {
            return []
        }

        var ports: [Int] = []
        for line in output.split(separator: "\n") {
            let str = String(line)
            guard str.contains("(LISTEN)") else { continue }
            // 匹配例如 127.0.0.1:57643 或 *:57643
            if let colonIndex = str.lastIndex(of: ":") {
                let afterColon = str[str.index(after: colonIndex)...]
                let portStr = afterColon.prefix { $0.isNumber }
                if let port = Int(portStr), !ports.contains(port) {
                    ports.append(port)
                }
            }
        }

        return ports
    }

    private func parseEndpoint(_ address: String, csrfToken: String) throws -> ResolvedEndpoint {
        let rawURL = address.contains("://") ? address : "http://\(address)"
        guard let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host,
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()),
              components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil,
              (1...65535).contains(components.port ?? 5387) else {
            throw PlatformError.unknown("Antigravity 端点必须是本机 HTTP/HTTPS 地址，例如 https://127.0.0.1:5387")
        }
        return ResolvedEndpoint(scheme: scheme, host: host, port: components.port ?? 5387, csrfToken: csrfToken)
    }

    private struct CommandResult {
        let status: Int32
        let data: Data
    }

    private func runCommand(executable: URL, arguments: [String], timeout: TimeInterval, environment: [String: String]? = nil, workingDirectory: URL? = nil) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("codebar-agy-\(UUID().uuidString)")
                    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                        throw PlatformError.unknown("无法创建 AGY 输出缓冲")
                    }
                    defer { try? FileManager.default.removeItem(at: outputURL) }
                    let output = try FileHandle(forWritingTo: outputURL)
                    defer { try? output.close() }
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.environment = environment
                    process.currentDirectoryURL = workingDirectory
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                    if process.isRunning {
                        process.terminate()
                        let terminationDeadline = Date().addingTimeInterval(0.5)
                        while process.isRunning && Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.02) }
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        process.waitUntilExit()
                        throw PlatformError.unknown("Antigravity 命令超时，请确认桌面端或 CLI 已登录且能正常查询 /usage")
                    }
                    process.waitUntilExit()
                    let size = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
                    guard size <= 4_194_304 else { throw PlatformError.unknown("Antigravity 命令输出过大") }
                    let data = try Data(contentsOf: outputURL)
                    continuation.resume(returning: CommandResult(status: process.terminationStatus, data: data))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func makeLocalSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
        ]
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 4.0
        return URLSession(configuration: config, delegate: SelfSignedTLSDelegate(), delegateQueue: nil)
    }

    // MARK: - 数据转换

    private func makePlatformUsageData(
        groups: [AntigravityQuotaGroup],
        userStatus: AntigravityUserStatusResponse?,
        sourceDescription: String
    ) -> PlatformUsageData {
        var items: [UsageItem] = []

        for group in groups {
            for bucket in group.buckets ?? [] {
                let key = bucket.bucketId
                let label = Self.displayLabel(for: bucket, group: group)
                guard let fraction = bucket.remainingFraction, fraction.isFinite else { continue }
                let remaining = max(0, min(1, fraction))
                let used = max(0, min(100, Int(((1.0 - remaining) * 100).rounded())))
                let resetDate = parseResetDate(bucket.resetTime)

                items.append(UsageItem(
                    key: key,
                    label: label,
                    used: used,
                    total: 100,
                    unit: "%",
                    resetDate: resetDate
                ))
            }
        }

        var extra: [(label: String, value: String)] = []
        if let planName = userStatus?.userTier?.name, !planName.isEmpty {
            extra.append((label: "订阅类型", value: planName))
        }
        if let email = userStatus?.email, !email.isEmpty {
            extra.append((label: "Google 账号", value: email))
        }
        extra.append((label: "凭据来源", value: sourceDescription))

        let planType = userStatus?.userTier?.name ?? "Google AI"

        return PlatformUsageData(
            platformName: platformName,
            planType: planType,
            items: items,
            extraInfo: extra
        )
    }

    private static func displayLabel(for bucket: AntigravityQuotaBucket, group: AntigravityQuotaGroup) -> String {
        switch bucket.bucketId {
        case "gemini-5h":
            return "Gemini 5小时"
        case "gemini-weekly":
            return "Gemini 周额度"
        case "3p-5h":
            return "Claude/GPT 5小时"
        case "3p-weekly":
            return "Claude/GPT 周额度"
        case "gemini-argon-wtu-weekly":
            return "Argon 周额度"
        default:
            let windowTitle = bucket.window?.lowercased().contains("5h") == true ? "5小时" : "周额度"
            let groupTitle = group.displayName
                .replacingOccurrences(of: " Models", with: "")
                .replacingOccurrences(of: " models", with: "")
            return "\(groupTitle) \(windowTitle)"
        }
    }

    private func parseResetDate(_ dateStr: String?) -> Date? {
        guard let dateStr, !dateStr.isEmpty else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr)
    }

    // MARK: - 测试辅助方法

    #if CODEBAR_BEHAVIOR_TESTS
    static func testCLI(config: AntigravityConfig, timeout: TimeInterval) async throws -> PlatformUsageData {
        try await AntigravityProvider(config: config).fetchFromCLI(timeout: timeout)
    }

    static func testUsage(from jsonString: String) throws -> PlatformUsageData {
        let data = Data(jsonString.utf8)
        let response = try JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data)
        guard let groups = response.response?.groups else {
            throw PlatformError.unknown("无配额组数据")
        }
        return AntigravityProvider().makePlatformUsageData(
            groups: groups,
            userStatus: nil,
            sourceDescription: "测试数据"
        )
    }
    #endif
}

// MARK: - TLS Delegate

private final class SelfSignedTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           ["127.0.0.1", "localhost", "::1", "[::1]"].contains(challenge.protectionSpace.host.lowercased()),
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - API 响应模型

struct AntigravityQuotaSummaryResponse: Decodable {
    let response: AntigravityQuotaSummaryData?

    private enum CodingKeys: String, CodingKey { case response, groups }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.response) {
            response = try container.decodeIfPresent(AntigravityQuotaSummaryData.self, forKey: .response)
        } else if container.contains(.groups) {
            // The CLI unwraps RetrieveUserQuotaSummary into command.data.groups.
            response = try AntigravityQuotaSummaryData(from: decoder)
        } else {
            response = nil
        }
    }
}

struct AntigravityQuotaSummaryData: Decodable {
    let groups: [AntigravityQuotaGroup]?
    let description: String?
}

struct AntigravityQuotaGroup: Decodable {
    let displayName: String
    let description: String?
    let buckets: [AntigravityQuotaBucket]?

    private enum CodingKeys: String, CodingKey { case displayName, name, description, buckets }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        buckets = try container.decodeIfPresent([AntigravityQuotaBucket].self, forKey: .buckets)
    }
}

struct AntigravityQuotaBucket: Decodable {
    let bucketId: String
    let displayName: String
    let description: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case bucketId, id, displayName, name, description, window, remainingFraction, resetTime
        case remainingFractionCLI = "remaining_fraction"
        case resetTimeCLI = "reset_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucketId = try container.decodeIfPresent(String.self, forKey: .bucketId)
            ?? container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name) ?? bucketId
        description = try container.decodeIfPresent(String.self, forKey: .description)
        window = try container.decodeIfPresent(String.self, forKey: .window)
        remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction)
            ?? container.decodeIfPresent(Double.self, forKey: .remainingFractionCLI)
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
            ?? container.decodeIfPresent(String.self, forKey: .resetTimeCLI)
    }
}

struct AntigravityUserStatusResponse: Decodable {
    let email: String?
    let userTier: AntigravityUserTier?

    private enum CodingKeys: String, CodingKey { case userStatus, email, userTier }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.userStatus) {
            let status = try container.decode(AntigravityUserStatusResponse.self, forKey: .userStatus)
            email = status.email
            userTier = status.userTier
        } else {
            email = try container.decodeIfPresent(String.self, forKey: .email)
            userTier = try container.decodeIfPresent(AntigravityUserTier.self, forKey: .userTier)
        }
    }
}

struct AntigravityUserTier: Decodable {
    let id: String?
    let name: String?
    let description: String?
}

struct AntigravityCLIReport: Decodable {
    let status: String?
    let command: AntigravityCLICommand?
}

struct AntigravityCLICommand: Decodable {
    let name: String?
    let data: AntigravityQuotaSummaryResponse?
}
