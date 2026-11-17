import Foundation
import Testing
@testable import PrtScCore

@Suite("KeyCombo.displayString")
struct KeyComboDisplayTests {
    @Test(arguments: [
        (0x00, "A"), (0x01, "S"), (0x08, "C"), (0x0D, "W"), (0x06, "Z"), (0x2E, "M"),
        (0x1D, "0"), (0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"), (0x17, "5"),
        (0x16, "6"), (0x1A, "7"), (0x1C, "8"), (0x19, "9"),
    ] as [(UInt32, String)])
    func lettersAndDigits(keyCode: UInt32, expected: String) {
        #expect(KeyCombo(keyCode: keyCode, modifiers: []).displayString == expected)
    }

    @Test(arguments: [
        (0x7A, "F1"), (0x78, "F2"), (0x63, "F3"), (0x76, "F4"), (0x60, "F5"), (0x61, "F6"),
        (0x62, "F7"), (0x64, "F8"), (0x65, "F9"), (0x6D, "F10"), (0x67, "F11"), (0x6F, "F12"),
        (0x69, "F13"), (0x6B, "F14"), (0x71, "F15"), (0x6A, "F16"), (0x40, "F17"),
        (0x4F, "F18"), (0x50, "F19"), (0x5A, "F20"),
    ] as [(UInt32, String)])
    func functionKeys(keyCode: UInt32, expected: String) {
        #expect(KeyCombo(keyCode: keyCode, modifiers: []).displayString == expected)
    }

    @Test(arguments: [
        (0x7B, "←"), (0x7C, "→"), (0x7E, "↑"), (0x7D, "↓"),
        (0x24, "Return"), (0x31, "Space"), (0x35, "Esc"), (0x33, "Delete"), (0x30, "Tab"),
    ] as [(UInt32, String)])
    func namedKeys(keyCode: UInt32, expected: String) {
        #expect(KeyCombo(keyCode: keyCode, modifiers: []).displayString == expected)
    }

    @Test func modifiersUseAppleOrder() {
        let all: KeyModifiers = [.command, .shift, .option, .control]
        #expect(KeyCombo(keyCode: 0x13, modifiers: all).displayString == "⌃⌥⇧⌘2")
        #expect(KeyCombo(keyCode: 0x13, modifiers: [.command, .shift]).displayString == "⇧⌘2")
        #expect(KeyCombo(keyCode: 0x13, modifiers: [.control, .command, .shift]).displayString == "⌃⇧⌘2")
        #expect(KeyCombo(keyCode: 0x13, modifiers: [.option, .command, .shift]).displayString == "⌥⇧⌘2")
        #expect(KeyCombo(keyCode: 0x69, modifiers: [.shift]).displayString == "⇧F13")
        #expect(KeyCombo(keyCode: 0x69, modifiers: [.option]).displayString == "⌥F13")
        #expect(KeyCombo(keyCode: 0x00, modifiers: [.control]).displayString == "⌃A")
        #expect(KeyCombo(keyCode: 0x31, modifiers: [.command]).displayString == "⌘Space")
    }

    @Test func modifierOrderIndependentOfInsertionOrder() {
        let a = KeyCombo(keyCode: 0x13, modifiers: [.command, .control])
        let b = KeyCombo(keyCode: 0x13, modifiers: [.control, .command])
        #expect(a.displayString == b.displayString)
    }

    @Test func unknownKeyCodeHasStableFallback() {
        let s = KeyCombo(keyCode: 0xFE, modifiers: []).displayString
        #expect(!s.isEmpty)
        #expect(s == KeyCombo(keyCode: 0xFE, modifiers: []).displayString)
    }

    @Test func everyAnsiLetterAndDigitIsDistinct() {
        let codes: [UInt32] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D,
                               0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19,
                               0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x25, 0x26,
                               0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x32]
        let names = Set(codes.map { KeyCombo(keyCode: $0, modifiers: []).displayString })
        #expect(names.count == codes.count)
    }
}

@Suite("KeyCombo Codable")
struct KeyComboCodableTests {
    @Test func roundTrips() throws {
        let combo = KeyCombo(keyCode: 0x13, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}

@Suite("HotkeyBindings")
struct HotkeyBindingsTests {
    @Test func defaultsMatchSpec() {
        let d = HotkeyBindings.defaults.bindings
        #expect(d[.openScreenshotUI] == KeyCombo(keyCode: 0x13, modifiers: [.command, .shift]))
        #expect(d[.instantScreen] == KeyCombo(keyCode: 0x13, modifiers: [.control, .command, .shift]))
        #expect(d[.instantWindow] == KeyCombo(keyCode: 0x13, modifiers: [.option, .command, .shift]))
    }

    @Test func printKeyAliasesMatchSpec() {
        let a = HotkeyBindings.printKeyAliases
        #expect(a[KeyCombo(keyCode: 0x69, modifiers: [])] == .openScreenshotUI)
        #expect(a[KeyCombo(keyCode: 0x69, modifiers: [.shift])] == .instantScreen)
        #expect(a[KeyCombo(keyCode: 0x69, modifiers: [.option])] == .instantWindow)
        #expect(a.count == 3)
    }

    @Test func defaultsHaveNoConflicts() {
        #expect(HotkeyBindings.defaults.conflicts().isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(HotkeyBindings.defaults)
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: data)
        #expect(decoded == HotkeyBindings.defaults)
    }

    @Test func partialBindingsRoundTrip() throws {
        let partial = HotkeyBindings(bindings: [.instantWindow: KeyCombo(keyCode: 0x0D, modifiers: [.control])])
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: JSONEncoder().encode(partial))
        #expect(decoded == partial)
    }

    @Test func emptyRoundTrip() throws {
        let empty = HotkeyBindings(bindings: [:])
        let data = try JSONEncoder().encode(empty)
        #expect(String(decoding: data, as: UTF8.self) == "{}")
        #expect(try JSONDecoder().decode(HotkeyBindings.self, from: data) == empty)
    }

    @Test func encodesAsJSONObjectKeyedByRawValue() throws {
        let data = try JSONEncoder().encode(HotkeyBindings.defaults)
        let object = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(object as? [String: Any])
        #expect(Set(dict.keys) == Set(HotkeyAction.allCases.map(\.rawValue)))
        let screen = try #require(dict["instantScreen"] as? [String: Any])
        #expect(screen["keyCode"] as? Int == 0x13)
    }

    @Test func decodesHandWrittenObject() throws {
        let json = #"{"openScreenshotUI":{"keyCode":105,"modifiers":0}}"#
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: Data(json.utf8))
        #expect(decoded.bindings == [.openScreenshotUI: KeyCombo(keyCode: 105, modifiers: [])])
    }

    @Test func decodingIgnoresUnknownActions() throws {
        let json = #"{"openScreenshotUI":{"keyCode":105,"modifiers":0},"futureAction":{"keyCode":1,"modifiers":0}}"#
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: Data(json.utf8))
        #expect(decoded.bindings.count == 1)
        #expect(decoded.bindings[.openScreenshotUI] != nil)
    }

    @Test func decodingRejectsNonObject() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HotkeyBindings.self, from: Data("[1,2]".utf8))
        }
    }

    @Test func conflictsFindsDuplicateBindings() {
        let combo = KeyCombo(keyCode: 0x13, modifiers: [.command, .shift])
        var b = HotkeyBindings.defaults
        b.bindings[.instantScreen] = combo
        let c = b.conflicts()
        #expect(c.count == 1)
        #expect(c[combo] == [.openScreenshotUI, .instantScreen])
    }

    @Test func conflictsListsAllThreeActions() {
        let combo = KeyCombo(keyCode: 0x00, modifiers: [.control])
        let b = HotkeyBindings(bindings: Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, combo) }))
        #expect(b.conflicts() == [combo: [.openScreenshotUI, .instantScreen, .instantWindow]])
    }

    @Test func conflictsCountsPrintKeyAliasCollisions() {
        // instantScreen bound to F13 collides with the fixed F13 → openScreenshotUI alias.
        let f13 = KeyCombo(keyCode: 0x69, modifiers: [])
        var b = HotkeyBindings.defaults
        b.bindings[.instantScreen] = f13
        #expect(b.conflicts() == [f13: [.openScreenshotUI, .instantScreen]])
    }

    @Test func bindingAnActionToItsOwnAliasIsNotAConflict() {
        let f13 = KeyCombo(keyCode: 0x69, modifiers: [])
        var b = HotkeyBindings.defaults
        b.bindings[.openScreenshotUI] = f13
        #expect(b.conflicts().isEmpty)
    }

    @Test func conflictsIgnoreUnrelatedDistinctCombos() {
        let b = HotkeyBindings(bindings: [
            .openScreenshotUI: KeyCombo(keyCode: 0x00, modifiers: [.command]),
            .instantScreen: KeyCombo(keyCode: 0x00, modifiers: [.command, .shift]),
        ])
        #expect(b.conflicts().isEmpty)
    }

    @Test func aliasCollisionAndBindingCollisionTogether() {
        let f13 = KeyCombo(keyCode: 0x69, modifiers: [])
        let b = HotkeyBindings(bindings: [
            .instantScreen: f13,
            .instantWindow: f13,
        ])
        #expect(b.conflicts() == [f13: [.openScreenshotUI, .instantScreen, .instantWindow]])
    }
}
