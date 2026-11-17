import Foundation
import Testing
@testable import PrtScCore

@Suite("SaveFolderResolver")
struct SaveFolderResolverTests {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    private func resolve(_ configured: String?, existing: Set<String> = ["/Users/tester/Pictures"]) -> String {
        SaveFolderResolver.resolve(configured: configured, home: home,
                                   directoryExists: { existing.contains($0.path) }).path
    }

    @Test func defaultsToPicturesScreenshots() {
        #expect(resolve(nil) == "/Users/tester/Pictures/Screenshots")
    }

    @Test func defaultsEvenWhenScreenshotsFolderDoesNotExistYet() {
        #expect(resolve(nil, existing: ["/Users/tester/Pictures"]) == "/Users/tester/Pictures/Screenshots")
    }

    @Test func fallsBackToHomeWhenPicturesMissing() {
        #expect(resolve(nil, existing: []) == "/Users/tester")
    }

    @Test(arguments: ["", " ", "   ", "\t", "\n  \t"])
    func blankConfiguredMeansNotConfigured(configured: String) {
        #expect(resolve(configured) == "/Users/tester/Pictures/Screenshots")
        #expect(resolve(configured, existing: []) == "/Users/tester")
    }

    @Test func absolutePathIsUsedAsIs() {
        #expect(resolve("/Volumes/Shots/stuff") == "/Volumes/Shots/stuff")
    }

    @Test func configuredIsUsedEvenIfItDoesNotExist() {
        #expect(resolve("/does/not/exist", existing: []) == "/does/not/exist")
    }

    @Test func tildeAloneExpandsToHome() {
        #expect(resolve("~") == "/Users/tester")
    }

    @Test func tildeSlashExpandsAgainstProvidedHome() {
        #expect(resolve("~/Desktop/Shots") == "/Users/tester/Desktop/Shots")
        #expect(resolve("~/") == "/Users/tester")
    }

    @Test func tildeExpansionDoesNotUseRealHome() {
        let other = URL(fileURLWithPath: "/somewhere/else", isDirectory: true)
        let url = SaveFolderResolver.resolve(configured: "~/Pics", home: other, directoryExists: { _ in true })
        #expect(url.path == "/somewhere/else/Pics")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(resolve("  ~/Desktop \n") == "/Users/tester/Desktop")
        #expect(resolve(" /tmp/x ") == "/tmp/x")
    }

    @Test func tildeUserFormIsNotExpanded() {
        // "~bob/x" is not "~/x"; treat as a plain relative-looking path and leave it alone.
        #expect(!resolve("~bob/x").hasPrefix("/Users/tester/bob"))
    }

    @Test func resultIsFileURL() {
        let url = SaveFolderResolver.resolve(configured: "~/Pics", home: home, directoryExists: { _ in true })
        #expect(url.isFileURL)
    }
}
