import AppKit
import SwiftUI
import Sparkle

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    /// The single shortcut-recording session for the window; it suspends/resumes the global hotkeys.
    private let hotkeyManager: HotkeyManager
    private let recordingSession: HotkeyRecordingSession
    private let updater: SPUUpdater?

    init(settings: SettingsStore, hotkeyManager: HotkeyManager, updater: SPUUpdater?) {
        self.settings = settings
        self.hotkeyManager = hotkeyManager
        self.recordingSession = HotkeyRecordingSession { isRecording in
            if isRecording { hotkeyManager.suspend() } else { hotkeyManager.resume() }
        }
        self.updater = updater
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the Settings window (SwiftUI SettingsView hosted in an NSWindow).
    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, hotkeyManager: hotkeyManager, recordingSession: recordingSession, updater: updater)))
            window.title = String(localized: "PrtSc Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            let visible = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 540, height: min(640, visible - 80)))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Ending an active recording also resumes the global hotkeys.
        recordingSession.cancel()
    }

    func windowDidResignKey(_ notification: Notification) {
        recordingSession.cancel()
    }
}
