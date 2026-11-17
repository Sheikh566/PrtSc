import Carbon.HIToolbox
import Observation
import PrtScCore

/// Registers global hotkeys with Carbon `RegisterEventHotKey` (no Accessibility permission needed).
@MainActor
@Observable
final class HotkeyManager {
    /// Combos that macOS refused to register (taken by another app or the system). Shown in Settings.
    private(set) var failedCombos: Set<KeyCombo> = []

    @ObservationIgnored private var handler: (@MainActor (HotkeyAction) -> Void)?
    @ObservationIgnored private var bindings: HotkeyBindings = .defaults
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var registrations: [UInt32: (ref: EventHotKeyRef, action: HotkeyAction)] = [:]
    @ObservationIgnored private var eventHandlerRef: EventHandlerRef?
    @ObservationIgnored private var nextID: UInt32 = 1

    private static let signature: OSType = 0x5052_5453 // 'PRTS'

    init() {}

    /// Registers bindings + HotkeyBindings.printKeyAliases. Call again when settings change.
    func register(_ bindings: HotkeyBindings, handler: @escaping @MainActor (HotkeyAction) -> Void) {
        self.bindings = bindings
        self.handler = handler
        registerIfActive()
    }

    /// Unregisters every hot key (the bindings and handler are kept for `resume()`).
    func unregisterAll() {
        for (_, registration) in registrations {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        failedCombos = []
    }

    /// Temporarily unregisters everything (the shortcut recorder must see the keys itself).
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        registerIfActive()
    }

    // MARK: - Registration

    private func registerIfActive() {
        unregisterAll()
        guard !isSuspended, handler != nil else { return }
        installEventHandlerIfNeeded()

        var failed: Set<KeyCombo> = []
        var seen: Set<KeyCombo> = []
        // User bindings first, so they win over an identical alias.
        var wanted: [(KeyCombo, HotkeyAction)] = []
        for action in HotkeyAction.allCases {
            if let combo = bindings.bindings[action] { wanted.append((combo, action)) }
        }
        for (combo, action) in HotkeyBindings.printKeyAliases.sorted(by: { $0.value.rawValue < $1.value.rawValue }) {
            wanted.append((combo, action))
        }
        for (combo, action) in wanted where seen.insert(combo).inserted {
            if !registerHotKey(combo, action: action) {
                failed.insert(combo)
            }
        }
        failedCombos = failed
    }

    private func registerHotKey(_ combo: KeyCombo, action: HotkeyAction) -> Bool {
        let id = nextID
        nextID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode,
                                         Self.carbonModifiers(combo.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        registrations[id] = (ref, action)
        return true
    }

    static func carbonModifiers(_ modifiers: KeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    // MARK: - Event handling

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated {
                manager.takeUnretainedValue().fire(id: id)
            }
            return noErr
        }, 1, &eventType, userData, &eventHandlerRef)
    }

    private func fire(id: UInt32) {
        guard let action = registrations[id]?.action else { return }
        handler?(action)
    }
}
