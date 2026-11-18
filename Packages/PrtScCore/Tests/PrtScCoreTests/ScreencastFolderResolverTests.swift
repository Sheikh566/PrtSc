import Foundation
import Testing
@testable import PrtScCore

@Suite("ScreencastFolderResolver")
struct ScreencastFolderResolverTests {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    private func resolve(_ configured: String?, existing: Set<String> = ["/Users/tester/Movies"]) -> String {
        ScreencastFolderResolver.resolve(configured: configured, home: home,
                                         directoryExists: { existing.contains($0.path) }).path
    }

    @Test func defaultsToMoviesScreencasts() {
        #expect(resolve(nil) == "/Users/tester/Movies/Screencasts")
    }

    @Test func existingScreencastsFolderIsUsed() {
        #expect(resolve(nil, existing: ["/Users/tester/Movies", "/Users/tester/Movies/Screencasts"])
                == "/Users/tester/Movies/Screencasts")
    }

    @Test func screencastsFolderIsDefaultEvenIfItDoesNotExistYet() {
        #expect(resolve(nil, existing: ["/Users/tester/Movies"]) == "/Users/tester/Movies/Screencasts")
    }

    @Test func fallsBackToHomeWhenMoviesMissing() {
        #expect(resolve(nil, existing: []) == "/Users/tester")
        // A stray Screencasts folder without Movies is not reachable in practice, but is still honoured.
        #expect(resolve(nil, existing: ["/Users/tester/Movies/Screencasts"]) == "/Users/tester/Movies/Screencasts")
    }

    @Test(arguments: ["", " ", "\t", "\n  \t"])
    func blankConfiguredMeansNotConfigured(configured: String) {
        #expect(resolve(configured) == "/Users/tester/Movies/Screencasts")
        #expect(resolve(configured, existing: []) == "/Users/tester")
    }

    @Test func absolutePathIsUsedAsIs() {
        #expect(resolve("/Volumes/Video/clips") == "/Volumes/Video/clips")
    }

    @Test func configuredIsUsedEvenIfItDoesNotExist() {
        #expect(resolve("/does/not/exist", existing: []) == "/does/not/exist")
    }

    @Test func tildeExpandsAgainstProvidedHome() {
        #expect(resolve("~") == "/Users/tester")
        #expect(resolve("~/") == "/Users/tester")
        #expect(resolve("~/Desktop/Clips") == "/Users/tester/Desktop/Clips")
        let other = URL(fileURLWithPath: "/somewhere/else", isDirectory: true)
        let url = ScreencastFolderResolver.resolve(configured: "~/Clips", home: other, directoryExists: { _ in true })
        #expect(url.path == "/somewhere/else/Clips")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(resolve("  ~/Desktop \n") == "/Users/tester/Desktop")
    }

    @Test func resultIsFileURL() {
        #expect(ScreencastFolderResolver.resolve(configured: nil, home: home, directoryExists: { _ in true }).isFileURL)
    }
}
