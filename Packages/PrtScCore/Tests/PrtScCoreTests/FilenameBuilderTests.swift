import Foundation
import Testing
@testable import PrtScCore

@Suite("FilenameBuilder")
struct FilenameBuilderTests {
    /// 2026-11-17 23:12:04 UTC
    let date = Date(timeIntervalSince1970: 1_794_957_124)
    let utc = TimeZone(identifier: "UTC")!

    @Test func baseNameFormat() {
        #expect(FilenameBuilder.baseName(for: date, timeZone: utc) == "Screenshot from 2026-11-17 23-12-04")
    }

    @Test func baseNameUsesGivenTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(FilenameBuilder.baseName(for: date, timeZone: tokyo) == "Screenshot from 2026-11-18 08-12-04")
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(FilenameBuilder.baseName(for: date, timeZone: la) == "Screenshot from 2026-11-17 15-12-04")
    }

    @Test func baseNameZeroPadsAndUses24HourClock() {
        // 2026-01-02 03:04:05 UTC
        let d = Date(timeIntervalSince1970: 1_767_323_045)
        #expect(FilenameBuilder.baseName(for: d, timeZone: utc) == "Screenshot from 2026-01-02 03-04-05")
        // midnight is 00, not 12 or 24
        let midnight = Date(timeIntervalSince1970: 1_767_312_000) // 2026-01-02 00:00:00 UTC
        #expect(FilenameBuilder.baseName(for: midnight, timeZone: utc) == "Screenshot from 2026-01-02 00-00-00")
    }

    @Test func baseNameIgnoresUserLocaleAndCalendar() {
        // Thai Buddhist calendar year would be 2569; Arabic-Indic digits etc. must never leak in.
        // We can't change the process locale, so verify the output is pure ASCII digits/Gregorian.
        let name = FilenameBuilder.baseName(for: date, timeZone: utc)
        #expect(name.unicodeScalars.allSatisfy { $0.isASCII })
        #expect(name.contains("2026"))
    }

    @Test func baseNameDefaultsToCurrentTimeZone() {
        #expect(FilenameBuilder.baseName(for: date) == FilenameBuilder.baseName(for: date, timeZone: .current))
    }

    @Test func uniqueURLWhenNothingExists() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let url = FilenameBuilder.uniqueURL(in: folder, date: date, timeZone: utc, fileExists: { _ in false })
        #expect(url.path == "/tmp/shots/Screenshot from 2026-11-17 23-12-04.png")
    }

    @Test func uniqueURLAppendsConflictSuffixDirectly() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let taken: Set<String> = [
            "/tmp/shots/Screenshot from 2026-11-17 23-12-04.png",
            "/tmp/shots/Screenshot from 2026-11-17 23-12-04-1.png",
        ]
        let url = FilenameBuilder.uniqueURL(in: folder, date: date, timeZone: utc,
                                            fileExists: { taken.contains($0.path) })
        #expect(url.lastPathComponent == "Screenshot from 2026-11-17 23-12-04-2.png")
    }

    @Test func uniqueURLFirstConflictIsDashOne() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let url = FilenameBuilder.uniqueURL(in: folder, date: date, timeZone: utc,
                                            fileExists: { $0.lastPathComponent.hasSuffix("04.png") })
        #expect(url.lastPathComponent == "Screenshot from 2026-11-17 23-12-04-1.png")
    }

    @Test func uniqueURLHonoursPathExtension() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let url = FilenameBuilder.uniqueURL(in: folder, date: date, pathExtension: "jpg", timeZone: utc,
                                            fileExists: { _ in false })
        #expect(url.lastPathComponent == "Screenshot from 2026-11-17 23-12-04.jpg")
    }

    @Test func uniqueURLLivesInTheGivenFolder() {
        let folder = URL(fileURLWithPath: "/Users/me/Pictures/Screenshots", isDirectory: true)
        let url = FilenameBuilder.uniqueURL(in: folder, date: date, timeZone: utc, fileExists: { _ in false })
        #expect(url.deletingLastPathComponent().path == folder.path)
    }

    @Test func uniqueURLCallsFileExistsWithFullURLs() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        nonisolated(unsafe) var seen: [String] = []
        _ = FilenameBuilder.uniqueURL(in: folder, date: date, timeZone: utc, fileExists: { url in
            seen.append(url.lastPathComponent)
            return seen.count < 3
        })
        #expect(seen == [
            "Screenshot from 2026-11-17 23-12-04.png",
            "Screenshot from 2026-11-17 23-12-04-1.png",
            "Screenshot from 2026-11-17 23-12-04-2.png",
        ])
    }
}
