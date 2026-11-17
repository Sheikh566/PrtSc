import CoreGraphics
import Foundation

// All GNOME (main) Selection behaviour.

public enum ArrowDirection: Sendable { case left, right, up, down }

public struct EditModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ⌥ — move instead of resize
    public static let move = EditModifiers(rawValue: 1 << 0)
    /// ⌘ — 1 pt steps (⌃ is NOT used: ⌃←/→ switch Spaces system-wide)
    public static let fine = EditModifiers(rawValue: 1 << 1)
    /// ⇧ — steps of the primary display's full width/height
    public static let large = EditModifiers(rawValue: 1 << 2)
}

public enum SelectionHandle: Equatable, Sendable {
    case none, move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
}

public struct SelectionEditor: Equatable, Sendable {
    public static let defaultStep: CGFloat = 5
    /// A click without dragging → square ±20 pt around the point.
    public static let clickPadding: CGFloat = 20
    /// Hit-test tolerance (pt) that `dragBegan` uses to decide whether a drag grabs a handle.
    public static let defaultHandleTolerance: CGFloat = 15
    /// Pointer movement (pt) up to which a new-selection drag still counts as a click.
    static let clickSlop: CGFloat = 2
    /// Slack (pt) for "inside bounds" checks: `rect.maxX` is computed as `x + width`, which can land one
    /// ulp past the edge it was built from.
    static let containmentSlack: CGFloat = 1e-6

    /// Global CG points, always non-empty and inside bounds.
    public private(set) var rect: CGRect
    /// Union of all display frames.
    public let bounds: CGRect
    public let primaryDisplayFrame: CGRect
    /// Tolerance used by `dragBegan` for handle hit-testing.
    public var handleTolerance: CGFloat = SelectionEditor.defaultHandleTolerance

    private var drag: Drag?

    /// Default rect = centre of the primary display from 3/8 to 5/8 on both axes.
    /// `remembered` is used instead when it lies entirely inside bounds (and is non-empty).
    public init(bounds: CGRect, primaryDisplayFrame: CGRect, remembered: CGRect?) {
        self.bounds = bounds
        self.primaryDisplayFrame = primaryDisplayFrame
        if let remembered {
            let r = remembered.standardized
            if !r.isNull, r.width >= 1, r.height >= 1,
               bounds.insetBy(dx: -Self.containmentSlack, dy: -Self.containmentSlack).contains(r) {
                self.rect = r.intersection(bounds)
                return
            }
        }
        self.rect = Self.defaultRect(bounds: bounds, primary: primaryDisplayFrame)
    }

    // MARK: Keyboard

    /// Arrows resize by moving the right edge (←/→) or bottom edge (↑/↓): → and ↓ grow, ← and ↑ shrink.
    /// With .move, the whole rect moves instead. The step is defaultStep, 1 with .fine, and the primary
    /// display's width/height with .large (.fine wins if both are given). The result is clamped to
    /// bounds; minimum size 1×1.
    public mutating func handleArrow(_ direction: ArrowDirection, modifiers: EditModifiers) {
        let horizontal = direction == .left || direction == .right
        let step: CGFloat
        if modifiers.contains(.fine) {
            step = 1
        } else if modifiers.contains(.large) {
            step = horizontal ? primaryDisplayFrame.width : primaryDisplayFrame.height
        } else {
            step = Self.defaultStep
        }
        let delta = (direction == .right || direction == .down) ? step : -step

        if modifiers.contains(.move) {
            var origin = rect.origin
            if horizontal { origin.x += delta } else { origin.y += delta }
            rect.origin = clampedOrigin(origin, size: rect.size)
        } else if horizontal {
            rect.size.width = min(max(rect.width + delta, 1), max(bounds.maxX - rect.minX, 1))
        } else {
            rect.size.height = min(max(rect.height + delta, 1), max(bounds.maxY - rect.minY, 1))
        }
    }

    /// R key: back to the default centre rect.
    public mutating func reset() {
        drag = nil
        rect = Self.defaultRect(bounds: bounds, primary: primaryDisplayFrame)
    }

    // MARK: Hit testing

    /// Handles within `tolerance` of an edge or corner; inside → .move; outside → .none.
    /// Corners beat edges.
    public func handle(at point: CGPoint, tolerance: CGFloat) -> SelectionHandle {
        let r = rect
        let tol = max(tolerance, 0)
        let dLeft = abs(point.x - r.minX), dRight = abs(point.x - r.maxX)
        let dTop = abs(point.y - r.minY), dBottom = abs(point.y - r.maxY)
        let nearLeft = dLeft <= tol, nearRight = dRight <= tol
        let nearTop = dTop <= tol, nearBottom = dBottom <= tol
        let inXRange = point.x >= r.minX - tol && point.x <= r.maxX + tol
        let inYRange = point.y >= r.minY - tol && point.y <= r.maxY + tol

        // On a rect so small that both sides are in range, the closer side wins (ties → left/top).
        let horizontalSide: SelectionHandle? =
            nearLeft && nearRight ? (dLeft <= dRight ? .left : .right) : nearLeft ? .left : nearRight ? .right : nil
        let verticalSide: SelectionHandle? =
            nearTop && nearBottom ? (dTop <= dBottom ? .top : .bottom) : nearTop ? .top : nearBottom ? .bottom : nil

        switch (horizontalSide, verticalSide) {
        case (.left?, .top?): return .topLeft
        case (.right?, .top?): return .topRight
        case (.left?, .bottom?): return .bottomLeft
        case (.right?, .bottom?): return .bottomRight
        default: break
        }
        if let side = horizontalSide, inYRange { return side }
        if let side = verticalSide, inXRange { return side }
        if inXRange && inYRange && point.x >= r.minX && point.x <= r.maxX
            && point.y >= r.minY && point.y <= r.maxY {
            return .move
        }
        return .none
    }

    // MARK: Dragging

    /// forceNew = right-drag or ⌃-drag: always starts a new selection. Otherwise a drag that starts on a
    /// handle (within `handleTolerance`) resizes, inside the rect moves, and elsewhere starts a new selection.
    public mutating func dragBegan(at point: CGPoint, forceNew: Bool) {
        let start = rect
        let grabbed = forceNew ? SelectionHandle.none : handle(at: point, tolerance: handleTolerance)
        switch grabbed {
        case .none:
            drag = .newSelection(anchor: clamped(point), exceededSlop: false)
        case .move:
            drag = .move(grab: CGPoint(x: point.x - start.minX, y: point.y - start.minY), size: start.size)
        case .left, .topLeft, .bottomLeft, .right, .topRight, .bottomRight, .top, .bottom:
            var horizontal: Axis?
            var vertical: Axis?
            switch grabbed {
            case .left, .topLeft, .bottomLeft: horizontal = Axis(fixed: start.maxX, offset: start.minX - point.x)
            case .right, .topRight, .bottomRight: horizontal = Axis(fixed: start.minX, offset: start.maxX - point.x)
            default: break
            }
            switch grabbed {
            case .top, .topLeft, .topRight: vertical = Axis(fixed: start.maxY, offset: start.minY - point.y)
            case .bottom, .bottomLeft, .bottomRight: vertical = Axis(fixed: start.minY, offset: start.maxY - point.y)
            default: break
            }
            drag = .resize(start: start, horizontal: horizontal, vertical: vertical)
        }
    }

    public mutating func dragMoved(to point: CGPoint) {
        guard let current = drag else { return }
        switch current {
        case .newSelection(let anchor, let exceeded):
            let moved = exceeded || hypot(point.x - anchor.x, point.y - anchor.y) > Self.clickSlop
            drag = .newSelection(anchor: anchor, exceededSlop: moved)
            if moved {
                let x = Self.span(fixed: anchor.x, moving: point.x, lo: bounds.minX, hi: bounds.maxX)
                let y = Self.span(fixed: anchor.y, moving: point.y, lo: bounds.minY, hi: bounds.maxY)
                rect = CGRect(x: x.min, y: y.min, width: x.max - x.min, height: y.max - y.min)
            }
        case .move(let grab, let size):
            rect = CGRect(origin: clampedOrigin(CGPoint(x: point.x - grab.x, y: point.y - grab.y), size: size),
                          size: size)
        case .resize(let start, let horizontal, let vertical):
            var x = (min: start.minX, max: start.maxX)
            var y = (min: start.minY, max: start.maxY)
            if let h = horizontal {
                x = Self.span(fixed: h.fixed, moving: point.x + h.offset, lo: bounds.minX, hi: bounds.maxX)
            }
            if let v = vertical {
                y = Self.span(fixed: v.fixed, moving: point.y + v.offset, lo: bounds.minY, hi: bounds.maxY)
            }
            rect = CGRect(x: x.min, y: y.min, width: x.max - x.min, height: y.max - y.min)
        }
    }

    /// If a new-selection drag ended without moving more than 2 pt, the rect becomes the click square:
    /// ±`clickPadding` around the point, shifted if needed to stay inside bounds.
    public mutating func dragEnded(at point: CGPoint) {
        guard drag != nil else { return }
        dragMoved(to: point)
        if case .newSelection(let anchor, let exceeded)? = drag, !exceeded {
            let side = Self.clickPadding * 2
            let size = CGSize(width: min(side, bounds.width), height: min(side, bounds.height))
            let origin = CGPoint(x: anchor.x - Self.clickPadding, y: anchor.y - Self.clickPadding)
            rect = CGRect(origin: clampedOrigin(origin, size: size), size: size)
        }
        drag = nil
    }

    // MARK: Helpers

    private enum Drag: Equatable, Sendable {
        case newSelection(anchor: CGPoint, exceededSlop: Bool)
        case move(grab: CGPoint, size: CGSize)
        case resize(start: CGRect, horizontal: Axis?, vertical: Axis?)
    }

    /// One dragged axis: the opposite edge stays at `fixed`; the moving edge is pointer + `offset`.
    private struct Axis: Equatable, Sendable {
        var fixed: CGFloat
        var offset: CGFloat
    }

    private static func defaultRect(bounds: CGRect, primary: CGRect) -> CGRect {
        let r = CGRect(x: primary.minX + primary.width * 3 / 8,
                       y: primary.minY + primary.height * 3 / 8,
                       width: max(primary.width / 4, 1),
                       height: max(primary.height / 4, 1))
        guard !bounds.insetBy(dx: -Self.containmentSlack, dy: -Self.containmentSlack).contains(r) else { return r }
        // Degenerate geometry (primary outside bounds): fit as well as possible.
        let size = CGSize(width: min(r.width, max(bounds.width, 1)), height: min(r.height, max(bounds.height, 1)))
        let x = min(max(r.minX, bounds.minX), bounds.maxX - size.width)
        let y = min(max(r.minY, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    /// Clamps an origin so a rect of `size` lies fully inside bounds (size is preserved).
    private func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: min(max(origin.x, bounds.minX), max(bounds.maxX - size.width, bounds.minX)),
                y: min(max(origin.y, bounds.minY), max(bounds.maxY - size.height, bounds.minY)))
    }

    /// Normalised 1-D range between a fixed edge and a moving edge, clamped to [lo, hi], at least 1 pt
    /// long. If the edges collapse, the range extends away from the side the moving edge is on (or the
    /// other way when there's no room), so it always stays inside [lo, hi].
    private static func span(fixed: CGFloat, moving: CGFloat, lo: CGFloat, hi: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let fixed = Swift.min(Swift.max(fixed, lo), hi)
        let e = Swift.min(Swift.max(moving, lo), hi)
        if abs(e - fixed) >= 1 { return (Swift.min(e, fixed), Swift.max(e, fixed)) }
        if e >= fixed {
            return fixed + 1 <= hi ? (fixed, fixed + 1) : (fixed - 1, fixed)
        }
        return fixed - 1 >= lo ? (fixed - 1, fixed) : (fixed, fixed + 1)
    }
}
