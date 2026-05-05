import Foundation

struct JetBrainsProvider: PlatformProvider {
    let platformName = "JetBrains AI"

    private var quotaFilePath: String?

    private let creditScale: Double = 100000.0

    init() {
        quotaFilePath = Self.findQuotaFile()
    }

    var isConfigured: Bool {
        quotaFilePath != nil
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard let path = quotaFilePath,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw PlatformError.unknown("Quota file not found")
        }

        var usedCredits: Double = 0
        var totalCredits: Double = 0
        var nextRefill: Date?

        // Simple XML parsing for the quota values
        if let usedMatch = content.range(of: "(?<=usedCredits=\")[^\"]+", options: .regularExpression) {
            usedCredits = Double(content[usedMatch]) ?? 0
        }
        if let totalMatch = content.range(of: "(?<=totalCredits=\")[^\"]+", options: .regularExpression) {
            totalCredits = Double(content[totalMatch]) ?? 0
        }
        if let refillMatch = content.range(of: "(?<=nextRefill=\")[^\"]+", options: .regularExpression) {
            let refillStr = String(content[refillMatch])
            if let ms = Int64(refillStr) {
                nextRefill = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            }
        }

        let usedDisplay = Int(usedCredits / creditScale)
        let totalDisplay = Int(totalCredits / creditScale)
        let resetDate = nextRefill ?? Date().addingTimeInterval(24 * 3600)

        var extra: [(label: String, value: String)] = []
        let remaining = totalDisplay - usedDisplay
        extra.append((label: "Used", value: "\(usedDisplay) / \(totalDisplay) credits"))
        extra.append((label: "Remaining", value: "\(remaining) credits"))

        return PlatformUsageData(
            platformName: platformName,
            planType: "AI Assistant",
            items: [
                UsageItem(
                    key: "quota", label: "Quota",
                    used: usedDisplay, total: totalDisplay, unit: "credits",
                    resetDate: resetDate
                ),
            ],
            extraInfo: extra
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private static func findQuotaFile() -> String? {
        let home = NSHomeDirectory()
        let basePath = home + "/Library/Application Support/JetBrains"

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath) else {
            return nil
        }

        let idePatterns = [
            "IntelliJIdea", "PyCharm", "GoLand", "WebStorm", "PhpStorm",
            "CLion", "RubyMine", "Rider", "DataGrip", "RustRover",
            "DataSpell", "Fleet", "AndroidStudio", "Aqua",
        ]

        // Find the most recent IDE version directory
        var bestPath: String?
        var bestVersion = ""

        for dir in contents {
            for pattern in idePatterns {
                if dir.hasPrefix(pattern) {
                    let version = String(dir.dropFirst(pattern.count))
                    if version > bestVersion {
                        let quotaPath = basePath + "/\(dir)/options/AIAssistantQuotaManager2.xml"
                        if FileManager.default.fileExists(atPath: quotaPath) {
                            bestVersion = version
                            bestPath = quotaPath
                        }
                    }
                }
            }
        }

        return bestPath
    }
}
