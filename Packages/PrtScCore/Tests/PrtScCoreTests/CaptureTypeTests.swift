import Foundation
import Testing
@testable import PrtScCore

@Suite("CaptureType")
struct CaptureTypeTests {
    @Test func allCasesAreScreenshotThenScreencast() {
        #expect(CaptureType.allCases == [.screenshot, .screencast])
    }

    @Test func toggledFlipsBetweenTheTwoTypes() {
        #expect(CaptureType.screenshot.toggled == .screencast)
        #expect(CaptureType.screencast.toggled == .screenshot)
    }

    @Test(arguments: ["v", "V"] as [Character])
    func vTogglesTheCurrentType(character: Character) {
        #expect(CaptureType.forKey(character, from: .screenshot) == .screencast)
        #expect(CaptureType.forKey(character, from: .screencast) == .screenshot)
    }

    @Test(arguments: ["s", "c", "w", "p", "r", "x", "1", " ", "\n", "é"] as [Character])
    func otherCharactersAreNotTheToggleKey(character: Character) {
        #expect(CaptureType.forKey(character, from: .screenshot) == nil)
        #expect(CaptureType.forKey(character, from: .screencast) == nil)
    }

    @Test func codableUsesRawValue() throws {
        let data = try JSONEncoder().encode([CaptureType.screencast])
        #expect(String(decoding: data, as: UTF8.self) == "[\"screencast\"]")
        #expect(try JSONDecoder().decode([CaptureType].self, from: data) == [.screencast])
    }
}
