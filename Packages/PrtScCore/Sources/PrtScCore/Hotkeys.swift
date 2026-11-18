import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift   = KeyModifiers(rawValue: 1 << 1)
    public static let option  = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

public struct KeyCombo: Codable, Hashable, Sendable {
    /// Carbon virtual key code (kVK_*)
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Modifiers in Apple's order (⌃⌥⇧⌘) followed by the key name, e.g. "⌃⇧⌘2", "F13".
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyNames.name(forKeyCode: keyCode)
    }
}

/// Carbon virtual key code (kVK_*) → display name, for ANSI keys, F-keys and common named keys.
enum KeyNames {
    static func name(forKeyCode keyCode: UInt32) -> String {
        table[keyCode] ?? "Key \(keyCode)"
    }

    private static let table: [UInt32: String] = [
        // Letters (kVK_ANSI_*)
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        // Digits
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        // Punctuation
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`",
        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14",
        0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        // Arrows
        0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓",
        // Named keys
        0x24: "Return", 0x31: "Space", 0x35: "Esc", 0x33: "Delete", 0x30: "Tab",
        0x75: "Forward Delete", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
    ]
}

public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case openScreenshotUI, instantScreen, instantWindow
    /// Opens the Screenshot UI in Screencast mode, or stops the running Screencast.
    case screencast

    /// Actions added after the first release. A stored binding set that lacks one of them predates it, so
    /// decoding gives it its default instead of treating it as cleared; clearing one is stored as `null`.
    var addedAfterFirstRelease: Bool { self == .screencast }
}

public struct HotkeyBindings: Codable, Equatable, Sendable {
    public var bindings: [HotkeyAction: KeyCombo]

    public init(bindings: [HotkeyAction: KeyCombo]) {
        self.bindings = bindings
    }

    /// ⇧⌘2 / ⌃⇧⌘2 / ⌥⇧⌘2  (kVK_ANSI_2 = 0x13), ⌥⇧⌘R for Screencast (kVK_ANSI_R = 0x0F)
    public static let defaults = HotkeyBindings(bindings: [
        .openScreenshotUI: KeyCombo(keyCode: 0x13, modifiers: [.command, .shift]),
        .instantScreen:    KeyCombo(keyCode: 0x13, modifiers: [.control, .command, .shift]),
        .instantWindow:    KeyCombo(keyCode: 0x13, modifiers: [.option, .command, .shift]),
        .screencast:       KeyCombo(keyCode: 0x0F, modifiers: [.option, .command, .shift]),
    ])

    /// Fixed Print-key aliases (PC keyboards send F13, kVK_F13 = 0x69):
    /// F13 → openScreenshotUI, ⇧F13 → instantScreen, ⌥F13 → instantWindow.
    public static let printKeyAliases: [KeyCombo: HotkeyAction] = [
        KeyCombo(keyCode: 0x69, modifiers: []):        .openScreenshotUI,
        KeyCombo(keyCode: 0x69, modifiers: [.shift]):  .instantScreen,
        KeyCombo(keyCode: 0x69, modifiers: [.option]): .instantWindow,
    ]

    /// Actions bound to the same combo as another action (to warn in Settings). Only combos used by two
    /// or more distinct actions are returned; the fixed `printKeyAliases` count as bindings too. Actions
    /// are listed in `HotkeyAction.allCases` order.
    public func conflicts() -> [KeyCombo: [HotkeyAction]] {
        var used: [KeyCombo: Set<HotkeyAction>] = [:]
        for (action, combo) in bindings { used[combo, default: []].insert(action) }
        for (combo, action) in Self.printKeyAliases { used[combo, default: []].insert(action) }
        var result: [KeyCombo: [HotkeyAction]] = [:]
        for (combo, actions) in used where actions.count > 1 {
            result[combo] = HotkeyAction.allCases.filter(actions.contains)
        }
        return result
    }

    // MARK: Codable — a JSON object keyed by HotkeyAction.rawValue.
    // (A [HotkeyAction: KeyCombo] dictionary would otherwise encode as a flat array.)
    // An action added after the first release that is absent from the stored object gets its default
    // (the object predates it); a user who cleared it is stored as an explicit `null`.

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: KeyCombo?].self)
        var result: [HotkeyAction: KeyCombo] = [:]
        for (key, combo) in raw {
            // Unknown actions are ignored; `null` means the action is unbound.
            if let action = HotkeyAction(rawValue: key), let combo { result[action] = combo }
        }
        for action in HotkeyAction.allCases where action.addedAfterFirstRelease && raw[action.rawValue] == nil {
            result[action] = Self.defaults.bindings[action]
        }
        self.bindings = result
    }

    public func encode(to encoder: any Encoder) throws {
        var raw: [String: KeyCombo?] = [:]
        for (action, combo) in bindings { raw[action.rawValue] = .some(combo) }
        for action in HotkeyAction.allCases where action.addedAfterFirstRelease && bindings[action] == nil {
            raw[action.rawValue] = .some(nil)
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
