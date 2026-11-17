import CoreGraphics

struct CapturedImage: Sendable {
    let image: CGImage
    /// Backing scale factor of the image (2 on Retina); drives DPI metadata.
    let scale: CGFloat
}
