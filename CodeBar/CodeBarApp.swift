import SwiftUI
import UserNotifications

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
    private struct StatusItemComponents {
        let contentStack: NSStackView
        let iconView: NSImageView
        let aliasLabel: NSTextField
        let topLabel: NSTextField
        let bottomLabel: NSTextField
        let titleStack: NSStackView
    }

    private struct StatusTitleSnapshot: Equatable {
        let top: String
        let bottom: String
        let alias: String
        let platform: PlatformType?
        let length: CGFloat
        let tooltip: String

        static func == (lhs: StatusTitleSnapshot, rhs: StatusTitleSnapshot) -> Bool {
            lhs.top == rhs.top &&
                lhs.bottom == rhs.bottom &&
                lhs.alias == rhs.alias &&
                lhs.platform?.rawValue == rhs.platform?.rawValue &&
                lhs.length == rhs.length &&
                lhs.tooltip == rhs.tooltip
        }
    }

    var statusItem: NSStatusItem?
    private var defaultStatusComponents: StatusItemComponents?
    private var moduleStatusItems: [String: NSStatusItem] = [:]
    private var moduleStatusComponents: [String: StatusItemComponents] = [:]
    private var statusTitleSnapshots: [ObjectIdentifier: StatusTitleSnapshot] = [:]
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var rotationTimer: Timer?
    private var currentPlatformIndex: Int = 0
    private var currentModuleIndex: Int = 0
    private var islandController: CodeBarIslandController?
    private var isUsingIslandMode = false
    private weak var popoverAnchorButton: NSStatusBarButton?
    private var eventMonitor: Any?
    private let statusTitleFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    private let singleLineStatusTitleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    private let statusContentStack = NSStackView()
    private let statusIconView = NSImageView()
    private let statusTopLabel = NSTextField(labelWithString: "Code")
    private let statusBottomLabel = NSTextField(labelWithString: "Bar")
    private let statusTitleStack = NSStackView()

    deinit {
        rotationTimer?.invalidate()
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        isUsingIslandMode = setupIslandMode()
        if !isUsingIslandMode {
            rebuildStatusItems()

            // 创建弹窗视图
            popover = NSPopover()
            popover?.behavior = .transient
            let hostingController = NSHostingController(rootView: MenuBarView(tracker: UsageTracker.shared, updateChecker: UpdateChecker.shared))
            hostingController.sizingOptions = [.preferredContentSize]
            popover?.contentViewController = hostingController
        }

        // 启动时只检查通知状态，避免无用户动作时弹出系统授权
        UsageTracker.shared.checkNotificationPermission()

        // 监听显示设置窗口通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettingsWindow(_:)),
            name: .showSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePresentationChanged),
            name: .moduleStatusItemsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUsageDataUpdated),
            name: .usageDataUpdated,
            object: nil
        )

        if !isUsingIslandMode {
            updateRotationTimer()
        }

        // 初始加载用量信息
        UsageTracker.shared.refresh()

        // 检查更新
        Task { @MainActor in
            await UpdateChecker.shared.checkForUpdate()
        }
    }

    private func setupIslandMode() -> Bool {
        let controller = CodeBarIslandController(
            tracker: UsageTracker.shared,
            updateChecker: UpdateChecker.shared,
            onSettings: { [weak self] in
                self?.showSettingsWindow(nil)
            }
        )
        guard controller.show() else { return false }
        islandController = controller
        return true
    }

    private func startRotationTimer() {
        rotationTimer = Timer.scheduledTimer(withTimeInterval: Constants.rotationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.needsRotationTimer() else {
                    self.updateRotationTimer()
                    return
                }
                self.advancePlatform()
                self.updateStatusItemTitle()
            }
        }
    }

    private func updateRotationTimer() {
        guard !isUsingIslandMode, needsRotationTimer() else {
            rotationTimer?.invalidate()
            rotationTimer = nil
            return
        }
        guard rotationTimer == nil else { return }
        startRotationTimer()
    }

    private func needsRotationTimer() -> Bool {
        let tracker = UsageTracker.shared
        return tracker.hasAnyModule &&
            tracker.menuBarDisplayMode == .rotating &&
            tracker.menuBarModules.count > 1
    }

    private func advancePlatform() {
        let tracker = UsageTracker.shared
        if tracker.hasAnyModule {
            guard tracker.menuBarDisplayMode == .rotating else { return }
            let modules = tracker.menuBarModules
            guard modules.count > 1 else { return }
            currentModuleIndex = (currentModuleIndex + 1) % modules.count
            return
        }

        let platforms = tracker.configuredPlatforms
        guard platforms.count > 1 else { return }
        currentPlatformIndex = (currentPlatformIndex + 1) % platforms.count
    }

    @objc func updateStatusItemTitle() {
        let tracker = UsageTracker.shared
        if tracker.hasAnyModule {
            guard !tracker.menuBarModules.isEmpty else {
                setStatusTitle(top: "Code", bottom: "Bar", platform: nil)
                return
            }

            switch tracker.menuBarDisplayMode {
            case .independent:
                updateModuleStatusItems()
            case .rotating:
                updateRotatingModuleStatusItem()
            }
            return
        }

        setStatusTitle(top: "Code", bottom: "Bar", platform: nil)
    }

    @objc private func rebuildStatusItems() {
        let tracker = UsageTracker.shared
        let menuModules = tracker.menuBarModules

        for item in moduleStatusItems.values {
            statusTitleSnapshots.removeValue(forKey: ObjectIdentifier(item))
            NSStatusBar.system.removeStatusItem(item)
        }
        moduleStatusItems = [:]
        moduleStatusComponents = [:]

        if menuModules.isEmpty || tracker.menuBarDisplayMode == .rotating {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem?.button?.action = #selector(togglePopover(_:))
                statusItem?.button?.target = self
                setupStatusTitleView()
            }
            updateStatusItemTitle()
            return
        }

        if let statusItem {
            statusTitleSnapshots.removeValue(forKey: ObjectIdentifier(statusItem))
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            defaultStatusComponents = nil
        }

        for module in menuModules {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.action = #selector(togglePopover(_:))
            item.button?.target = self
            moduleStatusItems[module.id] = item
            moduleStatusComponents[module.id] = setupStatusTitleView(for: item)
        }
        updateModuleStatusItems()
    }

    @objc private func handlePresentationChanged() {
        if isUsingIslandMode {
            islandController?.refreshLayout()
        } else {
            rebuildStatusItems()
            updateRotationTimer()
        }
    }

    @objc private func handleUsageDataUpdated() {
        if !isUsingIslandMode {
            updateStatusItemTitle()
            updateRotationTimer()
        }
    }

    private func updateModuleStatusItems() {
        let tracker = UsageTracker.shared
        guard tracker.menuBarDisplayMode == .independent else {
            rebuildStatusItems()
            return
        }
        let expectedIDs = Set(tracker.menuBarModules.map(\.id))
        if expectedIDs != Set(moduleStatusItems.keys) {
            rebuildStatusItems()
            return
        }

        for module in tracker.menuBarModules {
            guard let item = moduleStatusItems[module.id],
                  let components = moduleStatusComponents[module.id] else { continue }

            guard let usage = tracker.moduleUsages[module.id] else {
                setStatusTitle(
                    top: module.platform.shortName,
                    bottom: "Loading",
                    alias: module.aliasDisplayName,
                    platform: module.platform,
                    item: item,
                    components: components
                )
                continue
            }

            let visibleItems = usage.items.filter { tracker.displayKeys(for: module).contains($0.key) }
            let preferredItems = preferredStatusItems(from: visibleItems)
            let top = preferredItems.first.map { statusLineText(for: $0, module: module) } ?? module.platform.shortName
            let bottom = preferredItems.dropFirst().first.map { statusLineText(for: $0, module: module) } ?? ""
            setStatusTitle(
                top: top,
                bottom: bottom,
                alias: module.aliasDisplayName,
                platform: module.platform,
                item: item,
                components: components
            )
        }
    }

    private func updateRotatingModuleStatusItem() {
        let tracker = UsageTracker.shared
        guard tracker.menuBarDisplayMode == .rotating else {
            rebuildStatusItems()
            return
        }

        let modules = tracker.menuBarModules
        guard !modules.isEmpty else {
            setStatusTitle(top: "Code", bottom: "Bar", platform: nil)
            return
        }

        if statusItem == nil || defaultStatusComponents == nil {
            rebuildStatusItems()
            return
        }

        let safeIndex = currentModuleIndex % modules.count
        let module = modules[safeIndex]

        guard let usage = tracker.moduleUsages[module.id] else {
            setStatusTitle(
                top: module.platform.shortName,
                bottom: "Loading",
                alias: module.aliasDisplayName,
                platform: module.platform
            )
            return
        }

        let visibleItems = usage.items.filter { tracker.displayKeys(for: module).contains($0.key) }
        let preferredItems = preferredStatusItems(from: visibleItems)
        let top = preferredItems.first.map { statusLineText(for: $0, module: module) } ?? module.platform.shortName
        let bottom = preferredItems.dropFirst().first.map { statusLineText(for: $0, module: module) } ?? ""
        setStatusTitle(top: top, bottom: bottom, alias: module.aliasDisplayName, platform: module.platform)
    }

    private func preferredStatusItems(from items: [UsageItem]) -> [UsageItem] {
        let preferredKeys = ["5hour", "7day"]
        var result: [UsageItem] = []

        for key in preferredKeys {
            if let item = items.first(where: { $0.key == key }) {
                result.append(item)
            }
        }

        for item in items where !result.contains(where: { $0.key == item.key }) {
            result.append(item)
            if result.count >= 2 { break }
        }

        return Array(result.prefix(2))
    }

    private func statusLineText(for item: UsageItem, platform: PlatformType) -> String {
        var text = "\(compactLabel(for: item)) \(String(format: "%.0f%%", item.percent))"

        if UsageTracker.shared.isResetTimeEnabled(item.key, for: platform),
           let resetText = compactResetText(until: item.resetDate) {
            text += "(\(resetText))"
        }

        return text
    }

    private func statusLineText(for item: UsageItem, module: MonitorModule) -> String {
        var text = "\(compactLabel(for: item)) \(UsageStatusFormatting.compactPercentText(for: item, displayMode: module.percentDisplayMode))"

        if UsageTracker.shared.isResetTimeEnabled(item.key, for: module),
           let resetText = compactResetText(until: item.resetDate) {
            text += "(\(resetText))"
        }

        return text
    }

    private func compactResetText(until resetDate: Date) -> String? {
        let remaining = resetDate.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        let totalMinutes = max(1, Int(remaining) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func compactLabel(for item: UsageItem) -> String {
        switch item.key {
        case "5hour":
            return "5h"
        case "7day":
            return "7d"
        default:
            if item.label.contains("小时") {
                return item.label.replacingOccurrences(of: "小时", with: "h")
            }
            if item.label.contains("天") {
                return item.label.replacingOccurrences(of: "天", with: "d")
            }
            return item.label
        }
    }

    private func setStatusTitle(top: String, bottom: String, alias: String? = nil, platform: PlatformType?) {
        guard let statusItem, let components = defaultStatusComponents else { return }
        setStatusTitle(top: top, bottom: bottom, alias: alias, platform: platform, item: statusItem, components: components)
    }

    private func setStatusTitle(
        top: String,
        bottom: String,
        alias: String? = nil,
        platform: PlatformType?,
        item: NSStatusItem,
        components: StatusItemComponents
    ) {
        let aliasText = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isSingleLine = bottom.isEmpty
        let topFont = isSingleLine ? singleLineStatusTitleFont : statusTitleFont
        let bottomFont = statusTitleFont
        let titleWidth = max(
            statusTextWidth(top, font: topFont),
            statusTextWidth(bottom, font: bottomFont)
        )
        let aliasWidth = aliasText.isEmpty ? 0 : statusTextWidth(aliasText, font: components.aliasLabel.font ?? statusTitleFont) + 4
        let length = max(40, titleWidth + aliasWidth + 32)
        let usageTooltip = bottom.isEmpty ? top : "\(top) / \(bottom)"
        let tooltip = aliasText.isEmpty ? usageTooltip : "\(aliasText) · \(usageTooltip)"
        let snapshot = StatusTitleSnapshot(
            top: top,
            bottom: bottom,
            alias: aliasText,
            platform: platform,
            length: length,
            tooltip: tooltip
        )
        let snapshotKey = ObjectIdentifier(item)
        guard statusTitleSnapshots[snapshotKey] != snapshot else { return }
        statusTitleSnapshots[snapshotKey] = snapshot

        item.button?.image = nil
        item.button?.title = ""
        item.button?.attributedTitle = NSAttributedString(string: "")
        components.iconView.image = statusIcon(for: platform)

        components.aliasLabel.stringValue = aliasText
        components.aliasLabel.isHidden = aliasText.isEmpty
        components.topLabel.stringValue = top
        components.bottomLabel.stringValue = bottom
        components.bottomLabel.isHidden = bottom.isEmpty

        components.topLabel.font = topFont
        components.bottomLabel.font = bottomFont
        components.titleStack.spacing = isSingleLine ? 0 : -1

        item.length = length
        item.button?.toolTip = tooltip
    }

    private func setupStatusTitleView() {
        guard let button = statusItem?.button else { return }
        defaultStatusComponents = setupStatusTitleView(for: button)
    }

    private func setupStatusTitleView(for item: NSStatusItem) -> StatusItemComponents? {
        guard let button = item.button else { return nil }
        return setupStatusTitleView(for: button)
    }

    @discardableResult
    private func setupStatusTitleView(for button: NSStatusBarButton) -> StatusItemComponents {
        let statusContentStack = NSStackView()
        let statusIconView = NSImageView()
        let statusAliasLabel = NSTextField(labelWithString: "")
        let statusTopLabel = NSTextField(labelWithString: "Code")
        let statusBottomLabel = NSTextField(labelWithString: "Bar")
        let statusTitleStack = NSStackView()

        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.imageScaling = .scaleProportionallyDown
        statusIconView.contentTintColor = .labelColor
        statusIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            statusIconView.widthAnchor.constraint(equalToConstant: 13),
            statusIconView.heightAnchor.constraint(equalToConstant: 13),
        ])

        statusAliasLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusAliasLabel.lineBreakMode = .byTruncatingTail
        statusAliasLabel.textColor = .labelColor
        statusAliasLabel.maximumNumberOfLines = 1
        statusAliasLabel.isHidden = true
        statusAliasLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        statusAliasLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        [statusTopLabel, statusBottomLabel].forEach { label in
            label.alignment = .center
            label.lineBreakMode = .byClipping
            label.textColor = .labelColor
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        statusTitleStack.orientation = .vertical
        statusTitleStack.alignment = .centerX
        statusTitleStack.distribution = .fill
        statusTitleStack.translatesAutoresizingMaskIntoConstraints = false
        statusTitleStack.addArrangedSubview(statusTopLabel)
        statusTitleStack.addArrangedSubview(statusBottomLabel)

        statusContentStack.orientation = .horizontal
        statusContentStack.alignment = .centerY
        statusContentStack.distribution = .fill
        statusContentStack.spacing = 4
        statusContentStack.translatesAutoresizingMaskIntoConstraints = false
        statusContentStack.addArrangedSubview(statusIconView)
        statusContentStack.addArrangedSubview(statusAliasLabel)
        statusContentStack.addArrangedSubview(statusTitleStack)

        button.addSubview(statusContentStack)
        NSLayoutConstraint.activate([
            statusContentStack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            statusContentStack.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 1.5),
            statusContentStack.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 5),
            statusContentStack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -5),
        ])

        return StatusItemComponents(
            contentStack: statusContentStack,
            iconView: statusIconView,
            aliasLabel: statusAliasLabel,
            topLabel: statusTopLabel,
            bottomLabel: statusBottomLabel,
            titleStack: statusTitleStack
        )
    }

    private func statusIcon(for platform: PlatformType?) -> NSImage? {
        if let assetName = platform?.logoAssetName,
           let image = NSImage(named: assetName)?.copy() as? NSImage {
            image.isTemplate = platform?.usesOriginalLogoColor != true
            return image
        }

        let symbolName = platform?.icon ?? "menubar.dock.rectangle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: platform?.shortName ?? "CodeBar")
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return image?.withSymbolConfiguration(configuration)
    }

    private func statusTextWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    @objc func togglePopover(_ sender: Any?) {
        let button = (sender as? NSStatusBarButton) ?? statusItem?.button ?? popoverAnchorButton
        guard let button, let popover = popover else { return }
        popoverAnchorButton = button
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
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
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: Constants.settingsWindowWidth, height: Constants.settingsWindowHeight)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Constants.settingsWindowWidth, height: Constants.settingsWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeBar 设置"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
    static let moduleStatusItemsChanged = Notification.Name("moduleStatusItemsChanged")
    static let usageDataUpdated = Notification.Name("usageDataUpdated")
}
