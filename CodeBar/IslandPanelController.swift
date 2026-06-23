import AppKit
import Combine
import SwiftUI

final class CodeBarIslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        isReleasedWhenClosed = false
        allowsToolTipsWhenApplicationIsInactive = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NotificationCenter.default.post(name: .codeBarIslandEscapePressed, object: self)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class CodeBarIslandController: NSObject, ObservableObject {
    @Published private(set) var state: CodeBarIslandState = .closed

    private let tracker: UsageTracker
    private let updateChecker: UpdateChecker
    private let onSettings: () -> Void
    private var panel: CodeBarIslandPanel?
    private var hostingController: NSHostingController<CodeBarIslandView>?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var maxContentHeight = Constants.islandOpenedMaximumHeight - Constants.islandClosedHeight - 16
    private var pendingLayoutRefresh: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        tracker: UsageTracker,
        updateChecker: UpdateChecker,
        onSettings: @escaping () -> Void
    ) {
        self.tracker = tracker
        self.updateChecker = updateChecker
        self.onSettings = onSettings
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEscapePressed(_:)),
            name: .codeBarIslandEscapePressed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        tracker.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleLayoutRefresh() }
            }
            .store(in: &cancellables)
        updateChecker.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleLayoutRefresh() }
            }
            .store(in: &cancellables)
    }

    deinit {
        pendingLayoutRefresh?.cancel()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func show() -> Bool {
        guard let screen = targetScreen() else { return false }
        let panel = CodeBarIslandPanel(contentRect: frame(for: .closed, screen: screen, contentHeight: nil))
        self.panel = panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        rebuildRootView()
        panel.orderFrontRegardless()
        return true
    }

    func open() {
        state = .opened
        rebuildRootView()
        refreshLayout()
        panel?.makeKey()
        installOutsideMonitors()
    }

    func close() {
        state = .closed
        removeOutsideMonitors()
        rebuildRootView()
        refreshLayout()
        panel?.resignKey()
    }

    func toggle() {
        if state.isOpened {
            close()
        } else {
            open()
        }
    }

    func refreshLayout() {
        guard let screen = targetScreen() else { return }
        pendingLayoutRefresh?.cancel()
        pendingLayoutRefresh = nil
        let contentHeight = state.isOpened ? measuredContentHeight(for: screen) : nil
        let nextFrame = frame(for: state, screen: screen, contentHeight: contentHeight)
        maxContentHeight = state.isOpened
            ? CodeBarIslandLayout.openedContentHeight(panelHeight: nextFrame.height)
            : Constants.islandOpenedMaximumHeight - Constants.islandClosedHeight - 16
        rebuildRootView()
        panel?.setFrame(nextFrame, display: true, animate: true)
    }

    private func scheduleLayoutRefresh() {
        guard state.isOpened else { return }
        pendingLayoutRefresh?.cancel()
        pendingLayoutRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.refreshLayout()
        }
    }

    private func rebuildRootView() {
        let root = CodeBarIslandView(
            tracker: tracker,
            updateChecker: updateChecker,
            state: state,
            onOpen: { [weak self] in self?.open() },
            onClose: { [weak self] in self?.close() },
            onSettings: { [weak self] in
                self?.close()
                self?.onSettings()
            },
            onQuit: { NSApplication.shared.terminate(nil) },
            maxContentHeight: maxContentHeight
        )

        if let hostingController {
            hostingController.rootView = root
        } else {
            let hostingController = NSHostingController(rootView: root)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            self.hostingController = hostingController
            panel?.contentViewController = hostingController
        }
    }

    private func targetScreen() -> NSScreen? {
        if let panelScreen = panel?.screen {
            return panelScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func frame(for state: CodeBarIslandState, screen: NSScreen, contentHeight: CGFloat?) -> CGRect {
        if state.isOpened {
            return CodeBarIslandLayout.openedFrame(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                contentHeight: contentHeight ?? Constants.islandOpenedMaximumHeight
            )
        }

        return CodeBarIslandLayout.frame(
            screenFrame: screen.frame,
            size: CGSize(width: Constants.islandClosedWidth, height: Constants.islandClosedHeight)
        )
    }

    private func measuredContentHeight(for screen: NSScreen) -> CGFloat {
        let maximumPanelHeight = min(Constants.islandOpenedMaximumHeight, screen.visibleFrame.height)
        maxContentHeight = CodeBarIslandLayout.openedContentHeight(panelHeight: maximumPanelHeight)
        rebuildRootView()

        guard let view = hostingController?.view else {
            return Constants.islandOpenedMaximumHeight
        }

        view.frame.size = CGSize(width: Constants.islandOpenedWidth, height: maximumPanelHeight)
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.height
    }

    private func installOutsideMonitors() {
        removeOutsideMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        guard let panel else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel else { return event }
            if event.window !== panel {
                Task { @MainActor in self?.close() }
            }
            return event
        }
    }

    private func removeOutsideMonitors() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    @objc private func handleEscapePressed(_ notification: Notification) {
        guard notification.object as? CodeBarIslandPanel === panel else { return }
        close()
    }

    @objc private func handleScreenParametersChanged(_ notification: Notification) {
        refreshLayout()
    }

    @objc private func handlePanelDidResignKey(_ notification: Notification) {
        guard state.isOpened, notification.object as? CodeBarIslandPanel === panel else { return }
        close()
    }

    @objc private func handleApplicationDidResignActive(_ notification: Notification) {
        guard state.isOpened else { return }
        close()
    }
}

extension Notification.Name {
    static let codeBarIslandEscapePressed = Notification.Name("codeBarIslandEscapePressed")
}
