import CoreGraphics
import Testing
@testable import PrtScCore

@Suite("InstantWindowTargetResolver")
struct InstantWindowTargetResolverTests {
    static func win(_ id: UInt32, pid: Int32, frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
                    layer: Int = 0, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: pid, ownerBundleID: nil, title: "w\(id)",
                   frame: frame, layer: layer, isOnScreen: onScreen)
    }

    func resolve(frontmost: Int32? = 10, own: Int32 = 99, _ windows: [WindowInfo], display: UInt32 = 7) -> InstantWindowTarget {
        InstantWindowTargetResolver.resolve(frontmostPID: frontmost, ownPID: own, windows: windows,
                                            displayUnderPointer: display)
    }

    @Test func picksFrontMostWindowOfFrontmostApp() {
        let a = Self.win(1, pid: 20)
        let b = Self.win(2, pid: 10)
        let c = Self.win(3, pid: 10)
        #expect(resolve([a, b, c]) == .window(b, attached: []))
    }

    @Test func nilFrontmostFallsBackToScreen() {
        #expect(resolve(frontmost: nil, [Self.win(1, pid: 10)]) == .screen(displayID: 7))
    }

    @Test func ownPIDFallsBackToScreen() {
        #expect(resolve(frontmost: 99, own: 99, [Self.win(1, pid: 99)]) == .screen(displayID: 7))
    }

    @Test func noWindowsFallsBackToScreen() {
        #expect(resolve([]) == .screen(displayID: 7))
    }

    @Test func appWithNoWindowsFallsBackToScreen() {
        // e.g. Finder frontmost but only showing the desktop
        #expect(resolve([Self.win(1, pid: 20)]) == .screen(displayID: 7))
    }

    @Test func ignoresNonZeroLayerWhenChoosingMainWindow() {
        let menu = Self.win(1, pid: 10, layer: 25)
        let normal = Self.win(2, pid: 10)
        #expect(resolve([menu, normal]) == .window(normal, attached: [menu]))
    }

    @Test func onlyNonZeroLayerWindowsFallsBackToScreen() {
        #expect(resolve([Self.win(1, pid: 10, layer: 3)]) == .screen(displayID: 7))
    }

    @Test func ignoresOffScreenWindows() {
        let hidden = Self.win(1, pid: 10, onScreen: false)
        let shown = Self.win(2, pid: 10)
        #expect(resolve([hidden, shown]) == .window(shown, attached: []))
        #expect(resolve([hidden]) == .screen(displayID: 7))
    }

    @Test(arguments: [
        CGSize(width: 39, height: 400), CGSize(width: 400, height: 39), CGSize(width: 10, height: 10), .zero,
    ])
    func ignoresWindowsSmallerThan40(size: CGSize) {
        let tiny = Self.win(1, pid: 10, frame: CGRect(origin: CGPoint(x: 5, y: 5), size: size))
        #expect(resolve([tiny]) == .screen(displayID: 7))
    }

    @Test func exactly40x40Qualifies() {
        let w = Self.win(1, pid: 10, frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(resolve([w]) == .window(w, attached: []))
    }

    @Test func smallWindowSkippedInFavourOfNextLargeOne() {
        let tiny = Self.win(1, pid: 10, frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let big = Self.win(2, pid: 10)
        #expect(resolve([tiny, big]).windowID == 2)
    }

    @Test func attachedAreSameAppWindowsAboveThatIntersect() {
        let main = Self.win(5, pid: 10, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let sheet = Self.win(2, pid: 10, frame: CGRect(x: 300, y: 100, width: 300, height: 200), layer: 8)
        let popover = Self.win(3, pid: 10, frame: CGRect(x: 850, y: 500, width: 100, height: 100), layer: 101)
        let farAway = Self.win(4, pid: 10, frame: CGRect(x: 2000, y: 2000, width: 100, height: 100), layer: 3)
        let otherApp = Self.win(1, pid: 20, frame: CGRect(x: 300, y: 100, width: 300, height: 200))
        let below = Self.win(6, pid: 10, frame: CGRect(x: 200, y: 200, width: 100, height: 100))
        let result = resolve([otherApp, sheet, popover, farAway, main, below])
        #expect(result == .window(main, attached: [sheet, popover]))
    }

    @Test func attachedIncludesNegativeLayersNever() {
        // "any layer ≥ 0": a layer -1 window above in z-order (unusual) is not attached.
        let main = Self.win(2, pid: 10)
        let weird = Self.win(1, pid: 10, layer: -1)
        #expect(resolve([weird, main]) == .window(main, attached: []))
    }

    @Test func attachedExcludesOffScreenWindows() {
        let main = Self.win(2, pid: 10)
        let hidden = Self.win(1, pid: 10, frame: CGRect(x: 120, y: 120, width: 100, height: 100), onScreen: false)
        #expect(resolve([hidden, main]) == .window(main, attached: []))
    }

    @Test func touchingEdgesDoNotIntersect() {
        let main = Self.win(2, pid: 10, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let adjacent = Self.win(1, pid: 10, frame: CGRect(x: 900, y: 100, width: 200, height: 200), layer: 101)
        #expect(resolve([adjacent, main]) == .window(main, attached: []))
    }

    @Test func attachedKeepFrontToBackOrder() {
        let main = Self.win(9, pid: 10)
        let s1 = Self.win(1, pid: 10, frame: CGRect(x: 150, y: 150, width: 100, height: 100), layer: 8)
        let s2 = Self.win(2, pid: 10, frame: CGRect(x: 160, y: 160, width: 100, height: 100), layer: 8)
        #expect(resolve([s1, s2, main]) == .window(main, attached: [s1, s2]))
    }

    @Test func smallSameAppWindowAboveCanBeAttached() {
        // Attached windows have no minimum size (e.g. a small popover).
        let main = Self.win(2, pid: 10)
        let pop = Self.win(1, pid: 10, frame: CGRect(x: 120, y: 120, width: 20, height: 20), layer: 101)
        #expect(resolve([pop, main]) == .window(main, attached: [pop]))
    }

    // MARK: Sheets (normal-layer windows attached to a parent)

    static let parentFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    /// Centred, hanging from the parent's top edge below a 52 pt titlebar + toolbar, like a real sheet.
    static let sheetFrame = CGRect(x: 300, y: 152, width: 400, height: 250)

    @Test func layerZeroSheetInFrontResolvesToItsParent() {
        let sheet = Self.win(1, pid: 10, frame: Self.sheetFrame)
        let parent = Self.win(2, pid: 10, frame: Self.parentFrame)
        #expect(resolve([sheet, parent]) == .window(parent, attached: [sheet]))
    }

    @Test func layerZeroSheetWithUnrelatedWindowsAround() {
        let otherApp = Self.win(1, pid: 20, frame: Self.sheetFrame)
        let sheet = Self.win(2, pid: 10, frame: Self.sheetFrame)
        let parent = Self.win(3, pid: 10, frame: Self.parentFrame)
        let belowParent = Self.win(4, pid: 10, frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        #expect(resolve([otherApp, sheet, parent, belowParent]) == .window(parent, attached: [sheet]))
    }

    @Test func sheetOnASheetResolvesToTheTopLevelWindow() {
        let inner = Self.win(1, pid: 10, frame: CGRect(x: 350, y: 200, width: 300, height: 150))
        let sheet = Self.win(2, pid: 10, frame: Self.sheetFrame)
        let parent = Self.win(3, pid: 10, frame: Self.parentFrame)
        #expect(resolve([inner, sheet, parent]) == .window(parent, attached: [inner, sheet]))
    }

    @Test func parentWithSheetBehindOtherLayerZeroWindowStaysTopLevel() {
        // A normal window in front of the parent that isn't sheet-shaped is the target on its own.
        let front = Self.win(1, pid: 10, frame: CGRect(x: 600, y: 300, width: 700, height: 500))
        let parent = Self.win(2, pid: 10, frame: Self.parentFrame)
        #expect(resolve([front, parent]) == .window(front, attached: []))
    }

    @Test func offCentreWindowInsideParentIsNotASheet() {
        let utility = Self.win(1, pid: 10, frame: CGRect(x: 120, y: 152, width: 400, height: 250))
        let parent = Self.win(2, pid: 10, frame: Self.parentFrame)
        #expect(resolve([utility, parent]) == .window(utility, attached: []))
    }

    @Test func centredWindowFarBelowTheTopEdgeIsNotASheet() {
        let dialog = Self.win(1, pid: 10, frame: CGRect(x: 300, y: 350, width: 400, height: 200))
        let parent = Self.win(2, pid: 10, frame: Self.parentFrame)
        #expect(resolve([dialog, parent]) == .window(dialog, attached: []))
    }

    @Test func windowAsWideAsTheParentIsNotASheet() {
        let same = Self.win(1, pid: 10, frame: CGRect(x: 100, y: 152, width: 800, height: 250))
        let parent = Self.win(2, pid: 10, frame: Self.parentFrame)
        #expect(resolve([same, parent]) == .window(same, attached: []))
    }

    @Test func sheetOfAnotherAppsWindowIsNotMatched() {
        // Same geometry but a different PID: not a sheet of that window.
        #expect(!InstantWindowTargetResolver.isSheet(Self.win(1, pid: 20, frame: Self.sheetFrame),
                                                     of: Self.win(2, pid: 10, frame: Self.parentFrame)))
        #expect(InstantWindowTargetResolver.isSheet(Self.win(1, pid: 10, frame: Self.sheetFrame),
                                                    of: Self.win(2, pid: 10, frame: Self.parentFrame)))
    }

    @Test func screenFallbackUsesGivenDisplay() {
        #expect(resolve(frontmost: nil, [], display: 42) == .screen(displayID: 42))
    }
}

private extension InstantWindowTarget {
    var windowID: UInt32? {
        if case .window(let w, _) = self { return w.windowID }
        return nil
    }
}
