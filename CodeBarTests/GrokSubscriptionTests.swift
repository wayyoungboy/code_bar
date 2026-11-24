import Foundation
import Darwin

enum GrokSubscriptionTests {
    static let issuer = "https://auth.x.ai"
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let entryID = issuer + "::" + clientID
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let billing = Data(#"{"config":{"creditUsagePercent":23.6,"currentPeriod":{"end":"2027-01-22T08:00:00Z"}},"subscriptionTier":"SuperGrok"}"#.utf8)

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func httpRetryAfterDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    static func auth(at url: URL, expired: Bool = true, refresh: Bool = true, userID: String? = nil) throws {
        var entry: [String: Any] = [
            "key": "fixture-access-old", "auth_mode": "oidc",
            "oidc_issuer": issuer, "oidc_client_id": clientID,
            "principal_type": "User", "principal_id": "fixture-user",
            "expires_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(expired ? -10 : 3600)),
            "preserved_metadata": "keep-me",
        ]
        if let userID { entry["user_id"] = userID }
        if refresh { entry["refresh_token"] = "fixture-refresh+&=secret" }
        let document: [String: Any] = [entryID: entry, "another-login": ["key": "unrelated-key"]]
        try JSONSerialization.data(withJSONObject: document).write(to: url)
    }

    static func read(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("codebar-grok-oauth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("auth.json")

        try auth(at: url)
        let fixture = GrokHTTPFixture()
        let client = GrokSubscriptionClient(transport: { try await fixture.send($0) }, now: { now })
        let data = try await client.fetch(authURL: url, proxyURL: nil)
        expect(data == billing, "Expired OAuth must refresh and fetch subscription billing directly")
        let counts = await fixture.counts()
        expect(counts == [1, 1], "One expired token should cause one refresh and one billing request")
        let saved = try read(url)
        let entry = saved[entryID] as! [String: Any]
        expect(entry["key"] as? String == "fixture-access-new", "Refreshed access tokens must be saved for the CLI too")
        expect(entry["refresh_token"] as? String == "fixture-refresh-rotated", "Rotated refresh tokens must be persisted")
        expect(entry["preserved_metadata"] as? String == "keep-me" && saved["another-login"] != nil, "Credential updates must preserve metadata and other accounts")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Persisted credentials must be owner-only")
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        expect(Set(remainingFiles) == ["auth.json", "auth.json.lock"], "OAuth must not leave credential copies or start a CLI workspace")

        try auth(at: url, expired: false)
        let fresh = GrokHTTPFixture(acceptOld: true)
        _ = try await GrokSubscriptionClient(transport: { try await fresh.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
        let freshCounts = await fresh.counts()
        expect(freshCounts == [0, 1], "Valid tokens should fetch billing without an unnecessary refresh")

        try auth(at: url, expired: false)
        let unauthorized = GrokHTTPFixture()
        _ = try await GrokSubscriptionClient(transport: { try await unauthorized.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
        let retryCounts = await unauthorized.counts()
        expect(retryCounts == [1, 2], "A 401 with a fresh-looking token must refresh once and retry")

        try auth(at: url, expired: false)
        let denied = GrokHTTPFixture(alwaysUnauthorized: true)
        do {
            _ = try await GrokSubscriptionClient(transport: { try await denied.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
            fatalError("Repeated 401 responses must surface a login error")
        } catch {
            expect(error.localizedDescription.contains("登录"), "Auth failures must explain that login is required")
        }
        let deniedCounts = await denied.counts()
        expect(deniedCounts == [1, 2], "Unauthorized responses must not create an infinite token refresh loop")

        for failure in [400, 429, 500] {
            try auth(at: url)
            let before = try Data(contentsOf: url)
            let failing = GrokHTTPFixture(tokenStatus: failure)
            do {
                _ = try await GrokSubscriptionClient(transport: { try await failing.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
                fatalError("Rejected token refresh must fail")
            } catch {
                expect(!error.localizedDescription.contains("fixture-refresh"), "Server error messages must not expose credentials")
            }
            let after = try Data(contentsOf: url)
            expect(after == before, "A failed refresh must leave the credential file intact")
        }

        try auth(at: url)
        let concurrent = GrokHTTPFixture(delay: true)
        let coalesced = GrokSubscriptionClient(transport: { try await concurrent.send($0) }, now: { now })
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { try await coalesced.fetch(authURL: url, proxyURL: nil) } }
            for try await result in group { expect(result == billing, "Concurrent readers should receive the same subscription data") }
        }
        let concurrentCounts = await concurrent.counts()
        expect(concurrentCounts == [1, 1], "Concurrent refreshes must share one request rather than reuse a rotating refresh token")

        try auth(at: url)
        let shared = GrokHTTPFixture(delay: true)
        let first = GrokSubscriptionClient(transport: { try await shared.send($0) }, now: { now })
        let second = GrokSubscriptionClient(transport: { try await shared.send($0) }, now: { now })
        async let a = first.fetch(authURL: url, proxyURL: nil)
        async let b = second.fetch(authURL: url, proxyURL: nil)
        _ = try await (a, b)
        let sharedCounts = await shared.counts()
        expect(sharedCounts == [1, 2], "Separate clients must coordinate through the CLI credential lock and adopt the refreshed disk token")

        try auth(at: url)
        let locked = Darwin.open(url.path + ".lock", O_RDWR | O_CREAT, 0o600)
        expect(locked >= 0 && flock(locked, LOCK_EX | LOCK_NB) == 0, "Lock fixture should own the CLI auth lock")
        let blocked = GrokHTTPFixture()
        do {
            _ = try await GrokSubscriptionClient(transport: { try await blocked.send($0) }, now: { now }, lockTimeout: 0.1).fetch(authURL: url, proxyURL: nil)
            fatalError("A CLI-owned credential lock must not be bypassed")
        } catch { }
        flock(locked, LOCK_UN); Darwin.close(locked)
        let blockedCounts = await blocked.counts()
        expect(blockedCounts == [0, 0], "Lock timeout must not send a refresh token")

        try auth(at: url)
        let switched = GrokHTTPFixture(beforeTokenResponse: {
            var current = try read(url)
            var selected = current[entryID] as! [String: Any]
            selected["key"] = "fixture-new-cli-login"
            current[entryID] = selected
            try JSONSerialization.data(withJSONObject: current).write(to: url, options: .atomic)
        })
        do {
            _ = try await GrokSubscriptionClient(transport: { try await switched.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
            fatalError("A concurrent login change must abort the stale update")
        } catch { }
        let switchedEntry = try read(url)[entryID] as! [String: Any]
        expect(switchedEntry["key"] as? String == "fixture-new-cli-login", "Refreshing must never overwrite another login or resurrect a logged-out session")

        for scenario in ["untrusted-issuer", "no-refresh", "missing"] {
            try auth(at: url, refresh: scenario != "no-refresh")
            if scenario == "untrusted-issuer" {
                var current = try read(url)
                var selected = current[entryID] as! [String: Any]
                selected["oidc_issuer"] = "https://attacker.invalid"
                current[entryID] = selected
                try JSONSerialization.data(withJSONObject: current).write(to: url)
            } else if scenario == "missing" { try FileManager.default.removeItem(at: url) }
            let unused = GrokHTTPFixture()
            do {
                _ = try await GrokSubscriptionClient(transport: { try await unused.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
                fatalError("Invalid or missing OAuth configuration must fail")
            } catch { }
            let unusedCounts = await unused.counts()
            expect(unusedCounts == [0, 0], "Unsupported credentials must never be sent to a remote endpoint")
        }
        try auth(at: url, expired: false, userID: "fixture-user-id")
        let identified = GrokHTTPFixture(acceptOld: true)
        _ = try await GrokSubscriptionClient(transport: { try await identified.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
        let identifiedHeaders = await identified.billingHeaders()
        expect(identifiedHeaders["Authorization"] == "Bearer fixture-access-old", "Billing must still use the access token")
        expect(identifiedHeaders["X-XAI-Token-Auth"] == "xai-grok-cli", "Billing must send the official CLI token-auth header")
        expect(identifiedHeaders["x-userid"] == "fixture-user-id", "Billing may send x-userid only when auth.json already has user_id")
        expect(identifiedHeaders["x-grok-client-mode"] == "cli", "Billing should keep the existing client mode header")

        try auth(at: url, expired: false)
        let anonymous = GrokHTTPFixture(acceptOld: true)
        _ = try await GrokSubscriptionClient(transport: { try await anonymous.send($0) }, now: { now }).fetch(authURL: url, proxyURL: nil)
        let anonymousHeaders = await anonymous.billingHeaders()
        expect(anonymousHeaders["X-XAI-Token-Auth"] == "xai-grok-cli", "The official token-auth header does not require a user id")
        expect(anonymousHeaders["x-userid"] == nil, "x-userid must not be invented when auth.json has no user_id")

        try auth(at: url, expired: false)
        let clock = GrokTestClock(now)
        let limited = GrokHTTPFixture(acceptOld: true, billingStatus: 429, retryAfter: "120")
        let limitedClient = GrokSubscriptionClient(transport: { try await limited.send($0) }, now: { clock.now })
        do {
            _ = try await limitedClient.fetch(authURL: url, proxyURL: nil)
            fatalError("A billing 429 must surface a rate-limit error")
        } catch {
            expect(error.localizedDescription.contains("限流") && error.localizedDescription.contains("不是用量为 0"), "Rate limiting must be explained as a query failure, not zero usage")
        }
        let limitedCounts = await limited.counts()
        expect(limitedCounts == [0, 1], "The first rate-limited query should send exactly one billing request")
        do {
            _ = try await limitedClient.fetch(authURL: url, proxyURL: nil)
            fatalError("A cooldown must be served without another billing request")
        } catch {
            expect(error.localizedDescription.contains("限流"), "Cooldown should keep returning the rate-limit error")
        }
        let cooledCounts = await limited.counts()
        expect(cooledCounts == [0, 1], "Cooldown must not send another billing request")
        clock.now = now.addingTimeInterval(121)
        do {
            _ = try await limitedClient.fetch(authURL: url, proxyURL: nil)
            fatalError("A billing 429 after cooldown should still fail the query")
        } catch {
            expect(error.localizedDescription.contains("限流"), "A later 429 should remain a rate-limit error")
        }
        let retriedCounts = await limited.counts()
        expect(retriedCounts == [0, 2], "After the cooldown expires the client may query billing again")

        let httpDate = httpRetryAfterDate(now.addingTimeInterval(180))
        expect(abs(GrokSubscriptionClient.cooldownEnd(header: httpDate, now: now).timeIntervalSince(now) - 180) < 1, "Retry-After HTTP-date should schedule the cooldown from the timestamp")
        expect(GrokSubscriptionClient.cooldownEnd(header: nil, now: now) == now.addingTimeInterval(GrokSubscriptionClient.defaultRateLimitCooldown), "A missing Retry-After should use the default 5-minute cooldown")
        expect(GrokSubscriptionClient.cooldownEnd(header: "not-a-date", now: now) == now.addingTimeInterval(GrokSubscriptionClient.defaultRateLimitCooldown), "An unparsable Retry-After should use the default 5-minute cooldown")

        try auth(at: url, expired: false)
        let dateClock = GrokTestClock(now)
        let dated = GrokHTTPFixture(acceptOld: true, billingStatus: 429, retryAfter: httpDate)
        let datedClient = GrokSubscriptionClient(transport: { try await dated.send($0) }, now: { dateClock.now })
        do { _ = try await datedClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let datedFirst = await dated.counts()
        expect(datedFirst == [0, 1], "The first HTTP-date 429 should send one billing request")
        do { _ = try await datedClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let datedCooled = await dated.counts()
        expect(datedCooled == [0, 1], "An HTTP-date cooldown must not send another billing request")
        dateClock.now = now.addingTimeInterval(181)
        do { _ = try await datedClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let datedRetried = await dated.counts()
        expect(datedRetried == [0, 2], "After the HTTP-date cooldown the client may query billing again")

        try auth(at: url, expired: false)
        let defaultClock = GrokTestClock(now)
        let defaulted = GrokHTTPFixture(acceptOld: true, billingStatus: 429)
        let defaultClient = GrokSubscriptionClient(transport: { try await defaulted.send($0) }, now: { defaultClock.now })
        do { _ = try await defaultClient.fetch(authURL: url, proxyURL: nil) } catch { }
        do { _ = try await defaultClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let defaultFirst = await defaulted.counts()
        expect(defaultFirst == [0, 1], "A billing 429 without Retry-After should use the default cooldown")
        defaultClock.now = now.addingTimeInterval(GrokSubscriptionClient.defaultRateLimitCooldown - 1)
        do { _ = try await defaultClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let defaultActive = await defaulted.counts()
        expect(defaultActive == [0, 1], "Default cooldown should still be active just before 5 minutes")
        defaultClock.now = now.addingTimeInterval(GrokSubscriptionClient.defaultRateLimitCooldown + 1)
        do { _ = try await defaultClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let defaultExpired = await defaulted.counts()
        expect(defaultExpired == [0, 2], "Default 5-minute cooldown should expire afterwards")

        try auth(at: url) // expired token, so the first request is a refresh
        let tokenClock = GrokTestClock(now)
        let tokenLimited = GrokHTTPFixture(tokenStatus: 429)
        let tokenClient = GrokSubscriptionClient(transport: { try await tokenLimited.send($0) }, now: { tokenClock.now })
        do { _ = try await tokenClient.fetch(authURL: url, proxyURL: nil) } catch {
            expect(error.localizedDescription.contains("限流"), "A token-endpoint 429 must surface as a rate limit, not zero usage")
        }
        let tokenFirst = await tokenLimited.counts()
        expect(tokenFirst == [1, 0], "A token 429 should not continue to the billing request")
        do { _ = try await tokenClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let tokenCooled = await tokenLimited.counts()
        expect(tokenCooled == [1, 0], "A token 429 must start the same account cooldown")
        tokenClock.now = now.addingTimeInterval(GrokSubscriptionClient.defaultRateLimitCooldown + 1)
        do { _ = try await tokenClient.fetch(authURL: url, proxyURL: nil) } catch { }
        let tokenRetried = await tokenLimited.counts()
        expect(tokenRetried == [2, 0], "After the default cooldown the client may refresh the token again")

        print("Grok subscription OAuth tests passed")
    }
}

final class GrokTestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private actor GrokHTTPFixture {
    var tokens = 0
    var billings = 0
    var lastBillingHeaders: [String: String] = [:]
    let acceptOld: Bool
    let alwaysUnauthorized: Bool
    let tokenStatus: Int
    let billingStatus: Int
    let retryAfter: String?
    let delay: Bool
    let beforeTokenResponse: (() throws -> Void)?

    init(acceptOld: Bool = false, alwaysUnauthorized: Bool = false, tokenStatus: Int = 200, billingStatus: Int = 200, retryAfter: String? = nil, delay: Bool = false, beforeTokenResponse: (() throws -> Void)? = nil) {
        self.acceptOld = acceptOld; self.alwaysUnauthorized = alwaysUnauthorized
        self.tokenStatus = tokenStatus; self.billingStatus = billingStatus
        self.retryAfter = retryAfter; self.delay = delay; self.beforeTokenResponse = beforeTokenResponse
    }
    func counts() -> [Int] { [tokens, billings] }
    func billingHeaders() -> [String: String] { lastBillingHeaders.filter { !$0.value.isEmpty } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        var status = 200
        let data: Data
        if url.absoluteString == "https://auth.x.ai/oauth2/token" {
            tokens += 1
            GrokSubscriptionTests.expect(request.httpMethod == "POST", "OAuth refresh uses POST")
            GrokSubscriptionTests.expect(request.value(forHTTPHeaderField: "Authorization") == nil, "Expired access tokens must not be sent to the token endpoint")
            let pairs = String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&")
            let form = Dictionary(uniqueKeysWithValues: pairs.map { part -> (String, String) in
                let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                return (String(pieces[0]), String(pieces[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding!)
            })
            GrokSubscriptionTests.expect(form["grant_type"] == "refresh_token" && form["client_id"] == GrokSubscriptionTests.clientID, "Refresh must use the CLI OAuth public client")
            GrokSubscriptionTests.expect(form["refresh_token"] == "fixture-refresh+&=secret", "Form encoding must preserve refresh token punctuation")
            GrokSubscriptionTests.expect(form["principal_type"] == "User" && form["principal_id"] == "fixture-user", "Refresh must preserve the selected CLI principal")
            if delay { try await Task.sleep(nanoseconds: 120_000_000) }
            try beforeTokenResponse?()
            status = tokenStatus
            data = Data((status == 200 ? #"{"access_token":"fixture-access-new","refresh_token":"fixture-refresh-rotated","expires_in":3600}"# : #"{"error":"invalid_grant","error_description":"fixture-refresh+&=secret"}"#).utf8)
        } else {
            billings += 1
            GrokSubscriptionTests.expect(url.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits" && request.httpMethod == "GET", "Quota queries must use the fixed first-party subscription billing route")
            lastBillingHeaders = [
                "Authorization": request.value(forHTTPHeaderField: "Authorization") ?? "",
                "X-XAI-Token-Auth": request.value(forHTTPHeaderField: "X-XAI-Token-Auth") ?? "",
                "x-userid": request.value(forHTTPHeaderField: "x-userid") ?? "",
                "x-grok-client-mode": request.value(forHTTPHeaderField: "x-grok-client-mode") ?? "",
            ]
            let token = request.value(forHTTPHeaderField: "Authorization")
            if alwaysUnauthorized || (!acceptOld && token != "Bearer fixture-access-new") {
                status = 401
            } else {
                status = billingStatus
            }
            data = status == 200 ? GrokSubscriptionTests.billing : Data(#"{"error":"unavailable"}"#.utf8)
        }
        var headers: [String: String] = [:]
        if status == 429, let retryAfter {
            headers["Retry-After"] = retryAfter
        }
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
