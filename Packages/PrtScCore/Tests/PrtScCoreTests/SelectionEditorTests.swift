import CoreGraphics
import Testing
@testable import PrtScCore

// Single 1000×800 display at the origin unless stated otherwise.
// Default rect = x 375…625, y 300…500 → CGRect(375, 300, 250, 200).
private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let defaultRect = CGRect(x: 375, y: 300, width: 250, height: 200)

private func makeEditor(remembered: CGRect? = nil) -> SelectionEditor {
    SelectionEditor(bounds: screen, primaryDisplayFrame: screen, remembered: remembered)
}

/// Primary 1440×900 display at the origin plus a 1920×1080 display to its left (negative x).
private let multiBounds = CGRect(x: -1920, y: 0, width: 3360, height: 1080)
private let multiPrimary = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func makeMultiEditor(remembered: CGRect? = nil) -> SelectionEditor {
    SelectionEditor(bounds: multiBounds, primaryDisplayFrame: multiPrimary, remembered: remembered)
}

@Suite("SelectionEditor init / reset")
struct SelectionEditorInitTests {
    @Test func defaultRectIsCentreOfPrimaryFrom3Over8To5Over8() {
        #expect(makeEditor().rect == defaultRect)
    }

    @Test func defaultRectOnPrimaryWithNonZeroOriginAndMultiDisplayBounds() {
        #expect(makeMultiEditor().rect == CGRect(x: 540, y: 337.5, width: 360, height: 225))
        let primary = CGRect(x: 1920, y: 100, width: 1600, height: 800)
        let e = SelectionEditor(bounds: CGRect(x: 0, y: 0, width: 3520, height: 1080), primaryDisplayFrame: primary, remembered: nil)
        #expect(e.rect == CGRect(x: 1920 + 600, y: 100 + 300, width: 400, height: 200))
    }

    @Test func storesBoundsAndPrimaryFrame() {
        let e = makeMultiEditor()
        #expect(e.bounds == multiBounds)
        #expect(e.primaryDisplayFrame == multiPrimary)
    }

    @Test func rememberedRectInsideBoundsIsUsed() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 100)
        #expect(makeEditor(remembered: r).rect == r)
    }

    @Test func rememberedRectOneUlpPastBoundsIsStillUsed() {
        // `rect.maxX` is `x + width`, which can overshoot the edge it was built from by an ulp.
        let overshoot = CGRect(x: 0, y: 0, width: screen.width.nextUp, height: screen.height.nextUp)
        #expect(overshoot.maxX > screen.maxX)
        let e = makeEditor(remembered: overshoot)
        #expect(e.rect == screen)
    }

    @Test func rememberedRectClearlyPastBoundsIsIgnored() {
        #expect(makeEditor(remembered: CGRect(x: 0, y: 0, width: 1000.01, height: 800)).rect == defaultRect)
    }

    @Test func rememberedRectEqualToBoundsIsUsed() {
        #expect(makeEditor(remembered: screen).rect == screen)
    }

    @Test(arguments: [
        CGRect(x: 900, y: 700, width: 200, height: 200),    // partly outside
        CGRect(x: -10, y: 10, width: 100, height: 100),
        CGRect(x: 2000, y: 2000, width: 50, height: 50),    // fully outside
        CGRect(x: 0, y: 0, width: 1001, height: 800),       // one point too wide
        CGRect(x: 10, y: 10, width: 0, height: 50),         // empty
        CGRect(x: 10, y: 10, width: 50, height: 0),
        .zero, .null,
    ])
    func unusableRememberedRectFallsBackToDefault(remembered: CGRect) {
        #expect(makeEditor(remembered: remembered).rect == defaultRect)
    }

    @Test func rememberedRectIsOnlyChecked_againstUnionBounds() {
        // A rect on the left display is valid in the multi-display bounds.
        let r = CGRect(x: -1500, y: 200, width: 400, height: 300)
        #expect(makeMultiEditor(remembered: r).rect == r)
    }

    @Test func resetReturnsDefaultCentreRect() {
        var e = makeEditor(remembered: CGRect(x: 10, y: 10, width: 20, height: 20))
        e.handleArrow(.right, modifiers: [.move])
        e.reset()
        #expect(e.rect == defaultRect)
    }

    @Test func resetAfterDragReturnsDefaultAndCancelsDrag() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 800, y: 700), forceNew: false)
        e.dragMoved(to: CGPoint(x: 900, y: 750))
        e.reset()
        #expect(e.rect == defaultRect)
        e.dragMoved(to: CGPoint(x: 10, y: 10))
        #expect(e.rect == defaultRect)
    }
}

@Suite("SelectionEditor arrows")
struct SelectionEditorArrowTests {
    @Test func defaultStepConstants() {
        #expect(SelectionEditor.defaultStep == 5)
        #expect(SelectionEditor.clickPadding == 20)
    }

    @Test(arguments: [
        (ArrowDirection.right, CGRect(x: 375, y: 300, width: 255, height: 200)),
        (.left, CGRect(x: 375, y: 300, width: 245, height: 200)),
        (.down, CGRect(x: 375, y: 300, width: 250, height: 205)),
        (.up, CGRect(x: 375, y: 300, width: 250, height: 195)),
    ])
    func arrowsResizeByMovingRightOrBottomEdge(direction: ArrowDirection, expected: CGRect) {
        var e = makeEditor()
        e.handleArrow(direction, modifiers: [])
        #expect(e.rect == expected)
    }

    @Test(arguments: [
        (ArrowDirection.right, CGRect(x: 376, y: 300, width: 250, height: 200)),
        (.left, CGRect(x: 374, y: 300, width: 250, height: 200)),
        (.down, CGRect(x: 375, y: 301, width: 250, height: 200)),
        (.up, CGRect(x: 375, y: 299, width: 250, height: 200)),
    ])
    func moveModifierMovesWholeRect(direction: ArrowDirection, expected: CGRect) {
        var e = makeEditor()
        e.handleArrow(direction, modifiers: [.move, .fine])
        #expect(e.rect == expected)
    }

    @Test func moveWithDefaultStepIs5() {
        var e = makeEditor()
        e.handleArrow(.right, modifiers: [.move])
        #expect(e.rect == CGRect(x: 380, y: 300, width: 250, height: 200))
    }

    @Test func fineResizeIs1pt() {
        var e = makeEditor()
        e.handleArrow(.right, modifiers: [.fine])
        e.handleArrow(.down, modifiers: [.fine])
        #expect(e.rect == CGRect(x: 375, y: 300, width: 251, height: 201))
    }

    @Test func largeStepIsPrimaryDisplayWidthHorizontallyAndHeightVertically() {
        var e = makeMultiEditor()   // default (540, 337.5, 360, 225)
        e.handleArrow(.right, modifiers: [.large])
        // would grow by 1440 → clamped to bounds.maxX (1440)
        #expect(e.rect == CGRect(x: 540, y: 337.5, width: 900, height: 225))
        e.handleArrow(.down, modifiers: [.large])
        // would grow by 900 → clamped to bounds.maxY (1080)
        #expect(e.rect == CGRect(x: 540, y: 337.5, width: 900, height: 742.5))
    }

    @Test func largeMoveMovesByPrimarySizeClampedToBounds() {
        var e = makeMultiEditor()
        e.handleArrow(.left, modifiers: [.move, .large])
        // 540 - 1440 = -900, still inside bounds (min x = -1920): moved exactly one primary width
        #expect(e.rect == CGRect(x: -900, y: 337.5, width: 360, height: 225))
        e.handleArrow(.left, modifiers: [.move, .large])
        // -900 - 1440 = -2340 → clamped to -1920
        #expect(e.rect == CGRect(x: -1920, y: 337.5, width: 360, height: 225))
        e.handleArrow(.up, modifiers: [.move, .large])
        #expect(e.rect == CGRect(x: -1920, y: 0, width: 360, height: 225))
    }

    @Test func largeShrinkClampsToMinimumSize() {
        var e = makeEditor()
        e.handleArrow(.left, modifiers: [.large])
        #expect(e.rect == CGRect(x: 375, y: 300, width: 1, height: 200))
        e.handleArrow(.up, modifiers: [.large])
        #expect(e.rect == CGRect(x: 375, y: 300, width: 1, height: 1))
    }

    @Test func fineBeatsLargeWhenBothHeld() {
        var e = makeEditor()
        e.handleArrow(.right, modifiers: [.fine, .large])
        #expect(e.rect.width == 251)
    }

    @Test func resizeNeverShrinksBelowOnePoint() {
        var e = makeEditor()
        for _ in 0..<100 { e.handleArrow(.left, modifiers: []); e.handleArrow(.up, modifiers: []) }
        #expect(e.rect.size == CGSize(width: 1, height: 1))
        e.handleArrow(.left, modifiers: [.fine])
        #expect(e.rect.size == CGSize(width: 1, height: 1))
    }

    @Test func resizeClampsToBoundsAndKeepsOrigin() {
        var e = makeEditor(remembered: CGRect(x: 900, y: 700, width: 98, height: 98))
        e.handleArrow(.right, modifiers: [])
        e.handleArrow(.down, modifiers: [])
        #expect(e.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
        e.handleArrow(.right, modifiers: [])
        #expect(e.rect == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func moveClampsToBoundsPreservingSize() {
        var e = makeEditor(remembered: CGRect(x: 960, y: 5, width: 38, height: 40))
        e.handleArrow(.right, modifiers: [.move])   // 965 would exceed (maxX 1003) → clamp to 962
        #expect(e.rect == CGRect(x: 962, y: 5, width: 38, height: 40))
        e.handleArrow(.up, modifiers: [.move])      // 5 - 5 = 0
        e.handleArrow(.up, modifiers: [.move])      // stays at 0
        #expect(e.rect == CGRect(x: 962, y: 0, width: 38, height: 40))
        e.handleArrow(.left, modifiers: [.move, .large])
        #expect(e.rect == CGRect(x: 0, y: 0, width: 38, height: 40))
        e.handleArrow(.down, modifiers: [.move, .large])
        #expect(e.rect == CGRect(x: 0, y: 760, width: 38, height: 40))
    }

    @Test func rectAlwaysInsideBoundsAndNonEmptyAfterManyArrows() {
        var e = makeMultiEditor()
        let dirs: [ArrowDirection] = [.left, .right, .up, .down]
        let mods: [EditModifiers] = [[], [.move], [.fine], [.large], [.move, .large], [.move, .fine]]
        var seed = 12345
        for _ in 0..<2000 {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            e.handleArrow(dirs[seed % 4], modifiers: mods[(seed / 7) % mods.count])
            #expect(e.bounds.contains(e.rect))
            #expect(e.rect.width >= 1 && e.rect.height >= 1)
        }
    }
}

@Suite("SelectionEditor hit testing")
struct SelectionEditorHandleTests {
    // rect: x 375…625, y 300…500; tolerance 10
    let tol: CGFloat = 10

    @Test(arguments: [
        (CGPoint(x: 375, y: 300), SelectionHandle.topLeft),
        (CGPoint(x: 625, y: 300), .topRight),
        (CGPoint(x: 375, y: 500), .bottomLeft),
        (CGPoint(x: 625, y: 500), .bottomRight),
        (CGPoint(x: 500, y: 300), .top),
        (CGPoint(x: 500, y: 500), .bottom),
        (CGPoint(x: 375, y: 400), .left),
        (CGPoint(x: 625, y: 400), .right),
        (CGPoint(x: 500, y: 400), .move),
        (CGPoint(x: 0, y: 0), SelectionHandle.none),
        (CGPoint(x: 500, y: 100), .none),
        (CGPoint(x: 900, y: 400), .none),
    ])
    func handleAtPoint(point: CGPoint, expected: SelectionHandle) {
        #expect(makeEditor().handle(at: point, tolerance: tol) == expected)
    }

    @Test func toleranceAppliesInsideAndOutsideTheEdge() {
        let e = makeEditor()
        #expect(e.handle(at: CGPoint(x: 370, y: 400), tolerance: tol) == .left)    // outside by 5
        #expect(e.handle(at: CGPoint(x: 380, y: 400), tolerance: tol) == .left)    // inside by 5
        #expect(e.handle(at: CGPoint(x: 365, y: 400), tolerance: tol) == .left)    // exactly tolerance
        #expect(e.handle(at: CGPoint(x: 364.9, y: 400), tolerance: tol) == SelectionHandle.none)
        #expect(e.handle(at: CGPoint(x: 385, y: 400), tolerance: tol) == .left)
        #expect(e.handle(at: CGPoint(x: 385.1, y: 400), tolerance: tol) == .move)
    }

    @Test func cornersBeatEdges() {
        let e = makeEditor()
        // 4 pt right of the left edge and 4 pt below the top edge → within tolerance of both edges.
        #expect(e.handle(at: CGPoint(x: 379, y: 304), tolerance: tol) == .topLeft)
        #expect(e.handle(at: CGPoint(x: 621, y: 496), tolerance: tol) == .bottomRight)
        #expect(e.handle(at: CGPoint(x: 621, y: 304), tolerance: tol) == .topRight)
        #expect(e.handle(at: CGPoint(x: 379, y: 496), tolerance: tol) == .bottomLeft)
        // Along the edge but beyond the corner tolerance → plain edge.
        #expect(e.handle(at: CGPoint(x: 379, y: 320), tolerance: tol) == .left)
    }

    @Test func edgeHandleExtendsByToleranceBeyondTheCornerOnlyAsCorner() {
        let e = makeEditor()
        // Beyond the rect's x extent by more than tolerance while level with the top edge → none.
        #expect(e.handle(at: CGPoint(x: 360, y: 300), tolerance: tol) == SelectionHandle.none)
        // Slightly outside the corner diagonally, within tolerance on both axes → corner.
        #expect(e.handle(at: CGPoint(x: 366, y: 291), tolerance: tol) == .topLeft)
    }

    @Test func tinyRectStillHasAHandleEverywhereNearIt() {
        let e = makeEditor(remembered: CGRect(x: 100, y: 100, width: 4, height: 4))
        #expect(e.handle(at: CGPoint(x: 102, y: 102), tolerance: tol) != .none)
        #expect(e.handle(at: CGPoint(x: 100, y: 100), tolerance: tol) == .topLeft)
        #expect(e.handle(at: CGPoint(x: 104, y: 104), tolerance: tol) == .bottomRight)
    }

    @Test func zeroToleranceOnlyHitsExactEdges() {
        let e = makeEditor()
        #expect(e.handle(at: CGPoint(x: 375, y: 400), tolerance: 0) == .left)
        #expect(e.handle(at: CGPoint(x: 376, y: 400), tolerance: 0) == .move)
        #expect(e.handle(at: CGPoint(x: 374, y: 400), tolerance: 0) == SelectionHandle.none)
    }
}

@Suite("SelectionEditor dragging")
struct SelectionEditorDragTests {
    // MARK: resize via handles

    @Test func draggingBottomRightCornerResizes() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 500), forceNew: false)
        e.dragMoved(to: CGPoint(x: 700, y: 560))
        #expect(e.rect == CGRect(x: 375, y: 300, width: 325, height: 260))
        e.dragEnded(at: CGPoint(x: 700, y: 560))
        #expect(e.rect == CGRect(x: 375, y: 300, width: 325, height: 260))
    }

    @Test func draggingTopLeftCornerResizes() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 375, y: 300), forceNew: false)
        e.dragMoved(to: CGPoint(x: 335, y: 250))
        #expect(e.rect == CGRect(x: 335, y: 250, width: 290, height: 250))
    }

    @Test func draggingEdgeOnlyChangesThatAxis() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 400), forceNew: false)   // right edge
        e.dragMoved(to: CGPoint(x: 700, y: 50))                     // y movement must be ignored
        #expect(e.rect == CGRect(x: 375, y: 300, width: 325, height: 200))

        e.dragEnded(at: CGPoint(x: 700, y: 50))
        e.dragBegan(at: CGPoint(x: 500, y: 300), forceNew: false)   // top edge
        e.dragMoved(to: CGPoint(x: 900, y: 250))
        #expect(e.rect == CGRect(x: 375, y: 250, width: 325, height: 250))
    }

    @Test func draggingRightEdgePastLeftFlipsAndStaysNormalised() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 400), forceNew: false)
        e.dragMoved(to: CGPoint(x: 300, y: 400))
        #expect(e.rect == CGRect(x: 300, y: 300, width: 75, height: 200))
        // and back again, past the anchor to the right
        e.dragMoved(to: CGPoint(x: 800, y: 400))
        #expect(e.rect == CGRect(x: 375, y: 300, width: 425, height: 200))
    }

    @Test func draggingLeftEdgePastRightFlips() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 375, y: 400), forceNew: false)
        e.dragMoved(to: CGPoint(x: 700, y: 400))
        #expect(e.rect == CGRect(x: 625, y: 300, width: 75, height: 200))
    }

    @Test func draggingTopAndBottomEdgesPastEachOtherFlip() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 300), forceNew: false)   // top
        e.dragMoved(to: CGPoint(x: 500, y: 600))
        #expect(e.rect == CGRect(x: 375, y: 500, width: 250, height: 100))
        e.dragEnded(at: CGPoint(x: 500, y: 600))

        var f = makeEditor()
        f.dragBegan(at: CGPoint(x: 500, y: 500), forceNew: false)   // bottom
        f.dragMoved(to: CGPoint(x: 500, y: 100))
        #expect(f.rect == CGRect(x: 375, y: 100, width: 250, height: 200))
    }

    @Test func draggingCornerPastOppositeCornerFlipsBothAxes() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 375, y: 300), forceNew: false)   // top-left
        e.dragMoved(to: CGPoint(x: 700, y: 600))
        #expect(e.rect == CGRect(x: 625, y: 500, width: 75, height: 100))
    }

    @Test func resizeNeverCollapsesBelowOnePoint() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 500), forceNew: false)
        e.dragMoved(to: CGPoint(x: 375, y: 300))   // exactly onto the opposite corner
        #expect(e.rect.width >= 1 && e.rect.height >= 1)
        e.dragMoved(to: CGPoint(x: 375.2, y: 299.9))
        #expect(e.rect.width >= 1 && e.rect.height >= 1)
        #expect(e.bounds.contains(e.rect))
    }

    @Test func collapsedRectAtBoundsEdgeStaysInsideBounds() {
        var e = makeEditor(remembered: CGRect(x: 900, y: 700, width: 100, height: 100))
        e.dragBegan(at: CGPoint(x: 900, y: 700), forceNew: false)    // top-left; anchor is the bottom-right = bounds corner
        e.dragMoved(to: CGPoint(x: 1000, y: 800))
        #expect(e.bounds.contains(e.rect))
        #expect(e.rect.width >= 1 && e.rect.height >= 1)
        e.dragMoved(to: CGPoint(x: 5000, y: 5000))
        #expect(e.bounds.contains(e.rect))
        #expect(e.rect.width >= 1 && e.rect.height >= 1)
    }

    @Test func resizeClampsToBounds() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 500), forceNew: false)
        e.dragMoved(to: CGPoint(x: 5000, y: 5000))
        #expect(e.rect == CGRect(x: 375, y: 300, width: 625, height: 500))
        e.dragMoved(to: CGPoint(x: -5000, y: -5000))
        #expect(e.rect == CGRect(x: 0, y: 0, width: 375, height: 300))
    }

    @Test func grabbingAnEdgeOffTheLineDoesNotJump() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 630, y: 400), forceNew: false)   // 5 pt right of the right edge
        e.dragMoved(to: CGPoint(x: 630, y: 400))
        #expect(e.rect == defaultRect)
        e.dragMoved(to: CGPoint(x: 650, y: 400))
        #expect(e.rect.maxX == 645)
    }

    @Test func clickingAHandleWithoutMovingKeepsTheRect() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 625, y: 500), forceNew: false)
        e.dragEnded(at: CGPoint(x: 625, y: 500))
        #expect(e.rect == defaultRect)
    }

    // MARK: move

    @Test func dragInsideMovesPreservingSize() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: false)
        e.dragMoved(to: CGPoint(x: 540, y: 380))
        #expect(e.rect == CGRect(x: 415, y: 280, width: 250, height: 200))
        e.dragEnded(at: CGPoint(x: 540, y: 380))
        #expect(e.rect == CGRect(x: 415, y: 280, width: 250, height: 200))
    }

    @Test func moveDragClampsInsideBoundsPreservingSize() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: false)
        e.dragMoved(to: CGPoint(x: 5000, y: 5000))
        #expect(e.rect == CGRect(x: 750, y: 600, width: 250, height: 200))
        e.dragMoved(to: CGPoint(x: -5000, y: -5000))
        #expect(e.rect == CGRect(x: 0, y: 0, width: 250, height: 200))
    }

    @Test func moveDragIsRelativeToGrabPoint() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 400, y: 320), forceNew: false)
        e.dragMoved(to: CGPoint(x: 410, y: 320))
        #expect(e.rect.origin == CGPoint(x: 385, y: 300))
        // moving in steps equals moving in one go
        e.dragMoved(to: CGPoint(x: 450, y: 360))
        #expect(e.rect.origin == CGPoint(x: 425, y: 340))
    }

    @Test func moveWithoutMotionDoesNothingEvenOnRelease() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: false)
        e.dragEnded(at: CGPoint(x: 500, y: 400))
        #expect(e.rect == defaultRect)
    }

    // MARK: new selection

    @Test func dragOutsideStartsANewSelection() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 300, y: 250))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 200, height: 150))
        e.dragEnded(at: CGPoint(x: 300, y: 250))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func newSelectionDraggedUpAndLeftIsNormalised() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 300, y: 250), forceNew: false)
        e.dragMoved(to: CGPoint(x: 100, y: 100))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func newSelectionFlipsAcrossTheAnchor() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 50, y: 40))
        #expect(e.rect == CGRect(x: 50, y: 40, width: 50, height: 60))
        e.dragMoved(to: CGPoint(x: 160, y: 130))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 60, height: 30))
    }

    @Test func newSelectionIsClampedToBounds() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 5000, y: -5000))
        #expect(e.rect == CGRect(x: 100, y: 0, width: 900, height: 100))
    }

    @Test func newSelectionStartingOutsideBoundsClampsAnchor() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: -50, y: -50), forceNew: false)
        e.dragMoved(to: CGPoint(x: 100, y: 100))
        #expect(e.rect == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func straightLineDragStillHasAtLeastOnePointOfHeight() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 300, y: 100))
        #expect(e.rect.width == 200)
        #expect(e.rect.height >= 1)
        #expect(e.bounds.contains(e.rect))
    }

    @Test func forceNewStartsNewSelectionEvenOverAHandleOrInside() {
        var inside = makeEditor()
        inside.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: true)
        inside.dragMoved(to: CGPoint(x: 560, y: 450))
        #expect(inside.rect == CGRect(x: 500, y: 400, width: 60, height: 50))

        var onHandle = makeEditor()
        onHandle.dragBegan(at: CGPoint(x: 625, y: 500), forceNew: true)
        onHandle.dragMoved(to: CGPoint(x: 700, y: 560))
        #expect(onHandle.rect == CGRect(x: 625, y: 500, width: 75, height: 60))
    }

    // MARK: click without drag

    @Test func clickWithoutDragMakesSquareAroundThePoint() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragEnded(at: CGPoint(x: 100, y: 100))
        #expect(e.rect == CGRect(x: 80, y: 80, width: 40, height: 40))
    }

    @Test(arguments: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0), CGPoint(x: -2, y: 0), CGPoint(x: 0, y: 2), CGPoint(x: 1.4, y: 1.4)])
    func jitterOfUpToTwoPointsStillCountsAsAClick(delta: CGPoint) {
        var e = makeEditor()
        let start = CGPoint(x: 100, y: 100)
        let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        e.dragBegan(at: start, forceNew: false)
        e.dragMoved(to: end)
        e.dragEnded(at: end)
        #expect(e.rect == CGRect(x: 80, y: 80, width: 40, height: 40))
    }

    @Test func movingMoreThanTwoPointsIsADrag() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 103.5, y: 100))
        e.dragEnded(at: CGPoint(x: 103.5, y: 100))
        #expect(e.rect.minX == 100 && e.rect.width == 3.5)
    }

    @Test func clickSquareIsClampedInsideBoundsKeepingItsSize() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 5, y: 5), forceNew: false)
        e.dragEnded(at: CGPoint(x: 5, y: 5))
        #expect(e.rect == CGRect(x: 0, y: 0, width: 40, height: 40))

        e.dragBegan(at: CGPoint(x: 999, y: 799), forceNew: false)
        e.dragEnded(at: CGPoint(x: 999, y: 799))
        #expect(e.rect == CGRect(x: 960, y: 760, width: 40, height: 40))
    }

    @Test func forceNewClickWithoutDragMakesClickSquareToo() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: true)   // inside current rect
        e.dragEnded(at: CGPoint(x: 500, y: 400))
        #expect(e.rect == CGRect(x: 480, y: 380, width: 40, height: 40))
    }

    @Test func clickOnTheRectInteriorWithoutForceNewDoesNotReplaceIt() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 500, y: 400), forceNew: false)
        e.dragEnded(at: CGPoint(x: 500, y: 400))
        #expect(e.rect == defaultRect)
    }

    // MARK: stray events

    @Test func moveAndEndWithoutBeginAreIgnored() {
        var e = makeEditor()
        e.dragMoved(to: CGPoint(x: 10, y: 10))
        e.dragEnded(at: CGPoint(x: 10, y: 10))
        #expect(e.rect == defaultRect)
    }

    @Test func eventsAfterEndAreIgnored() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragMoved(to: CGPoint(x: 300, y: 250))
        e.dragEnded(at: CGPoint(x: 300, y: 250))
        e.dragMoved(to: CGPoint(x: 900, y: 700))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func dragEndedAppliesTheFinalPosition() {
        var e = makeEditor()
        e.dragBegan(at: CGPoint(x: 100, y: 100), forceNew: false)
        e.dragEnded(at: CGPoint(x: 300, y: 250))
        #expect(e.rect == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    // MARK: across displays

    @Test func dragSpansAcrossDisplays() {
        var e = makeMultiEditor()
        e.dragBegan(at: CGPoint(x: -100, y: 100), forceNew: true)
        e.dragMoved(to: CGPoint(x: 200, y: 400))
        #expect(e.rect == CGRect(x: -100, y: 100, width: 300, height: 300))
    }

    // MARK: invariants

    @Test func rectStaysNonEmptyAndInsideBoundsUnderRandomDrags() {
        var e = makeMultiEditor()
        let slackBounds = e.bounds.insetBy(dx: -1e-6, dy: -1e-6)   // origin + size arithmetic can be an ulp off
        var seed = 987654321
        func next(_ range: ClosedRange<CGFloat>) -> CGFloat {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return range.lowerBound + CGFloat(seed % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
        }
        for _ in 0..<500 {
            let start = CGPoint(x: next(-2200...1700), y: next(-100...1300))
            e.dragBegan(at: start, forceNew: next(0...1) > 0.8)
            for _ in 0..<5 {
                let to = CGPoint(x: next(-2200...1700), y: next(-100...1300))
                e.dragMoved(to: to)
                #expect(slackBounds.contains(e.rect))
                #expect(e.rect.width >= 1 && e.rect.height >= 1)
            }
            e.dragEnded(at: CGPoint(x: next(-2200...1700), y: next(-100...1300)))
            #expect(slackBounds.contains(e.rect))
            #expect(e.rect.width >= 1 && e.rect.height >= 1)
        }
    }
}
