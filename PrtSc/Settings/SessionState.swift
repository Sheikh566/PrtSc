import CoreGraphics
import Observation
import PrtScCore

/// In-memory state that lives for the app session; not persisted.
@MainActor
@Observable
final class SessionState {
    var showPointer: Bool = false
    var rememberedSelection: CGRect?
    var lastCaptureMode: CaptureMode = .selection

    init() {}
}
