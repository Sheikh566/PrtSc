import CoreGraphics
import Foundation
import Testing
@testable import PrtScCore

@Suite("RecordingGeometry")
struct RecordingGeometryTests {
    let retina = DisplayInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2, isPrimary: true)
    /// A 1× display to the left of the main one (negative global x).
    let left = DisplayInfo(displayID: 2, frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080), scale: 1, isPrimary: false)

    // MARK: pixel size

    @Test(arguments: [
        (1512.0, 2.0, 3024), (982.0, 2.0, 1964), (1920.0, 1.0, 1920), (101.0, 1.0, 100), (100.5, 1.0, 100),
        (99.9, 1.0, 98), (1.0, 1.0, 2), (0.2, 1.0, 2), (0.0, 2.0, 2), (401.0, 2.0, 802),
    ] as [(CGFloat, CGFloat, Int)])
    func evenPixelCountFloorsToEvenWithAMinimumOfTwo(points: CGFloat, scale: CGFloat, expected: Int) {
        #expect(RecordingGeometry.pixelSize(for: CGSize(width: points, height: 10), scale: scale).width == expected)
    }

    @Test func pixelSizeUsesTheScaleOnBothAxes() {
        let size = RecordingGeometry.pixelSize(for: CGSize(width: 1512, height: 982), scale: 2)
        #expect(size.width == 3024 && size.height == 1964)
    }

    @Test func pixelSizeTreatsBadScaleAsOne() {
        #expect(RecordingGeometry.pixelSize(for: CGSize(width: 100, height: 50), scale: 0).width == 100)
        #expect(RecordingGeometry.pixelSize(for: CGSize(width: 100, height: 50), scale: -2).height == 50)
        #expect(RecordingGeometry.pixelSize(for: CGSize(width: 100, height: 50), scale: .nan).width == 100)
    }

    // MARK: region

    @Test func wholeDisplaySelectionCoversTheDisplay() throws {
        let region = try #require(RecordingGeometry.region(for: retina.frame, on: retina))
        #expect(region.sourceRect == CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(region.pixelWidth == 3024 && region.pixelHeight == 1964)
    }

    @Test func sourceRectIsDisplayLocal() throws {
        let selection = CGRect(x: -1500, y: 300, width: 400, height: 200)
        let region = try #require(RecordingGeometry.region(for: selection, on: left))
        #expect(region.sourceRect == CGRect(x: 420, y: 200, width: 400, height: 200))
        #expect(region.pixelWidth == 400 && region.pixelHeight == 200)
    }

    @Test func oddSizesShrinkToEvenPixelCounts() throws {
        let selection = CGRect(x: 10, y: 20, width: 101, height: 51)
        let region = try #require(RecordingGeometry.region(for: selection, on: left.moved(toOrigin: .zero)))
        #expect(region.pixelWidth == 100 && region.pixelHeight == 50)
        #expect(region.sourceRect.size == CGSize(width: 100, height: 50))
    }

    @Test func retinaRegionIsSnappedToWholePixels() throws {
        // 100.25 x 50.25 pt at 2× = 200.5 x 100.5 px → origin and edges rounded to the pixel grid, size even.
        let selection = CGRect(x: 10.25, y: 20.25, width: 100.25, height: 50.25)
        let region = try #require(RecordingGeometry.region(for: selection, on: retina))
        #expect(region.pixelWidth % 2 == 0 && region.pixelHeight % 2 == 0)
        #expect(region.sourceRect.width * 2 == CGFloat(region.pixelWidth))
        #expect(region.sourceRect.height * 2 == CGFloat(region.pixelHeight))
        #expect((region.sourceRect.minX * 2).rounded() == region.sourceRect.minX * 2)
        #expect((region.sourceRect.minY * 2).rounded() == region.sourceRect.minY * 2)
    }

    @Test func selectionSpanningDisplaysIsClampedToTheDisplay() throws {
        // Straddles the seam between `left` (x −1920…0) and the Retina display: the part on `left` is kept.
        let selection = CGRect(x: -100, y: 200, width: 300, height: 100)
        let region = try #require(RecordingGeometry.region(for: selection, on: left))
        #expect(region.sourceRect == CGRect(x: 1820, y: 100, width: 100, height: 100))
        #expect(region.pixelWidth == 100 && region.pixelHeight == 100)
    }

    @Test func selectionPastTheBottomRightIsClamped() throws {
        let selection = CGRect(x: 1500, y: 970, width: 100, height: 100)
        let region = try #require(RecordingGeometry.region(for: selection, on: retina))
        #expect(region.sourceRect == CGRect(x: 1500, y: 970, width: 12, height: 12))
        #expect(region.pixelWidth == 24 && region.pixelHeight == 24)
    }

    @Test func regionNeverLeavesTheDisplayEvenWhenEvenRoundingWouldPushItOut() throws {
        // 1 px wide sliver at the right edge of a 1× display: min size is 2 px, so it shifts left.
        let selection = CGRect(x: 1919, y: 100, width: 1, height: 1)
        let region = try #require(RecordingGeometry.region(for: selection, on: left.moved(toOrigin: .zero)))
        #expect(region.pixelWidth == 2 && region.pixelHeight == 2)
        #expect(region.sourceRect.maxX <= 1920)
        #expect(region.sourceRect.minX >= 0)
    }

    @Test func selectionOutsideTheDisplayHasNoRegion() {
        #expect(RecordingGeometry.region(for: CGRect(x: 3000, y: 0, width: 100, height: 100), on: retina) == nil)
        #expect(RecordingGeometry.region(for: .zero, on: retina) == nil)
        #expect(RecordingGeometry.region(for: .null, on: retina) == nil)
    }
}

private extension DisplayInfo {
    func moved(toOrigin origin: CGPoint) -> DisplayInfo {
        DisplayInfo(displayID: displayID, frame: CGRect(origin: origin, size: frame.size), scale: scale, isPrimary: isPrimary)
    }
}
