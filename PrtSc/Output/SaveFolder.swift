import Foundation
import PrtScCore

/// Resolves and prepares the SaveFolder.
enum SaveFolder {
    /// The configured folder, else ~/Pictures/Screenshots (or home if ~/Pictures is missing).
    static func url(configured: String?,
                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        SaveFolderResolver.resolve(configured: configured, home: home) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Creates the folder (and parents) if needed.
    static func ensureExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
