import AppKit
import PrtScCore
import Sparkle

/// Owns one instance of each service and wires them together.
@MainActor
final class AppCoordinator {
    let settings: SettingsStore
    let session: SessionState
    let permissions: PermissionsService
    let capturer: ScreenCapturer
    let output: OutputService
    let screenshotUI: ScreenshotUIController
    let instantCapture: InstantCaptureService
    let hotkeys: HotkeyManager
    let menuBar: MenuBarController
    let welcomeWindow: WelcomeWindowController
    let settingsWindow: SettingsWindowController
    /// Sparkle 2. Only started once SUPublicEDKey is a real key (see `UpdateSupport`).
    let updaterController: SPUStandardUpdaterController

    init() {
        let settings = SettingsStore()
        let session = SessionState()
        let permissions = PermissionsService()
        let capturer = ScreenCapturer()
        // OutputService installs the notification delegate; nothing posts before this.
        let output = OutputService(settings: settings)
        let updaterController = SPUStandardUpdaterController(startingUpdater: UpdateSupport.isConfigured,
                                                             updaterDelegate: nil,
                                                             userDriverDelegate: nil)
        let hotkeys = HotkeyManager()

        self.settings = settings
        self.session = session
        self.permissions = permissions
        self.capturer = capturer
        self.output = output
        self.updaterController = updaterController
        self.hotkeys = hotkeys
        self.screenshotUI = ScreenshotUIController(capturer: capturer, output: output,
                                                   settings: settings, session: session)
        self.instantCapture = InstantCaptureService(capturer: capturer, output: output, settings: settings)
        self.menuBar = MenuBarController(settings: settings)
        self.welcomeWindow = WelcomeWindowController(permissions: permissions, settings: settings)
        self.settingsWindow = SettingsWindowController(
            settings: settings,
            hotkeyManager: hotkeys,
            updater: UpdateSupport.isConfigured ? updaterController.updater : nil)
    }

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PRTSC_SKIP_LOGIN_ITEM"] == nil {
            settings.syncLaunchAtLogin()
        }
        #else
        settings.syncLaunchAtLogin()
        #endif

        let reportFailure: @MainActor (Error) -> Void = { [weak self] error in
            self?.handleCaptureFailure(error)
        }
        screenshotUI.onFailure = reportFailure
        instantCapture.onFailure = reportFailure

        wireMenu()
        menuBar.canCheckForUpdates = UpdateSupport.isConfigured
        menuBar.install()

        observeForever { [weak self] in
            guard let self else { return }
            let bindings = self.settings.hotkeys
            self.hotkeys.register(bindings) { [weak self] action in
                self?.perform(action)
            }
        }

        if !settings.hasSeenWelcome || !permissions.hasScreenRecording {
            welcomeWindow.show()
        }
    }

    func openSettings() {
        settingsWindow.show()
    }

    // MARK: - Actions

    private func wireMenu() {
        menuBar.onTakeScreenshot = { [weak self] in self?.performFromMenu(.openScreenshotUI) }
        menuBar.onCaptureScreen = { [weak self] in self?.performFromMenu(.instantScreen) }
        menuBar.onCaptureWindow = { [weak self] in self?.performFromMenu(.instantWindow) }
        menuBar.onOpenSaveFolder = { [weak self] in self?.openSaveFolder() }
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBar.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }

    /// Menu items give the menu a moment to close, so it isn't part of the Frozen Frame.
    private func performFromMenu(_ action: HotkeyAction) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.perform(action)
        }
    }

    private func perform(_ action: HotkeyAction) {
        // The open hotkey while the Screenshot UI is open closes it.
        if action == .openScreenshotUI, screenshotUI.isPresented {
            screenshotUI.toggle()
            return
        }
        guard permissions.hasScreenRecording else {
            welcomeWindow.show()
            return
        }
        switch action {
        case .openScreenshotUI:
            screenshotUI.toggle()
        case .instantScreen:
            Task { await instantCapture.captureScreen() }
        case .instantWindow:
            Task { await instantCapture.captureWindow() }
        }
    }

    /// A capture could not be taken. Without Screen Recording the Welcome window explains how to fix it;
    /// otherwise the user gets a beep and an alert with the reason.
    private func handleCaptureFailure(_ error: Error) {
        NSSound.beep()
        guard permissions.hasScreenRecording else {
            welcomeWindow.show()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't Take Screenshot")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    private func openSaveFolder() {
        let url = output.saveFolderURL
        do {
            try SaveFolder.ensureExists(url)
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }
}
