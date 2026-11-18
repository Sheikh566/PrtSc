# PrtSc

PrtSc is a macOS menu bar app that brings the **GNOME Shell screenshot UI** to the Mac. Press a key and the screen freezes; pick a Selection, a whole Screen or a Window, optionally show the pointer, and capture. It behaves like the screenshot tool you get when you press Print on GNOME 42+ (Ubuntu 22.04+), wearing a native macOS 26 Liquid Glass look instead of libadwaita.

> *Screenshot coming soon.* <!-- Add docs/images/screenshot.png and embed it here once the UI is final. -->

## Features

- **Same flow as GNOME Shell**: one hotkey freezes every display, then you choose what to capture in a floating capsule (the Capture Panel).
- **Three modes**: Selection (drag or edit a rectangle), Screen (one display) and Window (a window picker that spreads out the Space's windows, unobscured).
- **Show Pointer** toggle, applied to Selection, Screen and Window captures.
- **Keyboard-first Selection**: resize, move, fine and large steps, reset, all like GNOME.
- **Screencasts** from the same UI: switch the Capture Type to video (or press V, or ⌥⇧⌘R), pick a Selection, a Screen or a Window and record. A red dot and timer in the menu bar show the recording; click it (or press ⌥⇧⌘R again) to stop. Saved as HEVC (or H.264) `.mp4` in `~/Movies/Screencasts` at native resolution and 60 fps, with optional system audio and microphone, plus a notification with a thumbnail.
- **Instant captures** without opening the UI: whole screen, or the front-most window including its sheets and popovers.
- **Multi-display aware**: the panel opens on the display with the pointer, and a Selection can span displays with different scale factors.
- **Output the GNOME way**: every capture goes to the clipboard and to a PNG named `Screenshot from YYYY-MM-DD HH-MM-SS.png` in `~/Pictures/Screenshots` (configurable), with a notification (thumbnail, click to open, Show in Finder).
- **Print-key aliases** for PC keyboards: F13, ⇧F13, ⌥F13.
- **Native bits**: ScreenCaptureKit, Liquid Glass, Reduce Transparency fallback, VoiceOver labels, launch at login, optional hidden menu bar icon.
- **Updates** through Sparkle.

See [ADR 0001](docs/adr/0001-copy-gnome-shell-screenshot-ui-not-gnome-screenshot-app.md) for what is deliberately out of scope.

## Shortcuts

### Global (configurable in Settings)

| Shortcut | Action |
| --- | --- |
| ⇧⌘2 | Open the Screenshot UI (press again to close it) |
| ⌃⇧⌘2 | Instant Screen: capture the display under the pointer |
| ⌥⇧⌘2 | Instant Window: capture the front-most window |
| ⌥⇧⌘R | Open the Screenshot UI in Screencast mode; while recording, stop the Screencast |
| F13 | Same as ⇧⌘2 (the Print key on PC keyboards sends F13) |
| ⇧F13 | Same as ⌃⇧⌘2 |
| ⌥F13 | Same as ⌥⇧⌘2 |

### Inside the Screenshot UI

| Key | Action |
| --- | --- |
| S / C / W | Selection / Screen / Window mode |
| V | Switch the Capture Type between Screenshot and Screencast |
| P | Toggle Show Pointer |
| Return, Space or ⌘C | Capture (in Screencast mode: start recording) |
| Esc | Close without capturing |
| ← → ↑ ↓ | Selection mode: resize (→ and ↓ grow, ← and ↑ shrink, 5 pt steps). Screen and Window modes: move between displays or windows |
| ⌥ + arrows | Move the Selection instead of resizing it |
| ⌘ + arrows | Fine steps of 1 pt |
| ⇧ + arrows | Large steps (the primary display's full width or height) |
| R | Reset the Selection to the default centred rectangle |
| Click | Make a small square Selection around the point |
| Right-drag | Always start a new Selection |

## Install

### Homebrew

```sh
brew install --cask sheikh566/tap/prtsc
```

### Download

Get `PrtSc-<version>.dmg` from the [Releases](https://github.com/Sheikh566/PrtSc/releases) page, open it and drag **PrtSc** to **Applications**.

### Unsigned builds

PrtSc is not yet signed with an Apple Developer ID, so releases are **unsigned builds** that Gatekeeper does not recognise. The first time you open the app, right-click **PrtSc.app** and choose **Open**, or approve it in **System Settings > Privacy & Security**. (The Homebrew cask removes the quarantine flag for you.) Because the signature is not stable, macOS may ask for Screen Recording permission again after an update. Signed and notarized builds will replace this once a Developer ID exists; see [docs/releasing.md](docs/releasing.md).

Requires macOS 26 (Tahoe) or later.

## Permissions

- **Screen & System Audio Recording** (required): PrtSc cannot capture anything without it. The Welcome window opens on first launch and explains it; grant it in System Settings > Privacy & Security > Screen & System Audio Recording. macOS may ask you to quit and reopen PrtSc afterwards.
- **Microphone** (optional): only if you turn on "Record microphone" in Settings. macOS asks the first time; if you say no, the switch goes back off.
- **Notifications** (optional): for the "Screenshot Captured" and "Screencast Recorded" notifications. Capture, clipboard and saving work without it.

PrtSc is not sandboxed (it needs to write to your Save Folder and Screencast Folder and use global hotkeys) and sends nothing anywhere except the Sparkle update check to `sheikh566.github.io`.

## Build from source

Requires macOS 26+ and Xcode 27.

```sh
git clone https://github.com/Sheikh566/PrtSc.git
cd PrtSc
xcodebuild -project PrtSc.xcodeproj -scheme PrtSc -configuration Debug build
```

Or open `PrtSc.xcodeproj` in Xcode and run the `PrtSc` scheme. Swift Package Manager resolves Sparkle on first build.

## Tests

```sh
cd Packages/PrtScCore && swift test      # UI-free logic, Swift Testing
scripts/selftest.sh                      # release scripts (appcast, cask, dmg)
```

The app target itself is checked by building it in CI and by [docs/manual-test-checklist.md](docs/manual-test-checklist.md).

## Project layout

```
PrtSc.xcodeproj       app project
PrtSc/                app target (AppKit + SwiftUI): App, MenuBar, Hotkeys, Settings, Onboarding,
                      Permissions, Output, Capture, ScreenshotUI, Resources
Packages/PrtScCore/   local Swift package with UI-free, tested logic (Selection editing, geometry, filenames, hotkeys)
scripts/              release helpers (dmg, signing, notarization, appcast, cask)
packaging/            Homebrew cask template, Sparkle appcast template
.github/workflows/    ci.yml, release.yml
docs/                 architecture, ADRs, release guide, manual test checklist
```

## Documentation

- [CONTEXT.md](CONTEXT.md): the vocabulary used in code and docs
- [docs/architecture.md](docs/architecture.md): design and the PrtScCore API contract
- [docs/adr/](docs/adr/): architecture decision records ([ADR 0001](docs/adr/0001-copy-gnome-shell-screenshot-ui-not-gnome-screenshot-app.md))
- [docs/releasing.md](docs/releasing.md): secrets, signing, notarization, how to cut a release
- [docs/manual-test-checklist.md](docs/manual-test-checklist.md): what to check by hand

## License

MIT, see [LICENSE](LICENSE).

## Credits

The behaviour and interaction design come from the screenshot UI in [GNOME Shell](https://gitlab.gnome.org/GNOME/gnome-shell) (`js/ui/screenshot.js`). PrtSc is an independent project: it is not affiliated with, endorsed by or sponsored by the GNOME Project. "GNOME" is a trademark of the GNOME Foundation. No GNOME source code is used here; the behaviour was re-implemented for macOS. Updates are delivered with [Sparkle](https://sparkle-project.org).
