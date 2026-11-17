import AppKit
import Observation
import PrtScCore
import SwiftUI
import UserNotifications

/// Live permission state for the Welcome window.
@MainActor
@Observable
final class WelcomeModel {
    private(set) var screenRecordingGranted: Bool
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored let permissions: PermissionsService

    init(permissions: PermissionsService) {
        self.permissions = permissions
        self.screenRecordingGranted = permissions.hasScreenRecording
    }

    var notificationsGranted: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    func refresh() async {
        screenRecordingGranted = permissions.hasScreenRecording
        notificationStatus = await permissions.notificationAuthorizationStatus()
    }

    func requestNotifications() {
        Task {
            if notificationStatus == .notDetermined {
                _ = await permissions.requestNotificationAuthorization()
            } else {
                permissions.openNotificationSettings()
            }
            await refresh()
        }
    }
}

struct WelcomeView: View {
    let model: WelcomeModel
    let settings: SettingsStore
    let relaunch: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to PrtSc")
                        .font(.title.bold())
                    Text("Screenshots the GNOME way, from your menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    permissionCard(
                        symbol: "record.circle",
                        title: String(localized: "Screen Recording"),
                        detail: String(localized: "Required. macOS asks for this permission before any app can capture other windows or the display."),
                        granted: model.screenRecordingGranted
                    ) {
                        Button("Grant Access") { model.permissions.requestScreenRecording() }
                            .buttonStyle(.glassProminent)
                        Button("Open System Settings") { model.permissions.openScreenRecordingSettings() }
                            .buttonStyle(.glass)
                    }
                    permissionCard(
                        symbol: "bell.badge",
                        title: String(localized: "Notifications"),
                        detail: String(localized: "Optional. Shows a banner with a thumbnail after each capture; click it to open the file."),
                        granted: model.notificationsGranted
                    ) {
                        Button(model.notificationStatus == .notDetermined
                               ? String(localized: "Allow Notifications")
                               : String(localized: "Open System Settings")) {
                            model.requestNotifications()
                        }
                        .buttonStyle(.glass)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .accessibilityHidden(true)
                if let combo = settings.hotkeys.bindings[.openScreenshotUI] {
                    Text("Press \(combo.displayString) to take a screenshot.")
                } else {
                    Text("Set a shortcut for taking screenshots in Settings.")
                }
            }
            .font(.callout)

            Text("After granting Screen Recording, macOS may ask you to quit and reopen PrtSc before it takes effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Relaunch PrtSc", action: relaunch)
                    .buttonStyle(.glass)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private func permissionCard<Actions: View>(
        symbol: String, title: String, detail: String, granted: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Label(granted ? String(localized: "Granted") : String(localized: "Not granted"),
                          systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack { actions() }
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}
