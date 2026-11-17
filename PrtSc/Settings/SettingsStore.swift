import Foundation
import Observation
import PrtScCore

/// UserDefaults-backed user settings. Automatic updates live in Sparkle's own defaults.
@MainActor
@Observable
final class SettingsStore {
    enum Key {
        static let saveFolderPath = "saveFolderPath"
        static let includeWindowShadow = "includeWindowShadow"
        static let launchAtLogin = "launchAtLogin"
        static let hideMenuBarIcon = "hideMenuBarIcon"
        static let hotkeys = "hotkeys"
        static let hasSeenWelcome = "hasSeenWelcome"
    }

    /// nil means the default (~/Pictures/Screenshots).
    var saveFolderPath: String? {
        didSet {
            guard saveFolderPath != oldValue else { return }
            if let saveFolderPath, !saveFolderPath.isEmpty {
                defaults.set(saveFolderPath, forKey: Key.saveFolderPath)
            } else {
                defaults.removeObject(forKey: Key.saveFolderPath)
            }
        }
    }

    var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: Key.includeWindowShadow) }
    }

    /// Reflects the real SMAppService status once `syncLaunchAtLogin()` has run.
    var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(previous: oldValue)
        }
    }

    var hideMenuBarIcon: Bool {
        didSet { defaults.set(hideMenuBarIcon, forKey: Key.hideMenuBarIcon) }
    }

    var hotkeys: HotkeyBindings {
        didSet {
            guard hotkeys != oldValue else { return }
            if let data = try? JSONEncoder().encode(hotkeys) {
                defaults.set(data, forKey: Key.hotkeys)
            }
        }
    }

    /// Whether the Welcome window has been shown once.
    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    /// Set when enabling/disabling the login item failed or needs approval; shown in Settings.
    private(set) var launchAtLoginMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: (any LoginItemControlling)?
    @ObservationIgnored private var isSyncingLaunchAtLogin = false

    /// - Parameter loginItem: pass nil (tests) to leave the system login item alone.
    init(defaults: UserDefaults = .standard, loginItem: (any LoginItemControlling)? = SystemLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem

        saveFolderPath = defaults.string(forKey: Key.saveFolderPath).flatMap { $0.isEmpty ? nil : $0 }
        includeWindowShadow = defaults.object(forKey: Key.includeWindowShadow) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        hideMenuBarIcon = defaults.object(forKey: Key.hideMenuBarIcon) as? Bool ?? false
        hasSeenWelcome = defaults.object(forKey: Key.hasSeenWelcome) as? Bool ?? false
        if let data = defaults.data(forKey: Key.hotkeys),
           let decoded = try? JSONDecoder().decode(HotkeyBindings.self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = .defaults
        }
    }

    // MARK: - Launch at login

    /// Call once at launch. Registers the login item on first launch (the default is on), otherwise
    /// reflects whatever the system says (the user may have changed it in System Settings).
    func syncLaunchAtLogin() {
        guard let loginItem else { return }
        let firstLaunch = defaults.object(forKey: Key.launchAtLogin) == nil
        if firstLaunch {
            do {
                try loginItem.setRegistered(true)
                launchAtLoginMessage = nil
            } catch {
                launchAtLoginMessage = error.localizedDescription
            }
        }
        refreshLaunchAtLogin()
    }

    /// Re-reads the real status (e.g. when the Settings window appears).
    func refreshLaunchAtLogin() {
        guard let loginItem else { return }
        setLaunchAtLoginSilently(loginItem.isRegistered)
        let approval = loginItem.requiresApproval
        if approval {
            launchAtLoginMessage = String(localized: "Approve PrtSc in System Settings › General › Login Items.")
        } else if showingApprovalMessage {
            launchAtLoginMessage = nil
        }
        showingApprovalMessage = approval
    }

    @ObservationIgnored private var showingApprovalMessage = false

    private func setLaunchAtLoginSilently(_ value: Bool) {
        isSyncingLaunchAtLogin = true
        launchAtLogin = value
        isSyncingLaunchAtLogin = false
        defaults.set(value, forKey: Key.launchAtLogin)
    }

    private func applyLaunchAtLogin(previous: Bool) {
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        guard let loginItem else { return }
        do {
            try loginItem.setRegistered(launchAtLogin)
            launchAtLoginMessage = nil
            refreshLaunchAtLogin()
        } catch {
            launchAtLoginMessage = error.localizedDescription
            setLaunchAtLoginSilently(previous)
        }
    }
}
