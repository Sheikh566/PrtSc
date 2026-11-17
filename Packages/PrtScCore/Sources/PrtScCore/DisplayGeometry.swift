import CoreGraphics
import Foundation

public struct DisplayInfo: Equatable, Hashable, Sendable {
    public var displayID: UInt32
    /// Global CG points.
    public var frame: CGRect
    /// Backing scale factor (2 on Retina).
    public var scale: CGFloat
    public var isPrimary: Bool

    public init(displayID: UInt32, frame: CGRect, scale: CGFloat, isPrimary: Bool) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
        self.isPrimary = isPrimary
    }
}

public struct DisplaySegment: Equatable, Sendable {
    public var displayID: UInt32
    /// In that display's image pixels (top-left origin). Integral; never larger than the display image.
    public var sourcePixelRect: CGRect
    /// In the output image pixels (top-left origin). The destination rects of all segments tile the canvas.
    public var destinationPixelRect: CGRect
    /// Where the *whole* `sourcePixelRect` is drawn in the output pixels. It maps each source pixel to
    /// exactly `outputScale / displayScale` output pixels (1:1 when the scales match) at an integral
    /// offset, so nothing is resampled by a fractional shift. It always covers `destinationPixelRect`;
    /// the stitcher clips the drawing to the destination, which trims the rounding surplus (at most one
    /// source pixel per edge).
    public var drawPixelRect: CGRect

    public init(displayID: UInt32, sourcePixelRect: CGRect, destinationPixelRect: CGRect,
                drawPixelRect: CGRect) {
        self.displayID = displayID
        self.sourcePixelRect = sourcePixelRect
        self.destinationPixelRect = destinationPixelRect
        self.drawPixelRect = drawPixelRect
    }
}

public enum DisplayGeometry {
    /// The display whose frame contains `point` (frames are half-open: min edges inclusive, max exclusive).
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
    }

    /// The display the CapturePanel goes on: contains the pointer, else primary, else first.
    public static func panelDisplay(pointer: CGPoint, displays: [DisplayInfo]) -> DisplayInfo? {
        display(containing: pointer, in: displays)
            ?? displays.first(where: \.isPrimary)
            ?? displays.first
    }

    /// Bounding rect of all display frames; `.zero` when there are none.
    public static func union(of displays: [DisplayInfo]) -> CGRect {
        guard let first = displays.first else { return .zero }
        return displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// The output scale for a rect = max scale of the displays it intersects (touching edges don't count).
    /// If it intersects none: the primary display's scale, else the first display's, else 1.
    public static func outputScale(for rect: CGRect, displays: [DisplayInfo]) -> CGFloat {
        let r = rect.standardized
        let hit = displays.filter { overlaps($0.frame, r) }.map(\.scale)
        if let best = hit.max() { return best }
        return (displays.first(where: \.isPrimary) ?? displays.first)?.scale ?? 1
    }

    /// Size in output pixels of the image for `rect` at `scale`: rect.size × scale, rounded.
    public static func outputPixelSize(for rect: CGRect, scale: CGFloat) -> CGSize {
        let r = rect.standardized
        return CGSize(width: (r.width * scale).rounded(), height: (r.height * scale).rounded())
    }

    /// Splits a global rect into the pieces needed to stitch the image from per-display images
    /// at outputScale, without resampling the pixels that exist.
    ///
    /// The output image's origin is `rect.origin` and its size is `outputPixelSize(for:scale:)` at
    /// `outputScale`. Each display's image is placed on the output canvas at one integral offset (where
    /// its pixel (0, 0) lands, rounded to the nearest output pixel), so a source pixel maps to exactly
    /// `outputScale / displayScale` output pixels (1:1 on a display at the output scale) and a selection
    /// at a fractional point origin is *shifted* by at most half a pixel instead of stretched.
    /// `destinationPixelRect`s are rounded from shared edge positions, so pieces from adjacent displays
    /// tile the output with no gaps or overlaps; `sourcePixelRect` is the smallest integral source rect
    /// that covers the destination at that placement and `drawPixelRect` is where it is drawn
    /// (clip to the destination). Parts of `rect` outside every display produce no segment. Segments come
    /// in the order of `displays`.
    public static func segments(for rect: CGRect, displays: [DisplayInfo]) -> [DisplaySegment] {
        let r = rect.standardized
        guard r.width > 0, r.height > 0 else { return [] }
        let scale = outputScale(for: r, displays: displays)
        let out = outputPixelSize(for: r, scale: scale)

        var result: [DisplaySegment] = []
        for display in displays {
            guard overlaps(display.frame, r) else { continue }
            let inter = display.frame.intersection(r)
            let ratio = scale / display.scale
            guard let x = placement(intersectionMin: inter.minX, intersectionMax: inter.maxX,
                                    rectMin: r.minX, displayMin: display.frame.minX,
                                    outputLength: out.width, outputScale: scale, ratio: ratio,
                                    displayPixels: (display.frame.width * display.scale).rounded()),
                  let y = placement(intersectionMin: inter.minY, intersectionMax: inter.maxY,
                                    rectMin: r.minY, displayMin: display.frame.minY,
                                    outputLength: out.height, outputScale: scale, ratio: ratio,
                                    displayPixels: (display.frame.height * display.scale).rounded())
            else { continue }

            result.append(DisplaySegment(
                displayID: display.displayID,
                sourcePixelRect: CGRect(x: x.source.lowerBound, y: y.source.lowerBound,
                                        width: x.source.upperBound - x.source.lowerBound,
                                        height: y.source.upperBound - y.source.lowerBound),
                destinationPixelRect: CGRect(x: x.destination.lowerBound, y: y.destination.lowerBound,
                                             width: x.destination.upperBound - x.destination.lowerBound,
                                             height: y.destination.upperBound - y.destination.lowerBound),
                drawPixelRect: CGRect(x: x.draw.lowerBound, y: y.draw.lowerBound,
                                      width: x.draw.upperBound - x.draw.lowerBound,
                                      height: y.draw.upperBound - y.draw.lowerBound)))
        }
        return result
    }

    /// One axis of a segment: destination, source and draw ranges in pixels.
    private struct AxisPlacement {
        var destination: ClosedRange<CGFloat>
        var source: ClosedRange<CGFloat>
        var draw: ClosedRange<CGFloat>
    }

    private static func placement(intersectionMin: CGFloat, intersectionMax: CGFloat,
                                  rectMin: CGFloat, displayMin: CGFloat,
                                  outputLength: CGFloat, outputScale: CGFloat, ratio: CGFloat,
                                  displayPixels: CGFloat) -> AxisPlacement? {
        // Destination edges come from shared positions so adjacent displays tile.
        var d0 = clamp(((intersectionMin - rectMin) * outputScale).rounded(), 0, outputLength)
        var d1 = clamp(((intersectionMax - rectMin) * outputScale).rounded(), 0, outputLength)
        guard d1 > d0 else { return nil }

        // Where the display image's pixel 0 lands on the output canvas: one integral offset. It is moved
        // by a pixel when needed so the display image still covers the whole destination range.
        let footprint = displayPixels * ratio
        let ideal = ((displayMin - rectMin) * outputScale).rounded()
        let offset = min(max(ideal, d1 - footprint), d0)
        d0 = max(d0, offset)
        d1 = min(d1, offset + footprint)
        guard d1 > d0 else { return nil }

        // Tolerance keeps float noise (e.g. 1080.0000000001) from adding a whole source pixel.
        let epsilon: CGFloat = 1e-6
        let s0 = clamp(((d0 - offset) / ratio + epsilon).rounded(.down), 0, displayPixels)
        let s1 = clamp(((d1 - offset) / ratio - epsilon).rounded(.up), 0, displayPixels)
        guard s1 > s0 else { return nil }
        return AxisPlacement(destination: d0...d1, source: s0...s1,
                             draw: (offset + s0 * ratio)...(offset + s1 * ratio))
    }

    /// The display that shows most of a window: the one with the largest intersection area with `frame`.
    /// Ties (equal areas) go to the lowest `displayID`. nil when the frame intersects no display.
    public static func displayShowingMost(of frame: CGRect, displays: [DisplayInfo]) -> DisplayInfo? {
        var best: (display: DisplayInfo, area: CGFloat)?
        for display in displays {
            let inter = display.frame.intersection(frame)
            guard !inter.isNull, inter.width > 0, inter.height > 0 else { continue }
            let area = inter.width * inter.height
            if let current = best {
                if area > current.area || (area == current.area && display.displayID < current.display.displayID) {
                    best = (display, area)
                }
            } else {
                best = (display, area)
            }
        }
        return best?.display
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > 0 && i.height > 0
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}
