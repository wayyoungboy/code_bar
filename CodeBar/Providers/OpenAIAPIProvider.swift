import Foundation

enum OpenAIAPIError: LocalizedError {
    case invalidKey, permission, rateLimited, invalidResponse, network, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "OpenAI Admin API Key 无效，请检查组织管理密钥"
        case .permission: return "OpenAI Admin API Key 无权读取组织用量或费用，请检查管理权限"
        case .rateLimited: return "OpenAI 用量查询过于频繁，请稍后刷新"
        case .invalidResponse: return "OpenAI 返回的计费数据无效，请稍后刷新"
        case .network: return "OpenAI 计费请求失败，请检查网络或模块代理"
        case .http(let status): return "OpenAI 计费接口返回 HTTP \(status)"
        }
    }
}

/// Organization API billing, independent of ChatGPT/Codex subscription limits.
struct OpenAIAPIProvider: PlatformProvider {
    let platformName = "OpenAI API"
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let config: OpenAIAPIConfig
    private let transport: Transport?
    private let now: () -> Date

    init(config: OpenAIAPIConfig, transport: Transport? = nil, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.transport = transport
        self.now = now
    }

    var isConfigured: Bool { config.isValid }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard isConfigured else { throw OpenAIAPIError.invalidKey }
        let connection = try transport == nil ? OpenAIAPIHTTPClient(proxyURL: config.proxyURL) : nil
        defer { connection?.invalidate() }
        let send: Transport = transport ?? { try await connection!.send($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = now()
        let today = calendar.startOfDay(for: instant)
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: instant))!
        let start = Int(month.timeIntervalSince1970)
        // The API requires a nonempty exclusive range, including at exactly UTC midnight.
        let end = max(start + 1, Int(instant.timeIntervalSince1970))
        let costs: [Bucket<Cost>] = try await pages(path: "costs", start: start, end: end, send: send)
        var monthCost: Decimal = 0
        var todayCost: Decimal = 0
        var records = 0
        for bucket in costs {
            guard bucket.start_time >= start, bucket.start_time < end else { throw OpenAIAPIError.invalidResponse }
            for result in bucket.results {
                guard result.amount.currency.lowercased() == "usd", !result.amount.value.isNaN else { throw OpenAIAPIError.invalidResponse }
                monthCost += result.amount.value
                if bucket.start_time >= Int(today.timeIntervalSince1970) { todayCost += result.amount.value }
                records += 1
            }
        }
        let items = [
            UsageItem(key: "openai.cost.today", label: "今日费用", used: try Self.microdollars(todayCost), total: 0, unit: "USD", resetDate: calendar.date(byAdding: .day, value: 1, to: today)),
            UsageItem(key: "openai.cost.month", label: "本月费用", used: try Self.microdollars(monthCost), total: 0, unit: "USD", resetDate: calendar.date(byAdding: .month, value: 1, to: month)),
        ]
        var info: [(label: String, value: String)] = [
            ("数据范围", "当前组织全部项目的 API 费用"),
            ("统计时区", "UTC"),
            ("费用说明", "以费用接口已入账数据为准；不是账户余额"),
        ]
        if records == 0 { info.append(("费用记录", "当前月份暂无费用记录")) }
        do {
            let buckets: [Bucket<CompletionUsage>] = try await pages(path: "usage/completions", start: start, end: end, send: send)
            var input = 0, output = 0, cached = 0, requests = 0
            for bucket in buckets {
                guard bucket.start_time >= start, bucket.start_time < end else { throw OpenAIAPIError.invalidResponse }
                for result in bucket.results {
                    try Self.add(result.input_tokens, to: &input)
                    try Self.add(result.output_tokens, to: &output)
                    try Self.add(result.input_cached_tokens ?? 0, to: &cached)
                    try Self.add(result.num_model_requests, to: &requests)
                }
            }
            info += [("本月输入 Token", String(input)), ("本月输出 Token", String(output)), ("其中缓存输入 Token", String(cached)), ("本月请求数", String(requests)), ("Token 统计范围", "Completions 用量；费用包含全部 API 产品")]
        } catch {
            // Billing totals remain useful when token-detail permissions are unavailable.
            let safe = (error as? OpenAIAPIError)?.localizedDescription ?? OpenAIAPIError.invalidResponse.localizedDescription
            info.append(("Token 明细", safe))
        }
        return PlatformUsageData(platformName: platformName, planType: "API 按量计费", items: items, extraInfo: info)
    }

    private func pages<Result: Decodable>(path: String, start: Int, end: Int, send: Transport) async throws -> [Bucket<Result>] {
        var buckets: [Bucket<Result>] = []
        var cursor: String?
        var visited = Set<String>()
        for _ in 0..<20 {
            var url = URLComponents(string: "https://api.openai.com/v1/organization/\(path)")!
            url.queryItems = [URLQueryItem(name: "start_time", value: String(start)), URLQueryItem(name: "end_time", value: String(end)), URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "31")]
            if let cursor { url.queryItems!.append(URLQueryItem(name: "page", value: cursor)) }
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            var request = URLRequest(url: url.url!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(config.adminAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let result: (Data, HTTPURLResponse)
            do { result = try await send(request) }
            catch { throw OpenAIAPIError.network }
            switch result.1.statusCode {
            case 200: break
            case 401: throw OpenAIAPIError.invalidKey
            case 403: throw OpenAIAPIError.permission
            case 429: throw OpenAIAPIError.rateLimited
            default: throw OpenAIAPIError.http(result.1.statusCode)
            }
            guard result.0.count <= 2 * 1024 * 1024,
                  let page = try? JSONDecoder().decode(Page<Result>.self, from: result.0), page.object == "page" else { throw OpenAIAPIError.invalidResponse }
            buckets += page.data
            if !page.has_more { return buckets }
            guard let next = page.next_page, !next.isEmpty, next.count <= 4096, visited.insert(next).inserted else { throw OpenAIAPIError.invalidResponse }
            cursor = next
        }
        throw OpenAIAPIError.invalidResponse
    }

    private static func microdollars(_ value: Decimal) throws -> Int {
        var scaled = value * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard !rounded.isNaN, rounded <= Decimal(Int.max), rounded >= Decimal(Int.min) else { throw OpenAIAPIError.invalidResponse }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private static func add(_ value: Int, to total: inout Int) throws {
        let sum = total.addingReportingOverflow(value)
        guard value >= 0, !sum.overflow else { throw OpenAIAPIError.invalidResponse }
        total = sum.partialValue
    }

    private struct Page<Result: Decodable>: Decodable {
        let object: String
        let data: [Bucket<Result>]
        let has_more: Bool
        let next_page: String?
    }
    private struct Bucket<Result: Decodable>: Decodable {
        let start_time: Int
        let end_time: Int
        let results: [Result]
    }
    private struct Cost: Decodable {
        let amount: Amount
        struct Amount: Decodable { let value: Decimal; let currency: String }
    }
    private struct CompletionUsage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let input_cached_tokens: Int?
        let num_model_requests: Int
    }
}

/// Fixed-host Admin requests must never follow redirects with administrative credentials.
private final class OpenAIAPIHTTPClient: NSObject, URLSessionTaskDelegate {
    private var session: URLSession!
    init(proxyURL: String?) throws {
        let configuration = try ModuleProxyConfiguration.sessionConfiguration(proxyURL: proxyURL)
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OpenAIAPIError.invalidResponse }
        return (data, response)
    }
    func invalidate() { session.finishTasksAndInvalidate() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
