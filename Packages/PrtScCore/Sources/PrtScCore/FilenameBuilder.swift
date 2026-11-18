import Foundation

public enum FilenameBuilder {
    /// "Screenshot from 2026-11-17 23-12-04" (lowercase "from", 24-hour clock, local time zone by default).
    /// `prefix` replaces "Screenshot" ("Screencast from …" for recordings).
    /// Always formatted with the en_US_POSIX locale and the Gregorian calendar, whatever the user's settings.
    public static func baseName(for date: Date, prefix: String = "Screenshot",
                                timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        let year = String(format: "%04d", c.year ?? 0)
        return "\(prefix) from \(year)-\(two(c.month))-\(two(c.day)) \(two(c.hour))-\(two(c.minute))-\(two(c.second))"
    }

    /// First of "<base>.png", "<base>-1.png", "<base>-2.png", … for which fileExists returns false.
    public static func uniqueURL(in folder: URL, date: Date, prefix: String = "Screenshot",
                                 pathExtension: String = "png", timeZone: TimeZone = .current,
                                 fileExists: (URL) -> Bool) -> URL {
        let base = baseName(for: date, prefix: prefix, timeZone: timeZone)
        var suffix = 0
        while true {
            let name = suffix == 0 ? base : "\(base)-\(suffix)"
            let url = folder.appendingPathComponent(name).appendingPathExtension(pathExtension)
            if !fileExists(url) { return url }
            suffix += 1
        }
    }
}
