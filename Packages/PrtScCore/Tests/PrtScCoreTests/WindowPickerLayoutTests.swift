import CoreGraphics
import Testing
@testable import PrtScCore

@Suite("WindowPickerLayout")
struct WindowPickerLayoutTests {
    let area = CGRect(x: 100, y: 50, width: 1000, height: 700)

    func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }

    @Test func noWindowsNoRects() {
        #expect(WindowPickerLayout.layout(sizes: [], in: area, spacing: 20).isEmpty)
    }

    @Test func singleSmallWindowIsCentredAtNaturalSize() {
        let r = WindowPickerLayout.layout(sizes: [CGSize(width: 400, height: 300)], in: area, spacing: 20)
        #expect(r == [CGRect(x: 400, y: 250, width: 400, height: 300)])
    }

    @Test func singleLargeWindowScalesDownPreservingAspect() {
        let r = WindowPickerLayout.layout(sizes: [CGSize(width: 2000, height: 1000)], in: area, spacing: 20)
        #expect(r.count == 1)
        #expect(approx(r[0].width, 1000) && approx(r[0].height, 500))
        #expect(approx(r[0].midX, area.midX) && approx(r[0].midY, area.midY))
    }

    @Test func singleTallWindowIsLimitedByHeight() {
        let r = WindowPickerLayout.layout(sizes: [CGSize(width: 500, height: 1400)], in: area, spacing: 20)
        #expect(approx(r[0].height, 700) && approx(r[0].width, 250))
    }

    @Test func neverUpscales() {
        let sizes = [CGSize(width: 50, height: 40), CGSize(width: 60, height: 30), CGSize(width: 20, height: 20)]
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 10)
        for (rect, size) in zip(r, sizes) {
            #expect(approx(rect.width, size.width) && approx(rect.height, size.height))
        }
    }

    @Test func fourWindowsFormTwoByTwoGridAtFullSize() {
        let s = CGSize(width: 400, height: 300)
        let r = WindowPickerLayout.layout(sizes: Array(repeating: s, count: 4), in: area, spacing: 10)
        #expect(r.count == 4)
        for rect in r { #expect(approx(rect.width, 400) && approx(rect.height, 300)) }
        #expect(approx(r[0].minY, r[1].minY) && approx(r[2].minY, r[3].minY))
        #expect(approx(r[2].minY - r[0].maxY, 10))
        #expect(approx(r[1].minX - r[0].maxX, 10))
        #expect(approx(r[0].minX, r[2].minX) && approx(r[1].minX, r[3].minX))
        // Whole grid centred in the area.
        let grid = r.reduce(r[0]) { $0.union($1) }
        #expect(approx(grid.midX, area.midX) && approx(grid.midY, area.midY))
    }

    @Test func wideShallowAreaPicksSingleRow() {
        let wide = CGRect(x: 0, y: 0, width: 1400, height: 320)
        let s = CGSize(width: 400, height: 300)
        let r = WindowPickerLayout.layout(sizes: Array(repeating: s, count: 3), in: wide, spacing: 20)
        #expect(Set(r.map { $0.minY.rounded() }).count == 1)
        #expect(approx(r[0].width, 400))
    }

    @Test func tallNarrowAreaPicksSingleColumn() {
        let tall = CGRect(x: 0, y: 0, width: 420, height: 1000)
        let s = CGSize(width: 400, height: 300)
        let r = WindowPickerLayout.layout(sizes: Array(repeating: s, count: 3), in: tall, spacing: 20)
        #expect(Set(r.map { $0.minX.rounded() }).count == 1)
        #expect(approx(r[0].width, 400))
    }

    @Test func incompleteLastRowIsCentred() {
        let s = CGSize(width: 400, height: 300)
        let r = WindowPickerLayout.layout(sizes: Array(repeating: s, count: 3), in: area, spacing: 10)
        #expect(approx(r[2].midX, area.midX))
        #expect(r[2].minY > r[0].maxY)
        #expect(approx(r[0].minY, r[1].minY))
    }

    @Test func resultsAreInInputOrderWithAspectPreserved() {
        let sizes = [CGSize(width: 1200, height: 800), CGSize(width: 300, height: 900), CGSize(width: 800, height: 200),
                     CGSize(width: 640, height: 480), CGSize(width: 1000, height: 1000)]
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 16)
        #expect(r.count == sizes.count)
        for (rect, size) in zip(r, sizes) {
            #expect(approx(rect.width / rect.height, size.width / size.height, 1e-6))
        }
    }

    @Test func allWindowsShareOneScale() {
        let sizes = [CGSize(width: 1200, height: 800), CGSize(width: 600, height: 400), CGSize(width: 900, height: 900)]
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 16)
        let scales = zip(r, sizes).map { $0.0.width / $0.1.width }
        #expect(scales.allSatisfy { approx($0, scales[0]) })
        #expect(scales[0] <= 1)
    }

    @Test(arguments: [2, 3, 5, 7, 9, 12])
    func rectsStayInsideAreaAndNeverOverlap(count: Int) {
        let sizes = (0..<count).map { CGSize(width: 300 + CGFloat($0 * 70), height: 200 + CGFloat(($0 * 53) % 400)) }
        let spacing: CGFloat = 12
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: spacing)
        let inside = area.insetBy(dx: -1e-6, dy: -1e-6)
        for rect in r { #expect(inside.contains(rect)) }
        for i in 0..<r.count {
            for j in (i + 1)..<r.count {
                #expect(!r[i].insetBy(dx: 1e-6, dy: 1e-6).intersects(r[j]))
            }
        }
    }

    @Test func respectsAreaOrigin() {
        let r = WindowPickerLayout.layout(sizes: [CGSize(width: 100, height: 100)],
                                          in: CGRect(x: -500, y: -300, width: 200, height: 200), spacing: 0)
        #expect(r == [CGRect(x: -450, y: -250, width: 100, height: 100)])
    }

    @Test func isDeterministic() {
        let sizes = (0..<8).map { CGSize(width: 200 + CGFloat($0 * 37), height: 150 + CGFloat($0 * 21)) }
        let a = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 14)
        let b = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 14)
        #expect(a == b)
    }

    @Test func chosenRowCountMaximisesScale() {
        // Brute force: compare against a one-row and a one-column layout; the result's scale must be >= both.
        let sizes = (0..<6).map { CGSize(width: 500 + CGFloat($0 * 40), height: 350 + CGFloat($0 * 25)) }
        let spacing: CGFloat = 10
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: spacing)
        let scale = r[0].width / sizes[0].width
        let rowScale = min(1, (area.width - spacing * 5) / sizes.map(\.width).reduce(0, +),
                           area.height / sizes.map(\.height).max()!)
        let colScale = min(1, area.width / sizes.map(\.width).max()!,
                           (area.height - spacing * 5) / sizes.map(\.height).reduce(0, +))
        #expect(scale >= rowScale - 1e-9)
        #expect(scale >= colScale - 1e-9)
    }

    @Test func zeroSizedWindowDoesNotBreakLayout() {
        let sizes = [CGSize.zero, CGSize(width: 400, height: 300), CGSize(width: 0, height: 100)]
        let r = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 10)
        #expect(r.count == 3)
        for rect in r { #expect(rect.width.isFinite && rect.height.isFinite && rect.minX.isFinite && rect.minY.isFinite) }
        #expect(approx(r[1].width, 400) && approx(r[1].height, 300))
    }

    @Test func spacingLargerThanAreaDoesNotProduceNegativeSizes() {
        let r = WindowPickerLayout.layout(sizes: Array(repeating: CGSize(width: 100, height: 100), count: 4),
                                          in: CGRect(x: 0, y: 0, width: 50, height: 50), spacing: 200)
        #expect(r.count == 4)
        for rect in r { #expect(rect.width >= 0 && rect.height >= 0) }
    }

    @Test func emptyAreaDoesNotCrash() {
        let r = WindowPickerLayout.layout(sizes: [CGSize(width: 100, height: 100)], in: .zero, spacing: 10)
        #expect(r.count == 1)
        #expect(r[0].width == 0 && r[0].height == 0)
    }
}
