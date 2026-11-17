import Foundation

public enum SaveFolderResolver {
    /// configured (with ~ expanded) if set, else <home>/Pictures/Screenshots; if <home>/Pictures does not
    /// exist and nothing is configured, <home>. Does not touch the disk except via `directoryExists`.
    /// A blank (empty or whitespace-only) configured string counts as not configured. `~` and `~/…` are
    /// expanded against `home`, never the real home directory.
    public static func resolve(configured: String?, home: URL, directoryExists: (URL) -> Bool) -> URL {
        if let configured {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return expand(trimmed, home: home)
            }
        }
        let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
        guard directoryExists(pictures) else { return home }
        return pictures.appendingPathComponent("Screenshots", isDirectory: true)
    }

    private static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            let rest = String(path.dropFirst(2))
            guard !rest.isEmpty else { return home }
            return home.appendingPathComponent(rest, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
