import AppKit

/// The menu bar glyph: the app icon's capture symbol (four corner brackets around a rounded dot), drawn
/// as a vector template image at full menu bar size.
///
/// An SF Symbol in a status item takes the menu bar's small text size, which made PrtSc noticeably smaller
/// than neighbouring icons (they're drawn at ~16–18 pt). Drawing our own also matches the app icon.
enum MenuBarIcon {
    /// Canvas size in points. The glyph fills the width and is a little shorter than it is wide, like
    /// the app icon's glyph.
    static let size = NSSize(width: 20, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 1.75
            let arm: CGFloat = 5.5
            // Inset by half the line width so the round caps aren't clipped.
            let frame = NSRect(x: rect.minX + 1.5, y: rect.minY + 2,
                               width: rect.width - 3, height: rect.height - 4)

            NSColor.black.setStroke()
            let brackets = NSBezierPath()
            brackets.lineWidth = lineWidth
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            let corners: [(NSPoint, CGFloat, CGFloat)] = [
                (NSPoint(x: frame.minX, y: frame.maxY), 1, -1),   // top-left
                (NSPoint(x: frame.maxX, y: frame.maxY), -1, -1),  // top-right
                (NSPoint(x: frame.minX, y: frame.minY), 1, 1),    // bottom-left
                (NSPoint(x: frame.maxX, y: frame.minY), -1, 1),   // bottom-right
            ]
            for (corner, dx, dy) in corners {
                brackets.move(to: NSPoint(x: corner.x + dx * arm, y: corner.y))
                brackets.line(to: corner)
                brackets.line(to: NSPoint(x: corner.x, y: corner.y + dy * arm))
            }
            brackets.stroke()

            NSColor.black.setFill()
            let dotSide: CGFloat = 5
            let dot = NSRect(x: frame.midX - dotSide / 2, y: frame.midY - dotSide / 2,
                             width: dotSide, height: dotSide)
            NSBezierPath(roundedRect: dot, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true // follows the menu bar's light/dark appearance and highlight
        image.accessibilityDescription = String(localized: "PrtSc")
        return image
    }
}
