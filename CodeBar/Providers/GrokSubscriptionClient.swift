import Foundation
import Darwin

protocol GrokSubscriptionFetching {
    func fetch(authURL: URL, proxyURL: String?) async throws -> Data
}

enum GrokSubscriptionError: LocalizedError {
    case loginRequired, credentialsChanged, credentialsBusy, invalidCredentials, invalidResponse
    case network, http(Int)

    var errorDescription: String? {
        switch self {
        case .loginRequired: return "Grok 登录已失效，请先在 Grok 中重新登录，再刷新 CodeBar"
        case .credentialsChanged: return "Grok 登录信息已变化，请重新刷新"
        case .credentialsBusy: return "Grok 正在更新登录信息，请稍后刷新"
        case .invalidCredentials: return "无法读取 Grok 的 OAuth 登录信息，请先在 Grok 中完成登录"
        case .invalidResponse: return "Grok 返回的订阅用量数据无效，请稍后重试"
        case .network: return "Grok 网络请求失败，请检查网络或模块代理"
        case .http(let status): return "Grok 订阅请求失败（HTTP \(status)）"
        }
    }
}

/// Coordinates rotating OAuth tokens with both CodeBar callers and the official CLI.
actor GrokSubscriptionClient: GrokSubscriptionFetching {
    static let shared = GrokSubscriptionClient()
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!

    private let transport: Transport?
    private let now: () -> Date
    private let lockTimeout: TimeInterval
    private var requests: [String: Task<Data, Error>] = [:]

    init(transport: Transport? = nil, now: @escaping () -> Date = Date.init, lockTimeout: TimeInterval = 35) {
        self.transport = transport
        self.now = now
        self.lockTimeout = lockTimeout
    }

    func fetch(authURL: URL, proxyURL: String?) async throws -> Data {
        _ = try ModuleProxyConfiguration.parse(proxyURL)
        let canonical = authURL.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(authURL.lastPathComponent)
        let key = canonical.path + "|" + (proxyURL ?? "")
        if let request = requests[key] { return try await request.value }
        // An individual UI cancellation must not discard an already-rotated refresh token.
        let request = Task { try await self.load(authURL: canonical, proxyURL: proxyURL) }
        requests[key] = request
        defer { requests[key] = nil }
        return try await request.value
    }

    private func load(authURL: URL, proxyURL: String?) async throws -> Data {
        let native = try transport == nil ? GrokNativeHTTPClient(proxyURL: proxyURL) : nil
        defer { native?.invalidate() }
        let send: Transport = transport ?? { request in try await native!.send(request) }
        let store = GrokCredentialStore(url: authURL)
        var credential = try await freshCredential(store: store, rejectedToken: nil, send: send)
        var result = try await billing(token: credential.accessToken, send: send)
        if result.1.statusCode == 401 {
            credential = try await freshCredential(store: store, rejectedToken: credential.accessToken, send: send)
            result = try await billing(token: credential.accessToken, send: send)
        }
        guard result.1.statusCode != 401 else { throw GrokSubscriptionError.loginRequired }
        try check(result.1.statusCode)
        return result.0
    }

    private func freshCredential(store: GrokCredentialStore, rejectedToken: String?, send: Transport) async throws -> GrokCredential {
        let initial = try store.load()
        if initial.isUsable(at: now()), rejectedToken == nil || initial.accessToken != rejectedToken { return initial }
        let lock = try await GrokCredentialLock.acquire(for: store.url, timeout: lockTimeout)
        defer { lock.release() }
        let credential = try store.load()
        guard credential.entryID == initial.entryID else { throw GrokSubscriptionError.credentialsChanged }
        if credential.isUsable(at: now()), rejectedToken == nil || credential.accessToken != rejectedToken { return credential }
        guard let refreshToken = credential.refreshToken else { throw GrokSubscriptionError.loginRequired }
        try lock.validate()
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = ["grant_type": "refresh_token", "client_id": credential.clientID, "refresh_token": refreshToken]
        if let principalType = credential.principalType { fields["principal_type"] = principalType }
        if let principalID = credential.principalID { fields["principal_id"] = principalID }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await send(request)
        if [400, 401, 403].contains(response.statusCode) { throw GrokSubscriptionError.loginRequired }
        try check(response.statusCode)
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = reply["access_token"] as? String, GrokCredential.validToken(access) else {
            throw GrokSubscriptionError.invalidResponse
        }
        let rotated = reply["refresh_token"] as? String
        if let rotated, !GrokCredential.validToken(rotated) { throw GrokSubscriptionError.invalidResponse }
        let expiresIn = (reply["expires_in"] as? NSNumber)?.doubleValue
            ?? (reply["expires_in"] as? String).flatMap(Double.init)
        if let expiresIn, !expiresIn.isFinite || expiresIn <= 0 { throw GrokSubscriptionError.invalidResponse }
        let expiration = expiresIn.map { now().addingTimeInterval($0) } ?? GrokCredential.jwtExpiration(access)
        try lock.validate()
        // Save the rotated refresh token before attempting the billing request.
        try store.update(credential, accessToken: access, refreshToken: rotated ?? refreshToken, expiration: expiration)
        return try store.load()
    }

    private func billing(token: String, send: Transport) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.billingURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
        return try await send(request)
    }

    private func check(_ status: Int) throws {
        if status == 429 { throw PlatformError.rateLimited }
        guard (200..<300).contains(status) else { throw GrokSubscriptionError.http(status) }
    }
}

final class GrokNativeHTTPClient: NSObject, URLSessionTaskDelegate {
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
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch { throw GrokSubscriptionError.network }
        guard let response = result.1 as? HTTPURLResponse, result.0.count <= 2 * 1_024 * 1_024 else {
            throw GrokSubscriptionError.invalidResponse
        }
        return (result.0, response)
    }

    func invalidate() { session.finishTasksAndInvalidate() }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward access or refresh credentials through a redirect.
        completionHandler(nil)
    }
}

private struct GrokCredential {
    let entryID: String
    let accessToken: String
    let refreshToken: String?
    let clientID: String
    let principalType: String?
    let principalID: String?
    let expiration: Date?

    func isUsable(at now: Date) -> Bool { expiration.map { $0.timeIntervalSince(now) > 60 } ?? true }

    static func validToken(_ value: String) -> Bool {
        !value.isEmpty && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func jwtExpiration(_ token: String) -> Date? {
        let pieces = token.split(separator: ".")
        guard pieces.count == 3 else { return nil }
        var base64 = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double, exp.isFinite else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

private struct GrokCredentialStore {
    let url: URL
    private static let issuer = "https://auth.x.ai"
    private static let defaultEntry = issuer + "::b1a00492-073a-47ea-816f-4c329264a828"

    private func document() throws -> [String: Any] {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_024 * 1_024 else {
                throw GrokSubscriptionError.invalidCredentials
            }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GrokSubscriptionError.invalidCredentials
            }
            return object
        } catch { throw GrokSubscriptionError.invalidCredentials }
    }

    func load() throws -> GrokCredential {
        let object = try document()
        let entryID: String
        if object[Self.defaultEntry] != nil {
            entryID = Self.defaultEntry
        } else {
            let candidates = object.keys.filter { $0.hasPrefix(Self.issuer + "::") }
            guard candidates.count == 1, let selected = candidates.first else { throw GrokSubscriptionError.invalidCredentials }
            entryID = selected
        }
        guard let entry = object[entryID] as? [String: Any], entry["auth_mode"] as? String == "oidc",
              entry["oidc_issuer"] as? String == Self.issuer,
              let clientID = entry["oidc_client_id"] as? String, !clientID.isEmpty,
              entryID == Self.issuer + "::" + clientID,
              let access = entry["key"] as? String, GrokCredential.validToken(access) else {
            throw GrokSubscriptionError.invalidCredentials
        }
        let refresh = entry["refresh_token"] as? String
        if let refresh, !GrokCredential.validToken(refresh) { throw GrokSubscriptionError.invalidCredentials }
        return GrokCredential(entryID: entryID, accessToken: access, refreshToken: refresh, clientID: clientID,
                              principalType: entry["principal_type"] as? String,
                              principalID: entry["principal_id"] as? String,
                              expiration: GrokCredential.date(entry["expires_at"] as? String) ?? GrokCredential.jwtExpiration(access))
    }

    func update(_ expected: GrokCredential, accessToken: String, refreshToken: String, expiration: Date?) throws {
        let current = try load()
        guard current.entryID == expected.entryID, current.accessToken == expected.accessToken,
              current.refreshToken == expected.refreshToken else { throw GrokSubscriptionError.credentialsChanged }
        var object = try document()
        guard var entry = object[expected.entryID] as? [String: Any] else { throw GrokSubscriptionError.credentialsChanged }
        entry["key"] = accessToken
        entry["refresh_token"] = refreshToken
        if let expiration {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            entry["expires_at"] = formatter.string(from: expiration)
        } else { entry.removeValue(forKey: "expires_at") }
        object[expected.entryID] = entry
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var template = Array(url.deletingLastPathComponent().appendingPathComponent(".codebar-auth-XXXXXX").path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard descriptor >= 0 else { throw GrokSubscriptionError.credentialsBusy }
        let temporary = String(cString: template)
        defer { Darwin.close(descriptor); Darwin.unlink(temporary) }
        do {
            guard fchmod(descriptor, 0o600) == 0 else { throw GrokSubscriptionError.credentialsBusy }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            guard Darwin.rename(temporary, url.path) == 0 else { throw GrokSubscriptionError.credentialsBusy }
        } catch { throw GrokSubscriptionError.credentialsBusy }
    }
}

private final class GrokCredentialLock {
    private var descriptor: Int32
    private let path: String
    private init(descriptor: Int32, path: String) { self.descriptor = descriptor; self.path = path }

    static func acquire(for authURL: URL, timeout: TimeInterval) async throws -> GrokCredentialLock {
        let path = authURL.path + ".lock"
        let descriptor = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw GrokSubscriptionError.credentialsBusy }
        let lock = GrokCredentialLock(descriptor: descriptor, path: path)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw GrokSubscriptionError.credentialsBusy }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw GrokSubscriptionError.credentialsBusy }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try lock.validate()
        return lock
    }

    func validate() throws {
        var held = stat(), current = stat()
        guard descriptor >= 0, fstat(descriptor, &held) == 0, lstat(path, &current) == 0,
              held.st_dev == current.st_dev, held.st_ino == current.st_ino else {
            throw GrokSubscriptionError.credentialsChanged
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); Darwin.close(descriptor); descriptor = -1
    }
    deinit { release() }
}
