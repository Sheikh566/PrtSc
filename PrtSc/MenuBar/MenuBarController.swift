import AppKit
import PrtScCore

/// NSStatusItem with the app menu.
/// Menu (see docs/architecture.md): Take Screenshot… · Capture Screen · Capture Window · ─ ·
/// Open Save Folder · Settings… · Check for Updates… · ─ · Quit PrtSc.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private var statusItem: NSStatusItem?

    var onTakeScreenshot: (@MainActor () -> Void)?
    var onCaptureScreen: (@MainActor () -> Void)?
    var onCaptureWindow: (@MainActor () -> Void)?
    var onOpenSaveFolder: (@MainActor () -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?
    var onCheckForUpdates: (@MainActor () -> Void)?

    /// False while Sparkle has no real public key (the item is shown but disabled).
    var canCheckForUpdates = false

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    /// Creates the status item. Hidden when `settings.hideMenuBarIcon`; follows that setting afterwards.
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "PrtScStatusItem"
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder",
                                accessibilityDescription: String(localized: "PrtSc"))
            image?.isTemplate = true
            button.image = image
            button.toolTip = String(localized: "PrtSc")
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        rebuildMenu(menu)

        observeForever { [weak self] in
            guard let self else { return }
            self.statusItem?.isVisible = !self.settings.hideMenuBarIcon
        }
    }

    func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(captureItem(.openScreenshotUI, selector: #selector(takeScreenshot)))
        menu.addItem(captureItem(.instantScreen, selector: #selector(captureScreen)))
        menu.addItem(captureItem(.instantWindow, selector: #selector(captureWindow)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open Save Folder"), #selector(openSaveFolder)))
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ",", modifiers: [.command]))
        let updates = item(String(localized: "Check for Updates…"), #selector(checkForUpdates))
        updates.isEnabled = canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit PrtSc"), #selector(quit), key: "q", modifiers: [.command]))
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.isEnabled = true
        return item
    }

    /// A capture item with its current shortcut as a key equivalent, or as plain text when the menu can't express it.
    private func captureItem(_ action: HotkeyAction, selector: Selector) -> NSMenuItem {
        let combo = settings.hotkeys.bindings[action]
        if let combo, let key = KeyCodes.menuKeyEquivalent(for: combo.keyCode) {
            return item(action.title, selector, key: key, modifiers: KeyCodes.menuModifierMask(combo.modifiers))
        }
        let title = combo.map { "\(action.title)  \($0.displayString)" } ?? action.title
        return item(title, selector)
    }

    @objc private func takeScreenshot() { onTakeScreenshot?() }
    @objc private func captureScreen() { onCaptureScreen?() }
    @objc private func captureWindow() { onCaptureWindow?() }
    @objc private func openSaveFolder() { onOpenSaveFolder?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
