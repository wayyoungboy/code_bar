import Foundation

struct OpenCodeProvider: PlatformProvider {
    let platformName = "OpenCode"

    private var hasAuth: Bool = false
    private let dbPath: String

    private static let sessionLimit: Double = 12.0
    private static let weeklyLimit: Double = 30.0
    private static let monthlyLimit: Double = 60.0

    init() {
        let home = NSHomeDirectory()
        dbPath = home + "/.local/share/opencode/opencode.db"

        // Check both auth and DB
        let authPath = home + "/.local/share/opencode/auth.json"
        hasAuth = FileManager.default.fileExists(atPath: authPath) &&
                  FileManager.default.fileExists(atPath: dbPath)
    }

    var isConfigured: Bool {
        hasAuth
    }

    func fetchUsage() async throws -> PlatformUsageData {
        guard hasAuth else {
            throw PlatformError.unknown("OpenCode not configured")
        }

        let now = Date()

        // Session: 5-hour rolling window
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let sessionCost = queryTotalCost(since: sessionStart)

        // Weekly: UTC week
        let weekStart = startOfUTCWeek(from: now)
        let weeklyCost = queryTotalCost(since: weekStart)

        // Monthly
        let monthStart = startOfMonth(from: now)
        let monthlyCost = queryTotalCost(since: monthStart)

        let sessionUsed = Int(sessionCost * 100)
        let sessionTotal = Int(Self.sessionLimit * 100)
        let weeklyUsed = Int(weeklyCost * 100)
        let weeklyTotal = Int(Self.weeklyLimit * 100)
        let monthlyUsed = Int(monthlyCost * 100)
        let monthlyTotal = Int(Self.monthlyLimit * 100)

        return PlatformUsageData(
            platformName: platformName,
            planType: "Go",
            items: [
                UsageItem(
                    key: "session", label: "Session",
                    used: sessionUsed, total: sessionTotal, unit: "$",
                    resetDate: now.addingTimeInterval(5 * 3600)
                ),
                UsageItem(
                    key: "weekly", label: "Weekly",
                    used: weeklyUsed, total: weeklyTotal, unit: "$",
                    resetDate: nextUTCWeekStart(from: now)
                ),
                UsageItem(
                    key: "monthly", label: "Monthly",
                    used: monthlyUsed, total: monthlyTotal, unit: "$",
                    resetDate: nextMonthStart(from: now)
                ),
            ]
        )
    }

    func validateConfig() async throws -> Bool {
        _ = try await fetchUsage()
        return true
    }

    private func queryTotalCost(since: Date) -> Double {
        let sql = """
            SELECT COALESCE(SUM(
                CAST(json_extract(metadata, '$.cost.totalCost') AS REAL)
            ), 0.0) as total
            FROM message
            WHERE created_at >= ?
            AND json_extract(metadata, '$.cost.totalCost') IS NOT NULL
        """

        let rows = SQLiteHelper.queryWithDouble(dbPath: dbPath, sql: sql, param: since.timeIntervalSince1970)
        if let first = rows.first, let totalStr = first["total"], let total = Double(totalStr) {
            return total
        }
        return 0.0
    }

    private func startOfUTCWeek(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    private func nextUTCWeekStart(from date: Date) -> Date {
        startOfUTCWeek(from: date).addingTimeInterval(7 * 24 * 3600)
    }

    private func startOfMonth(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func nextMonthStart(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(byAdding: .month, value: 1, to: startOfMonth(from: date)) ?? date.addingTimeInterval(30 * 24 * 3600)
    }
}
