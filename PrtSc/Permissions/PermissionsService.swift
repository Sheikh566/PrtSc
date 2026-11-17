import AppKit
import CoreGraphics
import UserNotifications

@MainActor
final class PermissionsService {
    static let screenRecordingSettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    static let notificationSettingsURL = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

    init() {}

    var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; afterwards macOS only lists PrtSc in Screen Recording settings.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        open(Self.screenRecordingSettingsURL)
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestNotificationAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func openNotificationSettings() {
        open(Self.notificationSettingsURL)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
