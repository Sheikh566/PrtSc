import AppKit
import SwiftUI

/// WelcomeWindow: shown on first launch and whenever Screen Recording permission is missing
/// at launch or when a hotkey/menu capture is attempted.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let permissions: PermissionsService
    private let settings: SettingsStore

    init(permissions: PermissionsService, settings: SettingsStore) {
        self.permissions = permissions
        self.settings = settings
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        settings.hasSeenWelcome = true
        if window == nil {
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Welcome to PrtSc")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        if window?.contentViewController == nil {
            let model = WelcomeModel(permissions: permissions)
            let view = WelcomeView(model: model, settings: settings,
                                   relaunch: { Self.relaunch() },
                                   close: { [weak self] in self?.window?.close() })
            window?.contentViewController = NSHostingController(rootView: view)
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the view so its permission polling task stops while the window is closed.
        window?.contentViewController = nil
    }

    /// Quits and opens a fresh instance (macOS may need this for Screen Recording to take effect).
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"$1\"", "sh", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
