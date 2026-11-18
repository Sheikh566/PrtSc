import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var reopenTask: Task<Void, Never>?

    /// How long a reopen waits for a possible notification response before opening Settings.
    private static let reopenSettleDelay: Duration = .milliseconds(400)
    /// A notification click this recent means the reopen came from that click.
    private static let notificationClickWindow: Duration = .milliseconds(1500)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if another PrtSc is already running, hand over to it and quit.
        if let other = Self.otherRunningInstance() {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    /// Quitting during a Screencast waits for the recording to be finalized, so the file stays playable.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.screencastRecorder.isBusy else { return .terminateNow }
        Task { @MainActor in
            await coordinator.stopScreencastForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func openSettings() {
        coordinator?.openSettings()
    }

    /// Relaunching the app while it is running opens Settings (this is how a hidden menu bar icon is recovered).
    ///
    /// Clicking a Capture Notification sends the same reopen event, and the notification response can arrive
    /// just before or just after it. So wait briefly and skip Settings if a notification was clicked: that
    /// click opens the file instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenTask?.cancel()
        reopenTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.reopenSettleDelay)
            guard !Task.isCancelled, let self else { return }
            self.reopenTask = nil
            if NotificationActivity.respondedRecently(within: Self.notificationClickWindow) { return }
            self.openSettings()
        }
        return false
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != myPID && !$0.isTerminated }
    }
}
