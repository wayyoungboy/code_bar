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
        popover?.behavior = .transient
        let hostingController = NSHostingController(rootView: MenuBarView(tracker: UsageTracker.shared))
        hostingController.sizingOptions = [.preferredContentSize]
        popover?.contentViewController = hostingController

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

        let activeKeys = tracker.displayKeys(for: platform)
        let visibleItems = usage.items.filter { activeKeys.contains($0.key) }

        var parts: [String] = [platform.shortName]
        for item in visibleItems {
            var text = "\(item.label)\(String(format: "%.0f%%", item.percent))"
            if tracker.isResetTimeEnabled(item.key, for: platform) {
                let remaining = item.resetDate.timeIntervalSinceNow
                if remaining > 0 {
                    let hours = Int(remaining) / 3600
                    let minutes = (Int(remaining) % 3600) / 60
                    if hours > 0 {
                        text += "(\(hours)h\(minutes)m)"
                    } else {
                        text += "(\(minutes)m)"
                    }
                }
            }
            parts.append(text)
        }

        statusItem?.button?.title = parts.joined(separator: " ")
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