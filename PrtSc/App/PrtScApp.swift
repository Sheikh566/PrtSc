import SwiftUI

@main
struct PrtScApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app is a menu bar agent (LSUIElement); windows are AppKit-managed by AppCoordinator.
        // SwiftUI requires at least one scene. Its Settings scene stays empty, and ⌘, (live whenever one of
        // PrtSc's own windows is key) opens the real Settings window instead of a blank one.
        SwiftUI.Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.openSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}
