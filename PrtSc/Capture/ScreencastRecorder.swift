import AppKit
import AVFoundation
import CoreMedia
import Observation
import os
import PrtScCore
import ScreenCaptureKit

/// What a Screencast records.
enum ScreencastTarget: Equatable, Sendable {
    /// A Selection (global CG points), already known to belong mostly to `display`. A Selection that spans
    /// displays is clamped to that display (`RecordingGeometry.region`).
    case selection(rect: CGRect, display: DisplayInfo)
    /// One whole display.
    case display(id: UInt32)
    /// One window, followed as it moves (`SCContentFilter(desktopIndependentWindow:)`).
    case window(id: UInt32)

    /// The display whose disappearance ends the recording; nil for a window.
    var displayID: UInt32? {
        switch self {
        case let .selection(_, display): display.displayID
        case let .display(id): id
        case .window: nil
        }
    }
}

struct ScreencastOptions: Sendable {
    /// The Screencast Folder; it already exists.
    var folder: URL
    var showsPointer: Bool
    var recordSystemAudio: Bool
    var recordMicrophone: Bool
    /// H.264 instead of HEVC.
    var preferH264: Bool
}

enum ScreencastError: LocalizedError {
    case busy
    case emptySelection
    case microphoneDenied
    case startFailed(Error)
    /// The recording ended early (the system stopped it, the disk filled up, …). `savedFile` is the part
    /// that was kept, if it is playable.
    case interrupted(reason: String, savedFile: URL?)
    case couldNotFinish

    var errorDescription: String? {
        switch self {
        case .busy:
            String(localized: "A Screencast is already being recorded.")
        case .emptySelection:
            String(localized: "The selected area isn't on a display.")
        case .microphoneDenied:
            String(localized: "PrtSc doesn't have access to the microphone. Allow it in System Settings › Privacy & Security › Microphone, or turn off “Record microphone” in PrtSc Settings.")
        case let .startFailed(error):
            Self.describe(error)
        case let .interrupted(reason, savedFile):
            if let savedFile {
                reason + "\n\n" + String(localized: "The part that was recorded is saved as “\(savedFile.lastPathComponent)”.")
            } else {
                reason
            }
        case .couldNotFinish:
            String(localized: "The recording could not be saved.")
        }
    }

    /// The file that was kept after an interruption.
    var savedFile: URL? {
        if case let .interrupted(_, savedFile) = self { return savedFile }
        return nil
    }

    private static let streamErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"

    /// SCStreamError codes (raw values; `insufficientStorage` only exists in newer SDKs).
    enum StreamCode {
        static let userDeclined = -3801
        static let noWindowList = -3813
        static let noDisplayList = -3814
        static let noCaptureSource = -3815
        static let userStopped = -3817
        static let failedToStartAudioCapture = -3818
        static let failedToStartMicrophoneCapture = -3820
        static let systemStoppedStream = -3821
        static let insufficientStorage = -3822
    }

    static func streamCode(of error: Error) -> Int? {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain || ns.domain == streamErrorDomain ? ns.code : nil
    }

    /// A user-facing reason for a ScreenCaptureKit failure.
    static func describe(_ error: Error) -> String {
        switch streamCode(of: error) {
        case StreamCode.userDeclined:
            String(localized: "PrtSc doesn't have permission to record the screen. Allow it in System Settings › Privacy & Security › Screen & System Audio Recording.")
        case StreamCode.insufficientStorage:
            String(localized: "There isn't enough free disk space to keep recording.")
        case StreamCode.systemStoppedStream:
            String(localized: "macOS stopped the recording.")
        case StreamCode.failedToStartAudioCapture:
            String(localized: "System audio couldn't be recorded.")
        case StreamCode.failedToStartMicrophoneCapture:
            String(localized: "The microphone couldn't be recorded.")
        case StreamCode.noWindowList, StreamCode.noDisplayList, StreamCode.noCaptureSource:
            String(localized: "The window or display being recorded is no longer available.")
        default:
            error.localizedDescription
        }
    }
}

/// Records a Screencast: `SCStream` + `SCRecordingOutput` writing an .mp4 straight into the Screencast
/// Folder. State machine: idle → starting → recording(startDate:) → stopping → idle.
///
/// The file is written under its final name (`FilenameBuilder.uniqueURL`, never an existing file). It is
/// reported through `onFinished` once ScreenCaptureKit has finalized it; if the recording ends early
/// (`didStopWithError`, a failed output, a full disk) what was written is kept when it plays, and
/// `onFailure` gets a `ScreencastError.interrupted`. A window that closes or a display that is unplugged
/// ends the recording normally (stop and save).
@MainActor
@Observable
final class ScreencastRecorder {
    enum State: Equatable, Sendable {
        case idle
        case starting
        case recording(startDate: Date)
        case stopping
    }

    private static let log = Logger(subsystem: "io.github.sheikh566.PrtSc", category: "Screencast")

    /// How long to wait for ScreenCaptureKit to finalize the file after the stream stopped.
    private static let finalizeTimeout: Duration = .seconds(10)
    /// After the last shared window disappears, how long to wait before checking whether it really closed
    /// (a minimized window also reports "inactive" but keeps its ID).
    private static let windowGoneGracePeriod: Duration = .milliseconds(1500)

    private(set) var state: State = .idle

    /// The finished, playable file.
    @ObservationIgnored var onFinished: (@MainActor (URL) -> Void)?
    /// The recording failed to start or ended early.
    @ObservationIgnored var onFailure: (@MainActor (Error) -> Void)?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Anything but idle: starting, recording or stopping.
    var isBusy: Bool { state != .idle }

    // MARK: Internals

    private enum StopCause {
        /// The user (or a system "stop sharing" control) ended it.
        case requested
        /// The window closed or the display went away.
        case targetGone
        case failed(Error)
    }

    private enum OutputResult {
        case finished
        case failed(Error)
    }

    private final class Session {
        let id: Int
        let stream: SCStream
        let output: SCRecordingOutput
        let delegate: Delegate
        let fileURL: URL
        let target: ScreencastTarget
        /// A stop that arrived before the stream finished starting.
        var pendingCause: StopCause?
        var outputResult: OutputResult?
        var isInactive = false

        init(id: Int, stream: SCStream, output: SCRecordingOutput, delegate: Delegate,
             fileURL: URL, target: ScreencastTarget) {
            self.id = id
            self.stream = stream
            self.output = output
            self.delegate = delegate
            self.fileURL = fileURL
            self.target = target
        }
    }

    /// ScreenCaptureKit calls these on its own queues; every callback hops to the main actor.
    private final class Delegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
        let onStreamStopped: @Sendable (Error) -> Void
        let onActivity: @Sendable (_ isActive: Bool) -> Void
        let onOutputFinished: @Sendable () -> Void
        let onOutputFailed: @Sendable (Error) -> Void

        init(onStreamStopped: @escaping @Sendable (Error) -> Void,
             onActivity: @escaping @Sendable (Bool) -> Void,
             onOutputFinished: @escaping @Sendable () -> Void,
             onOutputFailed: @escaping @Sendable (Error) -> Void) {
            self.onStreamStopped = onStreamStopped
            self.onActivity = onActivity
            self.onOutputFinished = onOutputFinished
            self.onOutputFailed = onOutputFailed
        }

        func stream(_ stream: SCStream, didStopWithError error: any Error) { onStreamStopped(error) }
        func streamDidBecomeActive(_ stream: SCStream) { onActivity(true) }
        func streamDidBecomeInactive(_ stream: SCStream) { onActivity(false) }
        func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { onOutputFinished() }
        func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
            onOutputFailed(error)
        }
    }

    @ObservationIgnored private var session: Session?
    /// A stop requested while starting but before the session exists (microphone check / setup still
    /// running). The session's `pendingCause` takes over once it's created.
    @ObservationIgnored private var stopRequestedWhileStarting = false
    @ObservationIgnored private var nextSessionID = 0
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init() {}

    // MARK: Start

    /// Starts recording. Throws (and stays idle) when the target is gone, permission is missing or
    /// ScreenCaptureKit refuses; a second call while busy throws `ScreencastError.busy`.
    func start(target: ScreencastTarget, options: ScreencastOptions) async throws {
        guard state == .idle else { throw ScreencastError.busy }
        state = .starting
        stopRequestedWhileStarting = false
        defer { stopRequestedWhileStarting = false }
        var fileURL: URL?
        do {
            if options.recordMicrophone { try await Self.ensureMicrophoneAccess() }

            let (filter, configuration) = try await Self.makeCapture(for: target, options: options)

            // Stopped before anything was created: don't start at all (no file, no notification).
            if stopRequestedWhileStarting {
                state = .idle
                Self.log.info("Screencast cancelled while starting")
                return
            }

            // Never overwrite: the first free "Screencast from … .mp4".
            let url = FilenameBuilder.uniqueURL(in: options.folder, date: Date(), prefix: "Screencast",
                                                pathExtension: "mp4") {
                FileManager.default.fileExists(atPath: $0.path)
            }

            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = url
            outputConfiguration.outputFileType = .mp4
            let wanted: AVVideoCodecType = options.preferH264 ? .h264 : .hevc
            outputConfiguration.videoCodecType =
                outputConfiguration.availableVideoCodecTypes.contains(wanted) ? wanted : .h264

            nextSessionID += 1
            let id = nextSessionID
            let delegate = Delegate(
                onStreamStopped: { [weak self] error in
                    Task { @MainActor in self?.streamStopped(error, sessionID: id) }
                },
                onActivity: { [weak self] isActive in
                    Task { @MainActor in self?.streamActivityChanged(isActive: isActive, sessionID: id) }
                },
                onOutputFinished: { [weak self] in
                    Task { @MainActor in self?.outputEnded(.finished, sessionID: id) }
                },
                onOutputFailed: { [weak self] error in
                    Task { @MainActor in self?.outputEnded(.failed(error), sessionID: id) }
                })
            let output = SCRecordingOutput(configuration: outputConfiguration, delegate: delegate)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
            try stream.addRecordingOutput(output)
            let newSession = Session(id: id, stream: stream, output: output, delegate: delegate,
                                     fileURL: url, target: target)
            session = newSession
            fileURL = url

            try await stream.startCapture()
        } catch {
            if let fileURL, !(await Self.isPlayable(fileURL)) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            session = nil
            state = .idle
            Self.log.error("Starting the Screencast failed: \(error.localizedDescription, privacy: .public)")
            if let error = error as? ScreencastError { throw error }
            if error is ScreenCapturerError { throw error }
            throw ScreencastError.startFailed(error)
        }

        state = .recording(startDate: Date())
        watchDisplays()
        Self.log.info("Screencast started")
        // A stop that came in while the stream was starting (second hotkey press, stream error).
        if let cause = session?.pendingCause {
            session?.pendingCause = nil
            await finish(cause)
        }
    }

    // MARK: Stop

    /// Stops and saves the Screencast. While it is still starting, the stop happens as soon as it has
    /// started. Does nothing when idle or already stopping.
    func stop() async {
        switch state {
        case .recording:
            await finish(.requested)
        case .starting:
            if let session {
                session.pendingCause = session.pendingCause ?? .requested
            } else {
                stopRequestedWhileStarting = true
            }
        case .idle, .stopping:
            break
        }
    }

    /// For quitting: stops (and so finalizes) a running recording and returns once the recorder is idle.
    func stopAndWaitUntilIdle() async {
        await stop()
        let deadline = ContinuousClock.now.advanced(by: Self.finalizeTimeout + .seconds(5))
        while state != .idle, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Stop the stream, wait for the file to be finalized, then report. Whatever started the stop wins;
    /// later events are ignored because the state is no longer `recording`.
    private func finish(_ cause: StopCause) async {
        guard case .recording = state, let session else { return }
        state = .stopping
        stopWatchingDisplays()

        // Already-stopped streams throw here (e.g. after didStopWithError); nothing to do about it.
        try? await session.stream.stopCapture()

        // ScreenCaptureKit finalizes the file asynchronously; its delegate says when it is done.
        let deadline = ContinuousClock.now.advanced(by: Self.finalizeTimeout)
        while session.outputResult == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }

        var failure: Error?
        if case let .failed(error) = cause { failure = error }
        if failure == nil, case let .failed(error)? = session.outputResult { failure = error }

        let url = session.fileURL
        let playable = await Self.isPlayable(url)
        self.session = nil
        state = .idle

        if let failure {
            Self.log.error("Screencast ended early: \(failure.localizedDescription, privacy: .public)")
            if playable {
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            onFailure?(ScreencastError.interrupted(reason: ScreencastError.describe(failure),
                                                   savedFile: playable ? url : nil))
        } else if playable {
            Self.log.info("Screencast saved")
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            onFinished?(url)
        } else {
            Self.log.error("Screencast file is missing or unplayable")
            try? FileManager.default.removeItem(at: url)
            onFailure?(ScreencastError.couldNotFinish)
        }
    }

    // MARK: Events from ScreenCaptureKit

    private func current(_ sessionID: Int) -> Session? {
        guard let session, session.id == sessionID else { return nil }
        return session
    }

    private func streamStopped(_ error: Error, sessionID: Int) {
        guard let session = current(sessionID) else { return }
        let cause: StopCause
        switch ScreencastError.streamCode(of: error) {
        case ScreencastError.StreamCode.userStopped?:
            cause = .requested
        case ScreencastError.StreamCode.noWindowList?, ScreencastError.StreamCode.noDisplayList?,
             ScreencastError.StreamCode.noCaptureSource?:
            cause = .targetGone
        default:
            cause = .failed(error)
        }
        trigger(cause, in: session)
    }

    private func outputEnded(_ result: OutputResult, sessionID: Int) {
        guard let session = current(sessionID) else { return }
        // The first result stands: a failure that follows a clean finish (or the reverse) is noise.
        if session.outputResult == nil { session.outputResult = result }
        if case let .failed(error) = result {
            trigger(.failed(error), in: session)
        }
    }

    /// Starts (or defers until the stream has started) the stop for `cause`.
    private func trigger(_ cause: StopCause, in session: Session) {
        switch state {
        case .starting:
            if session.pendingCause == nil { session.pendingCause = cause }
        case .recording:
            Task { await finish(cause) }
        case .idle, .stopping:
            break
        }
    }

    /// Window targets: when every shared window is gone ScreenCaptureKit reports "inactive". A closed window
    /// ends the recording; a minimized one (same signal) keeps it going.
    private func streamActivityChanged(isActive: Bool, sessionID: Int) {
        guard let session = current(sessionID), case let .window(windowID) = session.target else { return }
        session.isInactive = !isActive
        guard !isActive else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.windowGoneGracePeriod)
            guard let self, let session = self.current(sessionID), session.isInactive,
                  self.isRecording else { return }
            let exists = await Self.windowExists(windowID)
            // The user may have stopped this recording and started another during the await.
            guard !exists, self.current(sessionID) === session, self.isRecording else { return }
            self.trigger(.targetGone, in: session)
        }
    }

    // MARK: Display unplugged

    /// A recording ends when its own display disappears; other displays coming and going don't matter.
    private func watchDisplays() {
        stopWatchingDisplays()
        guard let displayID = session?.target.displayID else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session else { return }
                if !Self.displayIsConnected(displayID) {
                    self.trigger(.targetGone, in: session)
                }
            }
        }
    }

    private func stopWatchingDisplays() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private static func displayIsConnected(_ displayID: UInt32) -> Bool {
        NSScreen.screens.contains {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    // MARK: Building the capture

    private static func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw ScreencastError.microphoneDenied
        default:
            throw ScreencastError.microphoneDenied
        }
    }

    private static func windowExists(_ windowID: UInt32) async -> Bool {
        // Not limited to on-screen windows: a minimized window still exists.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return true } // can't tell: keep recording
        return content.windows.contains { $0.windowID == windowID }
    }

    /// The content filter and stream configuration for `target`: native pixels (points × scale, even),
    /// 60 fps, pointer and audio per `options`, PrtSc's own windows and sounds left out.
    private static func makeCapture(for target: ScreencastTarget,
                                    options: ScreencastOptions) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()
        switch target {
        case let .selection(rect, display):
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw ScreenCapturerError.displayNotFound(display.displayID)
            }
            guard let region = RecordingGeometry.region(for: rect, on: display) else {
                throw ScreencastError.emptySelection
            }
            filter = SCContentFilter(display: scDisplay, excludingApplications: ownApps, exceptingWindows: [])
            configuration.sourceRect = region.sourceRect
            configuration.width = region.pixelWidth
            configuration.height = region.pixelHeight

        case let .display(id):
            guard let scDisplay = content.displays.first(where: { $0.displayID == id }) else {
                throw ScreenCapturerError.displayNotFound(id)
            }
            filter = SCContentFilter(display: scDisplay, excludingApplications: ownApps, exceptingWindows: [])
            let scale = max(CGFloat(SCShareableContent.info(for: filter).pointPixelScale), 1)
            let size = RecordingGeometry.pixelSize(for: scDisplay.frame.size, scale: scale)
            configuration.width = size.width
            configuration.height = size.height

        case let .window(id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ScreenCapturerError.windowNotFound(id)
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = max(CGFloat(SCShareableContent.info(for: filter).pointPixelScale), 1)
            let size = RecordingGeometry.pixelSize(for: window.frame.size, scale: scale)
            configuration.width = size.width
            configuration.height = size.height
            // The window alone (no shadow margin), whole even when partly off the display.
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
            // The video keeps its starting size; a resized window is scaled to fit it (aspect preserved).
            configuration.scalesToFit = true
        }

        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = options.showsPointer
        configuration.captureResolution = .best
        configuration.capturesAudio = options.recordSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = options.recordMicrophone
        return (filter, configuration)
    }

    // MARK: Files

    /// A file that has a video track and a positive duration.
    nonisolated static func isPlayable(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        do {
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let video = try await asset.loadTracks(withMediaType: .video)
            return playable && duration.isNumeric && duration.seconds > 0 && !video.isEmpty
        } catch {
            return false
        }
    }
}
