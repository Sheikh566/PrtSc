import CoreGraphics
import Foundation

public enum InstantWindowTarget: Equatable, Sendable {
    /// attached = sheets/popovers to include
    case window(WindowInfo, attached: [WindowInfo])
    case screen(displayID: UInt32)
}

public enum InstantWindowTargetResolver {
    /// Windows smaller than this (either side) are never the main window.
    static let minimumSide: CGFloat = 40

    /// windows are ordered front to back. Picks the front-most on-screen, top-level layer-0 window of
    /// frontmostPID that's at least 40×40 pt. A layer-0 window that is a sheet of another window of the
    /// same app (see `isSheet(_:of:)`) is not top-level: its parent is the main window and the sheet is
    /// one of the `attached` windows. `attached` = other windows of the same PID that are above the main
    /// window in z-order (any layer ≥ 0) and intersect its frame. If there's no such window
    /// (e.g. Finder showing only the desktop), or frontmostPID is nil or ownPID, falls back to
    /// .screen(displayUnderPointer).
    public static func resolve(frontmostPID: Int32?, ownPID: Int32, windows: [WindowInfo],
                               displayUnderPointer: UInt32) -> InstantWindowTarget {
        let fallback = InstantWindowTarget.screen(displayID: displayUnderPointer)
        guard let pid = frontmostPID, pid != ownPID else { return fallback }

        func isCandidate(_ window: WindowInfo) -> Bool {
            window.ownerPID == pid && window.layer == 0 && window.isOnScreen
                && window.frame.width >= minimumSide && window.frame.height >= minimumSide
        }

        // The front-most candidate that is not a sheet of a candidate below it; a sheet resolves to its
        // parent (repeatedly, for a sheet on a sheet).
        var mainIndex: Int?
        for index in windows.indices where isCandidate(windows[index]) {
            var top = index
            while let parent = windows.indices.first(where: {
                $0 > top && isCandidate(windows[$0]) && isSheet(windows[top], of: windows[$0])
            }) {
                top = parent
            }
            mainIndex = top
            break
        }
        guard let mainIndex else { return fallback }

        let main = windows[mainIndex]
        let attached = windows[..<mainIndex].filter { candidate in
            guard candidate.ownerPID == pid, candidate.layer >= 0, candidate.isOnScreen else { return false }
            let overlap = candidate.frame.intersection(main.frame)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }
        return .window(main, attached: Array(attached))
    }

    /// Whether `candidate` looks like a sheet of `parent`. macOS gives no public parent link for another
    /// process's windows: a sheet is just another normal-layer window of the same app, in front of its
    /// parent, so this is a geometric heuristic over what a sheet looks like:
    /// - it is narrower than the parent and inside the parent's frame,
    /// - it is horizontally centred on the parent (within 3 pt),
    /// - it hangs from the parent's top edge: its top is at most 120 pt below the parent's top.
    /// A separate normal window that is smaller, centred and at the top of another window of the same app
    /// would be misread as a sheet; that is rarer than sheets, and the capture then still contains it.
    public static func isSheet(_ candidate: WindowInfo, of parent: WindowInfo) -> Bool {
        guard candidate.ownerPID == parent.ownerPID else { return false }
        let c = candidate.frame
        let p = parent.frame
        let tolerance: CGFloat = 1
        guard c.width < p.width - tolerance,
              c.minX >= p.minX - tolerance, c.maxX <= p.maxX + tolerance,
              c.minY >= p.minY - tolerance, c.maxY <= p.maxY + tolerance else { return false }
        guard abs(c.midX - p.midX) <= 3 else { return false }
        return c.minY - p.minY <= 120
    }
}
