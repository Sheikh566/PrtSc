import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

/// Posts the CaptureNotification and handles taps on it.
@MainActor
final class CaptureNotifier {
    nonisolated static let categoryIdentifier = "io.github.sheikh566.PrtSc.capture"
    nonisolated static let showInFinderActionIdentifier = "io.github.sheikh566.PrtSc.showInFinder"
    nonisolated static let pathKey = "path"

    private let responder = NotificationResponder()

    /// Set the delegate and register the category. Must run early in launch, before anything posts.
    init() {
        let center = UNUserNotificationCenter.current()
        center.delegate = responder
        let showInFinder = UNNotificationAction(identifier: Self.showInFinderActionIdentifier,
                                                title: String(localized: "Show in Finder"),
                                                options: [])
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier,
                                              actions: [showInFinder],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    /// The screenshot notification.
    /// - Parameters:
    ///   - thumbnailPNG: the screenshot thumbnail (written to a temp copy; attachments move files).
    ///   - fileURL: the saved file, nil if saving failed.
    func post(thumbnailPNG: Data, fileURL: URL?) async {
        await post(title: String(localized: "Screenshot Captured"),
                   body: String(localized: "You can paste the image from the clipboard"),
                   thumbnailPNG: thumbnailPNG,
                   thumbnailName: fileURL?.lastPathComponent ?? "Screenshot.png",
                   fileURL: fileURL)
    }

    /// The Screencast notification: "Screencast Recorded", with a thumbnail of the first frame.
    /// Clicking it opens the video.
    func postScreencast(thumbnailPNG: Data?, fileURL: URL) async {
        await post(title: String(localized: "Screencast Recorded"),
                   body: String(localized: "Click here to view the video"),
                   thumbnailPNG: thumbnailPNG,
                   thumbnailName: fileURL.deletingPathExtension().lastPathComponent + ".png",
                   fileURL: fileURL)
    }

    private func post(title: String, body: String, thumbnailPNG: Data?, thumbnailName: String,
                      fileURL: URL?) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let fileURL {
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [Self.pathKey: fileURL.path]
        }

        // The attachment's file is only moved into the notification store when the request is added, so
        // the temporary directory must outlive `center.add` (removed at the end of this function).
        var tempDirectory: URL?
        defer {
            if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        }
        if let thumbnailPNG {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PrtSc-\(UUID().uuidString)", isDirectory: true)
            tempDirectory = directory
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let tempFile = directory.appendingPathComponent(thumbnailName)
                try thumbnailPNG.write(to: tempFile)
                let attachment = try UNNotificationAttachment(
                    identifier: "thumbnail",
                    url: tempFile,
                    options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
                content.attachments = [attachment]
            } catch {
                // Post without a thumbnail.
            }
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

/// UNUserNotificationCenter delegate: banners while PrtSc is "active", open on tap, Show in Finder.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo[CaptureNotifier.pathKey] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            NotificationActivity.noteResponse()
            guard let path else { return }
            let url = URL(fileURLWithPath: path)
            switch action {
            case CaptureNotifier.showInFinderActionIdentifier:
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case UNNotificationDefaultActionIdentifier:
                NSWorkspace.shared.open(url)
            default:
                break
            }
        }
    }
}

/// When the user last clicked a PrtSc notification (or one of its actions).
///
/// Clicking a notification activates PrtSc, and because a menu bar app has no visible windows, macOS also
/// sends it a "reopen" event, the same one as relaunching it from Finder. `AppDelegate` uses this to
/// tell the two apart, so a notification click opens the file and not Settings.
@MainActor
enum NotificationActivity {
    private static var lastResponse: ContinuousClock.Instant?

    static func noteResponse() {
        lastResponse = .now
    }

    static func respondedRecently(within interval: Duration) -> Bool {
        guard let lastResponse else { return false }
        return ContinuousClock.now - lastResponse < interval
    }
}
