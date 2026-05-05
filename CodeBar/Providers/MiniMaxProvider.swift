import Foundation

struct MiniMaxProvider: PlatformProvider {
    let platformName = "MiniMax"

    private var apiKey: String?
    private var isChina: Bool = false

    private let globalURL = "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"
    private let chinaURL = "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"

    init() {
        let creds = Self.findApiKey()
        apiKey = creds.key
        isChina = creds.isChina
    }

    var isConfigured: Bool {
        apiKey != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let apiKey else {
            throw PlatformError.invalidAPIKey
        }

        let baseURL = isChina ? chinaURL : globalURL
        guard let url = URL(string: baseURL) else {
            throw PlatformError.unknown("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.networkTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlatformError.parseError(NSError(domain: "", code: -1))
        }

        var usedPrompts = 0
        var totalPrompts = 0

        if isChina {
            if let remains = json["model_call_count_remains"] as? Int,
               let total = json["model_call_count_total"] as? Int {
                // CN API returns model calls, divide by 15 for prompts
                totalPrompts = total / 15
                usedPrompts = (total - remains) / 15
            }
        } else {
            if let remains = json["prompt_count_remains"] as? Int,
               let total = json["prompt_count_total"] as? Int {
                totalPrompts = total
                usedPrompts = total - remains
            }
        }

        // Infer plan tier from limit
        let planType: String
        if isChina {
            switch totalPrompts {
            case ...40: planType = "Starter"
            case ...100: planType = "Plus"
            default: planType = "Max"
            }
        } else {
            switch totalPrompts {
            case ...100: planType = "Starter"
            case ...300: planType = "Plus"
            case ...1000: planType = "Max"
            default: planType = "Ultra"
            }
        }

        let regionLabel = isChina ? " (CN)" : " (Global)"

        return PlatformUsageData(
            platformName: platformName + regionLabel,
            planType: planType,
            items: [
                UsageItem(
                    key: "session", label: "Session",
                    used: usedPrompts, total: totalPrompts, unit: "prompts",
                    resetDate: Date().addingTimeInterval(5 * 3600)
                ),
            ]
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private static func findApiKey() -> (key: String?, isChina: Bool) {
        let env = ProcessInfo.processInfo.environment

        // Check CN keys first
        if let key = env["MINIMAX_CN_API_KEY"], !key.isEmpty {
            return (key, true)
        }

        // Check global keys
        if let key = env["MINIMAX_API_KEY"], !key.isEmpty {
            // Determine region based on key format or try global first
            return (key, false)
        }

        if let key = env["MINIMAX_API_TOKEN"], !key.isEmpty {
            return (key, false)
        }

        return (nil, false)
    }
}
