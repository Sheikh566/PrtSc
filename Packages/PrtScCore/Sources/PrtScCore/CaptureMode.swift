import Foundation

public enum CaptureMode: String, CaseIterable, Sendable, Codable {
    case selection, screen, window

    /// S → selection, C → screen, W → window (case-insensitive). nil otherwise.
    public static func forKey(_ character: Character) -> CaptureMode? {
        switch character {
        case "s", "S": return .selection
        case "c", "C": return .screen
        case "w", "W": return .window
        default: return nil
        }
    }
}
