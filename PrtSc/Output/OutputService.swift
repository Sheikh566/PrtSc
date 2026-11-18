import AppKit
import AVFoundation
import Foundation
import ImageIO
import PrtScCore
import UniformTypeIdentifiers

/// In order: copy to the pasteboard (PNG + TIFF), write the PNG to the SaveFolder, play the
/// capture sound if UI sound effects are enabled, post the CaptureNotification.
/// See docs/architecture.md "Output/CapturedImage + OutputService".
@MainActor
final class OutputService: CaptureSink {
    static let shutterSoundURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif")

    private let settings: SettingsStore
    private let notifier: CaptureNotifier
    private let home: URL
    private var sound: NSSound?
    /// Deliveries run strictly one after another in request order (see `deliver`).
    private let deliveries = SerialTaskQueue()

    /// Creating the OutputService installs the notification delegate, so build it before anything can post.
    init(settings: SettingsStore, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.settings = settings
        self.home = home
        self.notifier = CaptureNotifier()
    }

    /// The folder screenshots are written to right now.
    var saveFolderURL: URL {
        SaveFolder.url(configured: settings.saveFolderPath, home: home)
    }

    /// The folder Screencasts are written to right now (not created yet).
    var screencastFolderURL: URL {
        ScreencastFolder.url(configured: settings.screencastFolderPath, home: home)
    }

    /// A finished Screencast: post the Capture Notification (no clipboard, no sound). The file is already
    /// in the Screencast Folder and in recent documents.
    func deliverScreencast(_ url: URL) async {
        let thumbnail = await Self.thumbnailPNG(forVideoAt: url)
        await notifier.postScreencast(thumbnailPNG: thumbnail, fileURL: url)
    }

    /// Deliveries are serialized in request order: a later capture can't reach the clipboard before an
    /// earlier one, so the clipboard ends up holding the newest capture, and every capture is saved as its
    /// own file (the unique-name check runs one delivery at a time).
    func deliver(_ capture: CapturedImage) async {
        let date = Date()
        await deliveries.run { [self] in
            await performDelivery(capture, date: date)
        }
    }

    private func performDelivery(_ capture: CapturedImage, date: Date) async {
        let encoded = await Task.detached(priority: .userInitiated) {
            Self.encode(capture)
        }.value

        guard let encoded else {
            presentAlert(message: String(localized: "Couldn't encode the screenshot."), copiedToClipboard: false)
            return
        }

        // 1. Pasteboard (PNG + TIFF).
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(encoded.png, forType: .png)
        if let tiff = encoded.tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }

        // 2. File in the SaveFolder.
        var savedURL: URL?
        var saveError: Error?
        do {
            let folder = saveFolderURL
            try SaveFolder.ensureExists(folder)
            let url = FilenameBuilder.uniqueURL(in: folder, date: date) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            try encoded.png.write(to: url, options: .withoutOverwriting)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            savedURL = url
        } catch {
            saveError = error
        }

        // 3. Shutter sound.
        if Self.uiSoundEffectsEnabled() {
            playShutterSound()
        }

        // 4. CaptureNotification.
        await notifier.post(pngData: encoded.png, fileURL: savedURL)

        if let saveError {
            presentAlert(message: saveError.localizedDescription, copiedToClipboard: true)
        }
    }

    // MARK: - Encoding

    struct Encoded: Sendable {
        let png: Data
        let tiff: Data?
    }

    /// PNG via ImageIO keeps the image's colour space (ICC profile); DPI = 72 × scale.
    /// The TIFF carries the same Retina sizing (see `ImageEncoding.tiffData`).
    nonisolated static func encode(_ capture: CapturedImage) -> Encoded? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = ImageMetadata.dpi(forScale: capture.scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, capture.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Encoded(png: data as Data, tiff: ImageEncoding.tiffData(for: capture))
    }

    // MARK: - Screencast thumbnail

    /// The first frame of a video as PNG data (at most 640 px wide), nil if it can't be read.
    nonisolated static func thumbnailPNG(forVideoAt url: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        // The first sample may not sit exactly at time zero.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - Sound

    /// The user's "Play user interface sound effects" setting; true when it was never changed.
    nonisolated static func uiSoundEffectsEnabled(
        defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.systemsound")
    ) -> Bool {
        guard let value = defaults?.object(forKey: "com.apple.sound.uiaudio.enabled") as? NSNumber else {
            return true
        }
        return value.boolValue
    }

    private func playShutterSound() {
        guard FileManager.default.fileExists(atPath: Self.shutterSoundURL.path),
              let sound = NSSound(contentsOf: Self.shutterSoundURL, byReference: true) else { return }
        self.sound = sound
        sound.play()
    }

    // MARK: - Errors

    private func presentAlert(message: String, copiedToClipboard: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't Save Screenshot")
        alert.informativeText = copiedToClipboard
            ? message + "\n\n" + String(localized: "The screenshot is still on the clipboard.")
            : message
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }
}
