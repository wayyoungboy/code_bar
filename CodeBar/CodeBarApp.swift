import SwiftUI

@main
struct CodeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("操作") {
                Button("刷新用量") {
                    UsageTracker.shared.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var rotationTimer: Timer?
    private var currentPlatformIndex: Int = 0

    nonisolated deinit {
        Task { @MainActor in
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self
        statusItem?.button?.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: "CodeBar")

        // 设置初始标题
        updateStatusItemTitle()

        // 创建弹窗视图
        popover = NSPopover()
        popover?.contentSize = NSSize(width: Constants.popoverWidth, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(tracker: UsageTracker.shared))

        // 初始加载用量信息
        UsageTracker.shared.refresh()

        // 监听显示设置窗口通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow(_:)),
            name: .showSettings,
            object: nil
        )

        // 设置滚动定时器 - 多平台时轮播
        setupRotationTimer()
    }

    private func setupRotationTimer() {
        rotationTimer = Timer.scheduledTimer(withTimeInterval: Constants.rotationInterval, repeats: true) { [weak self] _ in
            self?.advancePlatform()
            self?.updateStatusItemTitle()
        }
    }

    private func advancePlatform() {
        let platforms = UsageTracker.shared.configuredPlatforms
        guard platforms.count > 1 else { return }
        currentPlatformIndex = (currentPlatformIndex + 1) % platforms.count
    }

    @objc func updateStatusItemTitle() {
        let tracker = UsageTracker.shared
        let platforms = tracker.configuredPlatforms

        guard !platforms.isEmpty else {
            statusItem?.button?.title = "CodeBar"
            return
        }

        // 单平台直接显示，多平台轮播
        let platform: PlatformType
        if platforms.count == 1 {
            platform = platforms[0]
        } else {
            let safeIndex = currentPlatformIndex % platforms.count
            platform = platforms[safeIndex]
        }

        guard let usage = tracker.platforms[platform] else {
            statusItem?.button?.title = platform.shortName
            return
        }

        let displayTypes = tracker.displayTypes[platform] ?? [.billMonth]

        // 构建显示文本：平台名 + 各类型百分比
        var parts: [String] = [platform.shortName]

        for type in displayTypes {
            let (percent, label) = getUsageInfo(usage: usage, displayType: type)
            parts.append("\(label)\(String(format: "%.0f%%", percent))")
        }

        statusItem?.button?.title = parts.joined(separator: " ")
    }

    private func getUsageInfo(usage: PlatformUsage, displayType: UsageDisplayType) -> (Double, String) {
        switch displayType {
        case .billMonth:
            return (usage.usagePercent, "账单月")
        case .fiveHour:
            return (usage.used5HourPercent, "5小时")
        case .week:
            return (usage.usedWeekPercent, "周")
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        popover?.performClose(nil)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsWindowView(tracker: UsageTracker.shared)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "CodeBar 设置"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {}
}

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
}