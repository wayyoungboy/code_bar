import Foundation
import Darwin

enum ModuleProxyTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func run() async throws {
        let address = "http://127.0.0.1:7890"
        let configurations: [MonitorModuleConfig] = [
            .bailian(BailianConfig(cookies: "fixture-cookie", secToken: "fixture-token")),
            .zenmux(ZenMuxAccountConfig(apiKey: String(repeating: "a", count: 24))),
            .mimo(MimoConfig(serviceToken: "fixture-token", userId: "fixture-user")),
            .codex(CodexConfig()), .gemini(GeminiConfig()),
            .grok(GrokConfig()), .antigravity(AntigravityConfig()),
        ]
        for var configuration in configurations {
            let legacy = try JSONEncoder().encode(configuration)
            let decodedLegacy = try JSONDecoder().decode(MonitorModuleConfig.self, from: legacy)
            expect(decodedLegacy.proxyURL == nil, "Existing modules must decode without a proxy setting")
            configuration.proxyURL = address
            let decoded = try JSONDecoder().decode(MonitorModuleConfig.self, from: JSONEncoder().encode(configuration))
            expect(decoded.proxyURL == address, "Every module must persist its own proxy")
            configuration.proxyURL = "  "
            expect(configuration.proxyURL == nil, "Clearing a module proxy should restore its default network settings")
        }

        let http = try ModuleProxyConfiguration.sessionConfiguration(proxyURL: address)
        let proxies = http.connectionProxyDictionary ?? [:]
        expect(proxies[kCFNetworkProxiesHTTPSProxy as String] as? String == "127.0.0.1", "HTTPS requests should use the configured HTTP proxy")
        expect(proxies[kCFNetworkProxiesHTTPSPort as String] as? Int == 7890, "The configured proxy port must reach URLSession")
        let socks = try ModuleProxyConfiguration.sessionConfiguration(proxyURL: " socks5://127.0.0.1:1080 ")
        expect(socks.connectionProxyDictionary?[kCFNetworkProxiesSOCKSPort as String] as? Int == 1080, "SOCKS5 should configure the native SOCKS transport")
        let inherited = try ModuleProxyConfiguration.sessionConfiguration(proxyURL: nil)
        expect(inherited.connectionProxyDictionary == nil, "Empty proxy fields should preserve the system network configuration")
        for invalid in ["127.0.0.1:7890", "ftp://127.0.0.1:7890", "http://localhost", "http://localhost:0", "http://localhost:70000", "http://user:password@localhost:7890", "http://localhost:7890/path"] {
            do {
                _ = try ModuleProxyConfiguration.sessionConfiguration(proxyURL: invalid)
                fatalError("Malformed proxy addresses must be rejected")
            } catch { }
        }

        let base = ["HTTPS_PROXY": "http://previous.invalid:8080", "NO_PROXY": "*", "UNRELATED": "preserved"]
        let environment = try ModuleProxyConfiguration.environment(proxyURL: address, inheriting: base)
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            expect(environment[key] == address, "A module's CLI proxy must override inherited proxy variables")
        }
        expect(environment["NO_PROXY"] == "localhost,127.0.0.1,::1", "CLI loopback traffic must stay local")
        expect(environment["UNRELATED"] == "preserved", "Module proxy configuration must preserve unrelated CLI environment")
        let unchanged = try ModuleProxyConfiguration.environment(proxyURL: nil, inheriting: base)
        expect(unchanged == base, "Clearing the proxy must restore inherited CLI settings")

        var account = ZenMuxAccountConfig(apiKey: String(repeating: "a", count: 24))
        account.proxyURL = address
        let module = MonitorModule(alias: "proxy-test", config: .zenmux(account), sortOrder: 0)
        expect(ModuleProviderConfiguration.zenMuxAccount(for: module).proxyURL == address, "ZenMux account conversion must retain the module proxy")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cli = folder.appendingPathComponent("agy")
        let report = #"{"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini","buckets":[{"id":"gemini-5h","name":"5h","remaining_fraction":0.8}]}]}}}"#
        let script = """
        #!/bin/sh
        [ "$PWD" != "/" ] && [ "$PWD" != "$HOME" ] || exit 19
        [ "$HTTPS_PROXY" = "\(address)" ] && [ "$http_proxy" = "\(address)" ] && [ "$NO_PROXY" = "localhost,127.0.0.1,::1" ] || exit 17
        printf '%s' '\(report)'
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let usage = try await AntigravityProvider(config: AntigravityConfig(cliPath: cli.path, proxyURL: address)).fetchUsage()
        expect(usage.items.first?.used == 20, "AGY must pass the configured proxy to its actual CLI process")

        let grokHome = folder.appendingPathComponent("grok")
        try FileManager.default.createDirectory(at: grokHome.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: grokHome.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let grokCLI = grokHome.appendingPathComponent("bin/grok")
        let grokScript = """
        #!/bin/sh
        [ "$PWD" != "/" ] && [ "$PWD" != "$HOME" ] || exit 19
        [ "$HTTPS_PROXY" = "\(address)" ] && [ "$all_proxy" = "\(address)" ] || exit 18
        printf '%s\\n' '{"ts":"proxy-fixture-start","msg":"startup timing"}' >> "$GROK_HOME/logs/unified.jsonl"
        while IFS= read -r command; do
          case "$command" in
            /usage) printf '%s\\n' '{"ts":"2026-10-27T00:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":31}}}' >> "$GROK_HOME/logs/unified.jsonl" ;;
            /quit) exit 0 ;;
          esac
        done
        """
        try Data(grokScript.utf8).write(to: grokCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: grokCLI.path)
        let grok = try await GrokProvider(config: GrokConfig(homeDirectory: grokHome.path, proxyURL: address, isCLIRefreshEnabled: true)).fetchUsage()
        expect(grok.items.first?.used == 31, "Grok must pass the module proxy through the real PTY subprocess path")
        expect(grok.extraInfo.contains { $0.label == "刷新状态" && $0.value == "主动刷新成功" }, "Grok proxy tests must perform a refresh instead of using a cached snapshot")

        let httpProbe = try ProxyProbe(socks: false)
        defer { httpProbe.stop() }
        let httpAddress = "http://127.0.0.1:\(httpProbe.port)"
        let providers: [any PlatformProvider] = [
            BailianProvider(config: BailianConfig(cookies: "fixture", secToken: "fixture", proxyURL: httpAddress)),
            MimoProvider(config: MimoConfig(serviceToken: "fixture", userId: "fixture", proxyURL: httpAddress)),
            ZenMuxProvider(config: ZenMuxConfig(accounts: [ZenMuxAccountConfig(apiKey: String(repeating: "a", count: 24), proxyURL: httpAddress)])),
        ]
        var errors: [String] = []
        for provider in providers {
            do {
                _ = try await provider.fetchUsage()
                fatalError("The proxy fixture deliberately rejects upstream connections")
            } catch { errors.append("\(provider.platformName): \(error.localizedDescription)") }
        }
        let targets = httpProbe.targets
        if targets.isEmpty {
            FileHandle.standardOutput.write(Data("Proxy routing diagnostics at \(httpAddress): \(errors)\n".utf8))
        } else {
            FileHandle.standardOutput.write(Data("Proxy routing targets: \(targets)\n".utf8))
        }
        for host in ["bailian-cs.console.aliyun.com:443", "platform.xiaomimimo.com:443", "zenmux.ai:443"] {
            expect(targets.contains { $0.contains(host) }, "The provider request must actually reach its configured HTTP proxy")
        }

        let otherProxy = try ProxyProbe(socks: false)
        defer { otherProxy.stop() }
        let priorCount = httpProbe.targets.count
        let isolatedAccounts = [
            ZenMuxAccountConfig(apiKey: String(repeating: "a", count: 24), proxyURL: httpAddress),
            ZenMuxAccountConfig(apiKey: String(repeating: "b", count: 24), proxyURL: "http://127.0.0.1:\(otherProxy.port)"),
        ]
        do { _ = try await ZenMuxProvider(config: ZenMuxConfig(accounts: isolatedAccounts)).fetchUsage() }
        catch { }
        expect(httpProbe.targets.count > priorCount && otherProxy.targets.contains { $0.contains("zenmux.ai:443") }, "Concurrent ZenMux accounts must use their respective proxy rather than sharing one")

        let socksProbe = try ProxyProbe(socks: true)
        defer { socksProbe.stop() }
        let session = try ModuleProxyConfiguration.makeSession(proxyURL: "socks5://127.0.0.1:\(socksProbe.port)")
        defer { session.finishTasksAndInvalidate() }
        do {
            _ = try await session.data(from: URL(string: "https://192.0.2.1/")!)
            fatalError("The SOCKS fixture deliberately rejects upstream connections")
        } catch { }
        expect(socksProbe.targets.contains("192.0.2.1"), "The configured SOCKS5 proxy must receive a real SOCKS connect request")
        print("Module proxy tests passed")
    }
}

/// Local rejecting proxies prove routing without forwarding credentials or contacting upstream services.
private final class ProxyProbe: @unchecked Sendable {
    private let descriptor: Int32
    private let lock = NSLock()
    private var captured: [String] = []
    let port: UInt16

    var targets: [String] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    init(socks: Bool) throws {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw PlatformError.unknown("Unable to create proxy fixture socket") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) }
        }
        guard bound == 0, named == 0, Darwin.listen(socketFD, 16) == 0 else {
            Darwin.close(socketFD)
            throw PlatformError.unknown("Unable to bind proxy fixture socket")
        }
        descriptor = socketFD
        port = UInt16(bigEndian: address.sin_port)
        DispatchQueue.global().async { [weak self] in
            while true {
                let client = Darwin.accept(socketFD, nil, nil)
                guard client >= 0 else { return }
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                var noSignal: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                if socks { self?.readSOCKS(client) } else { self?.readHTTP(client) }
                Darwin.close(client)
            }
        }
    }

    func stop() {
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func record(_ target: String) {
        lock.lock(); defer { lock.unlock() }
        captured.append(target)
    }

    private func receive(_ client: Int32, count: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes { buffer in
                Darwin.recv(client, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            guard received > 0 else { return nil }
            offset += received
        }
        return bytes
    }

    private func send(_ client: Int32, bytes: [UInt8]) {
        _ = bytes.withUnsafeBytes { Darwin.send(client, $0.baseAddress!, $0.count, 0) }
    }

    private func readHTTP(_ client: Int32) {
        var bytes: [UInt8] = []
        while bytes.count < 32_768, let byte = receive(client, count: 1)?.first {
            bytes.append(byte)
            if bytes.suffix(4) == [13, 10, 13, 10] { break }
        }
        if let text = String(bytes: bytes, encoding: .utf8) {
            record(text.components(separatedBy: "\r\n").first ?? "")
        }
        send(client, bytes: Array("HTTP/1.1 502 Proxy Test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
    }

    private func readSOCKS(_ client: Int32) {
        guard let greeting = receive(client, count: 2), greeting[0] == 5,
              receive(client, count: Int(greeting[1])) != nil else { return }
        send(client, bytes: [5, 0])
        guard let header = receive(client, count: 4), header[0] == 5 else { return }
        if header[3] == 1, let address = receive(client, count: 4) {
            record(address.map(String.init).joined(separator: "."))
        } else if header[3] == 3, let count = receive(client, count: 1)?.first,
                  let address = receive(client, count: Int(count)) {
            record(String(bytes: address, encoding: .utf8) ?? "")
        }
        _ = receive(client, count: 2)
        send(client, bytes: [5, 2, 0, 1, 0, 0, 0, 0, 0, 0])
    }
}
