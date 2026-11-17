import Foundation
import Testing
@testable import PrtScCore

@Suite("CaptureMode")
struct CaptureModeTests {
    @Test(arguments: [
        ("s", CaptureMode.selection), ("S", .selection),
        ("c", .screen), ("C", .screen),
        ("w", .window), ("W", .window),
    ] as [(Character, CaptureMode)])
    func forKeyMapsLetters(character: Character, expected: CaptureMode) {
        #expect(CaptureMode.forKey(character) == expected)
    }

    @Test(arguments: ["x", "P", "1", " ", "\n", "é", "ß"] as [Character])
    func forKeyReturnsNilForOtherCharacters(character: Character) {
        #expect(CaptureMode.forKey(character) == nil)
    }

    @Test func codableUsesRawValue() throws {
        let data = try JSONEncoder().encode([CaptureMode.window])
        #expect(String(decoding: data, as: UTF8.self) == "[\"window\"]")
        #expect(try JSONDecoder().decode([CaptureMode].self, from: data) == [.window])
    }

    @Test func allCasesAreSelectionScreenWindow() {
        #expect(CaptureMode.allCases == [.selection, .screen, .window])
    }
}
