import AppKit
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

    @State private var automaticallyChecksForUpdates: Bool

    init(settings: SettingsStore, hotkeyManager: HotkeyManager, recordingSession: HotkeyRecordingSession, updater: SPUUpdater?) {
        self.settings = settings
        self.hotkeyManager = hotkeyManager
        self.recordingSession = recordingSession
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater?.automaticallyChecksForUpdates ?? false)
    }

    var body: some View {
        Form {
            hotkeysSection
            saveFolderSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 420, idealHeight: 640)
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
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
        } header: {
            Text("Shortcuts")
        }
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

    // MARK: - Save folder

    private var saveFolderSection: some View {
        Section {
            LabeledContent("Folder") {
                Text(displayPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Choose…", action: chooseSaveFolder)
                Button("Reveal", action: revealSaveFolder)
                Spacer()
                Button("Reset to Default") { settings.saveFolderPath = nil }
                    .disabled(settings.saveFolderPath == nil)
            }
        } header: {
            Text("Save Folder")
        } footer: {
            Text("Every screenshot is also copied to the clipboard.")
        }
    }

    private var displayPath: String {
        (SaveFolder.url(configured: settings.saveFolderPath).path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Select")
        panel.message = String(localized: "Choose where PrtSc saves screenshots.")
        panel.directoryURL = SaveFolder.url(configured: settings.saveFolderPath)
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                settings.saveFolderPath = url.path
            }
        }
    }

    private func revealSaveFolder() {
        let url = SaveFolder.url(configured: settings.saveFolderPath)
        try? SaveFolder.ensureExists(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle("Include window shadow", isOn: $settings.includeWindowShadow)
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
                Text("To get the icon back, open PrtSc again (for example from Spotlight or Launchpad); that opens these settings.")
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
        } header: {
            Text("General")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Text(aboutLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var aboutLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "PrtSc \(version) (\(build)) · MIT License")
    }
}
