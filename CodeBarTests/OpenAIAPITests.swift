import Foundation

enum OpenAIAPITests {
    static let key = "sk-admin-" + String(repeating: "fixture", count: 8)
    static let now = ISO8601DateFormatter().date(from: "2026-11-10T12:30:00Z")!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func run() async throws {
        let fixture = OpenAIAPIFixture()
        let provider = OpenAIAPIProvider(config: OpenAIAPIConfig(adminAPIKey: key), transport: { try await fixture.send($0) }, now: { now })
        let usage = try await provider.fetchUsage()
        expect(usage.platformName == "OpenAI API", "API billing must be separate from Codex subscription usage")
        expect(usage.items.map(\.key) == ["openai.cost.today", "openai.cost.month"], "Billing should expose today's and this month's costs")
        expect(usage.items.map(\.used) == [200_000, 300_000], "Decimal USD totals must preserve microdollar precision across pages")
        expect(usage.items.allSatisfy { $0.unit == "USD" && $0.total == 0 }, "Costs must not invent a quota or remaining credit balance")
        expect(usage.extraInfo.contains { $0.label == "本月输入 Token" && $0.value == "1000" }, "Input tokens must include cached tokens exactly once")
        expect(usage.extraInfo.contains { $0.label == "本月请求数" && $0.value == "7" }, "Usage pages should aggregate request counts")
        expect(usage.extraInfo.contains { $0.label == "统计时区" && $0.value == "UTC" }, "Daily and monthly costs must disclose the UTC bucket boundary")
        let cost = usage.items[1]
        expect(UsageStatusFormatting.compactPercentText(for: cost, displayMode: .used) == "$0.30", "Menu bar billing must display dollars rather than 0 percent")
        expect(UsagePercentDisplayMode.remaining.value(for: cost) == cost.used, "An unbounded cost has no invented remaining value")
        expect(!UsagePercentDisplayMode.remaining.isNearLimit(cost), "An unbounded cost must not trigger quota warnings")
        expect(usage.items[0].resetDate == ISO8601DateFormatter().date(from: "2026-11-11T00:00:00Z"), "Today's costs should roll over at UTC midnight")
        expect(usage.items[1].resetDate == ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"), "Monthly costs should roll over at the next UTC month")

        let decoded = try JSONDecoder().decode(MonitorModuleConfig.self, from: JSONEncoder().encode(MonitorModuleConfig.openaiAPI(OpenAIAPIConfig(adminAPIKey: key, proxyURL: "http://127.0.0.1:7890"))))
        expect(decoded.platform == .openaiAPI && decoded.isValid && decoded.proxyURL != nil, "The new module and proxy must survive configuration persistence")
        let defaultKeys = await MainActor.run { ModuleEditorView.defaultDisplayKeys(for: .openaiAPI) }
        expect(defaultKeys == ["openai.cost.month", "openai.cost.today"], "The default menu bar selection should prefer monthly costs")

        for invalid in ["", "sk-proj-fixture", key + "\nheader", " " + key] {
            expect(!OpenAIAPIConfig(adminAPIKey: invalid).isValid, "Only a well-formed Admin API Key should be accepted")
        }
        for mode in ["empty", "usage-error"] {
            let server = OpenAIAPIFixture(mode: mode)
            let result = try await OpenAIAPIProvider(config: OpenAIAPIConfig(adminAPIKey: key), transport: { try await server.send($0) }, now: { now }).fetchUsage()
            if mode == "empty" {
                expect(result.items.allSatisfy { $0.used == 0 }, "A successful empty cost page is a real zero-cost result")
                expect(result.extraInfo.contains { $0.label == "费用记录" }, "Empty cost records should be disclosed separately from account balance")
            } else {
                expect(result.items[1].used == 300_000, "Optional usage detail failures should retain valid billing totals")
                expect(result.extraInfo.contains { $0.label == "Token 明细" }, "Missing token details must be explicit rather than fabricated as zero")
            }
        }
        for mode in ["401", "403", "429", "500", "redirect", "bad-json", "currency", "bad-amount", "cursor", "overflow"] {
            let server = OpenAIAPIFixture(mode: mode)
            do {
                _ = try await OpenAIAPIProvider(config: OpenAIAPIConfig(adminAPIKey: key), transport: { try await server.send($0) }, now: { now }).fetchUsage()
                fatalError("Invalid billing responses must fail: \(mode)")
            } catch {
                expect(!error.localizedDescription.contains(key), "Errors must not expose the Admin Key or raw server body")
            }
        }
        print("OpenAI API billing tests passed")
    }
}

private actor OpenAIAPIFixture {
    let mode: String
    init(mode: String = "normal") { self.mode = mode }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        OpenAIAPITests.expect(request.httpMethod == "GET" && request.httpBody == nil, "Billing integration must make read-only requests")
        OpenAIAPITests.expect(request.url?.scheme == "https" && request.url?.host == "api.openai.com", "Admin credentials must only be sent to OpenAI")
        OpenAIAPITests.expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + OpenAIAPITests.key, "Billing must authenticate with the supplied Admin Key")
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        OpenAIAPITests.expect(query["start_time"] == "1793491200" && query["end_time"] == "1794313800", "Query ranges must use the entire UTC month through the current instant")
        OpenAIAPITests.expect(query["bucket_width"] == "1d" && query["limit"] == "31", "A monthly query must request all daily buckets")
        if let page = query["page"], mode != "cursor" {
            OpenAIAPITests.expect(page == "page+2&x=y" && request.url!.absoluteString.contains("%2B"), "Pagination cursors must preserve plus signs and query punctuation")
        }
        let cost = request.url!.path == "/v1/organization/costs"
        OpenAIAPITests.expect(cost || request.url!.path == "/v1/organization/usage/completions", "No model or administrative mutation endpoint should be called")
        var status = 200
        var body: String
        if cost {
            if let failure = Int(mode) { status = failure; body = "{\"error\":{\"message\":\"\(OpenAIAPITests.key)\"}}" }
            else if mode == "redirect" { status = 302; body = "{}" }
            else if mode == "bad-json" { body = "{}" }
            else if mode == "empty" { body = #"{"object":"page","data":[],"has_more":false,"next_page":null}"# }
            else if mode == "cursor" { body = #"{"object":"page","data":[],"has_more":true,"next_page":"same"}"# }
            else {
                let next = query["page"] == nil
                let value = mode == "bad-amount" ? "true" : (mode == "overflow" ? "99999999999999999999999999" : (next ? "0.1" : "0.2"))
                let currency = mode == "currency" ? "eur" : "usd"
                let start = next ? 1793577600 : 1794268800
                body = "{\"object\":\"page\",\"data\":[{\"start_time\":\(start),\"end_time\":\(start + 86400),\"results\":[{\"amount\":{\"value\":\(value),\"currency\":\"\(currency)\"}}]}],\"has_more\":\(next),\"next_page\":\(next ? "\"page+2&x=y\"" : "null")}"
            }
        } else if mode == "usage-error" {
            status = 403; body = "{}"
        } else {
            body = #"{"object":"page","data":[{"start_time":1794268800,"end_time":1794355200,"results":[{"input_tokens":1000,"output_tokens":120,"input_cached_tokens":400,"num_model_requests":7}]}],"has_more":false,"next_page":null}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Location": "https://example.invalid"])!)
    }
}
