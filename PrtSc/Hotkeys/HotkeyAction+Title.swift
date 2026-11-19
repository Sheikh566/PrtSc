import PrtScCore

extension HotkeyAction {
    /// Menu / Settings title.
    var title: String {
        switch self {
        case .openScreenshotUI: String(localized: "Take Screenshot…")
        case .instantScreen: String(localized: "Capture Screen")
        case .instantWindow: String(localized: "Capture Window")
        case .screencast: String(localized: "Record Screencast…")
        }
    }

    /// Settings row label (no ellipsis).
    var settingsTitle: String {
        switch self {
        case .openScreenshotUI: String(localized: "Take a Screenshot")
        case .instantScreen: String(localized: "Capture Screen")
        case .instantWindow: String(localized: "Capture Window")
        case .screencast: String(localized: "Record a Screencast")
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .openScreenshotUI: String(localized: "Opens the Screenshot UI")
        case .instantScreen: String(localized: "Captures the display under the pointer immediately")
        case .instantWindow: String(localized: "Captures the frontmost window immediately")
        case .screencast: String(localized: "Opens the Screenshot UI in Screencast mode, or stops the running recording")
        }
    }
}
