# CodeBar Island Mode Design

## Context

CodeBar currently uses `NSStatusItem` as the visible menu bar entry and shows `MenuBarView` inside an `NSPopover`. The requested direction is to replace the visible menu bar popover interaction with a Ping Island-style top notch surface:

- no visible menu bar icon in the primary experience
- a small black notch remains at the top center of the screen
- clicking the notch expands it into the CodeBar usage panel
- closing returns it to the small notch

The implementation should borrow the product pattern from `erha19/ping-island`, but not copy its source directly. CodeBar will use a smaller, purpose-built version that matches this app's quota-monitoring scope.

## Goals

- Add a top-center Island surface that becomes the main CodeBar entry point.
- Hide the visible `NSStatusItem` in the first Island Mode implementation.
- Preserve all existing core actions: view usage, refresh, open settings, quit.
- Reuse existing usage data, module ordering, module collapse state, and percent display behavior.
- Keep the first version stable by avoiding hover auto-open, drag-detach, physical-notch detection, and full-screen special cases.

## Non-Goals

- No hover-to-open in v1.
- No detached floating companion.
- No drag gesture.
- No physical notch detection or true system-notch alignment in v1.
- No global rewrite of `MenuBarView`; visual adaptation should be isolated.
- No direct source copy from Ping Island.

## User Experience

### Closed State

The app displays a small black notch centered at the top edge of the active screen.

Closed notch content:

- CodeBar or provider logo
- one compact quota/status line
- if data is loading, show a compact loading indicator or `CodeBar`
- if there is an error, show a small warning symbol

The closed notch is always visible while CodeBar is running.

### Open State

Clicking the closed notch expands the same surface downward into a black panel. The panel contains a dark-themed version of the current usage view:

- module cards
- collapse/expand controls
- used/remaining display behavior
- refresh button
- settings button
- quit button
- update notice when available

Clicking outside the panel closes it back to the compact notch.

### Settings And Recovery

Because the menu bar icon is hidden, settings must remain reachable from the opened Island panel. The quit action must also remain available there.

If the Island panel cannot be created, CodeBar may fall back to the existing menu bar item as a recovery path. This is an implementation safety fallback, not a user-facing display mode in v1.

## Visual Design

The Island is visually inspired by Ping Island:

- pure black container
- top edge flush with the screen top
- inward top corner cuts
- larger bottom corner rounding
- spring animation between compact and opened sizes
- dark color scheme for the expanded content

The notch shape should be implemented locally as `CodeBarIslandShape`, using quadratic curves similar in spirit to Ping Island's shape but written from scratch for CodeBar.

Suggested dimensions:

- closed width: 180-220 px
- closed height: 32-38 px
- opened width: 420-520 px, responsive to current `Constants.popoverWidth`
- opened height: measured from content, capped to fit screen height

## Architecture

### New Components

`CodeBarIslandWindow`

- Small `NSPanel` subclass dedicated to the Island surface.
- Borderless, transparent, floating, non-activating where practical.
- Positioned at the top center of the active screen.
- Resized between closed and opened frames.

`CodeBarIslandController`

- Owns the panel lifecycle.
- Tracks opened/closed state.
- Positions the panel on screen changes.
- Installs/removes outside-click monitor while opened.
- Exposes `toggle`, `open`, `close`, and `refreshLayout`.

`CodeBarIslandView`

- SwiftUI root view for the panel.
- Renders closed notch and opened panel from one state.
- Receives `UsageTracker` and `UpdateChecker`.
- Calls controller closures for open/close/settings/quit where needed.

`CodeBarIslandShape`

- SwiftUI `Shape` for the black notch/panel silhouette.
- Animatable top and bottom corner radii.

### Existing Components To Reuse

`UsageTracker`

- Provides modules, usage data, errors, refresh state, settings state.

`MenuBarView`

- Its content structure should guide the opened Island panel.
- The first implementation should extract only the shared subviews needed for the opened Island panel and avoid a broad rewrite.

`SettingsWindowView`

- Opened through the Island settings button.

## App Lifecycle Changes

`AppDelegate` should stop creating a visible `NSStatusItem` for the normal startup path once Island Mode is enabled.

Instead, startup should:

1. Create the Island controller.
2. Show the closed Island panel.
3. Start usage refresh and update check as today.
4. Listen for existing module/status notifications and refresh the Island view.

The current status item code should remain available during development and as a fallback, but the intended user-facing path is the Island.

## Interaction Details

- Closed notch click opens the panel.
- Open panel outside click closes it.
- Escape key closes the panel when the panel is key.
- Refresh button runs `UsageTracker.shared.refresh()`.
- Settings button opens the existing settings window.
- Quit button terminates the app.

The v1 panel should not request Accessibility permission or rely on event taps. A standard global mouse-down monitor is enough for closing an already-open panel.

## Data Flow

The Island view reads the same published state as `MenuBarView`:

- `tracker.detailModules`
- `tracker.moduleUsages`
- `tracker.moduleErrors`
- `tracker.lastRefreshDate`
- `updateChecker.hasUpdate`

Closed compact status should be derived from module usage:

1. Prefer items nearest to limit.
2. Respect each module's `percentDisplayMode`.
3. Fall back to provider/module name when usage is unavailable.
4. Show compact error state when any visible module has an error.

## Testing Strategy

Unit/behavior tests:

- Compact status selection picks the most constrained quota item.
- Compact status respects remaining-vs-used display mode.
- Island state model toggles open/closed deterministically.
- Window sizing helpers produce centered top frames for closed and opened states.

Build checks:

- Existing behavior test script.
- Debug Xcode build.
- Release unsigned Xcode build.

Manual verification:

- Launch app and confirm no visible menu bar icon.
- Closed notch appears at top center.
- Click opens the panel.
- Click outside closes the panel.
- Refresh/settings/quit controls are reachable.
- Multiple modules remain readable.
- No panel overlap or text clipping on a small screen.

## Risks And Mitigations

Window focus and click behavior:

- Keep v1 panel bounds limited to the actual Island size rather than a full-width transparent overlay.
- Use outside-click monitor only while opened.

Loss of access because menu bar icon is hidden:

- Keep settings and quit inside the opened Island.
- Keep a code-level fallback to create the old status item if Island panel creation fails.

Visual mismatch with Ping Island:

- Match the important feel: black top-anchored notch, curved silhouette, smooth expansion.
- Avoid copying unrelated mascot/session UI.

Scope creep:

- Defer hover, full-screen hiding, detachment, and real notch metrics to future iterations.

## Acceptance Criteria

- CodeBar starts with a top-center closed Island and no visible menu bar icon.
- Clicking the Island expands the usage panel.
- Clicking outside closes it.
- Existing usage, refresh, settings, update notice, and quit flows remain available.
- Existing module collapse and percent display settings still work.
- Behavior tests and Debug/Release builds pass.
