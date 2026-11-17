import CoreGraphics
import Foundation

public enum ImageMetadata {
    /// 72 × scale (144 on Retina). Non-positive or non-finite scales fall back to 72.
    public static func dpi(forScale scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 72 }
        return 72 * scale
    }
}
