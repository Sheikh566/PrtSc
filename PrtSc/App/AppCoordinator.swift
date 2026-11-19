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
    let screencastRecorder: ScreencastRecorder
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
        self.screencastRecorder = ScreencastRecorder()
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
        screenshotUI.onRecord = { [weak self] target, showsPointer in
            self?.startScreencast(target, showsPointer: showsPointer)
        }
        screencastRecorder.onFinished = { [weak self] url in
            guard let self else { return }
            let output = self.output
            Task { await output.deliverScreencast(url) }
        }
        screencastRecorder.onFailure = { [weak self] error in
            self?.handleScreencastFailure(error)
        }

        wireMenu()
        menuBar.canCheckForUpdates = UpdateSupport.isConfigured
        menuBar.install()

        // The Recording Indicator follows the recorder's state.
        observeForever { [weak self] in
            guard let self else { return }
            switch self.screencastRecorder.state {
            case let .recording(startDate): self.menuBar.setIndicatorState(.recording(startDate: startDate))
            case .stopping: self.menuBar.setIndicatorState(.stopping)
            case .idle, .starting: self.menuBar.setIndicatorState(.idle)
            }
        }

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
        menuBar.onRecordScreencast = { [weak self] in self?.performFromMenu(.screencast) }
        menuBar.onStopScreencast = { [weak self] in self?.perform(.screencast) }
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
        // While a Screencast is recording, its hotkey stops it and the Screenshot UI can't open
        // (a beep and nothing else). Instant Captures keep working.
        if screencastRecorder.isBusy {
            switch action {
            case .screencast:
                Task { await screencastRecorder.stop() }
                return
            case .openScreenshotUI:
                NSSound.beep()
                return
            case .instantScreen, .instantWindow:
                break
            }
        }
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
        case .screencast:
            screenshotUI.toggle(captureType: .screencast)
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

    // MARK: - Screencast

    /// The record button was pressed (the overlay is already closed): start recording.
    private func startScreencast(_ target: ScreencastTarget, showsPointer: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let folder = try ScreencastFolder.prepare(configured: self.settings.screencastFolderPath)
                let options = ScreencastOptions(folder: folder,
                                                showsPointer: showsPointer,
                                                recordSystemAudio: self.settings.recordSystemAudio,
                                                recordMicrophone: self.settings.recordMicrophone,
                                                preferH264: self.settings.screencastPreferH264)
                try await self.screencastRecorder.start(target: target, options: options)
            } catch {
                self.handleScreencastFailure(error)
            }
        }
    }

    /// A Screencast could not start or ended early. Without Screen Recording the Welcome window explains how
    /// to fix it; otherwise the user gets a beep and an alert with the reason (and, when part of the
    /// recording was kept, a way to find it).
    private func handleScreencastFailure(_ error: Error) {
        NSSound.beep()
        if !permissions.hasScreenRecording, !(error is ScreencastError) {
            welcomeWindow.show()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't Record Screencast")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        let savedFile = (error as? ScreencastError)?.savedFile
        if savedFile != nil {
            alert.addButton(withTitle: String(localized: "Show in Finder"))
        }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn, let savedFile {
            NSWorkspace.shared.activateFileViewerSelecting([savedFile])
        }
    }

    /// Quitting while recording: stop and finalize the file first, so it stays playable.
    func stopScreencastForTermination() async {
        await screencastRecorder.stopAndWaitUntilIdle()
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
