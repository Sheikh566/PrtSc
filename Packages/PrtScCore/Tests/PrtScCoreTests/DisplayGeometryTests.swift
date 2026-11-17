import CoreGraphics
import Testing
@testable import PrtScCore

@Suite("DisplayGeometry")
struct DisplayGeometryTests {
    // Main 2× display at the origin, a 1× display to its right and a 1× display to its left (negative x).
    let main = DisplayInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2, isPrimary: true)
    let right = DisplayInfo(displayID: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1, isPrimary: false)
    let left = DisplayInfo(displayID: 3, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080), scale: 1, isPrimary: false)
    let above = DisplayInfo(displayID: 4, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), scale: 1, isPrimary: false)

    // MARK: display(containing:)

    @Test func displayContainingPoint() {
        let all = [main, right, left]
        #expect(DisplayGeometry.display(containing: CGPoint(x: 10, y: 10), in: all)?.displayID == 1)
        #expect(DisplayGeometry.display(containing: CGPoint(x: 2000, y: 500), in: all)?.displayID == 2)
        #expect(DisplayGeometry.display(containing: CGPoint(x: -50, y: 0), in: all)?.displayID == 3)
        #expect(DisplayGeometry.display(containing: CGPoint(x: -10, y: -10), in: all)?.displayID == 3)
    }

    @Test func displayContainingUsesHalfOpenFrames() {
        // x == 1440 belongs to the right display, not the main one.
        #expect(DisplayGeometry.display(containing: CGPoint(x: 1440, y: 10), in: [main, right])?.displayID == 2)
        #expect(DisplayGeometry.display(containing: CGPoint(x: 1439.9, y: 10), in: [main, right])?.displayID == 1)
        #expect(DisplayGeometry.display(containing: CGPoint(x: 0, y: 0), in: [main])?.displayID == 1)
    }

    @Test func displayContainingNilWhenOutsideOrEmpty() {
        #expect(DisplayGeometry.display(containing: CGPoint(x: 5000, y: 5000), in: [main, right]) == nil)
        #expect(DisplayGeometry.display(containing: .zero, in: []) == nil)
    }

    // MARK: panelDisplay

    @Test func panelDisplayPrefersPointerDisplay() {
        #expect(DisplayGeometry.panelDisplay(pointer: CGPoint(x: 2000, y: 10), displays: [main, right])?.displayID == 2)
    }

    @Test func panelDisplayFallsBackToPrimary() {
        #expect(DisplayGeometry.panelDisplay(pointer: CGPoint(x: 9999, y: 9999), displays: [right, main])?.displayID == 1)
    }

    @Test func panelDisplayFallsBackToFirstWhenNoPrimary() {
        #expect(DisplayGeometry.panelDisplay(pointer: CGPoint(x: 9999, y: 9999), displays: [right, left])?.displayID == 2)
    }

    @Test func panelDisplayNilWhenNoDisplays() {
        #expect(DisplayGeometry.panelDisplay(pointer: .zero, displays: []) == nil)
    }

    // MARK: union

    @Test func unionOfDisplaysWithNegativeOrigins() {
        let u = DisplayGeometry.union(of: [main, right, left, above])
        #expect(u == CGRect(x: -1920, y: -1080, width: 1920 + 1440 + 1920, height: 1080 + 1080))
    }

    @Test func unionOfOneAndNone() {
        #expect(DisplayGeometry.union(of: [right]) == right.frame)
        #expect(DisplayGeometry.union(of: []) == .zero)
    }

    @Test func unionDoesNotIncludeTheOriginImplicitly() {
        let far = DisplayInfo(displayID: 9, frame: CGRect(x: 5000, y: 5000, width: 100, height: 100), scale: 1, isPrimary: true)
        #expect(DisplayGeometry.union(of: [far]) == far.frame)
    }

    // MARK: outputScale

    @Test func outputScaleIsMaxOfIntersectedDisplays() {
        let all = [main, right, left]
        #expect(DisplayGeometry.outputScale(for: CGRect(x: 100, y: 100, width: 200, height: 200), displays: all) == 2)
        #expect(DisplayGeometry.outputScale(for: CGRect(x: 2000, y: 100, width: 200, height: 200), displays: all) == 1)
        #expect(DisplayGeometry.outputScale(for: CGRect(x: 1400, y: 100, width: 100, height: 100), displays: all) == 2)
        #expect(DisplayGeometry.outputScale(for: CGRect(x: -100, y: 100, width: 150, height: 100), displays: all) == 2)
    }

    @Test func outputScaleIgnoresDisplaysOnlyTouchingTheRect() {
        // Rect ends exactly at x = 1440; it only touches the 1× display on the right.
        let r = CGRect(x: 1340, y: 10, width: 100, height: 100)
        #expect(DisplayGeometry.outputScale(for: r, displays: [right, main]) == 2)
        let onlyTouching = CGRect(x: 1440 - 100, y: 10, width: 100, height: 100)
        #expect(DisplayGeometry.outputScale(for: onlyTouching, displays: [right]) != 0)
        let touchingRightOnly = CGRect(x: 3360, y: 10, width: 100, height: 100) // starts at right.maxX
        #expect(DisplayGeometry.outputScale(for: touchingRightOnly, displays: [main, right]) == 2) // fallback: primary
    }

    @Test func outputScaleFallbacks() {
        let outside = CGRect(x: 9000, y: 9000, width: 10, height: 10)
        #expect(DisplayGeometry.outputScale(for: outside, displays: [right, main]) == 2)   // primary
        #expect(DisplayGeometry.outputScale(for: outside, displays: [right, left]) == 1)   // first
        #expect(DisplayGeometry.outputScale(for: outside, displays: []) == 1)
    }

    // MARK: segments

    @Test func singleDisplaySegment() {
        let rect = CGRect(x: 100, y: 50, width: 300, height: 200)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs == [DisplaySegment(displayID: 1,
                                        sourcePixelRect: CGRect(x: 200, y: 100, width: 600, height: 400),
                                        destinationPixelRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                        drawPixelRect: CGRect(x: 0, y: 0, width: 600, height: 400))])
    }

    @Test func singleOneXDisplaySegment() {
        let rect = CGRect(x: 1540, y: 50, width: 300, height: 200)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs == [DisplaySegment(displayID: 2,
                                        sourcePixelRect: CGRect(x: 100, y: 50, width: 300, height: 200),
                                        destinationPixelRect: CGRect(x: 0, y: 0, width: 300, height: 200),
                                        drawPixelRect: CGRect(x: 0, y: 0, width: 300, height: 200))])
    }

    @Test func selectionSpanningRetinaAndNonRetinaDisplays() {
        // 200 pt wide: 100 pt on the 2× main display (right edge), 100 pt on the 1× display. Output at 2×.
        let rect = CGRect(x: 1340, y: 100, width: 200, height: 150)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs.count == 2)
        #expect(segs[0] == DisplaySegment(displayID: 1,
                                          sourcePixelRect: CGRect(x: 2680, y: 200, width: 200, height: 300),
                                          destinationPixelRect: CGRect(x: 0, y: 0, width: 200, height: 300),
                                          drawPixelRect: CGRect(x: 0, y: 0, width: 200, height: 300)))
        #expect(segs[1] == DisplaySegment(displayID: 2,
                                          sourcePixelRect: CGRect(x: 0, y: 100, width: 100, height: 150),
                                          destinationPixelRect: CGRect(x: 200, y: 0, width: 200, height: 300),
                                          drawPixelRect: CGRect(x: 200, y: 0, width: 200, height: 300)))
        // Output pixel size is rect.size × 2.
        #expect(DisplayGeometry.outputPixelSize(for: rect, scale: DisplayGeometry.outputScale(for: rect, displays: [main, right]))
                == CGSize(width: 400, height: 300))
    }

    @Test func selectionSpanningNegativeOriginDisplay() {
        // left display: x -1920..0, y -180..900 (scale 1). Rect -100..100 × 100..300.
        let rect = CGRect(x: -100, y: 100, width: 200, height: 200)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, left])
        #expect(segs.count == 2)
        let l = segs.first { $0.displayID == 3 }!
        let m = segs.first { $0.displayID == 1 }!
        #expect(l.sourcePixelRect == CGRect(x: 1820, y: 280, width: 100, height: 200))
        #expect(l.destinationPixelRect == CGRect(x: 0, y: 0, width: 200, height: 400))
        #expect(m.sourcePixelRect == CGRect(x: 0, y: 200, width: 200, height: 400))
        #expect(m.destinationPixelRect == CGRect(x: 200, y: 0, width: 200, height: 400))
    }

    @Test func selectionSpanningDisplayAboveMain() {
        let rect = CGRect(x: 100, y: -50, width: 100, height: 100)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, above])
        let a = segs.first { $0.displayID == 4 }!
        let m = segs.first { $0.displayID == 1 }!
        #expect(a.sourcePixelRect == CGRect(x: 100, y: 1030, width: 100, height: 50))
        #expect(a.destinationPixelRect == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(m.sourcePixelRect == CGRect(x: 200, y: 0, width: 200, height: 100))
        #expect(m.destinationPixelRect == CGRect(x: 0, y: 100, width: 200, height: 100))
    }

    @Test func segmentsAtOneXOutputWhenAllDisplaysAre1x() {
        let rect = CGRect(x: 1840, y: 0, width: 200, height: 100)
        let a = DisplayInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1, isPrimary: true)
        let b = DisplayInfo(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), scale: 1, isPrimary: false)
        let segs = DisplayGeometry.segments(for: rect, displays: [a, b])
        #expect(segs.map(\.destinationPixelRect) == [CGRect(x: 0, y: 0, width: 80, height: 100),
                                                     CGRect(x: 80, y: 0, width: 120, height: 100)])
    }

    @Test func fractionalRectRoundsPlacementAndTilesDestinationWithoutGaps() {
        let rect = CGRect(x: 1439.25, y: 10.25, width: 10.5, height: 10.5)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs.count == 2)
        for s in segs {
            for r in [s.sourcePixelRect, s.destinationPixelRect] {
                #expect(r.minX == r.minX.rounded() && r.maxX == r.maxX.rounded())
                #expect(r.minY == r.minY.rounded() && r.maxY == r.maxY.rounded())
            }
        }
        // Source (main, 2×): x from 1439.25*2 = 2878.5 → 2878, to 2880 (display edge).
        let m = segs.first { $0.displayID == 1 }!
        #expect(m.sourcePixelRect.minX == 2878)
        #expect(m.sourcePixelRect.maxX == 2880)
        #expect(m.sourcePixelRect.minY == 21)       // 10.25 * 2 = 20.5 → rounded to 21; 21 rows, no stretch
        #expect(m.sourcePixelRect.maxY == 42)
        // Destination tiles: no gap or overlap, covering the whole output (21 × 21).
        let r = segs.first { $0.displayID == 2 }!
        #expect(m.destinationPixelRect.maxX == r.destinationPixelRect.minX)
        #expect(m.destinationPixelRect.minX == 0)
        #expect(r.destinationPixelRect.maxX == 21)
        #expect(m.destinationPixelRect.height == 21)
    }

    @Test func sourceRectsStayInsideDisplayImages() {
        let rects = [CGRect(x: -0.4, y: -0.4, width: 5, height: 5), CGRect(x: 1438.7, y: 898.6, width: 3.3, height: 3.3)]
        for rect in rects {
            for s in DisplayGeometry.segments(for: rect, displays: [main, right]) {
                let d = [main, right].first { $0.displayID == s.displayID }!
                let bounds = CGRect(x: 0, y: 0, width: d.frame.width * d.scale, height: d.frame.height * d.scale)
                #expect(bounds.contains(s.sourcePixelRect))
            }
        }
    }

    @Test func rectInGapBetweenDisplaysYieldsOnlyIntersectingParts() {
        // main is 900 tall, right is 1080 tall: the strip below main at x < 1440 belongs to no display.
        let rect = CGRect(x: 1400, y: 1000, width: 100, height: 50)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs.map(\.displayID) == [2])
        #expect(segs[0].destinationPixelRect == CGRect(x: 40, y: 0, width: 60, height: 50))
    }

    @Test func rectOutsideAllDisplaysHasNoSegments() {
        #expect(DisplayGeometry.segments(for: CGRect(x: 9000, y: 9000, width: 10, height: 10), displays: [main]).isEmpty)
    }

    @Test func emptyRectOrNoDisplaysHasNoSegments() {
        #expect(DisplayGeometry.segments(for: .zero, displays: [main]).isEmpty)
        #expect(DisplayGeometry.segments(for: CGRect(x: 0, y: 0, width: 0, height: 10), displays: [main]).isEmpty)
        #expect(DisplayGeometry.segments(for: CGRect(x: 0, y: 0, width: 10, height: 10), displays: []).isEmpty)
    }

    @Test func wholeDisplaySegmentCoversItsEntireImage() {
        let segs = DisplayGeometry.segments(for: main.frame, displays: [main, right])
        #expect(segs == [DisplaySegment(displayID: 1,
                                        sourcePixelRect: CGRect(x: 0, y: 0, width: 2880, height: 1800),
                                        destinationPixelRect: CGRect(x: 0, y: 0, width: 2880, height: 1800),
                                        drawPixelRect: CGRect(x: 0, y: 0, width: 2880, height: 1800))])
    }

    @Test func outputPixelSizeRoundsRectTimesScale() {
        #expect(DisplayGeometry.outputPixelSize(for: CGRect(x: 0, y: 0, width: 10.4, height: 10.6), scale: 2)
                == CGSize(width: 21, height: 21))
        #expect(DisplayGeometry.outputPixelSize(for: CGRect(x: 5, y: 5, width: 640, height: 480), scale: 1)
                == CGSize(width: 640, height: 480))
    }

    // MARK: stitching without resampling

    /// Two 1× displays side by side, like a pair of external monitors.
    let oneXLeft = DisplayInfo(displayID: 11, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1, isPrimary: true)
    let oneXRight = DisplayInfo(displayID: 12, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), scale: 1, isPrimary: false)

    @Test func fractionalOriginAcrossTwoOneXDisplaysMapsEverySourcePixelOneToOne() {
        // y = 337.5, height 225: the old outward-rounded crop was 226 rows squeezed into 225.
        let rect = CGRect(x: 1900, y: 337.5, width: 40, height: 225)
        let segs = DisplayGeometry.segments(for: rect, displays: [oneXLeft, oneXRight])
        #expect(segs.count == 2)
        for s in segs {
            #expect(s.sourcePixelRect.height == 225)
            #expect(s.sourcePixelRect.size == s.destinationPixelRect.size)
            #expect(s.drawPixelRect == s.destinationPixelRect)
        }
        // 337.5 rounds to row 338 on both displays, so the two halves stay vertically aligned.
        #expect(segs.map(\.sourcePixelRect.minY) == [338, 338])
        #expect(segs[0].sourcePixelRect == CGRect(x: 1900, y: 338, width: 20, height: 225))
        #expect(segs[1].sourcePixelRect == CGRect(x: 0, y: 338, width: 20, height: 225))
        #expect(segs[0].destinationPixelRect == CGRect(x: 0, y: 0, width: 20, height: 225))
        #expect(segs[1].destinationPixelRect == CGRect(x: 20, y: 0, width: 20, height: 225))
    }

    @Test func fractionalOriginOnASingleOneXDisplayKeepsTheRequestedPixelCount() {
        let rect = CGRect(x: 100.5, y: 337.5, width: 300, height: 225)
        let segs = DisplayGeometry.segments(for: rect, displays: [oneXLeft])
        #expect(segs.count == 1)
        #expect(segs[0].sourcePixelRect.size == CGSize(width: 300, height: 225))
        #expect(segs[0].destinationPixelRect == CGRect(x: 0, y: 0, width: 300, height: 225))
        #expect(segs[0].drawPixelRect == segs[0].destinationPixelRect)
    }

    @Test func fractionalOriginReachingTheDisplayEdgeDoesNotLeaveAGap() {
        // Output is 743 rows (742.5 rounded up) but the display only has 742 rows below the rounded
        // start: the placement shifts by a pixel instead of leaving a transparent row.
        let rect = CGRect(x: 10, y: 337.5, width: 100, height: 742.5)
        let segs = DisplayGeometry.segments(for: rect, displays: [oneXLeft])
        #expect(segs.count == 1)
        #expect(segs[0].destinationPixelRect.height == 743)
        #expect(segs[0].sourcePixelRect.maxY <= 1080)
        #expect(segs[0].sourcePixelRect.height == 743)
    }

    @Test func fractionalOriginAcrossRetinaAndOneXKeepsNativePixelsAndScalesTheOneXPartExactly() {
        // main is 2×, right is 1×: the output is 2×. The Retina part is copied 1:1; the 1× part is
        // drawn at exactly 2× (an integer factor), and the odd source row is clipped, not stretched.
        let rect = CGRect(x: 1400, y: 337.5, width: 80, height: 225)
        let segs = DisplayGeometry.segments(for: rect, displays: [main, right])
        #expect(segs.count == 2)
        let m = segs[0]
        let r = segs[1]
        #expect(m.displayID == 1)
        #expect(m.sourcePixelRect.size == m.destinationPixelRect.size)
        #expect(m.drawPixelRect == m.destinationPixelRect)
        #expect(m.destinationPixelRect.height == 450)
        #expect(r.displayID == 2)
        #expect(r.drawPixelRect.width == r.sourcePixelRect.width * 2)
        #expect(r.drawPixelRect.height == r.sourcePixelRect.height * 2)
        #expect(r.drawPixelRect.contains(r.destinationPixelRect))
        // Never more than one source pixel of surplus per side (it is clipped).
        #expect(r.drawPixelRect.width - r.destinationPixelRect.width <= 2)
        #expect(r.drawPixelRect.height - r.destinationPixelRect.height <= 2)
        // The two pieces still tile the 160 × 450 canvas.
        #expect(m.destinationPixelRect.maxX == r.destinationPixelRect.minX)
        #expect(r.destinationPixelRect.maxX == 160)
    }

    @Test func placementInvariantsHoldForFractionalOrigins() {
        let all = [main, right, left, above]
        let rects = [
            CGRect(x: 1439.75, y: 337.5, width: 33.25, height: 225.5),
            CGRect(x: -0.5, y: -0.5, width: 20.25, height: 20.25),
            CGRect(x: -60.25, y: 100.75, width: 120.5, height: 90.5),
            CGRect(x: 1350.5, y: 0.25, width: 180, height: 120),
            CGRect(x: 10.125, y: -40.375, width: 50.75, height: 80.5),
        ]
        for rect in rects {
            let scale = DisplayGeometry.outputScale(for: rect, displays: all)
            let canvas = DisplayGeometry.outputPixelSize(for: rect, scale: scale)
            for s in DisplayGeometry.segments(for: rect, displays: all) {
                let d = all.first { $0.displayID == s.displayID }!
                let ratio = scale / d.scale
                let image = CGRect(x: 0, y: 0, width: d.frame.width * d.scale, height: d.frame.height * d.scale)
                for r in [s.sourcePixelRect, s.destinationPixelRect] {
                    #expect(r == r.integral)
                }
                #expect(image.contains(s.sourcePixelRect))
                #expect(CGRect(origin: .zero, size: canvas).contains(s.destinationPixelRect))
                // Exact scale from source to draw: no stretch from rounding.
                #expect(abs(s.drawPixelRect.width - s.sourcePixelRect.width * ratio) < 1e-9)
                #expect(abs(s.drawPixelRect.height - s.sourcePixelRect.height * ratio) < 1e-9)
                #expect(s.drawPixelRect.insetBy(dx: -1e-9, dy: -1e-9).contains(s.destinationPixelRect))
                if ratio == 1 {
                    #expect(s.sourcePixelRect.size == s.destinationPixelRect.size)
                }
            }
        }
    }

    // MARK: window → display assignment

    @Test func windowGoesToTheDisplayWithTheLargestIntersection() {
        // 300 pt on `main`, 100 pt on `right`.
        let frame = CGRect(x: 1140, y: 100, width: 400, height: 300)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [main, right])?.displayID == 1)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [right, main])?.displayID == 1)
    }

    @Test func partlyOffScreenWindowWithCentreOutsideEveryDisplayStillGetsADisplay() {
        // Centre x = 1440 + 100 = beyond the right edge of a single display at 0..1440.
        let frame = CGRect(x: 1000, y: 100, width: 1100, height: 400)
        #expect(frame.midX > main.frame.maxX)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [main])?.displayID == 1)
    }

    @Test func windowOverAGapBetweenStaggeredDisplaysGetsTheLargerSide() {
        // main is 900 tall, right 1080 tall; the window's centre (y = 950) is below main but on right.
        let frame = CGRect(x: 1340, y: 800, width: 200, height: 300)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [main, right])?.displayID == 2)
    }

    @Test func equalIntersectionsGoToTheLowestDisplayID() {
        let a = DisplayInfo(displayID: 20, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1, isPrimary: true)
        let b = DisplayInfo(displayID: 5, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 1, isPrimary: false)
        let frame = CGRect(x: 50, y: 10, width: 100, height: 50)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [a, b])?.displayID == 5)
        #expect(DisplayGeometry.displayShowingMost(of: frame, displays: [b, a])?.displayID == 5)
    }

    @Test func windowOutsideEveryDisplayHasNoDisplay() {
        #expect(DisplayGeometry.displayShowingMost(of: CGRect(x: 9000, y: 9000, width: 10, height: 10), displays: [main]) == nil)
        // Touching an edge is not an intersection.
        #expect(DisplayGeometry.displayShowingMost(of: CGRect(x: 1440, y: 0, width: 50, height: 50), displays: [main]) == nil)
        #expect(DisplayGeometry.displayShowingMost(of: main.frame, displays: []) == nil)
    }
}
