import AppKit
import Carbon.HIToolbox
import Observation
import PrtScCore
import SwiftUI

/// Records one shortcut. Click to record; Esc cancels; ⌫ clears; needs a modifier unless it is an F-key.
/// All rows of a Settings window share one `HotkeyRecordingSession`, so only one row records at a time.
struct HotkeyRecorderView: View {
    let action: HotkeyAction
    @Binding var combo: KeyCombo?
    let session: HotkeyRecordingSession

    private var isRecording: Bool { session.activeAction == action }

    var body: some View {
        let canClear = combo != nil && !isRecording
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    session.cancel()
                } else {
                    session.start(for: action) { newCombo in
                        combo = newCombo
                    }
                }
            } label: {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .accessibilityLabel(Text("Shortcut for \(action.settingsTitle)"))
            .accessibilityValue(isRecording ? Text("Recording shortcut") : Text(label))
            .accessibilityHint(Text("Click, then press the new shortcut"))

            Button {
                combo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Clear shortcut for \(action.settingsTitle)"))
            .help(Text("Clear shortcut"))
            .disabled(!canClear)
            .allowsHitTesting(canClear)
            .accessibilityHidden(!canClear)
            .opacity(canClear ? 1 : 0)
        }
        .onDisappear {
            if isRecording { session.cancel() }
        }
    }

    private var label: String {
        if isRecording {
            return session.hint ?? String(localized: "Type shortcut…")
        }
        return combo?.displayString ?? String(localized: "Not set")
    }
}

/// The one shortcut-recording session of the Settings window (one NSEvent local monitor in total).
/// Starting a recording for a row cancels whichever row was recording. `onActiveChange` is called with
/// true when recording goes from idle to active and false when it goes back to idle, so the owner can
/// suspend global hotkeys once and resume them only when no row is recording. The owner also calls
/// `cancel()` when the Settings window resigns key or closes.
@MainActor
@Observable
final class HotkeyRecordingSession {
    /// The row that is recording, if any.
    private(set) var activeAction: HotkeyAction?
    /// Shown instead of the prompt after an invalid key press (e.g. no modifier).
    private(set) var hint: String?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onCapture: ((KeyCombo?) -> Void)?
    @ObservationIgnored private let onActiveChange: @MainActor (Bool) -> Void

    init(onActiveChange: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.onActiveChange = onActiveChange
    }

    var isRecording: Bool { activeAction != nil }

    func start(for action: HotkeyAction, onCapture: @escaping (KeyCombo?) -> Void) {
        let wasRecording = isRecording
        removeMonitor()
        self.onCapture = onCapture
        hint = nil
        activeAction = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
        if !wasRecording { onActiveChange(true) }
    }

    /// Ends the current recording, if any. Safe to call when idle.
    func cancel() {
        removeMonitor()
        onCapture = nil
        hint = nil
        guard activeAction != nil else { return }
        activeAction = nil
        onActiveChange(false)
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let modifiers = KeyCodes.keyModifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))

        if keyCode == UInt32(kVK_Escape) && modifiers.isEmpty {
            cancel()
            return true
        }
        if (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) && modifiers.isEmpty {
            finish(with: nil)
            return true
        }
        guard !modifiers.isEmpty || KeyCodes.isFunctionKey(keyCode) else {
            let message = String(localized: "Add a modifier key")
            hint = message
            NSSound.beep()
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return true
        }
        finish(with: KeyCombo(keyCode: keyCode, modifiers: modifiers))
        return true
    }

    private func finish(with combo: KeyCombo?) {
        let capture = onCapture
        cancel()
        capture?(combo)
    }
}
