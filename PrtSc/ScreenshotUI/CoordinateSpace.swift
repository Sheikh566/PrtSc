import AppKit

/// The single place that converts between global CG coordinates (top-left origin of the main display,
/// y down; what PrtScCore uses) and AppKit's bottom-left global space.
@MainActor
enum CoordinateSpace {
    /// Height of the primary display (the screen at AppKit origin).
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Rectangles flip about the primary display's height, which is correct for any display arrangement
    /// because both spaces share the primary display's corner as their reference.
    static func appKitRect(fromGlobalCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func globalCGRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitPoint(fromGlobalCG point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func globalCGPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
