# CodeBar brand assets

The project mark keeps the composition already used in the shipped macOS App Icon and in `design_v1.svg`: a rounded indigo square, white code chevrons, and a cyan usage pill with a center dot.

- `design_v1.svg` is the earlier source file, left unchanged.
- `codebar-mark.svg` is the refined master. Colors match the App Icon sample (`#6366F1`, `#FFFFFF`, `#A5F3FC`), with a corner radius calibrated to that icon, and PNG exports that are antialiased (the checked-in App Icon PNGs are 4-color and look softer at 16–32px).
- `codebar-wordmark.svg` and `codebar-header.svg` use outlined Inter Display paths for the name and English tagline. They do not depend on model-rendered lettering.
- `png/` contains 32 / 64 / 128 / 256 / 512 / 1024 px marks, light and dark 32 / 64 previews, the header, and a contact sheet.

These files are for the README and the GitHub Pages site. The Xcode `AppIcon.appiconset` is unchanged in this update.
