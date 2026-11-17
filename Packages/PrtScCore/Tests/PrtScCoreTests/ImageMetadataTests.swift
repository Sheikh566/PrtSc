import CoreGraphics
import Testing
@testable import PrtScCore

@Suite("ImageMetadata")
struct ImageMetadataTests {
    @Test(arguments: [(1.0, 72.0), (2.0, 144.0), (3.0, 216.0), (1.5, 108.0)] as [(Double, Double)])
    func dpiIs72TimesScale(scale: Double, expected: Double) {
        #expect(ImageMetadata.dpi(forScale: CGFloat(scale)) == CGFloat(expected))
    }

    @Test(arguments: [0.0, -1.0, .nan] as [Double])
    func nonPositiveOrInvalidScaleFallsBackTo72(scale: Double) {
        #expect(ImageMetadata.dpi(forScale: CGFloat(scale)) == 72)
    }
}
