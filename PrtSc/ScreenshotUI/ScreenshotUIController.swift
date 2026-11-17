import AppKit
import os
import PrtScCore

enum ScreenshotUIError: LocalizedError {
    /// macOS didn't make PrtSc the active app in time, so the overlay would not receive keyboard input.
    case activationFailed

    var errorDescription: String? {
        switch self {
        case .activationFailed: String(localized: "PrtSc couldn't take keyboard focus to open the Screenshot UI.")
        }
    }
}

/// The Screenshot UI: freezes the screen and shows overlay panels + the CapturePanel.
///
/// Opening is a *session*: freeze the screen, make PrtSc the active app, and only then show the panels.
/// The session exists from the moment the open hotkey is pressed, so a second press, `dismiss()` or a
/// display change while the screen is still being frozen cancels it, and a stale freeze never presents.
@MainActor
final class ScreenshotUIController {
    private static let log = Logger(subsystem: "io.github.sheikh566.PrtSc", category: "ScreenshotUI")

    /// How long to wait for macOS to make PrtSc the active app before giving up.
    private static let activationTimeout: Duration = .seconds(1)

    /// Everything that exists only while the Screenshot UI is shown.
    private struct Presentation {
        let model: ScreenshotUIModel
        let panels: [OverlayPanel]
        let overlays: [OverlayView]
        let observers: [NSObjectProtocol]
    }

    /// One open request, from the hotkey press until the UI is dismissed.
    private final class Session {
        /// Compared with the controller's current generation: a session that has been dismissed or
        /// replaced is stale and must not present, whatever its task is still doing.
        let generation: Int
        /// The app that had focus when the UI was requested.
        let previousApp: NSRunningApplication?
        var task: Task<Void, Never>?
        /// Displays changed: the frozen images no longer match. Installed from the start, so it covers
        /// preparation as well as presentation.
        var screenObserver: NSObjectProtocol?
        var presentation: Presentation?

        init(generation: Int, previousApp: NSRunningApplication?) {
            self.generation = generation
            self.previousApp = previousApp
        }
    }

    private let capturer: ScreenCapturer
    private let output: CaptureSink
    private let settings: SettingsStore
    private let session: SessionState

    private var current: Session?
    private var generation = 0

    var isPresented: Bool { current?.presentation != nil }

    /// Called on the main actor when the Screenshot UI can't be opened (e.g. Screen Recording is missing,
    /// or macOS refused to activate PrtSc).
    var onFailure: (@MainActor (Error) -> Void)?

    init(capturer: ScreenCapturer, output: CaptureSink, settings: SettingsStore, session: SessionState) {
        self.capturer = capturer
        self.output = output
        self.settings = settings
        self.session = session
    }

    /// Opens the Screenshot UI; closes it (or cancels opening it) if already open or opening, which is
    /// what the open hotkey does while the UI is up.
    func toggle() {
        if current != nil {
            dismiss()
            return
        }

        // Read these before PrtSc does anything (or anything suspends) that could change them.
        let pointer = PointerSample.current()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let includeShadows = settings.includeWindowShadow

        generation += 1
        let newSession = Session(generation: generation, previousApp: frontmost)
        newSession.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        current = newSession
        newSession.task = Task { [weak self] in
            await self?.prepare(newSession, includeShadows: includeShadows, pointer: pointer)
        }
    }

    /// Closes the Screenshot UI, or cancels it while it's still opening.
    /// - Parameter restoreFocus: give focus back to the app that had it when the UI opened. False when the
    ///   user just switched away on their own (⌘Tab), so that choice isn't overridden.
    func dismiss(restoreFocus: Bool = true) {
        guard let ending = current else { return }
        current = nil
        // Invalidate anything still in flight for this session.
        generation += 1
        ending.task?.cancel()
        if let token = ending.screenObserver { NotificationCenter.default.removeObserver(token) }

        if let presentation = ending.presentation {
            for token in presentation.observers { NotificationCenter.default.removeObserver(token) }
            presentation.model.onChange = nil
            presentation.model.onClose = nil
            presentation.model.onCapture = nil
            for panel in presentation.panels {
                panel.keyHandler = nil
                panel.orderOut(nil)
                panel.contentView = nil
                panel.close()
            }
        }
        if restoreFocus { Self.restoreFocus(to: ending.previousApp) }
    }

    // MARK: Preparing

    private func isCurrent(_ session: Session) -> Bool {
        current === session && generation == session.generation && !Task.isCancelled
    }

    /// Freeze the screen, wait until PrtSc is the active app, then present. Every step after an `await`
    /// re-checks that the session is still the current one.
    private func prepare(_ session: Session, includeShadows: Bool, pointer: PointerSample) async {
        do {
            // The Frozen Frame is taken before any PrtSc window is shown.
            let frame = try await capturer.freezeFrame(includeShadows: includeShadows, pointer: pointer)
            guard isCurrent(session) else { return }
            guard !frame.displays.isEmpty else { throw ScreenCapturerError.noDisplays }

            // Panels must not cover the screen until PrtSc is active: otherwise keyboard input stays with
            // the previous app and PrtSc never gets the resignation that dismisses the UI.
            guard await activate(for: session) else {
                guard isCurrent(session) else { return }
                throw ScreenshotUIError.activationFailed
            }
            guard isCurrent(session) else { return }
            present(frame: frame, in: session)
        } catch {
            guard isCurrent(session) else { return }
            Self.log.error("Opening the Screenshot UI failed: \(error.localizedDescription, privacy: .public)")
            dismiss(restoreFocus: false)
            onFailure?(error)
        }
    }

    /// Makes PrtSc the active app and waits (briefly) for macOS to confirm it. `activate()` is a request
    /// that the system may decline. False if it wasn't confirmed in time or the session went stale.
    private func activate(for session: Session) async -> Bool {
        let app = NSApplication.shared
        if app.isActive { return true }
        app.activate()
        let deadline = ContinuousClock.now.advanced(by: Self.activationTimeout)
        while !app.isActive {
            guard isCurrent(session), ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return true
    }

    // MARK: Presenting

    /// Builds the panels and shows them. Runs synchronously right after the last staleness check.
    private func present(frame: FrozenFrame, in session: Session) {
        let model = ScreenshotUIModel(frame: frame, session: self.session,
                                      frontmostPID: session.previousApp?.processIdentifier)
        var panels: [OverlayPanel] = []
        var overlays: [OverlayView] = []
        for snapshot in frame.displays {
            let panel = OverlayPanel(frame: CoordinateSpace.appKitRect(fromGlobalCG: snapshot.info.frame))
            let overlay = OverlayView(model: model, snapshot: snapshot)
            panel.contentView = overlay
            panel.keyHandler = { [weak model] event in model?.handleKeyDown(event) ?? false }
            panels.append(panel)
            overlays.append(overlay)
        }

        model.onChange = { [weak self] in
            self?.current?.presentation?.overlays.forEach { $0.refresh() }
        }
        model.onClose = { [weak self] in self?.dismiss() }
        model.onCapture = { [weak self] captured in self?.finish(with: captured) }

        // Switching to another app (⌘Tab) closes the UI instead of leaving a screen-wide overlay behind.
        // Installed only now that PrtSc is active, so it can't fire for an activation that never happened.
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }

        session.presentation = Presentation(model: model, panels: panels, overlays: overlays, observers: [resign])

        for (index, panel) in panels.enumerated() where frame.displays[index].info.displayID != model.panelDisplayID {
            panel.orderFrontRegardless()
        }
        if let index = frame.displays.firstIndex(where: { $0.info.displayID == model.panelDisplayID }) {
            panels[index].makeKeyAndOrderFront(nil)
            panels[index].makeFirstResponder(overlays[index])
        }
    }

    /// Closes the overlay first, then hands the image to the output.
    private func finish(with captured: CapturedImage) {
        dismiss()
        let output = output
        Task { await output.deliver(captured) }
    }

    // MARK: Focus

    /// Gives focus back to `previous` with cooperative activation: PrtSc yields, then the other app
    /// activates itself. Calling `activate()` alone can leave PrtSc active after its panels are gone.
    private static func restoreFocus(to previous: NSRunningApplication?) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let previous, !previous.isTerminated, previous.processIdentifier != ownPID,
              NSApplication.shared.isActive else { return }
        NSApplication.shared.yieldActivation(to: previous)
        previous.activate(from: NSRunningApplication.current, options: [])
    }
}
