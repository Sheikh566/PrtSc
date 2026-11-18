import Foundation

/// What the Screenshot UI produces: a still image or a video. (Not to be confused with `CaptureMode`,
/// which is what the capture covers.)
public enum CaptureType: String, CaseIterable, Sendable, Codable {
    case screenshot, screencast

    /// The other type.
    public var toggled: CaptureType {
        switch self {
        case .screenshot: .screencast
        case .screencast: .screenshot
        }
    }

    /// V (case-insensitive) toggles the Capture Type: returns the type to switch to from `current`.
    /// nil for any other character.
    public static func forKey(_ character: Character, from current: CaptureType) -> CaptureType? {
        switch character {
        case "v", "V": return current.toggled
        default: return nil
        }
    }
}
