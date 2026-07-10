# CodeBar Notch Left Extension Design

## Context

The current notch presentation moves the compact status below the camera housing by adding the display's top safe-area inset to the panel height. On a MacBook with a 32-point top safe area, this produces a large black region below the menu bar instead of visually extending the hardware notch. The compact title and percentage also remain in one horizontal row, so they cannot use the visible areas beside the camera housing.

## Goals

- Keep the collapsed notch panel within the menu-bar band at approximately 36 points high.
- Extend the black panel horizontally only on the left side of the physical notch.
- Show the platform icon, name, and compact quota/status in one row in the left extension.
- Keep the physical notch area empty so no content is obscured.
- Expand the same panel downward when the left extension is clicked.
- Preserve a usable compact presentation on displays without a notch.
- Remove text prefixes from compact percentages, so both used and remaining modes show only the numeric percentage.

## Selected Approach

Use one `NSPanel` and derive the hardware notch geometry from `NSScreen.auxiliaryTopLeftArea` and `NSScreen.auxiliaryTopRightArea`. The closed panel begins 160 points before the hardware notch and ends at the hardware notch's right edge.

The alternatives were rejected for these reasons:

- A two-wing layout separates the platform identity from its value and looks visually unbalanced around the camera housing.
- A fixed center spacer would be simpler but would misalign on MacBook models with different camera-housing widths or display scales.

## Geometry

Introduce a pure layout value that contains:

- the target screen frame;
- the detected notch frame between the left and right auxiliary top areas;
- the notch center relative to the screen;
- the local center-gap range inside the panel;
- the left extension width;
- the collapsed and expanded panel frames.

For a notched display:

- Notch width is `rightArea.minX - leftArea.maxX`.
- The collapsed left extension is 160 points wide.
- Collapsed panel width is `notchWidth + 160` points.
- Collapsed panel height remains 36 points.
- The collapsed panel starts at `notchMinX - 160` and ends at `notchMaxX`.
- The expanded panel is centered on the detected notch center, not assumed to be centered on the screen.
- The center gap exactly matches the detected notch width.

For the current test display, the auxiliary areas end at `x = 663` and begin at `x = 848`, producing a 185-point gap and a 345-point collapsed panel at `x = 503...848`.

For a display without auxiliary top areas, fall back to the existing 210-by-36-point centered compact pill and do not insert a center gap.

## SwiftUI Layout

The compact header has two variants:

- Notched display: one left-aligned row containing the platform identity and compact status, followed by an empty camera-housing region.
- Non-notched display: the existing compact horizontal row without a center gap.

The panel background remains one continuous black shape, making the hardware notch read as extended to the left. The previous top safe-area padding is removed because the header itself occupies the safe menu-bar band and places no content in the camera-housing region.

When expanded:

- The panel grows to the existing 500-point width and its measured content height.
- The top 36-point header keeps the compact row on the visible left side of the notch.
- The full `MenuBarView` starts immediately below that header.
- The close control remains in the visible left header region when open.
- Clicking outside, pressing Escape, changing screens, and switching presentation modes keep their existing behavior.

## Compact Percentage Formatting

Compact percentage text never includes a text prefix. Used mode shows values such as `92%`, and remaining mode shows values such as `8%`. The module's configured percentage mode determines the meaning. This rule applies consistently to status-bar and notch compact presentations.

## Error And Loading States

The left extension shows the selected platform followed by the current compact state such as `刷新中`, `刷新异常`, or `未配置`. Existing warning, error, and loading colors remain unchanged.

If the auxiliary areas are missing, malformed, or do not leave a positive left extension, CodeBar uses the non-notched fallback rather than placing content over an uncertain center region.

## Testing

Add behavior tests that verify:

- the `x = 663...848` hardware notch maps to a 185-point local center gap;
- the collapsed panel is 345 by 36 points, starts at `x = 503`, and ends at the notch's right edge `x = 848`;
- the left content slot stops before the center gap;
- the expanded frame remains centered on the same notch center and fits the visible screen;
- displays without auxiliary top areas retain the 210-by-36-point fallback;
- used compact text is `92%` and remaining compact text is `8%`;
- existing layout, persistence, and provider behavior tests still pass.

Runtime verification will build and launch the macOS app in notch mode, inspect the resulting window frame, check steady-state CPU and error logs, and visually inspect the left-side placement when the desktop capture interface is available.

## Out Of Scope

- Multiple simultaneous notch panels on several displays.
- User-configurable extension widths or notch colors.
- Changes to quota selection, provider refresh logic, or full detail content.
