import AppKit
import AVFoundation
import PrtScCore
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let hotkeyManager: HotkeyManager
    /// Shared by every shortcut row: only one row records at a time.
    let recordingSession: HotkeyRecordingSession
    /// nil while Sparkle isn't configured (placeholder public key).
    let updater: SPUUpdater?
    /// The Settings NSWindow, used to attach folder-picker sheets via `beginSheetModal(for:)`.
    let hostWindow: @MainActor () -> NSWindow?

    @State private var automaticallyChecksForUpdates: Bool
    /// Why "Record microphone" was switched back off (permission denied).
    @State private var microphoneMessage: String?
    @State private var showingUIKeys = false

    init(
        settings: SettingsStore,
        hotkeyManager: HotkeyManager,
        recordingSession: HotkeyRecordingSession,
        updater: SPUUpdater?,
        hostWindow: @escaping @MainActor () -> NSWindow? = { nil }
    ) {
        self.settings = settings
        self.hotkeyManager = hotkeyManager
        self.recordingSession = recordingSession
        self.updater = updater
        self.hostWindow = hostWindow
        _automaticallyChecksForUpdates = State(initialValue: updater?.automaticallyChecksForUpdates ?? false)
    }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalTab
            }
            Tab("Screenshots", systemImage: "camera") {
                screenshotsTab
            }
            Tab("Screencast", systemImage: "video") {
                screencastTab
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                shortcutsTab
            }
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 460, idealHeight: 520)
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    if let message = settings.launchAtLoginMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarIcon)
                    Text("To get the icon back, open PrtSc again (for example from Spotlight or the Applications folder). This opens these settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                        .disabled(updater == nil)
                        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                            updater?.automaticallyChecksForUpdates = newValue
                        }
                    if updater == nil {
                        Text("Updates aren't available in this build.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(aboutLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "PrtSc \(version) (\(build)) · MIT License")
    }

    // MARK: - Screenshots

    private var screenshotsTab: some View {
        Form {
            Section {
                FolderSettingRow(
                    url: SaveFolder.url(configured: settings.saveFolderPath),
                    isDefault: settings.saveFolderPath == nil,
                    panelMessage: String(localized: "Choose where PrtSc saves screenshots."),
                    hostWindow: hostWindow,
                    onSelect: { settings.saveFolderPath = $0.path },
                    onReset: { settings.saveFolderPath = nil }
                )
            } header: {
                Text("Save Folder")
            } footer: {
                Text("Every screenshot is also copied to the clipboard.")
            }

            Section {
                Toggle("Include window shadow", isOn: $settings.includeWindowShadow)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Screencast

    private var screencastTab: some View {
        Form {
            Section {
                FolderSettingRow(
                    url: ScreencastFolder.url(configured: settings.screencastFolderPath),
                    isDefault: settings.screencastFolderPath == nil,
                    panelMessage: String(localized: "Choose where PrtSc saves Screencasts."),
                    hostWindow: hostWindow,
                    onSelect: { settings.screencastFolderPath = $0.path },
                    onReset: { settings.screencastFolderPath = nil }
                )
            } header: {
                Text("Screencast Folder")
            }

            Section {
                Toggle("Record system audio", isOn: $settings.recordSystemAudio)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Record microphone", isOn: microphoneBinding)
                    if let microphoneMessage {
                        Text(microphoneMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Microphone Settings", action: openMicrophoneSettings)
                            .font(.caption)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Most compatible format (H.264)", isOn: $settings.screencastPreferH264)
                    Text("Screencasts are saved as HEVC by default. Turn this on for players and editors that can't read HEVC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Screencasts are saved as .mp4 files at the screen's native resolution and 60 frames per second. They are not copied to the clipboard.")
            }
        }
        .formStyle(.grouped)
    }

    /// Switching the microphone on asks for permission first; if it is denied the switch goes back off.
    private var microphoneBinding: Binding<Bool> {
        Binding(
            get: { settings.recordMicrophone },
            set: { setMicrophone($0) }
        )
    }

    private func setMicrophone(_ enabled: Bool) {
        microphoneMessage = nil
        guard enabled else {
            settings.recordMicrophone = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            settings.recordMicrophone = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                settings.recordMicrophone = granted
                if !granted { microphoneMessage = Self.microphoneDeniedMessage }
            }
        default:
            settings.recordMicrophone = false
            microphoneMessage = Self.microphoneDeniedMessage
        }
    }

    private static var microphoneDeniedMessage: String {
        String(localized: "PrtSc doesn't have access to the microphone. Allow it in System Settings › Privacy & Security › Microphone.")
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent {
                            HotkeyRecorderView(action: action, combo: binding(for: action), session: recordingSession)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.settingsTitle)
                                Text(action.settingsSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let warning = warning(for: action) {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text("The Print key also works on keyboards that send F13: F13 takes a screenshot, ⇧F13 captures the screen and ⌥F13 captures the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(failedAliases, id: \.self) { combo in
                    Label("Couldn't register \(combo.displayString); another app or macOS is using it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        settings.hotkeys = .defaults
                    }
                    .disabled(settings.hotkeys == .defaults)
                }
            }

            Section {
                DisclosureGroup("Screenshot UI Keys", isExpanded: $showingUIKeys) {
                    VStack(alignment: .leading, spacing: 6) {
                        uiKeyRow(String(localized: "Switch Capture Mode (Selection, Screen, Window)"),
                                 keys: ["S", "C", "W"])
                        uiKeyRow(String(localized: "Switch Capture Type (Screenshot, Screencast)"),
                                 keys: ["V"])
                        uiKeyRow(String(localized: "Toggle Show Pointer"),
                                 keys: ["P"])
                        uiKeyRow(String(localized: "Capture or start recording"),
                                 keys: ["↩", String(localized: "Space"), "⌘C"])
                        uiKeyRow(String(localized: "Close the Screenshot UI"),
                                 keys: ["Esc"])
                        uiKeyRow(String(localized: "Resize Selection or move focus"),
                                 keys: ["←", "→", "↑", "↓"])
                        uiKeyRow(String(localized: "Move Selection"),
                                 keys: ["⌥", "←→↑↓"])
                        uiKeyRow(String(localized: "Fine 1 pt step"),
                                 keys: ["⌘", "←→↑↓"])
                        uiKeyRow(String(localized: "Full-screen step"),
                                 keys: ["⇧", "←→↑↓"])
                        uiKeyRow(String(localized: "Reset Selection"),
                                 keys: ["R"])
                        uiKeyRow(String(localized: "Draw a new Selection"),
                                 keys: [String(localized: "Right-drag"), String(localized: "⌃-drag")])
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func uiKeyRow(_ description: String, keys: [String]) -> some View {
        HStack(spacing: 8) {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    KeycapView(key)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func binding(for action: HotkeyAction) -> Binding<KeyCombo?> {
        Binding(
            get: { settings.hotkeys.bindings[action] },
            set: { settings.hotkeys.bindings[action] = $0 }
        )
    }

    private func warning(for action: HotkeyAction) -> String? {
        guard let combo = settings.hotkeys.bindings[action] else { return nil }
        if let others = settings.hotkeys.conflicts()[combo], others.count > 1 {
            let names = others.filter { $0 != action }.map(\.settingsTitle).formatted()
            return String(localized: "Same shortcut as \(names). Only one of them will work.")
        }
        if hotkeyManager.failedCombos.contains(combo) {
            return String(localized: "Couldn't register this shortcut; another app or macOS is using it.")
        }
        return nil
    }

    /// Print-key aliases that failed to register (they aren't shown in a recorder row).
    private var failedAliases: [KeyCombo] {
        let bound = Set(settings.hotkeys.bindings.values)
        return hotkeyManager.failedCombos
            .filter { HotkeyBindings.printKeyAliases[$0] != nil && !bound.contains($0) }
            .sorted { $0.modifiers.rawValue < $1.modifiers.rawValue }
    }
}

/// Shared folder-picker row used for Save Folder and Screencast Folder.
private struct FolderSettingRow: View {
    let url: URL
    let isDefault: Bool
    let panelMessage: String
    let hostWindow: @MainActor () -> NSWindow?
    let onSelect: (URL) -> Void
    let onReset: () -> Void

    private var abbreviatedPath: String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(abbreviatedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Choose…", action: chooseFolder)
                Button("Show in Finder", action: showInFinder)
                Spacer()
                Button("Reset to Default", action: onReset)
                    .disabled(isDefault)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Select")
        panel.message = panelMessage
        panel.directoryURL = url
        Task {
            let response: NSApplication.ModalResponse
            if let window = hostWindow() {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = await panel.begin()
            }
            if response == .OK, let selected = panel.url {
                onSelect(selected)
            }
        }
    }

    private func showInFinder() {
        try? SaveFolder.ensureExists(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
