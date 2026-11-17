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

    /// - Parameters:
    ///   - pngData: the screenshot, used for the thumbnail (a temp copy; attachments move files).
    ///   - fileURL: the saved file, nil if saving failed.
    func post(pngData: Data, fileURL: URL?) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Screenshot Captured")
        content.body = String(localized: "You can paste the image from the clipboard")
        content.categoryIdentifier = Self.categoryIdentifier
        if let fileURL {
            content.userInfo = [Self.pathKey: fileURL.path]
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrtSc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let tempFile = tempDirectory.appendingPathComponent(fileURL?.lastPathComponent ?? "Screenshot.png")
            try pngData.write(to: tempFile)
            let attachment = try UNNotificationAttachment(
                identifier: "screenshot",
                url: tempFile,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier])
            content.attachments = [attachment]
        } catch {
            // Post without a thumbnail.
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
