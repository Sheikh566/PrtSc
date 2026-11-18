import PrtScCore

extension CaptureMode {
    var localizedTitle: String {
        switch self {
        case .selection: String(localized: "Selection")
        case .screen: String(localized: "Screen")
        case .window: String(localized: "Window")
        }
    }

    /// The Screenshot UI key that switches to this mode (shown in its tooltip).
    var shortcutKey: String {
        switch self {
        case .selection: "S"
        case .screen: "C"
        case .window: "W"
        }
    }

    var symbolName: String {
        switch self {
        case .selection: "rectangle.dashed"
        case .screen: "display"
        case .window: "macwindow"
        }
    }

    /// Spoken when the mode changes.
    var announcement: String {
        switch self {
        case .selection: String(localized: "Selection mode")
        case .screen: String(localized: "Screen mode")
        case .window: String(localized: "Window mode")
        }
    }
}

extension CaptureType {
    var localizedTitle: String {
        switch self {
        case .screenshot: String(localized: "Screenshot")
        case .screencast: String(localized: "Screencast")
        }
    }

    var symbolName: String {
        switch self {
        case .screenshot: "camera"
        case .screencast: "video"
        }
    }

    /// Spoken when the Capture Type changes.
    var announcement: String {
        switch self {
        case .screenshot: String(localized: "Screenshot mode")
        case .screencast: String(localized: "Screencast mode")
        }
    }
}
