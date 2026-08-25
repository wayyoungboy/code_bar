import Foundation

/// Grok CLI 的本地周额度提供者。
///
/// Grok CLI 暂未向第三方暴露 billing RPC，因此这里只读取 CLI 自己写入的
/// `logs/unified.jsonl` 用量快照，绝不读取或复制 `auth.json` 中的登录令牌。
struct GrokProvider: PlatformProvider {
    let platformName = "Grok"
    private let config: GrokConfig
    private let maximumLogBytes = 8 * 1_024 * 1_024

    init(config: GrokConfig = GrokConfig()) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isValid && FileManager.default.fileExists(atPath: billingLogURL.path)
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard FileManager.default.fileExists(atPath: billingLogURL.path) else {
            throw PlatformError.unknown(missingSnapshotMessage)
        }

        do {
            let log = try readLogTail()
            return try Self.makeUsage(from: log, sourcePath: abbreviatedLogPath)
        } catch let error as PlatformError {
            throw error
        } catch {
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

    private var missingSnapshotMessage: String {
        "未找到 Grok 额度缓存。请先启动 Grok 并运行 /usage，然后在 CodeBar 中刷新。"
    }

    private func readLogTail() throws -> String {
        let handle = try FileHandle(forReadingFrom: billingLogURL)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let start = size > UInt64(maximumLogBytes) ? size - UInt64(maximumLogBytes) : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        var log = String(decoding: data, as: UTF8.self)

        // 从文件中部开始时，首行可能是不完整 JSON，丢弃它后继续向后查找。
        if start > 0, let newline = log.firstIndex(of: "\n") {
            log.removeSubrange(log.startIndex...newline)
        }
        return log
    }

    private static func makeUsage(from jsonl: String, sourcePath: String) throws -> PlatformUsageData {
        let decoder = JSONDecoder()
        var snapshot: GrokBillingSnapshot?

        for rawLine in jsonl.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(rawLine).data(using: .utf8),
                  let entry = try? decoder.decode(GrokLogEntry.self, from: data),
                  entry.message == "billing: fetched credits config",
                  let config = entry.context?.config,
                  let percent = config.creditUsagePercent else {
                continue
            }

            snapshot = GrokBillingSnapshot(
                percent: percent,
                resetDate: parseISO8601(config.currentPeriod?.end ?? config.billingPeriodEnd),
                tier: config.subscriptionTier ?? entry.context?.subscriptionTier,
                syncDate: parseISO8601(entry.timestamp)
            )
            break
        }

        guard let snapshot else {
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
            (label: "刷新方式", value: "启动 Grok 或运行 /usage 后更新"),
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
