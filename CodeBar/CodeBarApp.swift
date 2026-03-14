import SwiftUI

@main
struct CodeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var tracker: UsageTracker?
    var rotationTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建追踪器
        tracker = UsageTracker()

        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        // 设置初始标题
        updateStatusItemTitle()

        // 创建弹窗视图
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(tracker: tracker!))

        // 初始加载用量信息
        refreshUsage()

        // 监听用量刷新通知
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusItemTitle), name: NSApplication.didBecomeActiveNotification, object: nil)

        // 设置滚动定时器 - 每 5 秒更新一次状态栏标题
        setupRotationTimer()
    }

    private func setupRotationTimer() {
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatusItemTitle()
        }
    }

    @objc func updateStatusItemTitle() {
        guard let tracker = tracker,
              let usage = tracker.currentUsage else {
            statusItem?.button?.title = "Code Plan"
            return
        }

        // 如果只选择了一种显示类型，直接显示
        if tracker.displayTypes.count == 1 {
            let type = tracker.displayTypes.first
            switch type {
            case .billMonth:
                statusItem?.button?.title = "\(formatUsage(usage.used, total: usage.total))"
            case .fiveHour:
                statusItem?.button?.title = "\(formatUsage(usage.used5Hour, total: usage.total5Hour))"
            case .week:
                statusItem?.button?.title = "\(formatUsage(usage.usedWeek, total: usage.totalWeek))"
            case nil:
                statusItem?.button?.title = "Code Plan"
            }
        } else if tracker.displayTypes.isEmpty {
            statusItem?.button?.title = "Code Plan"
        } else {
            // 多种类型，根据当前索引显示
            let safeIndex = tracker.currentDisplayIndex % tracker.displayTypes.count
            let type = tracker.displayTypes[safeIndex]
            switch type {
            case .billMonth:
                statusItem?.button?.title = "\(formatUsage(usage.used, total: usage.total))"
            case .fiveHour:
                statusItem?.button?.title = "\(formatUsage(usage.used5Hour, total: usage.total5Hour))"
            case .week:
                statusItem?.button?.title = "\(formatUsage(usage.usedWeek, total: usage.totalWeek))"
            }
        }
    }

    private func formatUsage(_ used: Int, total: Int) -> String {
        let percent = Double(used) / Double(total) * 100
        return String(format: "百炼 %.0f%%", percent)
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func refreshUsage() {
        tracker?.refresh()
    }
}

extension Notification.Name {
    static let refreshUsage = Notification.Name("refreshUsage")
}
