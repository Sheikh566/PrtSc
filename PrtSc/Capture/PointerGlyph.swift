import AppKit

/// A snapshot of the system pointer: its image, size and hot spot (points, top-left origin).
struct PointerGlyph: Sendable {
    let image: CGImage
    let size: CGSize
    let hotSpot: CGPoint

    /// The pointer currently shown by the system, or nil if it can't be read.
    @MainActor
    static func current() -> PointerGlyph? {
        let cursor = NSCursor.currentSystem ?? NSCursor.arrow
        let nsImage = cursor.image
        let size = nsImage.size
        guard size.width > 0, size.height > 0 else { return nil }
        // Prefer the sharpest bitmap representation so Retina pointers stay crisp.
        let best = nsImage.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
        var proposed = CGRect(origin: .zero, size: size)
        guard let cgImage = best?.cgImage ?? nsImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        else { return nil }
        return PointerGlyph(image: cgImage, size: size, hotSpot: cursor.hotSpot)
    }
}

/// The pointer position and glyph read together, synchronously, when a capture is requested (before any
/// `await`), so every pointer variant of that capture agrees.
struct PointerSample: Sendable {
    /// Global CG points (top-left origin).
    let location: CGPoint
    let glyph: PointerGlyph?

    @MainActor
    static func current() -> PointerSample {
        PointerSample(location: ScreenCapturer.pointerLocation(), glyph: PointerGlyph.current())
    }
}
