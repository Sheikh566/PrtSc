import CoreGraphics
import Testing
@testable import PrtScCore

@Suite("DirectionalNavigation")
struct DirectionalNavigationTests {
    // Two displays side by side plus one above the left one.
    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    let above = CGRect(x: 0, y: -800, width: 1000, height: 800)

    func candidates() -> [(String, CGRect)] { [("left", left), ("right", right), ("above", above)] }

    @Test func movesToTheNeighbourInEachDirection() {
        #expect(DirectionalNavigation.nearest(from: left, in: candidates(), direction: .right) == "right")
        #expect(DirectionalNavigation.nearest(from: right, in: candidates(), direction: .left) == "left")
        #expect(DirectionalNavigation.nearest(from: left, in: candidates(), direction: .up) == "above")
        #expect(DirectionalNavigation.nearest(from: above, in: candidates(), direction: .down) == "left")
    }

    @Test func returnsNilWhenNothingLiesThatWay() {
        #expect(DirectionalNavigation.nearest(from: left, in: candidates(), direction: .left) == nil)
        #expect(DirectionalNavigation.nearest(from: left, in: candidates(), direction: .down) == nil)
        #expect(DirectionalNavigation.nearest(from: right, in: candidates(), direction: .right) == nil)
    }

    @Test func currentRectNeverQualifiesForItself() {
        let only: [(Int, CGRect)] = [(1, left)]
        for direction in [ArrowDirection.left, .right, .up, .down] {
            #expect(DirectionalNavigation.nearest(from: left, in: only, direction: direction) == nil)
        }
    }

    @Test func emptyCandidatesGiveNil() {
        let none: [(Int, CGRect)] = []
        #expect(DirectionalNavigation.nearest(from: left, in: none, direction: .right) == nil)
    }

    @Test func alignedNeighbourBeatsNearerDiagonalOne() {
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)       // centre (50, 50)
        let diagonal = CGRect(x: 150, y: 300, width: 100, height: 100)  // along 150, across 300 → 750
        let aligned = CGRect(x: 600, y: 0, width: 100, height: 100)     // along 600, across 0 → 600
        let result = DirectionalNavigation.nearest(from: current, in: [("diagonal", diagonal), ("aligned", aligned)],
                                                   direction: .right)
        #expect(result == "aligned")
    }

    @Test func nearerOfTwoAlignedCandidatesWins() {
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)
        let near = CGRect(x: 200, y: 0, width: 100, height: 100)
        let far = CGRect(x: 500, y: 0, width: 100, height: 100)
        #expect(DirectionalNavigation.nearest(from: current, in: [("far", far), ("near", near)], direction: .right) == "near")
    }

    @Test func scoreTiesGoToTheEarlierCandidate() {
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)
        let above = CGRect(x: 200, y: -100, width: 100, height: 100)
        let below = CGRect(x: 200, y: 100, width: 100, height: 100)
        #expect(DirectionalNavigation.nearest(from: current, in: [("below", below), ("above", above)], direction: .right) == "below")
        #expect(DirectionalNavigation.nearest(from: current, in: [("above", above), ("below", below)], direction: .right) == "above")
    }

    @Test func candidatesLessThanOnePointAwayAreIgnored() {
        let current = CGRect(x: 0, y: 0, width: 100, height: 100)
        let almostSame = CGRect(x: 1, y: 0, width: 100, height: 100)
        #expect(DirectionalNavigation.nearest(from: current, in: [("same", almostSame)], direction: .right) == nil)
    }
}

@Suite("WindowOrdering")
struct WindowOrderingTests {
    struct W: Equatable { var id: UInt32 }

    @Test func sortsByZOrderFrontToBack() {
        let windows = [W(id: 1), W(id: 2), W(id: 3)]
        let z: [UInt32: Int] = [1: 2, 2: 0, 3: 1]
        #expect(WindowOrdering.frontToBack(windows, windowID: \.id, zOrder: z).map(\.id) == [2, 3, 1])
    }

    @Test func unknownWindowsGoLastInInputOrder() {
        let windows = [W(id: 9), W(id: 1), W(id: 8), W(id: 2)]
        let z: [UInt32: Int] = [1: 5, 2: 3]
        #expect(WindowOrdering.frontToBack(windows, windowID: \.id, zOrder: z).map(\.id) == [2, 1, 9, 8])
    }

    @Test func emptyZOrderKeepsInputOrder() {
        let windows = [W(id: 3), W(id: 1), W(id: 2)]
        #expect(WindowOrdering.frontToBack(windows, windowID: \.id, zOrder: [:]).map(\.id) == [3, 1, 2])
    }

    @Test func equalKnownRanksKeepInputOrder() {
        // Input order (7, 3, 5) differs from window-ID order (3, 5, 7); all three share rank 4.
        let windows = [W(id: 7), W(id: 3), W(id: 5)]
        let z: [UInt32: Int] = [7: 4, 3: 4, 5: 4]
        #expect(WindowOrdering.frontToBack(windows, windowID: \.id, zOrder: z).map(\.id) == [7, 3, 5])
    }

    @Test func equalKnownRanksKeepInputOrderAmongOtherRanks() {
        let windows = [W(id: 9), W(id: 6), W(id: 2), W(id: 8), W(id: 4)]
        let z: [UInt32: Int] = [9: 1, 6: 0, 2: 1, 4: 1]
        // 6 is front-most; 9, 2, 4 tie at rank 1 and keep input order; unknown 8 goes last.
        #expect(WindowOrdering.frontToBack(windows, windowID: \.id, zOrder: z).map(\.id) == [6, 9, 2, 4, 8])
    }

    @Test func emptyInput() {
        #expect(WindowOrdering.frontToBack([W](), windowID: \.id, zOrder: [1: 0]).isEmpty)
    }
}
