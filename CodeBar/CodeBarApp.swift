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
    private struct StatusItemComponents {}

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
    private var statusUsageRotation = StatusBarUsageRotation()
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
    deinit {
        rotationTimer?.invalidate()
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPresentationMode(CodeBarPresentationMode.current())

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePresentationModePreferenceChanged),
            name: .codeBarPresentationModeChanged,
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

    private func applyPresentationMode(_ mode: CodeBarPresentationMode) {
        switch mode {
        case .statusBar:
            configureStatusBarMode()
        case .island:
            configureIslandMode()
        }
    }

    private func configureStatusBarMode() {
        if isUsingIslandMode {
            islandController?.hide()
            islandController = nil
            isUsingIslandMode = false
        }

        ensurePopover()
        rebuildStatusItems()
        updateRotationTimer()
    }

    private func configureIslandMode() {
        guard !isUsingIslandMode else {
            islandController?.refreshLayout()
            return
        }

        closePopover()
        popover = nil
        removeStatusItems()
        rotationTimer?.invalidate()
        rotationTimer = nil

        if setupIslandMode() {
            isUsingIslandMode = true
        } else {
            configureStatusBarMode()
        }
    }

    private func ensurePopover() {
        guard popover == nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: MenuBarView(tracker: UsageTracker.shared, updateChecker: UpdateChecker.shared))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        self.popover = popover
    }

    private func removeStatusItems() {
        for item in moduleStatusItems.values {
            statusTitleSnapshots.removeValue(forKey: ObjectIdentifier(item))
            NSStatusBar.system.removeStatusItem(item)
        }
        moduleStatusItems = [:]
        moduleStatusComponents = [:]

        if let statusItem {
            statusTitleSnapshots.removeValue(forKey: ObjectIdentifier(statusItem))
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        defaultStatusComponents = nil
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
                setStatusTitle(top: "CodeBar", bottom: "", platform: nil)
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

        setStatusTitle(top: "CodeBar", bottom: "", platform: nil)
    }

    @objc private func rebuildStatusItems() {
        let tracker = UsageTracker.shared
        let menuModules = tracker.menuBarModules

        removeStatusItems()

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
        statusUsageRotation.registerRefresh()
        if !isUsingIslandMode {
            updateStatusItemTitle()
            updateRotationTimer()
        }
    }

    @objc private func handlePresentationModePreferenceChanged() {
        applyPresentationMode(CodeBarPresentationMode.current())
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
                    top: "Loading",
                    bottom: "",
                    alias: module.aliasDisplayName,
                    platform: module.platform,
                    item: item,
                    components: components
                )
                continue
            }

            let preferredItems = ModuleUsageSelection.menuBarItems(from: usage, module: module)
            let presentation = StatusBarUsagePresentation.make(
                lines: preferredItems.map { statusLineText(for: $0, module: module) },
                rotationIndex: statusUsageRotation.index,
                fallback: module.platform.shortName
            )
            setStatusTitle(
                top: presentation.title,
                bottom: "",
                alias: module.aliasDisplayName,
                platform: module.platform,
                item: item,
                components: components,
                tooltip: presentation.tooltip
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
            setStatusTitle(top: "CodeBar", bottom: "", platform: nil)
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
                top: "Loading",
                bottom: "",
                alias: module.aliasDisplayName,
                platform: module.platform
            )
            return
        }

        let preferredItems = ModuleUsageSelection.menuBarItems(from: usage, module: module)
        let presentation = StatusBarUsagePresentation.make(
            lines: preferredItems.map { statusLineText(for: $0, module: module) },
            rotationIndex: statusUsageRotation.index,
            fallback: module.platform.shortName
        )
        setStatusTitle(
            top: presentation.title,
            bottom: "",
            alias: module.aliasDisplayName,
            platform: module.platform,
            tooltip: presentation.tooltip
        )
    }

    private func statusLineText(for item: UsageItem, platform: PlatformType) -> String {
        var text = "\(compactLabel(for: item)) \(String(format: "%.0f%%", item.percent))"

        if UsageTracker.shared.isResetTimeEnabled(item.key, for: platform),
           let resetDate = item.resetDate,
           let resetText = compactResetText(until: resetDate) {
            text += "(\(resetText))"
        }

        return text
    }

    private func statusLineText(for item: UsageItem, module: MonitorModule) -> String {
        var text = "\(compactLabel(for: item)) \(UsageStatusFormatting.compactPercentText(for: item, displayMode: module.percentDisplayMode))"

        if UsageTracker.shared.isResetTimeEnabled(item.key, for: module),
           let resetDate = item.resetDate,
           let resetText = compactResetText(until: resetDate) {
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
        case CodexQuotaKey.primary:
            if item.label.contains("小时") {
                return item.label.replacingOccurrences(of: "小时", with: "h")
            }
            if item.label.contains("天") {
                return item.label.replacingOccurrences(of: "天", with: "d")
            }
            return "短期"
        case CodexQuotaKey.secondary:
            if item.label.contains("小时") {
                return item.label.replacingOccurrences(of: "小时", with: "h")
            }
            if item.label.contains("天") {
                return item.label.replacingOccurrences(of: "天", with: "d")
            }
            return "长期"
        case CodexQuotaKey.codeReviewPrimary:
            if item.label.contains("小时") || item.label.contains("天") {
                return item.label
                    .replacingOccurrences(of: "代码审查 ", with: "审查")
                    .replacingOccurrences(of: "小时", with: "h")
                    .replacingOccurrences(of: "天", with: "d")
            }
            return "审查短期"
        case CodexQuotaKey.codeReviewSecondary:
            if item.label.contains("小时") || item.label.contains("天") {
                return item.label
                    .replacingOccurrences(of: "代码审查 ", with: "审查")
                    .replacingOccurrences(of: "小时", with: "h")
                    .replacingOccurrences(of: "天", with: "d")
            }
            return "审查长期"
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

    private func setStatusTitle(
        top: String,
        bottom: String,
        alias: String? = nil,
        platform: PlatformType?,
        tooltip: String? = nil
    ) {
        guard let statusItem, let components = defaultStatusComponents else { return }
        setStatusTitle(
            top: top,
            bottom: bottom,
            alias: alias,
            platform: platform,
            item: statusItem,
            components: components,
            tooltip: tooltip
        )
    }

    private func setStatusTitle(
        top: String,
        bottom: String,
        alias: String? = nil,
        platform: PlatformType?,
        item: NSStatusItem,
        components: StatusItemComponents,
        tooltip: String? = nil
    ) {
        let aliasText = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isSingleLine = bottom.isEmpty
        let topFont = isSingleLine ? singleLineStatusTitleFont : statusTitleFont
        let bottomFont = statusTitleFont
        let titleLines = statusTitleLines(top: top, bottom: bottom, alias: aliasText, topFont: topFont, bottomFont: bottomFont)
        let titleWidth = titleLines
            .map { statusTextWidth($0.text, font: $0.font) }
            .max() ?? 0
        let length = max(40, titleWidth + 30)
        let usageTooltip = tooltip ?? (bottom.isEmpty ? top : "\(top) / \(bottom)")
        let resolvedTooltip = aliasText.isEmpty ? usageTooltip : "\(aliasText) · \(usageTooltip)"
        let snapshot = StatusTitleSnapshot(
            top: top,
            bottom: bottom,
            alias: aliasText,
            platform: platform,
            length: length,
            tooltip: resolvedTooltip
        )
        let snapshotKey = ObjectIdentifier(item)
        guard statusTitleSnapshots[snapshotKey] != snapshot else { return }
        statusTitleSnapshots[snapshotKey] = snapshot

        item.button?.image = statusIcon(for: platform)
        item.button?.imagePosition = .imageLeft
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.attributedTitle = statusAttributedTitle(
            lines: titleLines,
            isSingleLine: isSingleLine
        )
        item.length = length
        item.button?.toolTip = resolvedTooltip
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
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.font = statusTitleFont
        return StatusItemComponents()
    }

    private func statusTitleLines(
        top: String,
        bottom: String,
        alias: String,
        topFont: NSFont,
        bottomFont: NSFont
    ) -> [(text: String, font: NSFont)] {
        if bottom.isEmpty {
            let text = alias.isEmpty ? top : "\(alias) \(top)"
            return [(text, topFont)]
        }

        let firstLine = alias.isEmpty ? top : "\(alias) \(top)"
        return [(firstLine, topFont), (bottom, bottomFont)]
    }

    private func statusAttributedTitle(lines: [(text: String, font: NSFont)], isSingleLine: Bool) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = isSingleLine ? 0 : -2

        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(NSAttributedString(
                string: line.text,
                attributes: [
                    .font: line.font,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }
        return result
    }

    private func statusIcon(for platform: PlatformType?) -> NSImage? {
        if let assetName = platform?.logoAssetName,
           let image = NSImage(named: assetName)?.copy() as? NSImage {
            let isTemplate = platform?.usesOriginalLogoColor != true
            return StatusBarIconRenderer.render(
                image,
                pointSize: Constants.statusBarIconSize,
                isTemplate: isTemplate
            )
        }

        let symbolName = platform?.icon ?? "menubar.dock.rectangle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: platform?.shortName ?? "CodeBar")
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let configuredImage = image?.withSymbolConfiguration(configuration)?.copy() as? NSImage else {
            return nil
        }
        return StatusBarIconRenderer.render(
            configuredImage,
            pointSize: Constants.statusBarIconSize,
            isTemplate: true
        )
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
