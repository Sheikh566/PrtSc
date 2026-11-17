import PrtScCore

extension CaptureMode {
    var localizedTitle: String {
        switch self {
        case .selection: String(localized: "Selection")
        case .screen: String(localized: "Screen")
        case .window: String(localized: "Window")
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
