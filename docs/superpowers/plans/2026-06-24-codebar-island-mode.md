# CodeBar Island Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the visible menu bar popover experience with a Ping Island-style top-center CodeBar Island surface.

**Architecture:** Add a small AppKit `NSPanel` controller for the top Island surface, a SwiftUI Island view for closed/opened states, and pure helper types for compact status and top-centered frame calculations. Keep the existing `NSStatusItem` code as a fallback path, but do not create a visible status item during normal Island startup.

**Tech Stack:** Swift 5, SwiftUI, AppKit `NSPanel`, existing `UsageTracker`, existing shell behavior test harness, Xcode project source membership.

---

## File Structure

- Create `CodeBar/IslandMode.swift`
  - `CodeBarIslandState`
  - `CodeBarIslandShape`
  - `CodeBarIslandCompactStatus`
  - `CodeBarIslandCompactStatusBuilder`
  - `CodeBarIslandLayout`
  - `CodeBarIslandView`
- Create `CodeBar/IslandPanelController.swift`
  - `CodeBarIslandPanel`
  - `CodeBarIslandController`
  - outside-click monitor lifecycle
  - settings/quit callbacks
- Modify `CodeBar/CodeBarApp.swift`
  - create Island controller at launch
  - skip normal status item creation when Island setup succeeds
  - keep fallback status item path if Island setup fails
  - route settings window opening through existing method
- Modify `CodeBar/Constants.swift`
  - add Island sizing constants
- Modify `CodeBarTests/ModuleBehaviorTests.swift`
  - add compact status and layout tests
- Modify `CodeBarTests/run_module_behavior_tests.sh`
  - compile `CodeBar/IslandMode.swift`
- Modify `CodeBar.xcodeproj/project.pbxproj`
  - add new Swift files to the CodeBar target sources

---

### Task 1: Compact Status And Layout Helpers

**Files:**
- Create: `CodeBar/IslandMode.swift`
- Modify: `CodeBarTests/ModuleBehaviorTests.swift`
- Modify: `CodeBarTests/run_module_behavior_tests.sh`

- [ ] **Step 1: Write failing behavior tests**

Add the new file to `CodeBarTests/run_module_behavior_tests.sh` immediately after `MenuBarView.swift`:

```sh
  "$SRCROOT/CodeBar/MenuBarView.swift" \
  "$SRCROOT/CodeBar/IslandMode.swift" \
  "$SRCROOT/CodeBar/SettingsWindow.swift" \
```

Append these assertions near the existing `UsagePercentDisplayMode` assertions in `CodeBarTests/ModuleBehaviorTests.swift`:

```swift
let depletedSoon = UsageItem(
    key: "depleted",
    label: "快耗尽",
    used: 95,
    total: 100,
    unit: "%",
    resetDate: fiveHourReset
)
let safeQuota = UsageItem(
    key: "safe",
    label: "安全",
    used: 20,
    total: 100,
    unit: "%",
    resetDate: sevenDayReset
)
let islandUsage = PlatformUsageData(
    platformName: "Gemini",
    planType: "CLI",
    items: [safeQuota, depletedSoon]
)
let islandModule = MonitorModule(
    alias: "work",
    config: .gemini(GeminiConfig()),
    percentDisplayMode: .remaining,
    sortOrder: 0
)
let compactStatus = CodeBarIslandCompactStatusBuilder.status(
    modules: [islandModule],
    usages: [islandModule.id: islandUsage],
    errors: [:]
)
expect(compactStatus.title == "Gemini", "Island compact status should use the module platform short name")
expect(compactStatus.detail == "剩5%", "Island compact status should show the most constrained remaining quota")
expect(compactStatus.tone == .warning, "Island compact status should warn for near-limit quota")

let errorStatus = CodeBarIslandCompactStatusBuilder.status(
    modules: [islandModule],
    usages: [islandModule.id: islandUsage],
    errors: [islandModule.id: "network failed"]
)
expect(errorStatus.tone == .error, "Island compact status should surface module errors")
expect(errorStatus.detail == "刷新异常", "Island compact status should use compact error text")

let closedFrame = CodeBarIslandLayout.frame(
    screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    size: CGSize(width: 200, height: 36)
)
expect(Int(closedFrame.origin.x) == 620, "Island closed frame should be horizontally centered")
expect(Int(closedFrame.origin.y) == 864, "Island closed frame should be pinned to the top edge")
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: compile failure because `CodeBar/IslandMode.swift`, `CodeBarIslandCompactStatusBuilder`, and `CodeBarIslandLayout` do not exist yet.

- [ ] **Step 3: Add minimal helper implementation**

Create `CodeBar/IslandMode.swift` with:

```swift
import AppKit
import SwiftUI

enum CodeBarIslandState: Equatable {
    case closed
    case opened

    var isOpened: Bool { self == .opened }
}

enum CodeBarIslandTone: Equatable {
    case normal
    case warning
    case error
    case loading
}

struct CodeBarIslandCompactStatus: Equatable {
    let title: String
    let detail: String
    let tone: CodeBarIslandTone
    let platform: PlatformType?

    static let empty = CodeBarIslandCompactStatus(
        title: "CodeBar",
        detail: "",
        tone: .loading,
        platform: nil
    )
}

enum CodeBarIslandCompactStatusBuilder {
    static func status(
        modules: [MonitorModule],
        usages: [String: PlatformUsageData],
        errors: [String: String]
    ) -> CodeBarIslandCompactStatus {
        if let erroredModule = modules.first(where: { errors[$0.id] != nil }) {
            return CodeBarIslandCompactStatus(
                title: erroredModule.platform.shortName,
                detail: "刷新异常",
                tone: .error,
                platform: erroredModule.platform
            )
        }

        var best: (module: MonitorModule, item: UsageItem, score: Double)?
        for module in modules {
            guard let usage = usages[module.id] else { continue }
            for item in usage.items {
                let score = remainingPercent(for: item)
                if best == nil || score < best!.score {
                    best = (module, item, score)
                }
            }
        }

        guard let best else { return .empty }
        let displayText = UsageStatusFormatting.compactPercentText(
            for: best.item,
            displayMode: best.module.percentDisplayMode
        )
        let tone: CodeBarIslandTone = best.module.percentDisplayMode.isNearLimit(best.item) ? .warning : .normal
        return CodeBarIslandCompactStatus(
            title: best.module.platform.shortName,
            detail: displayText,
            tone: tone,
            platform: best.module.platform
        )
    }

    private static func remainingPercent(for item: UsageItem) -> Double {
        max(0, min(100, 100 - item.percent))
    }
}

enum CodeBarIslandLayout {
    static func frame(screenFrame: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
```

- [ ] **Step 4: Run tests to verify helpers pass**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: `ModuleBehaviorTests passed`.

- [ ] **Step 5: Commit helper task**

```bash
git add CodeBar/IslandMode.swift CodeBarTests/ModuleBehaviorTests.swift CodeBarTests/run_module_behavior_tests.sh
git commit -m "Add island status helpers"
```

---

### Task 2: Island Shape And SwiftUI View

**Files:**
- Modify: `CodeBar/IslandMode.swift`
- Modify: `CodeBar/Constants.swift`

- [ ] **Step 1: Write failing shape/layout assertions**

Append these assertions to `CodeBarTests/ModuleBehaviorTests.swift` after the layout frame assertions:

```swift
expect(Constants.islandClosedWidth > 0, "Island closed width should be configured")
expect(Constants.islandOpenedWidth >= Constants.popoverWidth, "Island opened width should fit existing usage content")
expect(Constants.islandClosedHeight < Constants.islandOpenedMaximumHeight, "Island closed height should be smaller than opened maximum height")
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: compile failure because Island sizing constants do not exist.

- [ ] **Step 3: Add constants**

Add to `CodeBar/Constants.swift` under UI sizing:

```swift
    /// Island closed notch width
    static let islandClosedWidth: CGFloat = 210

    /// Island closed notch height
    static let islandClosedHeight: CGFloat = 36

    /// Island opened panel width
    static let islandOpenedWidth: CGFloat = 500

    /// Island opened maximum panel height
    static let islandOpenedMaximumHeight: CGFloat = 620
```

- [ ] **Step 4: Add shape and view implementation**

Extend `CodeBar/IslandMode.swift` with:

```swift
struct CodeBarIslandShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

struct CodeBarIslandView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var updateChecker: UpdateChecker
    let state: CodeBarIslandState
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    private var isOpened: Bool { state.isOpened }

    private var compactStatus: CodeBarIslandCompactStatus {
        CodeBarIslandCompactStatusBuilder.status(
            modules: tracker.detailModules,
            usages: tracker.moduleUsages,
            errors: tracker.moduleErrors
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Constants.islandClosedHeight)

            if isOpened {
                openedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, isOpened ? 18 : 14)
        .padding(.bottom, isOpened ? 16 : 0)
        .frame(
            width: isOpened ? Constants.islandOpenedWidth : Constants.islandClosedWidth,
            alignment: .top
        )
        .background(Color.black)
        .clipShape(CodeBarIslandShape(
            topCornerRadius: isOpened ? 18 : 6,
            bottomCornerRadius: isOpened ? 26 : 16
        ))
        .shadow(color: isOpened ? Color.black.opacity(0.55) : .clear, radius: 10)
        .preferredColorScheme(.dark)
        .onTapGesture {
            if !isOpened { onOpen() }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: state)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PlatformLogoView(platform: compactStatus.platform ?? .codex, size: 14)
                .opacity(compactStatus.platform == nil ? 0.5 : 1)
            Text(compactStatus.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if !compactStatus.detail.isEmpty {
                Text(compactStatus.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(toneColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isOpened {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private var toneColor: Color {
        switch compactStatus.tone {
        case .normal: return .white.opacity(0.76)
        case .warning: return .orange
        case .error: return .red
        case .loading: return .white.opacity(0.5)
        }
    }

    private var openedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuBarView(
                tracker: tracker,
                updateChecker: updateChecker,
                chrome: .island,
                onSettings: onSettings,
                onQuit: onQuit
            )
        }
        .frame(maxHeight: Constants.islandOpenedMaximumHeight, alignment: .top)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: compile failure because `MenuBarView` does not yet accept `chrome`, `onSettings`, or `onQuit`. Continue in Task 3.

- [ ] **Step 6: Do not commit yet**

This task intentionally depends on Task 3 before it can compile.

---

### Task 3: Adapt MenuBarView For Island Chrome

**Files:**
- Modify: `CodeBar/MenuBarView.swift`
- Continue: `CodeBar/IslandMode.swift`

- [ ] **Step 1: Add MenuBarView chrome API**

Modify the start of `MenuBarView`:

```swift
struct MenuBarView: View {
    enum Chrome {
        case popover
        case island
    }

    @ObservedObject var tracker: UsageTracker
    @ObservedObject var updateChecker: UpdateChecker
    var chrome: Chrome = .popover
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var hasLoadedOnce = false

    private var isIslandChrome: Bool {
        chrome == .island
    }
```

- [ ] **Step 2: Adjust root styling**

Replace the root modifiers at the end of `body`:

```swift
        .padding(isIslandChrome ? 0 : 20)
        .frame(width: isIslandChrome ? nil : Constants.popoverWidth)
        .foregroundStyle(isIslandChrome ? Color.white : Color.primary)
        .onAppear {
            hasLoadedOnce = true
        }
```

- [ ] **Step 3: Route Settings button through callback**

Replace the settings button action:

```swift
Button(action: {
    if let onSettings {
        onSettings()
    } else {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
}) {
    Image(systemName: "gearshape.fill")
    Text("设置")
}
```

- [ ] **Step 4: Route quit through callback**

Replace `private func quitApp()`:

```swift
private func quitApp() {
    if let onQuit {
        onQuit()
    } else {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 5: Make module card backgrounds work on black**

Change the module card background:

```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(isIslandChrome ? Color.white.opacity(0.08) : Color(hex: module.platform.brandColor).opacity(0.12))
)
```

Change the legacy platform card background in the same way:

```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(isIslandChrome ? Color.white.opacity(0.08) : Color(hex: platform.brandColor).opacity(0.12))
)
```

- [ ] **Step 6: Run behavior tests**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: `ModuleBehaviorTests passed`.

- [ ] **Step 7: Commit view task**

```bash
git add CodeBar/IslandMode.swift CodeBar/MenuBarView.swift CodeBar/Constants.swift CodeBarTests/ModuleBehaviorTests.swift CodeBarTests/run_module_behavior_tests.sh
git commit -m "Add island SwiftUI surface"
```

---

### Task 4: AppKit Island Panel Controller

**Files:**
- Create: `CodeBar/IslandPanelController.swift`
- Modify: `CodeBar/CodeBarApp.swift`

- [ ] **Step 1: Add controller implementation**

Create `CodeBar/IslandPanelController.swift`:

```swift
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
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = .mainMenu + 3
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
        let frame = frame(for: .closed, screen: screen)
        let panel = CodeBarIslandPanel(contentRect: frame)
        self.panel = panel
        rebuildRootView()
        panel.orderFront(nil)
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
    }

    private func rebuildRootView() {
        let root = CodeBarIslandView(
            tracker: tracker,
            updateChecker: updateChecker,
            state: state,
            onOpen: { [weak self] in self?.open() },
            onClose: { [weak self] in self?.close() },
            onSettings: { [weak self] in self?.onSettings() },
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
            guard let self, self.state.isOpened, let panel = self.panel else { return event }
            let location = NSEvent.mouseLocation
            if !panel.frame.contains(location) {
                self.close()
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
}

extension Notification.Name {
    static let codeBarIslandEscapePressed = Notification.Name("codeBarIslandEscapePressed")
}
```

- [ ] **Step 2: Wire AppDelegate**

Add properties to `AppDelegate`:

```swift
private var islandController: CodeBarIslandController?
private var isUsingIslandMode = false
```

Replace the first line of `applicationDidFinishLaunching`:

```swift
isUsingIslandMode = setupIslandMode()
if !isUsingIslandMode {
    rebuildStatusItems()
}
```

Change the popover setup block so it only runs when fallback status mode is active:

```swift
if !isUsingIslandMode {
    popover = NSPopover()
    popover?.behavior = .transient
    let hostingController = NSHostingController(rootView: MenuBarView(tracker: UsageTracker.shared, updateChecker: UpdateChecker.shared))
    hostingController.sizingOptions = [.preferredContentSize]
    popover?.contentViewController = hostingController
}
```

Add this method to `AppDelegate`:

```swift
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
```

Update the `.moduleStatusItemsChanged` observer selector to a new method:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handlePresentationChanged),
    name: .moduleStatusItemsChanged,
    object: nil
)
```

Add:

```swift
@objc private func handlePresentationChanged() {
    if isUsingIslandMode {
        islandController?.refreshLayout()
    } else {
        rebuildStatusItems()
    }
}
```

- [ ] **Step 3: Run behavior tests**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: `ModuleBehaviorTests passed`.

- [ ] **Step 4: Commit panel task**

```bash
git add CodeBar/IslandPanelController.swift CodeBar/CodeBarApp.swift
git commit -m "Add island panel controller"
```

---

### Task 5: Add New Files To Xcode Project

**Files:**
- Modify: `CodeBar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add Xcode source membership**

Add `CodeBar/IslandMode.swift` and `CodeBar/IslandPanelController.swift` to `CodeBar.xcodeproj/project.pbxproj` with fresh 24-character uppercase hex IDs:

- one `PBXFileReference` entry for each file under the existing `CodeBar` group
- one `PBXBuildFile` entry for each file in the `PBXBuildFile` section
- both build-file IDs in the CodeBar target `PBXSourcesBuildPhase.files` list

The project must include both files in the main app target. The behavior test script is not enough because Xcode does not automatically compile unreferenced Swift files.

Before editing, locate the target sections with:

```bash
rg -n "PBXFileReference|PBXBuildFile|PBXSourcesBuildPhase|CodeBarApp.swift|MenuBarView.swift" CodeBar.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Run Debug build**

Run:

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`, and the behavior test script phase prints `ModuleBehaviorTests passed`.

- [ ] **Step 3: Fix project membership or compile errors**

When Xcode cannot find `CodeBarIslandController` or `CodeBarIslandView`, inspect `CodeBar.xcodeproj/project.pbxproj` and confirm both Swift files appear in all three locations listed in Step 1. When SwiftUI preview code fails under tests, wrap preview blocks in:

```swift
#if !CODEBAR_BEHAVIOR_TESTS
// preview
#endif
```

- [ ] **Step 4: Commit project membership**

```bash
git add CodeBar.xcodeproj/project.pbxproj
git commit -m "Include island files in app target"
```

---

### Task 6: Implementation Review And Hardening

**Files:**
- Review all touched files.
- Modify only files needed to address review findings.

- [ ] **Step 1: Dispatch two independent implementation reviewers**

Reviewer A prompt:

```text
Review the CodeBar Island Mode implementation for requirements coverage.
Scope: /Volumes/code/code_bar.
Review diff from e31c2ce to HEAD.
Focus: no visible menu bar icon in normal path, top closed Island appears, click opens, outside click closes, settings/refresh/quit reachable, existing usage behavior preserved.
Do not modify files. Return Critical/Important/Minor findings with file:line references and verdict.
```

Reviewer B prompt:

```text
Review the CodeBar Island Mode implementation for AppKit/SwiftUI risks.
Scope: /Volumes/code/code_bar.
Review diff from e31c2ce to HEAD.
Focus: NSPanel lifecycle, outside-click monitors, screen positioning, project file membership, behavior tests, fallback status item path.
Do not modify files. Return Critical/Important/Minor findings with file:line references and verdict.
```

- [ ] **Step 2: Address Critical and Important findings**

For each valid Critical or Important finding, edit the relevant file and run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: `ModuleBehaviorTests passed`.

- [ ] **Step 3: Commit review hardening**

If changes were required:

```bash
git add CodeBar CodeBarTests CodeBar.xcodeproj/project.pbxproj
git commit -m "Harden island mode implementation"
```

If no changes were required, do not create an empty commit.

---

### Task 7: Final Verification

**Files:**
- No planned edits.

- [ ] **Step 1: Run patch check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Run behavior tests**

Run:

```bash
CodeBarTests/run_module_behavior_tests.sh
```

Expected: `ModuleBehaviorTests passed`.

- [ ] **Step 3: Run Debug build**

Run:

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run Release unsigned build**

Run:

```bash
xcodebuild -project CodeBar.xcodeproj -scheme CodeBar -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke test**

Launch the Debug app from Xcode build products. Confirm:

- no menu bar icon is visible
- top-center black notch is visible
- clicking notch opens the panel
- clicking outside closes it
- refresh button updates usage
- settings button opens settings
- quit button exits

- [ ] **Step 6: Push final branch**

```bash
git status -sb
git push origin main
```

Expected: push succeeds. If CI starts, wait for the CI run and confirm success.
