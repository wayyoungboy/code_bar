import Foundation

struct CopilotProvider: PlatformProvider {
    let platformName = "Copilot"

    private var token: String?

    private let apiURL = "https://api.github.com/copilot_internal/user"

    init() {
        token = Self.findToken()
    }

    var isConfigured: Bool {
        token != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let token else {
            throw PlatformError.invalidAPIKey
        }

        guard let url = URL(string: apiURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.100.0", forHTTPHeaderField: "Editor-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var items: [UsageItem] = []
        let planType = (json["copilot_plan"] as? String)?.capitalized ?? "Pro"
        let resetDate = Date().addingTimeInterval(30 * 24 * 3600)

        // Premium interactions
        if let premiumQuotas = json["premium_chat_quotas"] as? [String: Any],
           let used = premiumQuotas["chat_messages_used"] as? Int,
           let total = premiumQuotas["chat_messages_limit"] as? Int, total > 0 {
            items.append(UsageItem(
                key: "premium", label: "Premium",
                used: used, total: total, unit: "req",
                resetDate: resetDate
            ))
        }

        // Chat quota
        if let chatQuotas = json["chat_quotas"] as? [String: Any],
           let used = chatQuotas["premium_requests_used"] as? Int,
           let total = chatQuotas["premium_requests_limit"] as? Int, total > 0 {
            items.append(UsageItem(
                key: "chat", label: "Chat",
                used: used, total: total, unit: "req",
                resetDate: resetDate
            ))
        }

        // Completions
        if let completionQuotas = json["limited_user_quotas"] as? [String: Any],
           let used = completionQuotas["completions_used"] as? Int,
           let total = completionQuotas["completions_limit"] as? Int, total > 0 {
            items.append(UsageItem(
                key: "completions", label: "Completions",
                used: used, total: total, unit: "req",
                resetDate: resetDate
            ))
        }

        if items.isEmpty {
            items.append(UsageItem(
                key: "status", label: "Status",
                used: 0, total: 100, unit: "%",
                resetDate: resetDate
            ))
        }

        return PlatformUsageData(
            platformName: platformName,
            planType: planType,
            items: items
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private static func findToken() -> String? {
        let home = NSHomeDirectory()
        let ghDir = home + "/.config/gh"

        // Try file-based config first (no authorization prompt)
        let hostsPath = ghDir + "/hosts.yml"
        if let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("oauth_token:") {
                    let token = trimmed.replacingOccurrences(of: "oauth_token:", with: "").trimmingCharacters(in: .whitespaces)
                    if !token.isEmpty { return token }
                }
            }
        }

        // Only try keychain if gh CLI is installed
        if FileManager.default.fileExists(atPath: ghDir),
           let token = KeychainHelper.readExternalItem(service: "gh:github.com") {
            return token
        }

        return nil
    }

}
