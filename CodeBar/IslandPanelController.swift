import AppKit
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
    }

    deinit {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NotificationCenter.default.removeObserver(self)
    }

    func show() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let panel = CodeBarIslandPanel(contentRect: frame(for: .closed, screen: screen))
        self.panel = panel
        rebuildRootView()
        panel.orderFrontRegardless()
        return true
    }

    func open() {
        state = .opened
        refreshLayout()
        rebuildRootView()
        panel?.makeKey()
        installOutsideMonitors()
    }

    func close() {
        state = .closed
        removeOutsideMonitors()
        refreshLayout()
        rebuildRootView()
    }

    func toggle() {
        if state.isOpened {
            close()
        } else {
            open()
        }
    }

    func refreshLayout() {
        guard let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel?.setFrame(frame(for: state, screen: screen), display: true, animate: true)
        rebuildRootView()
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
            onQuit: { NSApplication.shared.terminate(nil) }
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

    private func frame(for state: CodeBarIslandState, screen: NSScreen) -> CGRect {
        let size = state.isOpened
            ? CGSize(width: Constants.islandOpenedWidth, height: Constants.islandOpenedMaximumHeight)
            : CGSize(width: Constants.islandClosedWidth, height: Constants.islandClosedHeight)
        return CodeBarIslandLayout.frame(screenFrame: screen.frame, size: size)
    }

    private func installOutsideMonitors() {
        removeOutsideMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.closeIfMouseOutsidePanel() }
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

    private func closeIfMouseOutsidePanel() {
        guard state.isOpened, let panel else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            close()
        }
    }

    @objc private func handleEscapePressed(_ notification: Notification) {
        guard notification.object as? CodeBarIslandPanel === panel else { return }
        close()
    }
}

extension Notification.Name {
    static let codeBarIslandEscapePressed = Notification.Name("codeBarIslandEscapePressed")
}
