import Foundation

/// Per-module network settings shared by native HTTP clients and CLI processes.
struct ModuleProxyConfiguration {
    let url: URL

    static func parse(_ value: String?) throws -> ModuleProxyConfiguration? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "socks", "socks5"].contains(scheme),
              let host = components.host, !host.isEmpty,
              let port = components.port, (1...65535).contains(port),
              components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil else {
            throw PlatformError.unknown("代理地址无效，请使用 http://host:port 或 socks5://host:port（不含账号密码或路径）")
        }
        components.scheme = scheme == "socks" ? "socks5" : scheme
        components.path = ""
        guard let url = components.url else { throw PlatformError.unknown("代理地址无效") }
        return ModuleProxyConfiguration(url: url)
    }

    static func validationMessage(for value: String?) -> String? {
        do { _ = try parse(value); return nil }
        catch { return error.localizedDescription }
    }

    static func sessionConfiguration(proxyURL: String?) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.networkTimeout
        configuration.timeoutIntervalForResource = Constants.networkTimeout
        if let proxy = try parse(proxyURL) {
            if proxy.url.scheme == "socks5" {
                configuration.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: true,
                    kCFNetworkProxiesSOCKSProxy as String: proxy.url.host!,
                    kCFNetworkProxiesSOCKSPort as String: proxy.url.port!,
                ]
            } else {
                configuration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: true,
                    kCFNetworkProxiesHTTPProxy as String: proxy.url.host!,
                    kCFNetworkProxiesHTTPPort as String: proxy.url.port!,
                    kCFNetworkProxiesHTTPSEnable as String: true,
                    kCFNetworkProxiesHTTPSProxy as String: proxy.url.host!,
                    kCFNetworkProxiesHTTPSPort as String: proxy.url.port!,
                ]
            }
        }
        return configuration
    }

    static func makeSession(proxyURL: String?) throws -> URLSession {
        URLSession(configuration: try sessionConfiguration(proxyURL: proxyURL))
    }

    static func environment(proxyURL: String?, inheriting original: [String: String]) throws -> [String: String] {
        guard let proxy = try parse(proxyURL) else { return original }
        var environment = original
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment[key] = proxy.url.absoluteString
        }
        // Never send local language-server or leader-socket traffic through a proxy.
        for key in ["NO_PROXY", "no_proxy"] { environment[key] = "localhost,127.0.0.1,::1" }
        return environment
    }
}
