# CodeBar Notch Left Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show CodeBar's compact platform and percentage in one 160-point extension on the left of the MacBook camera housing while keeping the compact panel 36 points high.

**Architecture:** Keep one `NSPanel` and the existing pure `CodeBarIslandDisplayGeometry`. The geometry aligns the collapsed panel's right edge with the physical notch's right edge; SwiftUI renders one compact row in the visible left extension and leaves the camera-housing region empty. Expanded content remains centered on the hardware notch.

**Tech Stack:** Swift 5, SwiftUI, AppKit `NSScreen`/`NSPanel`, behavior-test shell runner, Xcode macOS target.

## Global Constraints

- macOS deployment target remains 13.0.
- Collapsed panel height remains 36 points.
- Left extension width is 160 points.
- The current 185-point notch produces a 345-point collapsed panel at `x = 503...848`.
- Compact percentages contain no text prefixes.
- Displays without valid auxiliary top areas retain the 210-by-36 fallback pill.
- Preserve unrelated uncommitted workspace changes.

---

### Task 1: Left-Aligned Hardware Geometry

**Files:**
- Modify: `CodeBar/Constants.swift`
- Modify: `CodeBar/IslandMode.swift`
- Test: `CodeBarTests/ModuleBehaviorTests.swift`

**Interfaces:**
- Consumes: screen frame, visible frame, auxiliary top-left and top-right rectangles.
- Produces: `CodeBarIslandDisplayGeometry.closedFrame`, `closedLeftExtensionFrame`, and `closedNotchGapFrame`.

- [ ] **Step 1: Change geometry assertions before production code**

```swift
expect(notchedGeometry.closedSize == CGSize(width: 345, height: 36), "Collapsed notch should add one 160-point left extension")
expect(notchedGeometry.closedFrame.minX == 503, "Collapsed panel should begin 160 points before the notch")
expect(notchedGeometry.closedFrame.maxX == 848, "Collapsed panel should end at the hardware notch right edge")
expect(notchedGeometry.closedLeftExtensionFrame.maxX == notchedGeometry.closedNotchGapFrame.minX, "Left content must stop before the hardware notch")
```

Remove the right-wing assertion.

- [ ] **Step 2: Run tests and verify RED**

```bash
CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh
```

Expected: FAIL because the current geometry is 409 points wide and centered around two 112-point wings.

- [ ] **Step 3: Implement the left extension geometry**

Rename the constant and set its new value:

```swift
static let islandClosedLeftExtensionWidth: CGFloat = 160
```

Store the detected horizontal notch bounds in `CodeBarIslandDisplayGeometry`:

```swift
let notchMinX: CGFloat
let notchMaxX: CGFloat
```

For valid auxiliary areas, assign `notchMinX = left.maxX` and `notchMaxX = right.minX`. For fallback geometry, assign both to `screenFrame.midX`.

Use these calculations:

```swift
var closedSize: CGSize {
    CGSize(
        width: hasNotch
            ? Constants.islandClosedLeftExtensionWidth + notchGapWidth
            : Constants.islandClosedWidth,
        height: Constants.islandClosedHeight
    )
}

var closedFrame: CGRect {
    guard hasNotch else {
        return CodeBarIslandLayout.frame(screenFrame: screenFrame, size: closedSize)
    }
    return CGRect(
        x: notchMinX - Constants.islandClosedLeftExtensionWidth,
        y: screenFrame.maxY - closedSize.height,
        width: closedSize.width,
        height: closedSize.height
    )
}

var closedLeftExtensionFrame: CGRect {
    CGRect(x: 0, y: 0, width: hasNotch ? Constants.islandClosedLeftExtensionWidth : closedSize.width, height: closedSize.height)
}

var closedNotchGapFrame: CGRect {
    CGRect(x: closedLeftExtensionFrame.maxX, y: 0, width: notchGapWidth, height: closedSize.height)
}
```

Keep `openedFrame(contentHeight:)` centered on `notchCenterX`.

- [ ] **Step 4: Run tests and verify GREEN**

Run the behavior-test command. Expected: exit 0.

---

### Task 2: Render One Compact Row On The Left

**Files:**
- Modify: `CodeBar/IslandMode.swift`
- Verify: `CodeBar/IslandPanelController.swift`

**Interfaces:**
- Consumes: `notchGapWidth` and the existing compact status.
- Produces: a collapsed row containing platform icon, platform name, and compact detail entirely left of the camera housing.

- [ ] **Step 1: Change the compact width calculation**

```swift
private var compactWidth: CGFloat {
    notchGapWidth > 0
        ? notchGapWidth + Constants.islandClosedLeftExtensionWidth
        : Constants.islandClosedWidth
}
```

- [ ] **Step 2: Replace the notched header**

For closed state, render `platformIdentity`, `compactDetail`, then a spacer. For open state, split the expanded width into equal visible regions around the fixed notch gap, place identity, detail, and close control in the left region, and leave the right region empty:

```swift
if notchGapWidth > 0, isOpened {
    HStack(spacing: 0) {
        HStack(spacing: 8) {
            platformIdentity
            compactDetail
            closeButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Color.clear.frame(width: notchGapWidth)
        Color.clear.frame(maxWidth: .infinity)
    }
} else if notchGapWidth > 0 {
    HStack(spacing: 8) {
        platformIdentity
        compactDetail
        Spacer(minLength: 0)
    }
} else {
    HStack(spacing: 8) {
        platformIdentity
        compactDetail
        Spacer(minLength: 0)
        if isOpened { closeButton }
    }
}
```

- [ ] **Step 3: Run tests and build**

```bash
CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh
./script/build_and_run.sh --verify
```

Expected: both commands exit 0.

---

### Task 3: Runtime Verification

**Files:**
- Verify: `CodeBar/IslandMode.swift`
- Verify: `CodeBar/IslandPanelController.swift`

**Interfaces:**
- Consumes: the freshly built CodeBar app in island mode.
- Produces: geometry, visual, CPU, and log evidence.

- [ ] **Step 1: Inspect the collapsed window**

Expected current-screen bounds: width 345, height 36, `x = 503`, top-screen `y = 0` in window-server coordinates.

- [ ] **Step 2: Inspect the rendered panel**

Expected: one visible row on the left showing icon, `Codex`, and a bare percentage; no software extension or compact value appears to the right of the hardware notch.

- [ ] **Step 3: Run final checks**

```bash
CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh
./script/build_and_run.sh --verify
git diff --check
```

Expected: tests and build exit 0, diff check is silent, steady-state CPU is near 0%, and no errors repeat continuously.
