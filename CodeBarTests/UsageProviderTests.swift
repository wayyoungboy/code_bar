import Foundation

enum UsageProviderTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func run() async throws {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer fixture-secret", forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        var usedFallback = false
        let (recovered, _) = try await CodexHTTPTransport.load(
            request,
            primary: { _ in throw URLError(.secureConnectionFailed) },
            fallback: { _ in usedFallback = true; return (Data("recovered".utf8), response) }
        )
        expect(usedFallback && recovered == Data("recovered".utf8), "Codex should recover from the reproduced native TLS transport failure")
        usedFallback = false
        do {
            _ = try await CodexHTTPTransport.load(
                request,
                primary: { _ in throw URLError(.serverCertificateUntrusted) },
                fallback: { _ in usedFallback = true; return (Data(), response) }
            )
            fatalError("Codex should preserve certificate trust failures")
        } catch { expect(!usedFallback, "Certificate trust failures should not trigger a transport fallback") }
        let unauthorized = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        let (_, rejected) = try await CodexHTTPTransport.load(
            request,
            primary: { _ in (Data(), unauthorized) },
            fallback: { _ in fatalError("Codex should not retry rejected credentials") }
        )
        expect((rejected as? HTTPURLResponse)?.statusCode == 401, "Codex should retain the HTTP authentication response")
        let arguments = try CodexHTTPTransport.curlArguments(for: request, proxyURL: nil)
        expect(arguments.first == "--disable", "Codex curl should ignore user curlrc settings")
        expect(!arguments.joined().contains("fixture-secret"), "OAuth credentials must not appear in process arguments")
        expect(arguments.contains("*") && arguments.contains("--noproxy"), "Unconfigured Codex requests should use a direct connection")
        expect(!arguments.contains("--insecure"), "Codex fallback must keep TLS certificate verification enabled")
        let systemProxy = try CodexHTTPTransport.systemProxyURL(from: [[
            kCFProxyTypeKey as String: kCFProxyTypeHTTP as String,
            kCFProxyHostNameKey as String: "127.0.0.1",
            kCFProxyPortNumberKey as String: 7890,
        ]])
        expect(systemProxy == "http://127.0.0.1:7890", "Codex fallback should preserve the macOS system proxy")
        let directProxy = try CodexHTTPTransport.systemProxyURL(from: [[kCFProxyTypeKey as String: kCFProxyTypeNone as String]])
        expect(directProxy == nil, "Codex should not invent a default proxy")

        let status = try JSONDecoder().decode(AntigravityUserStatusResponse.self, from: Data("""
        {"userStatus":{"email":"fixture@example.invalid","userTier":{"name":"Google AI Pro"}}}
        """.utf8))
        expect(status.userTier?.name == "Google AI Pro", "AGY desktop should decode the userStatus envelope")
        expect(status.email == "fixture@example.invalid", "AGY desktop should decode its account from the envelope")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = directory.appendingPathComponent("agy")
        let report = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","name":"Five Hour","remaining_fraction":0.75,"reset_time":"2026-10-25T01:02:03.123Z"}]}]}}}"#
        try writeCLI(at: cli, body: """
        [ "$1" = "-p" ] && [ "$2" = "/usage" ] && [ "$3" = "--output-format" ] && [ "$4" = "json" ] || exit 9
        printf '%s' '\(report)'
        """)
        let usage = try await AntigravityProvider(config: AntigravityConfig(cliPath: cli.path)).fetchUsage()
        expect(usage.items.count == 1 && usage.items.first?.used == 25, "Explicit AGY CLI selection should use that CLI even while the desktop app runs")
        expect(usage.items.first?.resetDate != nil, "AGY should accept fractional reset timestamps")

        try writeCLI(at: cli, body: "printf '%s' '\(report)'\nexit 7")
        do {
            _ = try await AntigravityProvider(config: AntigravityConfig(cliPath: cli.path)).fetchUsage()
            fatalError("AGY must reject unsuccessful CLI exits even when stdout contains quota JSON")
        } catch { }

        let padded = report + String(repeating: " ", count: 200_000)
        try writeCLI(at: cli, body: "printf '%s' '\(padded)'")
        let largeUsage = try await AntigravityProvider(config: AntigravityConfig(cliPath: cli.path)).fetchUsage()
        expect(largeUsage.items.first?.used == 25, "AGY should drain CLI output larger than a pipe buffer")

        try writeCLI(at: cli, body: "exec /bin/sleep 5")
        let timeoutStart = Date()
        do {
            _ = try await AntigravityProvider.testCLI(config: AntigravityConfig(cliPath: cli.path), timeout: 0.1)
            fatalError("AGY should stop an unresponsive CLI")
        } catch { expect(Date().timeIntervalSince(timeoutStart) < 2, "AGY CLI timeout should not leave the request blocked") }

        let testAll = ProcessInfo.processInfo.environment["CODEBAR_LIVE_USAGE_TESTS"] == "1"
        if testAll {
            try await reportLiveUsage("Codex", provider: CodexProvider())
            try await reportLiveUsage("AGY desktop", provider: AntigravityProvider())
            if let path = ProcessInfo.processInfo.environment["CODEBAR_TEST_AGY_CLI"] {
                try await reportLiveUsage("AGY CLI", provider: AntigravityProvider(config: AntigravityConfig(cliPath: path)))
            }
        }
        let testGrok = ProcessInfo.processInfo.environment["CODEBAR_LIVE_GROK_TESTS"] == "1"
        if testGrok {
            let usage = try await reportLiveUsage("Grok", provider: GrokProvider(config: GrokConfig(isCLIRefreshEnabled: true)))
            expect(usage.extraInfo.contains { $0.label == "刷新状态" && $0.value == "主动刷新成功" }, "Grok live test should refresh its real quota instead of only returning a cached value")
        }
        if ProcessInfo.processInfo.environment["CODEBAR_LIVE_DISPLAY_TESTS"] == "1" {
            expect(Bundle.main.bundleURL.pathExtension == "app", "Live display tests require an app bundle for UserNotifications")
            let tracker = await UsageTracker()
            let platforms: [PlatformType] = testGrok
                ? (testAll ? [.codex, .antigravity, .grok] : [.grok])
                : [.codex, .antigravity]
            await MainActor.run { tracker.modules = tracker.modules.filter { platforms.contains($0.platform) } }
            await tracker.refresh()
            for platform in platforms {
                guard let module = await tracker.modules.first(where: { $0.platform == platform }) else {
                    fatalError("Live display should contain the \(platform.rawValue) module")
                }
                let items = await tracker.moduleUsages[module.id]?.items ?? []
                let error = await tracker.moduleErrors[module.id]
                expect(error == nil && !items.isEmpty, "Live module refresh should provide \(platform.rawValue) display data without an error")
                let selection = ModuleUsageSelection.menuBarItems(from: await tracker.moduleUsages[module.id]!, module: module)
                expect(!selection.isEmpty, "The \(platform.rawValue) menu bar should select real quota items")
                print("Live display verified: \(platform.rawValue), \(items.count) detail items, \(selection.count) menu bar items")
            }
        }
        print("Usage provider regression tests passed")
    }

    private static func writeCLI(at url: URL, body: String) throws {
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    @discardableResult
    private static func reportLiveUsage(_ label: String, provider: PlatformProvider) async throws -> PlatformUsageData {
        let usage = try await provider.fetchUsage()
        expect(!usage.items.isEmpty, "\(label) live request should return quota items")
        let summary: [String: Any] = [
            "live_provider": label,
            "plan": usage.planType,
            "items": usage.items.map { item -> [String: Any] in
                var result: [String: Any] = ["key": item.key, "label": item.label, "used_percent": item.used]
                if let reset = item.resetDate { result["reset_at"] = ISO8601DateFormatter().string(from: reset) }
                return result
            },
            "refresh_details": usage.extraInfo.filter { ["刷新状态", "Grok 同步时间"].contains($0.label) }.map { ["label": $0.label, "value": $0.value] },
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        return usage
    }
}
