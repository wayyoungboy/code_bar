import AppKit

enum StatusBarIconRenderer {
    static func render(
        _ source: NSImage,
        pointSize: CGFloat,
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2,
        isTemplate: Bool
    ) -> NSImage {
        let clampedScale = max(scale, 1)
        let pixelSize = max(1, Int((pointSize * clampedScale).rounded()))
        let targetSize = NSSize(width: pointSize, height: pointSize)

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            let fallback = source.copy() as? NSImage ?? source
            fallback.size = targetSize
            fallback.isTemplate = isTemplate
            return fallback
        }

        representation.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: representation) {
            NSGraphicsContext.current = context
            context.imageInterpolation = NSImageInterpolation.high
            let sourceRect = source.size.width > 0 && source.size.height > 0
                ? NSRect(origin: .zero, size: source.size)
                : .zero
            source.draw(
                in: NSRect(origin: .zero, size: targetSize),
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: targetSize)
        image.addRepresentation(representation)
        image.isTemplate = isTemplate
        return image
    }
}
