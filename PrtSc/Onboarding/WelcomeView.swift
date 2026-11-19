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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var grantAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to PrtSc")
                        .font(.title.bold())
                    Text("Screenshots the GNOME way, from your menu bar.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                permissionCard(
                    symbol: "record.circle",
                    title: String(localized: "Screen Recording"),
                    detail: String(localized: "Required. macOS asks for this permission before any app can capture other windows or the display."),
                    granted: model.screenRecordingGranted
                ) {
                    Button("Grant Access") { model.permissions.requestScreenRecording() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { model.permissions.openScreenRecordingSettings() }
                        .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
                }
            }

            shortcutsRow

            Text("After granting Screen Recording, macOS may ask you to quit and reopen PrtSc before it takes effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if !model.screenRecordingGranted {
                    Button("Relaunch PrtSc", action: relaunch)
                        .buttonStyle(.bordered)
                        .transition(reduceMotion ? .identity : .opacity)
                }
                Spacer()
                if model.screenRecordingGranted {
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: close)
                        .buttonStyle(.bordered)
                }
            }
            .animation(grantAnimation, value: model.screenRecordingGranted)
        }
        .padding(EdgeInsets(top: 34, leading: 24, bottom: 24, trailing: 24))
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

    private var shortcutsRow: some View {
        let screenshotCombo = settings.hotkeys.bindings[.openScreenshotUI]
        let screencastCombo = settings.hotkeys.bindings[.screencast]
        return HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if screenshotCombo != nil || screencastCombo != nil {
                HStack(spacing: 16) {
                    if let screenshotCombo {
                        shortcutHint(title: String(localized: "Screenshot"), combo: screenshotCombo)
                    }
                    if let screencastCombo {
                        shortcutHint(title: String(localized: "Screencast"), combo: screencastCombo)
                    }
                }
            } else {
                Text("Set a shortcut for taking screenshots in Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func shortcutHint(title: String, combo: KeyCombo) -> some View {
        HStack(spacing: 6) {
            KeycapView(combo.displayString)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func permissionCard<Actions: View>(
        symbol: String, title: String, detail: String, granted: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        let symbolTransition: ContentTransition = reduceMotion ? .identity : .symbolEffect(.replace)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .contentTransition(symbolTransition)
                        Text(granted ? String(localized: "Granted") : String(localized: "Not granted"))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .accessibilityElement(children: .combine)
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack { actions() }
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.7),
                    lineWidth: 1
                )
        }
        .animation(grantAnimation, value: granted)
        .accessibilityElement(children: .contain)
    }
}
