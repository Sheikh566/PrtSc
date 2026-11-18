import Foundation
import PrtScCore

/// Resolves and prepares the Screencast Folder.
enum ScreencastFolder {
    /// The configured folder, else ~/Movies/Screencasts (or home if ~/Movies is missing).
    static func url(configured: String?,
                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        ScreencastFolderResolver.resolve(configured: configured, home: home) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The Screencast Folder, created if needed. When the default folder can't be created, falls back to
    /// ~/Movies and then the home folder, so a recording can always start. A folder the user configured
    /// is never replaced: failing to create it throws.
    static func prepare(configured: String?,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let folder = url(configured: configured, home: home)
        do {
            try SaveFolder.ensureExists(folder)
            return folder
        } catch {
            let isDefault = configured?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            guard isDefault else { throw error }
            for fallback in [home.appendingPathComponent("Movies", isDirectory: true), home] {
                if (try? SaveFolder.ensureExists(fallback)) != nil { return fallback }
            }
            throw error
        }
    }
}
