import CoreGraphics
import PrtScCore

/// One display, captured once the moment the Screenshot UI opens.
struct DisplaySnapshot: Sendable {
    let info: DisplayInfo
    /// The display without the pointer.
    let image: CGImage
    /// The same capture with the pointer glyph composited at the recorded position (`image` itself when the
    /// glyph doesn't touch this display). Used by the overlay preview *and* the final capture.
    let imageWithPointer: CGImage

    func image(showingPointer: Bool) -> CGImage { showingPointer ? imageWithPointer : image }
}

/// One on-screen layer-0 window of the current Space, unobscured, captured once.
struct WindowSnapshot: Sendable {
    let info: WindowInfo
    /// The window without the pointer.
    let image: CGImage
    /// `image` with the pointer composited at the recorded position when the pointer was over the window;
    /// `image` itself otherwise. Used by the Window Picker thumbnails *and* the final capture.
    let imageWithPointer: CGImage
    /// Pixels per point of `image`.
    let scale: CGFloat
    /// Where `image` sits in global CG points. Equals `info.frame` without shadows; with shadows it
    /// extends past the frame by the shadow margin.
    let bounds: CGRect

    func image(showingPointer: Bool) -> CGImage { showingPointer ? imageWithPointer : image }
}

/// The snapshot of every display (and window) taken when the Screenshot UI opens.
struct FrozenFrame: Sendable {
    let displays: [DisplaySnapshot]
    let windows: [WindowSnapshot]
    /// Where the pointer was when the UI opened, in global CG points. Every pointer variant is derived
    /// from this one position and `pointerGlyph`.
    let pointer: CGPoint
    let pointerGlyph: PointerGlyph?
}
