import AppKit
import PrtScCore

/// NSStatusItem with the app menu.
/// Menu (see docs/architecture.md): Take Screenshot… · Capture Screen · Capture Window · Record Screencast… · ─ ·
/// Open Save Folder · Settings… · Check for Updates… · ─ · Quit PrtSc.
///
/// While a Screencast is recording the status item is the Recording Indicator (a red dot and the elapsed
/// time): a click stops the recording, and a right-click (or ⌃-click) opens the menu, whose first item is
/// then "Stop Screencast". While the recorder is finalizing the file, the indicator shows "Stopping…"
/// without a timer and is not clickable.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    enum IndicatorState: Equatable {
        case idle
        case recording(startDate: Date)
        case stopping
    }

    private let settings: SettingsStore
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var indicatorState: IndicatorState = .idle
    private var clockTask: Task<Void, Never>?

    var onTakeScreenshot: (@MainActor () -> Void)?
    var onCaptureScreen: (@MainActor () -> Void)?
    var onCaptureWindow: (@MainActor () -> Void)?
    var onOpenSaveFolder: (@MainActor () -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?
    var onCheckForUpdates: (@MainActor () -> Void)?
    var onRecordScreencast: (@MainActor () -> Void)?
    var onStopScreencast: (@MainActor () -> Void)?

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
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        self.menu = menu
        statusItem = item
        rebuildMenu(menu)
        applyIndicatorState()

        observeForever { [weak self] in
            guard let self else { return }
            self.updateVisibility(hidden: self.settings.hideMenuBarIcon)
        }
    }

    // MARK: - Recording Indicator

    /// Updates the status item to match the Screencast recorder's state.
    func setIndicatorState(_ state: IndicatorState) {
        guard indicatorState != state else { return }
        indicatorState = state
        updateVisibility(hidden: settings.hideMenuBarIcon)
        applyIndicatorState()
    }

    /// The indicator shows even when the menu bar icon is hidden, for as long as the recording runs or stops.
    private func updateVisibility(hidden: Bool) {
        statusItem?.isVisible = !hidden || indicatorState != .idle
    }

    private func recordingDotImage() -> NSImage? {
        let dot = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed])))
        dot?.isTemplate = false
        return dot
    }

    private func applyIndicatorState() {
        clockTask?.cancel()
        clockTask = nil
        guard let item = statusItem, let button = item.button else { return }

        switch indicatorState {
        case .idle:
            item.menu = menu
            button.target = nil
            button.action = nil
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = String(localized: "PrtSc")
            button.setAccessibilityLabel(String(localized: "PrtSc"))
            button.setAccessibilityHelp(nil)

        case let .recording(start):
            // No menu while recording: a click stops (see `statusButtonClicked`).
            item.menu = nil
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = recordingDotImage()
            button.imagePosition = .imageLeading
            let help = String(localized: "Click to stop the Screencast. Right-click or Control-click to open the menu.")
            button.toolTip = help
            button.setAccessibilityHelp(help)
            updateClock(startDate: start)

            // Tick on the second boundaries of the recording, so the text changes when the second does.
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    let untilNextSecond = 1 - elapsed.truncatingRemainder(dividingBy: 1)
                    try? await Task.sleep(for: .milliseconds(Int(untilNextSecond * 1000) + 20))
                    guard !Task.isCancelled else { return }
                    self?.updateClock(startDate: start)
                }
            }

        case .stopping:
            item.menu = nil
            button.target = nil
            button.action = nil
            button.image = recordingDotImage()
            button.imagePosition = .imageLeading
            let stopping = String(localized: "Stopping…")
            button.attributedTitle = NSAttributedString(
                string: " " + stopping,
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
            button.toolTip = stopping
            button.setAccessibilityLabel(String(localized: "Stopping Screencast"))
            button.setAccessibilityHelp(nil)
        }
    }

    private func updateClock(startDate: Date) {
        guard let button = statusItem?.button else { return }
        let text = RecordingClock.format(elapsed: Date().timeIntervalSince(startDate))
        button.attributedTitle = NSAttributedString(
            string: " " + text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
        button.setAccessibilityLabel(String(localized: "Recording Screencast, \(text)"))
    }

    /// While recording: click stops the Screencast; right-click or ⌃-click opens the menu instead.
    @objc private func statusButtonClicked() {
        guard case .recording = indicatorState else { return }
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard wantsMenu, let item = statusItem, let menu else {
            onStopScreencast?()
            return
        }
        // Borrow the standard menu for one tracking session.
        item.menu = menu
        item.button?.performClick(nil)
        if indicatorState != .idle { item.menu = nil }
    }

    func remove() {
        clockTask?.cancel()
        clockTask = nil
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
        let active = indicatorState != .idle
        if active {
            let stopItem = captureItem(.screencast, selector: #selector(stopScreencast),
                                       title: String(localized: "Stop Screencast"), symbol: "stop.circle")
            if case .stopping = indicatorState { stopItem.isEnabled = false }
            menu.addItem(stopItem)
            menu.addItem(.separator())
        }
        let takeScreenshot = captureItem(.openScreenshotUI, selector: #selector(takeScreenshot),
                                         symbol: "camera.viewfinder")
        // The Screenshot UI can't open during a recording.
        takeScreenshot.isEnabled = !active
        menu.addItem(takeScreenshot)
        menu.addItem(captureItem(.instantScreen, selector: #selector(captureScreen), symbol: "display"))
        menu.addItem(captureItem(.instantWindow, selector: #selector(captureWindow), symbol: "macwindow"))
        if !active {
            menu.addItem(captureItem(.screencast, selector: #selector(recordScreencast), symbol: "record.circle"))
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open Save Folder"), #selector(openSaveFolder), symbol: "folder"))
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings),
                          key: ",", modifiers: [.command], symbol: "gearshape"))
        let updates = item(String(localized: "Check for Updates…"), #selector(checkForUpdates),
                           symbol: "arrow.triangle.2.circlepath")
        updates.isEnabled = canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit PrtSc"), #selector(quit),
                          key: "q", modifiers: [.command], symbol: "power"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = [], symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.isEnabled = true
        if let symbol {
            item.image = menuSymbol(symbol)
        }
        return item
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration.preferringMonochrome())
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// A capture item with its current shortcut as a key equivalent, or as plain text when the menu can't express it.
    private func captureItem(_ action: HotkeyAction, selector: Selector,
                             title: String? = nil, symbol: String) -> NSMenuItem {
        let title = title ?? action.title
        let combo = settings.hotkeys.bindings[action]
        if let combo, let key = KeyCodes.menuKeyEquivalent(for: combo.keyCode) {
            return item(title, selector, key: key,
                        modifiers: KeyCodes.menuModifierMask(combo.modifiers), symbol: symbol)
        }
        return item(combo.map { "\(title)  \($0.displayString)" } ?? title, selector, symbol: symbol)
    }

    @objc private func takeScreenshot() { onTakeScreenshot?() }
    @objc private func captureScreen() { onCaptureScreen?() }
    @objc private func captureWindow() { onCaptureWindow?() }
    @objc private func openSaveFolder() { onOpenSaveFolder?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func recordScreencast() { onRecordScreencast?() }
    @objc private func stopScreencast() { onStopScreencast?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
