import CoreGraphics
import PrtScCore

/// Pure CGImage helpers: bitmap contexts, cross-display stitching and pointer compositing.
enum ImageOps {
    /// A 8-bit premultiplied BGRA context in `colorSpace`, falling back to sRGB when the colour space
    /// can't back a bitmap context.
    static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var candidates: [CGColorSpace] = []
        if let colorSpace { candidates.append(colorSpace) }
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { candidates.append(srgb) }
        for space in candidates {
            if let context = CGContext(data: nil, width: max(width, 1), height: max(height, 1),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                       bitmapInfo: bitmapInfo) {
                context.interpolationQuality = .high
                return context
            }
        }
        return nil
    }

    /// Cuts `rect` (global CG points) out of the per-display images, stitching across displays with
    /// `DisplayGeometry.segments`. Uses each display's image with the pointer when `showsPointer`.
    ///
    /// The output canvas is `DisplayGeometry.outputPixelSize(for:scale:)` at `outputScale`. Every segment
    /// draws its whole integral source crop at the segment's `drawPixelRect` (an exact multiple of the
    /// source pixels, at an integral offset) clipped to its `destinationPixelRect`, so native pixels are
    /// copied 1:1 and the rounding surplus is clipped rather than scaled into a smaller rect.
    static func stitch(rect: CGRect, snapshots: [DisplaySnapshot], showsPointer: Bool) -> CapturedImage? {
        let infos = snapshots.map(\.info)
        let scale = DisplayGeometry.outputScale(for: rect, displays: infos)
        let canvas = DisplayGeometry.outputPixelSize(for: rect, scale: scale)
        let segments = DisplayGeometry.segments(for: rect, displays: infos)
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        guard !segments.isEmpty, width > 0, height > 0 else { return nil }

        func snapshot(for segment: DisplaySegment) -> DisplaySnapshot? {
            snapshots.first { $0.info.displayID == segment.displayID }
        }
        func crop(_ segment: DisplaySegment) -> CGImage? {
            guard let snapshot = snapshot(for: segment) else { return nil }
            let source = snapshot.image(showingPointer: showsPointer)
            let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
            guard bounds.contains(segment.sourcePixelRect) else { return nil }
            return source.cropping(to: segment.sourcePixelRect)
        }

        // Fast path: the whole canvas is one unscaled crop. Lossless and keeps the display's colour space.
        let wholeCanvas = CGRect(x: 0, y: 0, width: width, height: height)
        if segments.count == 1, let segment = segments.first,
           segment.destinationPixelRect == wholeCanvas, segment.drawPixelRect == wholeCanvas,
           segment.sourcePixelRect.size == wholeCanvas.size, let cropped = crop(segment) {
            return CapturedImage(image: cropped, scale: scale)
        }

        let primary = snapshots.first(where: { $0.info.isPrimary }) ?? snapshots.first
        guard let context = makeContext(width: width, height: height, colorSpace: primary?.image.colorSpace) else {
            return nil
        }
        // Segment rects use a top-left origin; CGContext's origin is bottom-left.
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
        }
        for segment in segments {
            guard let cropped = crop(segment) else { continue }
            context.saveGState()
            context.clip(to: flipped(segment.destinationPixelRect))
            context.draw(cropped, in: flipped(segment.drawPixelRect))
            context.restoreGState()
        }
        guard let stitched = context.makeImage() else { return nil }
        return CapturedImage(image: stitched, scale: scale)
    }

    /// One image placed in a composite: where it sits in global CG points and its own pixels per point.
    struct Layer {
        let image: CGImage
        /// Global CG points.
        let bounds: CGRect
        let scale: CGFloat
    }

    /// Draws `layers` into one image at `scale`; later layers are drawn on top. Each layer is placed at an
    /// integral pixel offset and drawn at `scale / layer.scale` times its own pixels (1:1 when the scales
    /// match), and the canvas is exactly the union of the placed layers.
    static func composite(_ layers: [Layer], scale: CGFloat, colorSpace: CGColorSpace?) -> CGImage? {
        guard let first = layers.first else { return nil }
        let origin = layers.dropFirst().reduce(first.bounds.origin) {
            CGPoint(x: min($0.x, $1.bounds.minX), y: min($0.y, $1.bounds.minY))
        }
        let placed = layers.map { layer -> (layer: Layer, rect: CGRect) in
            let factor = scale / layer.scale
            let rect = CGRect(x: ((layer.bounds.minX - origin.x) * scale).rounded(),
                              y: ((layer.bounds.minY - origin.y) * scale).rounded(),
                              width: (CGFloat(layer.image.width) * factor).rounded(),
                              height: (CGFloat(layer.image.height) * factor).rounded())
            return (layer, rect)
        }
        let width = Int(placed.map(\.rect.maxX).max() ?? 0)
        let height = Int(placed.map(\.rect.maxY).max() ?? 0)
        guard let context = makeContext(width: width, height: height, colorSpace: colorSpace) else { return nil }
        for (layer, rect) in placed {
            context.draw(layer.image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY,
                                                 width: rect.width, height: rect.height))
        }
        return context.makeImage()
    }

    /// Draws the pointer onto a copy of `image`, or returns nil when the pointer glyph doesn't touch the
    /// image (callers then use `image` itself). `imageOrigin` is the global CG point (top-left) of the
    /// image's origin in points; `scale` is the image's pixels per point; `pointer` is the global position.
    /// This is the one place pointer variants are made: the overlay previews and the delivered capture
    /// both use its results.
    static func compositePointer(_ glyph: PointerGlyph, onto image: CGImage, scale: CGFloat,
                                 imageOrigin: CGPoint, pointer: CGPoint) -> CGImage? {
        let topLeft = CGPoint(x: pointer.x - imageOrigin.x - glyph.hotSpot.x,
                              y: pointer.y - imageOrigin.y - glyph.hotSpot.y)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let glyphRect = CGRect(x: topLeft.x * scale, y: topLeft.y * scale,
                               width: glyph.size.width * scale, height: glyph.size.height * scale)
        guard glyphRect.intersects(bounds),
              let context = makeContext(width: image.width, height: image.height, colorSpace: image.colorSpace)
        else { return nil }
        context.draw(image, in: bounds)
        context.draw(glyph.image, in: CGRect(x: glyphRect.minX,
                                             y: CGFloat(image.height) - glyphRect.maxY,
                                             width: glyphRect.width, height: glyphRect.height))
        return context.makeImage()
    }
}
