import AppKit
import CoreGraphics

/// Pure encoders for the pasteboard representations of a capture. See OutputService.
enum ImageEncoding {
    /// TIFF for the pasteboard. NSBitmapImageRep defaults to one point per pixel, so the size is set
    /// to the capture's size in points (`pixels / scale`); otherwise apps that pick TIFF over PNG paste a
    /// Retina capture at twice the intended size. The CGImage's colour space is kept.
    nonisolated static func tiffData(for capture: CapturedImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: capture.image)
        rep.size = pointSize(pixelWidth: capture.image.width, pixelHeight: capture.image.height, scale: capture.scale)
        return rep.tiffRepresentation
    }

    /// Size in points of a `pixelWidth` x `pixelHeight` image at backing scale `scale` (non-positive scales count as 1).
    nonisolated static func pointSize(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> NSSize {
        let scale = scale > 0 ? scale : 1
        return NSSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
    }
}
