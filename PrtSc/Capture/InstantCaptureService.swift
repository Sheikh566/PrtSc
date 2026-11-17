import AppKit
import os
import PrtScCore

/// Instant Capture: a capture triggered straight from a hotkey, without opening the Screenshot UI.
/// Instant Captures never include the pointer (GNOME's Shift+Print and Alt+Print have no pointer).
@MainActor
final class InstantCaptureService {
    private static let log = Logger(subsystem: "io.github.sheikh566.PrtSc", category: "InstantCapture")

    private let capturer: ScreenCapturer
    private let output: CaptureSink
    private let settings: SettingsStore
    private var isCapturing = false

    /// Called on the main actor when a capture fails, so the user sees something happened.
    var onFailure: (@MainActor (Error) -> Void)?

    init(capturer: ScreenCapturer, output: CaptureSink, settings: SettingsStore) {
        self.capturer = capturer
        self.output = output
        self.settings = settings
    }

    /// Instant Screen: the display under the pointer.
    func captureScreen() async {
        // What the user was pointing at when the shortcut fired, read before any `await`.
        let pointer = ScreenCapturer.pointerLocation()
        await run(name: "Instant Screen") {
            let displays = try await capturer.currentDisplays()
            guard let display = DisplayGeometry.panelDisplay(pointer: pointer, displays: displays) else {
                throw ScreenCapturerError.noDisplays
            }
            return try await capturer.captureDisplay(display, showsPointer: false)
        }
    }

    /// Instant Window: the frontmost window (InstantWindowTargetResolver), else the screen.
    func captureWindow() async {
        // Pointer and frontmost app as of the shortcut, read before the first `await`: enumerating
        // displays and windows suspends, and the user may move the pointer or switch apps meanwhile.
        let pointer = ScreenCapturer.pointerLocation()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        await run(name: "Instant Window") {
            let displays = try await capturer.currentDisplays()
            guard let pointerDisplay = DisplayGeometry.panelDisplay(pointer: pointer, displays: displays) else {
                throw ScreenCapturerError.noDisplays
            }
            let windows = try await capturer.onScreenWindowsFrontToBack()
            let target = InstantWindowTargetResolver.resolve(
                frontmostPID: frontmostPID,
                ownPID: ProcessInfo.processInfo.processIdentifier,
                windows: windows,
                displayUnderPointer: pointerDisplay.displayID)

            switch target {
            case let .window(window, attached):
                return try await capturer.captureWindow(window, attached: attached,
                                                        includeShadow: settings.includeWindowShadow)
            case let .screen(displayID):
                let display = displays.first(where: { $0.displayID == displayID }) ?? pointerDisplay
                return try await capturer.captureDisplay(display, showsPointer: false)
            }
        }
    }

    /// One Instant Capture at a time: a second hotkey press while one is in flight is ignored.
    private func run(name: String, _ capture: () async throws -> CapturedImage) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let captured = try await capture()
            await output.deliver(captured)
        } catch {
            Self.log.error("\(name, privacy: .public) capture failed: \(error.localizedDescription, privacy: .public)")
            onFailure?(error)
        }
    }
}
