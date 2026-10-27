import Foundation

enum GrokRefreshOutcome: Equatable {
    case disabled
    case refreshed
    case unavailable
    case timedOut
    case failed
}

protocol GrokUsageRefreshing {
    func refresh(
        logURL: URL,
        grokHomeURL: URL,
        proxyURL: String?
    ) async -> GrokRefreshOutcome
}

/// 通过官方 Grok CLI 主动刷新额度，避免 CodeBar 接触 OAuth 凭据或私有 HTTP 接口。
actor GrokCLIUsageRefresher: GrokUsageRefreshing {
    static let shared = GrokCLIUsageRefresher()

    private let pollDelayNanoseconds: UInt64 = 200_000_000
    private let startupTimeout: TimeInterval = 6
    private let timeout: TimeInterval = 8

    func refresh(
        logURL: URL,
        grokHomeURL: URL,
        proxyURL: String?
    ) async -> GrokRefreshOutcome {
        guard let executableURL = findExecutable(grokHomeURL: grokHomeURL) else {
            return .unavailable
        }
        guard let workingDirectory = try? CodeBarFileStore.shared.cliWorkingDirectory(for: "grok") else { return .failed }

        let previousMarker = latestBillingMarker(at: logURL)
        let previousStartupMarker = latestLogMarker(at: logURL, message: "startup timing")
        let process = Process()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.currentDirectoryURL = workingDirectory
        process.arguments = [
            "-q",
            "/dev/null",
            executableURL.path,
            "--no-alt-screen",
            "--no-subagents",
            "--cwd",
            workingDirectory.path,
        ]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard var environment = try? ModuleProxyConfiguration.environment(proxyURL: proxyURL, inheriting: ProcessInfo.processInfo.environment) else { return .failed }
        environment["GROK_HOME"] = grokHomeURL.path
        process.environment = environment

        do {
            try process.run()
        } catch {
            return .failed
        }

        let startupDeadline = Date().addingTimeInterval(startupTimeout)
        while Date() < startupDeadline, process.isRunning {
            if Task.isCancelled {
                await stop(process: process, inputPipe: inputPipe)
                return .failed
            }
            if let marker = latestLogMarker(at: logURL, message: "startup timing"),
               marker != previousStartupMarker {
                break
            }
            try? await Task.sleep(nanoseconds: pollDelayNanoseconds)
        }

        do {
            guard process.isRunning else {
                await stop(process: process, inputPipe: inputPipe)
                return .failed
            }
            try inputPipe.fileHandleForWriting.write(contentsOf: Data("/usage\r".utf8))
        } catch {
            await stop(process: process, inputPipe: inputPipe)
            return .failed
        }

        let deadline = Date().addingTimeInterval(timeout)
        var exitedBeforeRefresh = false
        while Date() < deadline {
            if Task.isCancelled {
                await stop(process: process, inputPipe: inputPipe)
                return .failed
            }
            if let marker = latestBillingMarker(at: logURL), marker != previousMarker {
                await stop(process: process, inputPipe: inputPipe)
                return .refreshed
            }
            if !process.isRunning {
                exitedBeforeRefresh = true
                break
            }
            try? await Task.sleep(nanoseconds: pollDelayNanoseconds)
        }

        await stop(process: process, inputPipe: inputPipe)
        return exitedBeforeRefresh ? .failed : .timedOut
    }

    private func findExecutable(grokHomeURL: URL) -> URL? {
        var candidates: [URL] = []
        if let customPath = ProcessInfo.processInfo.environment["GROK_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customPath.isEmpty {
            candidates.append(URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath))
        }
        candidates.append(grokHomeURL.appendingPathComponent("bin/grok"))
        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".grok/bin/grok")
        )

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("grok")
            })
        }

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private func latestBillingMarker(at logURL: URL) -> String? {
        guard let log = try? readGrokLogTail(at: logURL, maximumBytes: 1_024 * 1_024) else {
            return nil
        }

        let decoder = JSONDecoder()
        for rawLine in log.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(rawLine).data(using: .utf8),
                  let entry = try? decoder.decode(GrokLogEntry.self, from: data),
                  entry.message == "billing: fetched credits config",
                  entry.context?.config?.creditUsagePercent != nil else {
                continue
            }
            return entry.timestamp
        }
        return nil
    }

    private func latestLogMarker(at logURL: URL, message: String) -> String? {
        guard let log = try? readGrokLogTail(at: logURL, maximumBytes: 1_024 * 1_024) else {
            return nil
        }

        let decoder = JSONDecoder()
        for rawLine in log.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(rawLine).data(using: .utf8),
                  let entry = try? decoder.decode(GrokLogEntry.self, from: data),
                  entry.message == message else {
                continue
            }
            return entry.timestamp
        }
        return nil
    }

    private func stop(process: Process, inputPipe: Pipe) async {
        if process.isRunning {
            try? inputPipe.fileHandleForWriting.write(contentsOf: Data("/quit\r".utf8))
            for _ in 0..<5 where process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }
}

/// Grok CLI 的本地周额度提供者。
///
/// 默认只读取 `logs/unified.jsonl` 中的额度快照，不启动 CLI。
/// 用户启用后台 CLI 刷新后，才调用官方 CLI；失败时保留最近缓存。
struct GrokProvider: PlatformProvider {
    let platformName = "Grok"
    private let config: GrokConfig
    private let refresher: any GrokUsageRefreshing
    private let maximumLogBytes = 8 * 1_024 * 1_024

    init(
        config: GrokConfig = GrokConfig(),
        refresher: any GrokUsageRefreshing = GrokCLIUsageRefresher.shared
    ) {
        self.config = config
        self.refresher = refresher
    }

    var isConfigured: Bool {
        config.isValid && FileManager.default.fileExists(atPath: billingLogURL.path)
    }

    func fetchUsage() async throws -> PlatformUsageData {
        _ = try ModuleProxyConfiguration.parse(config.proxyURL)
        let refreshOutcome: GrokRefreshOutcome
        if config.isCLIRefreshEnabled {
            refreshOutcome = await refresher.refresh(
                logURL: billingLogURL,
                grokHomeURL: grokHomeURL,
                proxyURL: config.proxyURL
            )
        } else {
            refreshOutcome = .disabled
        }

        do {
            let log = try readLogTail()
            var usage = try Self.makeUsage(from: log, sourcePath: abbreviatedLogPath)
            usage.extraInfo.append((label: "刷新状态", value: Self.refreshStatus(refreshOutcome)))
            return usage
        } catch let error as PlatformError {
            if !FileManager.default.fileExists(atPath: billingLogURL.path) {
                throw PlatformError.unknown(missingSnapshotMessage(for: refreshOutcome))
            }
            throw error
        } catch {
            if !FileManager.default.fileExists(atPath: billingLogURL.path) {
                throw PlatformError.unknown(missingSnapshotMessage(for: refreshOutcome))
            }
            throw PlatformError.parseError(error)
        }
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

#if CODEBAR_BEHAVIOR_TESTS
    static func testUsage(from jsonl: String) throws -> PlatformUsageData {
        try makeUsage(from: jsonl, sourcePath: "~/.grok/logs/unified.jsonl")
    }
#endif

    private var grokHomeURL: URL {
        let customHome = config.homeDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentHome = ProcessInfo.processInfo.environment["GROK_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let path = customHome, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let path = environmentHome, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
    }

    private var billingLogURL: URL {
        grokHomeURL
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("unified.jsonl", isDirectory: false)
    }

    private var abbreviatedLogPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if billingLogURL.path.hasPrefix(homePath + "/") {
            return "~" + billingLogURL.path.dropFirst(homePath.count)
        }
        return billingLogURL.path
    }

    private func missingSnapshotMessage(for outcome: GrokRefreshOutcome) -> String {
        switch outcome {
        case .disabled:
            return "未找到 Grok 本地额度快照。请在 Grok 中手动运行 /usage；默认不会在后台启动 CLI。"
        case .unavailable:
            return "未找到 Grok CLI，且没有可用额度缓存。请安装并登录 Grok，运行 /usage 后重试。"
        case .timedOut:
            return "Grok 主动刷新超时，且没有可用额度缓存。请在 Grok 中运行 /usage 后重试。"
        case .failed:
            return "Grok 主动刷新失败，且没有可用额度缓存。请在 Grok 中运行 /usage 后重试。"
        case .refreshed:
            return "Grok 已主动刷新，但没有生成可用额度数据。请在 Grok 中运行 /usage 后重试。"
        }
    }

    private func readLogTail() throws -> String {
        try readGrokLogTail(at: billingLogURL, maximumBytes: maximumLogBytes)
    }

    private static func makeUsage(from jsonl: String, sourcePath: String) throws -> PlatformUsageData {
        guard let snapshot = latestSnapshot(from: jsonl) else {
            throw PlatformError.unknown(
                "Grok 本地缓存中没有额度数据。请在 Grok 中运行 /usage 后，再回到 CodeBar 刷新。"
            )
        }

        let used = max(0, min(100, Int(snapshot.percent.rounded())))
        let item = UsageItem(
            key: "grok.weekly",
            label: "周额度",
            used: used,
            total: 100,
            unit: "%",
            resetDate: snapshot.resetDate
        )

        var extraInfo: [(label: String, value: String)] = [
            (label: "数据来源", value: sourcePath),
            (label: "刷新方式", value: "读取本地额度快照；可在设置中选择后台 CLI 刷新"),
        ]
        if let syncDate = snapshot.syncDate {
            extraInfo.insert(
                (label: "Grok 同步时间", value: displayTimestamp(syncDate)),
                at: 1
            )
            if Date().timeIntervalSince(syncDate) > 24 * 60 * 60 {
                extraInfo.append((label: "提示", value: "本地额度缓存已超过 24 小时，请在 Grok 中运行 /usage"))
            }
        }

        let planType = snapshot.tier.flatMap { $0.isEmpty ? nil : $0 } ?? "Grok"
        return PlatformUsageData(
            platformName: "Grok",
            planType: planType,
            items: [item],
            extraInfo: extraInfo
        )
    }

    private static func latestSnapshot(from jsonl: String) -> GrokBillingSnapshot? {
        let decoder = JSONDecoder()
        for rawLine in jsonl.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(rawLine).data(using: .utf8),
                  let entry = try? decoder.decode(GrokLogEntry.self, from: data),
                  entry.message == "billing: fetched credits config",
                  let config = entry.context?.config,
                  let percent = config.creditUsagePercent else {
                continue
            }

            return GrokBillingSnapshot(
                percent: percent,
                resetDate: parseISO8601(config.currentPeriod?.end ?? config.billingPeriodEnd),
                tier: config.subscriptionTier ?? entry.context?.subscriptionTier,
                syncDate: parseISO8601(entry.timestamp)
            )
        }
        return nil
    }

    private static func refreshStatus(_ outcome: GrokRefreshOutcome) -> String {
        switch outcome {
        case .disabled:
            return "仅显示本地缓存（后台 CLI 刷新已关闭）"
        case .refreshed:
            return "主动刷新成功"
        case .unavailable:
            return "未找到 Grok CLI，已显示上次缓存"
        case .timedOut:
            return "主动刷新超时，已显示上次缓存"
        case .failed:
            return "主动刷新失败，已显示上次缓存"
        }
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func displayTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private func readGrokLogTail(at logURL: URL, maximumBytes: Int) throws -> String {
    let handle = try FileHandle(forReadingFrom: logURL)
    defer { try? handle.close() }

    let size = try handle.seekToEnd()
    let start = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
    try handle.seek(toOffset: start)
    let data = try handle.readToEnd() ?? Data()
    var log = String(decoding: data, as: UTF8.self)

    // 从文件中部开始时，首行可能是不完整 JSON，丢弃它后继续向后查找。
    if start > 0, let newline = log.firstIndex(of: "\n") {
        log.removeSubrange(log.startIndex...newline)
    }
    return log
}

private struct GrokLogEntry: Decodable {
    let timestamp: String?
    let message: String?
    let context: GrokLogContext?

    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case message = "msg"
        case context = "ctx"
    }
}

private struct GrokLogContext: Decodable {
    let config: GrokBillingConfig?
    let subscriptionTier: String?
}

private struct GrokBillingConfig: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: GrokBillingPeriod?
    let billingPeriodEnd: String?
    let subscriptionTier: String?
}

private struct GrokBillingPeriod: Decodable {
    let end: String?
}

private struct GrokBillingSnapshot {
    let percent: Double
    let resetDate: Date?
    let tier: String?
    let syncDate: Date?
}
