import CoreGraphics
import Foundation

/// What to capture from one display for a Screencast Selection.
public struct RecordingRegion: Equatable, Sendable {
    /// `SCStreamConfiguration.sourceRect`: display-local points, top-left origin, aligned to whole pixels.
    public var sourceRect: CGRect
    /// The output video size in pixels: always even and exactly `sourceRect.size × scale`, so nothing is
    /// resampled.
    public var pixelWidth: Int
    public var pixelHeight: Int
}

public enum RecordingGeometry {
    /// Video encoders want even dimensions. Largest even integer ≤ `value`, at least 2.
    static func evenPixelCount(_ value: CGFloat) -> Int {
        guard value.isFinite, value >= 2 else { return 2 }
        return Int(value.rounded(.down)) / 2 * 2
    }

    /// `size` (points) × `scale` as even pixel dimensions, rounded down (never scaled up past native).
    /// A scale that is not a positive finite number counts as 1.
    public static func pixelSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let s = (scale.isFinite && scale > 0) ? scale : 1
        return (evenPixelCount(size.width * s), evenPixelCount(size.height * s))
    }

    /// The part of a global CG `selection` that lies on `display`, as a pixel-aligned source rect in that
    /// display's local coordinates plus its even pixel size. A Selection spanning displays is thereby
    /// clamped to the display `display`. nil when the selection does not intersect the display.
    public static func region(for selection: CGRect, on display: DisplayInfo) -> RecordingRegion? {
        let clipped = selection.standardized.intersection(display.frame)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        let scale = (display.scale.isFinite && display.scale > 0) ? display.scale : 1

        let local = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let displayWidth = Int((display.frame.width * scale).rounded())
        let displayHeight = Int((display.frame.height * scale).rounded())

        // Snap the edges to the pixel grid, then shrink to an even size and keep it inside the display.
        let x0 = Int((local.minX * scale).rounded())
        let y0 = Int((local.minY * scale).rounded())
        let x1 = Int((local.maxX * scale).rounded())
        let y1 = Int((local.maxY * scale).rounded())
        let width = min(evenPixelCount(CGFloat(x1 - x0)), max(displayWidth / 2 * 2, 2))
        let height = min(evenPixelCount(CGFloat(y1 - y0)), max(displayHeight / 2 * 2, 2))
        let originX = max(0, min(x0, displayWidth - width))
        let originY = max(0, min(y0, displayHeight - height))

        let rect = CGRect(x: CGFloat(originX) / scale, y: CGFloat(originY) / scale,
                          width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return RecordingRegion(sourceRect: rect, pixelWidth: width, pixelHeight: height)
    }
}
