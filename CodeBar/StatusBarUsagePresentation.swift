import Foundation

struct StatusBarUsageRotation {
    private(set) var index = 0
    private var hasRegisteredRefresh = false

    mutating func registerRefresh() {
        guard hasRegisteredRefresh else {
            hasRegisteredRefresh = true
            return
        }
        index = (index + 1) % 2
    }
}

struct StatusBarUsagePresentation: Equatable {
    let title: String
    let tooltip: String

    static func make(lines: [String], rotationIndex: Int, fallback: String) -> StatusBarUsagePresentation {
        let visibleLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)

        guard !visibleLines.isEmpty else {
            return StatusBarUsagePresentation(title: fallback, tooltip: fallback)
        }

        let retainedLines = Array(visibleLines)
        let safeIndex = rotationIndex >= 0 ? rotationIndex % retainedLines.count : 0
        return StatusBarUsagePresentation(
            title: retainedLines[safeIndex],
            tooltip: retainedLines.joined(separator: " / ")
        )
    }
}
