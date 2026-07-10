# CodeBar Single-Line Status Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the clipped two-line status item with one rotating usage line without adding a timer.

**Architecture:** Add a small pure Swift presentation type that selects one of at most two formatted usage lines for the current refresh cycle while retaining both lines in the tooltip. `AppDelegate` owns one refresh-cycle state, advances it only from `.usageDataUpdated`, and passes an empty bottom line to the existing native `NSStatusBarButton` renderer.

**Tech Stack:** Swift 5, AppKit `NSStatusBarButton`, existing shell behavior-test harness, Xcode build script.

## Global Constraints

- Keep the native status button and the existing 13-point icon renderer.
- Do not add a timer or expand the existing module-rotation timer conditions.
- Show the first preferred quota on the first completed refresh, then alternate on later completed refreshes.
- Keep up to two quota lines in the status item tooltip.
- Leave the popover and notch-panel presentation unchanged.

---

### Task 1: Testable Single-Line Selection

**Files:**
- Create: `CodeBar/StatusBarUsagePresentation.swift`
- Modify: `CodeBarTests/ModuleBehaviorTests.swift`
- Modify: `CodeBarTests/run_module_behavior_tests.sh`
- Modify: `CodeBar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: preformatted usage strings in preferred display order.
- Produces: `StatusBarUsageRotation.registerRefresh()`, `StatusBarUsageRotation.index`, and `StatusBarUsagePresentation.make(lines:rotationIndex:fallback:)`.

- [ ] **Step 1: Write the failing behavior tests**

Add assertions that require this behavior:

```swift
var rotation = StatusBarUsageRotation()
rotation.registerRefresh()
expect(rotation.index == 0, "First refresh should retain the first quota")
rotation.registerRefresh()
expect(rotation.index == 1, "Second refresh should select the second quota")
rotation.registerRefresh()
expect(rotation.index == 0, "Third refresh should cycle back to the first quota")

let first = StatusBarUsagePresentation.make(
    lines: ["5h 45%", "7d 11%"],
    rotationIndex: 0,
    fallback: "Codex"
)
expect(first.title == "5h 45%", "First cycle should show one line")
expect(first.tooltip == "5h 45% / 7d 11%", "Tooltip should retain both quotas")
expect(StatusBarUsagePresentation.make(lines: ["5h 45%"], rotationIndex: 1, fallback: "Codex").title == "5h 45%", "Single quota should remain visible")
expect(StatusBarUsagePresentation.make(lines: [], rotationIndex: 0, fallback: "Codex").title == "Codex", "Empty quotas should use the fallback")
```

- [ ] **Step 2: Run the behavior tests and verify RED**

Run: `CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh`

Expected: compilation fails because `StatusBarUsageRotation` and `StatusBarUsagePresentation` do not exist.

- [ ] **Step 3: Implement the minimal presentation types**

Create the source file with a two-position refresh state and a presentation builder that filters empty lines, selects `rotationIndex % lines.count`, and joins all retained lines with ` / ` for the tooltip. Add the file to the Xcode Sources phase and shell test compilation list.

- [ ] **Step 4: Run the behavior tests and verify GREEN**

Run: `CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh`

Expected: exit code `0` with no assertion failure.

### Task 2: AppDelegate Integration

**Files:**
- Modify: `CodeBar/CodeBarApp.swift`

**Interfaces:**
- Consumes: the presentation and rotation types from Task 1.
- Produces: single-line titles for independent and rotating module status items.

- [ ] **Step 1: Add refresh-owned rotation state**

Add `private var usageRotation = StatusBarUsageRotation()` to `AppDelegate`. Call `usageRotation.registerRefresh()` at the start of `handleUsageDataUpdated()` before updating status titles. Do not call it from settings or presentation-change handlers.

- [ ] **Step 2: Render one preferred usage line**

For both `updateModuleStatusItems()` and `updateRotatingModuleStatusItem()`, format the preferred items into an array, build `StatusBarUsagePresentation`, and call `setStatusTitle(top: presentation.title, bottom: "", ..., tooltip: presentation.tooltip)`.

- [ ] **Step 3: Support tooltip override without changing title rendering**

Add an optional tooltip argument to both `setStatusTitle` overloads. Use the override for `StatusTitleSnapshot.tooltip` and `button.toolTip`; preserve the current generated tooltip for loading and fallback titles.

- [ ] **Step 4: Run behavior tests and build**

Run: `CODEBAR_BEHAVIOR_TESTS=1 CodeBarTests/run_module_behavior_tests.sh`

Run: `./script/build_and_run.sh --verify`

Expected: both commands exit `0`, and the script launches exactly one current-workspace CodeBar process.

### Task 3: Runtime Verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the launched CodeBar process.
- Produces: visual and runtime evidence for the original clipping report.

- [ ] **Step 1: Verify the accessibility title is single-line**

Read the CodeBar status menu item through Accessibility and confirm the title contains no newline and has the form `5h 45%` or `7d 11%`.

- [ ] **Step 2: Verify the external-display screenshot**

Capture display 2 and inspect a top-menu crop. Confirm the title has visible top and bottom padding and does not overlap the screen edge.

- [ ] **Step 3: Verify low runtime cost**

Sample CodeBar with `top` across several seconds. Confirm CPU remains near idle and that a single-module status-bar configuration does not have a 5-second title rotation.

- [ ] **Step 4: Check runtime errors**

Run `/usr/bin/log show` for the new process and confirm there is no repeated CodeBar error or fault sequence caused by status-item updates.
