import AppKit
import Observation
import PrtScCore

/// Where a Window Picker cell sits (global CG points) for one window.
struct WindowCell: Sendable {
    let windowID: UInt32
    let rect: CGRect
}

/// All state of one open Screenshot UI, shared by every overlay panel and the CapturePanel.
/// AppKit views redraw through `onChange`; SwiftUI observes the model directly.
@MainActor
@Observable
final class ScreenshotUIModel {
    let frame: FrozenFrame
    let displays: [DisplayInfo]
    let panelDisplayID: UInt32
    /// Window Picker cells per display ID, in `frame.windows` order (front to back).
    let windowCells: [UInt32: [WindowCell]]

    private(set) var mode: CaptureMode
    private(set) var showPointer: Bool
    private(set) var editor: SelectionEditor
    private(set) var selectedDisplayID: UInt32
    private(set) var selectedWindowID: UInt32?

    @ObservationIgnored private let session: SessionState
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onCapture: ((CapturedImage) -> Void)?

    /// Window mode needs at least one window to pick.
    var windowModeAvailable: Bool { windowCells.values.contains { !$0.isEmpty } }

    init(frame: FrozenFrame, session: SessionState, frontmostPID: Int32?) {
        let displays = frame.displays.map(\.info)
        let panelDisplayID = DisplayGeometry.panelDisplay(pointer: frame.pointer, displays: displays)?.displayID
            ?? displays.first?.displayID ?? 0
        let primaryFrame = (displays.first(where: \.isPrimary) ?? displays.first)?.frame ?? .zero
        let cells = Self.windowCells(for: frame)
        let placed = Set(cells.values.flatMap { $0 }.map(\.windowID))
        let candidates = frame.windows.filter { placed.contains($0.info.windowID) }
        let wanted = session.lastCaptureMode

        self.frame = frame
        self.displays = displays
        self.session = session
        self.panelDisplayID = panelDisplayID
        self.windowCells = cells
        self.showPointer = session.showPointer
        self.editor = SelectionEditor(bounds: DisplayGeometry.union(of: displays),
                                      primaryDisplayFrame: primaryFrame,
                                      remembered: session.rememberedSelection)
        // Screen mode preselects the display under the pointer.
        self.selectedDisplayID = DisplayGeometry.display(containing: frame.pointer, in: displays)?.displayID
            ?? panelDisplayID
        // Window mode preselects the frontmost window: the front-most one of the frontmost application,
        // else the front-most overall.
        self.selectedWindowID = (candidates.first(where: { $0.info.ownerPID == frontmostPID })
            ?? candidates.first)?.info.windowID
        // Window mode is disabled without windows and falls back to Selection.
        self.mode = (wanted == .window && candidates.isEmpty) ? .selection : wanted
    }

    // MARK: Mode and options

    func setMode(_ newMode: CaptureMode) {
        if newMode == .window && !windowModeAvailable { return }
        guard newMode != mode else { return }
        mode = newMode
        session.lastCaptureMode = newMode
        announce(newMode.announcement)
        if newMode == .selection { announceSelectionSize() }
        notify()
    }

    func togglePointer() {
        showPointer.toggle()
        session.showPointer = showPointer
        announce(showPointer ? String(localized: "Show Pointer on") : String(localized: "Show Pointer off"))
        notify()
    }

    // MARK: Screen and Window choice

    func selectDisplay(_ displayID: UInt32) {
        guard displayID != selectedDisplayID, displays.contains(where: { $0.displayID == displayID }) else { return }
        selectedDisplayID = displayID
        notify()
    }

    func selectWindow(at point: CGPoint) {
        for cell in windowCells.values.joined() where cell.rect.contains(point) {
            if selectedWindowID != cell.windowID {
                selectedWindowID = cell.windowID
                announceSelectedWindow()
                notify()
            }
            return
        }
    }

    func cells(on display: DisplayInfo) -> [WindowCell] {
        windowCells[display.displayID] ?? []
    }

    /// Every Window Picker cell, front to back (deterministic, unlike the per-display dictionary).
    private var orderedCells: [WindowCell] {
        let cells = Dictionary(uniqueKeysWithValues: windowCells.values.joined().map { ($0.windowID, $0) })
        return frame.windows.compactMap { cells[$0.info.windowID] }
    }

    func snapshot(forWindow id: UInt32) -> WindowSnapshot? {
        frame.windows.first { $0.info.windowID == id }
    }

    /// Arrow keys in Screen and Window mode move the choice to the nearest neighbour in that direction.
    private func navigate(_ direction: ArrowDirection) {
        switch mode {
        case .screen:
            guard let current = displays.first(where: { $0.displayID == selectedDisplayID }) else { return }
            let best = DirectionalNavigation.nearest(from: current.frame, in: displays.map { ($0.displayID, $0.frame) },
                                                  direction: direction)
            if let best { selectDisplay(best) }
        case .window:
            let all = orderedCells.map { ($0.windowID, $0.rect) }
            guard let id = selectedWindowID, let current = all.first(where: { $0.0 == id }) else { return }
            if let best = DirectionalNavigation.nearest(from: current.1, in: all, direction: direction) {
                selectedWindowID = best
                announceSelectedWindow()
                notify()
            }
        case .selection:
            break
        }
    }

    // MARK: Selection (mouse)

    /// The handle under `point`, using the same tolerance `dragBegan` uses to grab one.
    func handle(at point: CGPoint) -> SelectionHandle {
        editor.handle(at: point, tolerance: editor.handleTolerance)
    }

    func dragBegan(at point: CGPoint, forceNew: Bool) {
        editor.dragBegan(at: point, forceNew: forceNew)
        notify()
    }

    func dragMoved(to point: CGPoint) {
        editor.dragMoved(to: point)
        notify()
    }

    func dragEnded(at point: CGPoint) {
        editor.dragEnded(at: point)
        session.rememberedSelection = editor.rect
        announceSelectionSize()
        notify()
    }

    // MARK: Keys

    /// Returns true when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Esc
            close()
            return true
        case 36, 76, 49: // Return, Enter, Space
            capture()
            return true
        case 123, 124, 125, 126:
            let direction: ArrowDirection = switch event.keyCode {
            case 123: .left
            case 124: .right
            case 125: .down
            default: .up
            }
            if mode == .selection {
                var modifiers: EditModifiers = []
                if flags.contains(.option) { modifiers.insert(.move) }
                if flags.contains(.command) { modifiers.insert(.fine) }
                if flags.contains(.shift) { modifiers.insert(.large) }
                editor.handleArrow(direction, modifiers: modifiers)
                session.rememberedSelection = editor.rect
                announceSelectionSize()
                notify()
            } else {
                navigate(direction)
            }
            return true
        default:
            break
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if flags.contains(.command) {
            // ⌘C captures; every other ⌘ shortcut is left alone.
            guard character == "c", !flags.contains(.option), !flags.contains(.control) else { return false }
            capture()
            return true
        }
        guard !flags.contains(.control), !flags.contains(.option) else { return false }
        if let newMode = CaptureMode.forKey(character) {
            setMode(newMode)
            return true
        }
        switch character {
        case "p":
            togglePointer()
            return true
        case "r" where mode == .selection:
            editor.reset()
            session.rememberedSelection = editor.rect
            announceSelectionSize()
            notify()
            return true
        default:
            return false
        }
    }

    // MARK: Capture and close

    func close() {
        onClose?()
    }

    func capture() {
        guard let captured = makeCapture() else {
            NSSound.beep()
            return
        }
        session.lastCaptureMode = mode
        session.rememberedSelection = editor.rect
        onCapture?(captured)
    }

    /// Cuts the image for the current mode out of the Frozen Frame.
    private func makeCapture() -> CapturedImage? {
        switch mode {
        case .selection:
            return ScreenCapturer.stitch(rect: editor.rect, from: frame.displays, showsPointer: showPointer)
        case .screen:
            guard let snapshot = frame.displays.first(where: { $0.info.displayID == selectedDisplayID }) else {
                return nil
            }
            // The same image the overlay shows for this display.
            return CapturedImage(image: snapshot.image(showingPointer: showPointer), scale: snapshot.info.scale)
        case .window:
            guard let id = selectedWindowID, let snapshot = snapshot(forWindow: id) else { return nil }
            // The same image the Window Picker shows for this window.
            return CapturedImage(image: snapshot.image(showingPointer: showPointer), scale: snapshot.scale)
        }
    }

    // MARK: Announcements and notifications

    private func notify() {
        onChange?()
    }

    private func announceSelectionSize() {
        let width = Int(editor.rect.width.rounded())
        let height = Int(editor.rect.height.rounded())
        announce(String(localized: "\(width) by \(height)", comment: "Spoken selection size: width by height in points"))
    }

    private func announceSelectedWindow() {
        guard let id = selectedWindowID, let info = snapshot(forWindow: id)?.info else { return }
        let app = NSRunningApplication(processIdentifier: info.ownerPID)?.localizedName
        let title = [app, info.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !title.isEmpty { announce(title) }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Geometry helpers

    /// Window Picker cells for every display: each window goes to the display that shows most of it
    /// (`DisplayGeometry.displayShowingMost`), laid out in an Overview-style grid that leaves room for the
    /// CapturePanel at the bottom.
    private static func windowCells(for frame: FrozenFrame) -> [UInt32: [WindowCell]] {
        let infos = frame.displays.map(\.info)
        var byDisplay: [UInt32: [WindowSnapshot]] = [:]
        for window in frame.windows {
            guard let display = DisplayGeometry.displayShowingMost(of: window.info.frame, displays: infos) else {
                continue
            }
            byDisplay[display.displayID, default: []].append(window)
        }

        var result: [UInt32: [WindowCell]] = [:]
        for display in infos {
            guard let windows = byDisplay[display.displayID], !windows.isEmpty else { continue }
            let bounds = display.frame
            let area = CGRect(x: bounds.minX + 60, y: bounds.minY + 80,
                              width: max(bounds.width - 120, 1), height: max(bounds.height - 80 - 170, 1))
            let sizes = windows.map {
                CGSize(width: CGFloat($0.image.width) / $0.scale, height: CGFloat($0.image.height) / $0.scale)
            }
            let rects = WindowPickerLayout.layout(sizes: sizes, in: area, spacing: 24)
            result[display.displayID] = zip(windows, rects).map {
                WindowCell(windowID: $0.info.windowID, rect: $1)
            }
        }
        return result
    }
}
