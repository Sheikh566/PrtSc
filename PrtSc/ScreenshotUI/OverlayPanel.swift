import AppKit

/// One borderless, key-capable panel per display, covering it at `.screenSaver` level.
final class OverlayPanel: NSPanel {
    /// Receives key-downs first. Returns true when the key was handled.
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// `frame` is in AppKit global coordinates.
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        setFrame(frame, display: false)
    }

    /// Borderless panels must still cover the whole screen, including the menu bar area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// ⌘-combinations (⌘C, ⌘←…) reach the window here before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.contains(.command), keyHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
