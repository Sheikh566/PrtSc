# PrtSc architecture

This is the build contract shared by everyone working on the code. Read it together with [CONTEXT.md](../CONTEXT.md) for vocabulary and [ADR 0001](adr/0001-copy-gnome-shell-screenshot-ui-not-gnome-screenshot-app.md) for scope. **Use the glossary terms in code** (`ScreenshotUI`, `CapturePanel`, `CaptureMode`, `Selection`, `FrozenFrame`, `WindowPicker`, `InstantCapture`, `SaveFolder`, `CaptureNotification`, `CaptureType`, `Screencast`, `ScreencastFolder`, `RecordingIndicator`).

## Platform

- macOS 26+, Swift 6 language mode with strict concurrency, Xcode 27.
- Liquid Glass via SwiftUI (`.glassEffect(...)`, `GlassEffectContainer`, `.buttonStyle(.glass)`). Honour `accessibilityReduceTransparency` by falling back to a solid background.
- ScreenCaptureKit (`SCShareableContent`, `SCScreenshotManager`, `SCContentFilter`, `SCStreamConfiguration`) for every capture. No `CGWindowListCreateImage`; it's deprecated.
- Not sandboxed. Hardened runtime on. `LSUIElement = YES`, so there's no Dock icon.
- Bundle ID `io.github.sheikh566.PrtSc`. MIT license.
- Dependency: Sparkle 2 (SPM). The feed URL is `https://sheikh566.github.io/PrtSc/appcast.xml`, and `SUPublicEDKey` is a placeholder until keys are generated. `AppCoordinator` owns the one `SPUStandardUpdaterController`; it only starts once the key is real (`UpdateSupport.isConfigured`).

## Repository layout

```
PrtSc.xcodeproj               checked in; app target uses a file-system-synchronized group for PrtSc/
PrtSc/                        app target (AppKit + SwiftUI)
  App/                        @main, AppDelegate, AppCoordinator (wires everything)
  MenuBar/                    MenuBarController (NSStatusItem + menu)
  Hotkeys/                    HotkeyManager (Carbon RegisterEventHotKey), HotkeyRecorderView
  Settings/                   SettingsStore, SessionState, SettingsView, SettingsWindowController
  Onboarding/                 WelcomeWindowController + view
  Permissions/                PermissionsService
  Output/                     OutputService (save, clipboard, sound, CaptureNotification), ScreencastFolder
  Capture/                    ScreenCapturer, FrozenFrame, InstantCaptureService, ScreencastRecorder
  ScreenshotUI/               ScreenshotUIController, overlay windows/views, CapturePanelView, WindowPickerView
  Resources/                  Assets.xcassets, Localizable.xcstrings, Info.plist, PrtSc.entitlements
Packages/PrtScCore/           local Swift package: UI-free logic, tested with Swift Testing
.github/workflows/            ci.yml, release.yml
scripts/                      release helpers (dmg, appcast, cask bump)
packaging/                    Homebrew cask template, appcast template
docs/                         adr/, architecture.md, manual-test-checklist.md, releasing.md
```

## Coordinates

All geometry in `PrtScCore` uses **global CG coordinates in points**: the origin is the top-left of the main display and y grows downward, the same convention as `CGDisplayBounds`, `SCDisplay.frame` and `SCWindow.frame`. Converting to and from AppKit's bottom-left space happens only in the app target, through one helper, `CoordinateSpace` in `ScreenshotUI/`.

## PrtScCore public API (the contract)

The signatures are fixed. Implementations may add private helpers, but if a signature has to change, update this document too.

```swift
// CaptureMode.swift
public enum CaptureMode: String, CaseIterable, Sendable, Codable {
    case selection, screen, window
    /// S → selection, C → screen, W → window (case-insensitive). nil otherwise.
    public static func forKey(_ character: Character) -> CaptureMode?
}

// SelectionEditor.swift — all GNOME (main) Selection behaviour
public enum ArrowDirection: Sendable { case left, right, up, down }
public struct EditModifiers: OptionSet, Sendable {
    public static let move   // ⌥ — move instead of resize
    public static let fine   // ⌘ — 1 pt steps (⌃ is NOT used: ⌃←/→ switch Spaces system-wide)
    public static let large  // ⇧ — steps of the primary display's full width/height
}
public enum SelectionHandle: Equatable, Sendable {
    case none, move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
}
public struct SelectionEditor: Equatable, Sendable {
    public static let defaultStep: CGFloat = 5
    public static let clickPadding: CGFloat = 20      // a click without dragging → square ±20 pt around the point
    public static let defaultHandleTolerance: CGFloat = 15  // used by dragBegan to decide whether a drag grabs a handle
    public var handleTolerance: CGFloat                // defaults to defaultHandleTolerance
    public private(set) var rect: CGRect               // global CG points, always non-empty and inside bounds
                                                       // ("inside" tolerates the 1-ulp overshoot of x + width)
    public let bounds: CGRect                          // union of all display frames
    public let primaryDisplayFrame: CGRect
    /// Default rect = centre of the primary display from 3/8 to 5/8 on both axes.
    /// `remembered` is used instead when it lies entirely inside bounds.
    public init(bounds: CGRect, primaryDisplayFrame: CGRect, remembered: CGRect?)
    /// Arrows resize by moving the right edge (←/→) or bottom edge (↑/↓): → and ↓ grow, ← and ↑ shrink.
    /// With .move, the whole rect moves instead. The step is defaultStep, 1 with .fine, and the primary
    /// display's width/height with .large. The result is clamped to bounds; minimum size 1×1.
    public mutating func handleArrow(_ direction: ArrowDirection, modifiers: EditModifiers)
    /// R key: back to the default centre rect.
    public mutating func reset()
    /// Handles within `tolerance` of an edge or corner; inside → .move; outside → .none.
    public func handle(at point: CGPoint, tolerance: CGFloat) -> SelectionHandle
    /// forceNew = right-drag or ⌃-drag: always starts a new selection.
    public mutating func dragBegan(at point: CGPoint, forceNew: Bool)
    public mutating func dragMoved(to point: CGPoint)
    /// If a new-selection drag ended without moving more than 2 pt, the rect becomes the click square.
    public mutating func dragEnded(at point: CGPoint)
}

// CaptureType.swift
public enum CaptureType: String, CaseIterable, Sendable, Codable {
    case screenshot, screencast
    public var toggled: CaptureType
    /// V (case-insensitive) → the type to switch to from `current` (`current.toggled`). nil otherwise.
    public static func forKey(_ character: Character, from current: CaptureType) -> CaptureType?
}

// FilenameBuilder.swift
public enum FilenameBuilder {
    /// "Screenshot from 2026-11-17 23-12-04" (lowercase "from", 24-hour clock, local time zone by default).
    /// `prefix` replaces "Screenshot" ("Screencast from …").
    public static func baseName(for date: Date, prefix: String = "Screenshot",
                                timeZone: TimeZone = .current) -> String
    /// First of "<base>.png", "<base>-1.png", "<base>-2.png", … for which fileExists returns false.
    public static func uniqueURL(in folder: URL, date: Date, prefix: String = "Screenshot",
                                 pathExtension: String = "png", timeZone: TimeZone = .current,
                                 fileExists: (URL) -> Bool) -> URL
}

// SaveFolderResolver.swift
public enum SaveFolderResolver {
    /// configured (with ~ expanded) if set, else <home>/Pictures/Screenshots; if <home>/Pictures does not
    /// exist and nothing is configured, <home>. Does not touch the disk except via `directoryExists`.
    public static func resolve(configured: String?, home: URL, directoryExists: (URL) -> Bool) -> URL
}

// ScreencastFolderResolver.swift
public enum ScreencastFolderResolver {
    /// configured (with ~ expanded) if set, else <home>/Movies/Screencasts (also when it doesn't exist yet,
    /// as long as <home>/Movies does); if neither exists and nothing is configured, <home>. Blank counts as
    /// unconfigured. Does not touch the disk except via `directoryExists`.
    public static func resolve(configured: String?, home: URL, directoryExists: (URL) -> Bool) -> URL
}

// RecordingClock.swift
public enum RecordingClock {
    /// "m:ss" under an hour, "h:mm:ss" from one hour on; whole seconds, rounded down.
    /// Negative, NaN and infinite → "0:00".
    public static func format(elapsed: TimeInterval) -> String
}

// RecordingGeometry.swift — Screencast sizes. Video encoders need even dimensions.
public struct RecordingRegion: Equatable, Sendable {
    public var sourceRect: CGRect     // SCStreamConfiguration.sourceRect: display-local points, pixel-aligned
    public var pixelWidth: Int        // even; exactly sourceRect.size × scale, so nothing is resampled
    public var pixelHeight: Int
}
public enum RecordingGeometry {
    /// size × scale as even pixel dimensions, rounded down, at least 2. A bad scale counts as 1.
    public static func pixelSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int)
    /// The part of a global CG selection on `display` (a Selection spanning displays is clamped to it):
    /// edges snapped to the pixel grid, even size, kept inside the display. nil if they don't intersect.
    public static func region(for selection: CGRect, on display: DisplayInfo) -> RecordingRegion?
}

// WindowInfo.swift
public struct WindowInfo: Equatable, Hashable, Sendable {
    public var windowID: UInt32
    public var ownerPID: Int32
    public var ownerBundleID: String?
    public var title: String?
    public var frame: CGRect          // global CG points
    public var layer: Int             // 0 = normal app window
    public var isOnScreen: Bool
    public init(windowID: UInt32, ownerPID: Int32, ownerBundleID: String?, title: String?,
                frame: CGRect, layer: Int, isOnScreen: Bool)
}

// InstantWindowTargetResolver.swift
public enum InstantWindowTarget: Equatable, Sendable {
    case window(WindowInfo, attached: [WindowInfo])   // attached = sheets/popovers to include
    case screen(displayID: UInt32)
}
public enum InstantWindowTargetResolver {
    /// windows are ordered front to back. Picks the front-most on-screen, top-level layer-0 window of
    /// frontmostPID that's at least 40×40 pt. A layer-0 window that is a sheet of another window of the
    /// same PID (`isSheet`) is not top-level: its parent is the main window and the sheet is attached
    /// (so `[sheet, parent]` resolves to `.window(parent, attached: [sheet])`). `attached` = other
    /// windows of the same PID that are above the main window in z-order (any layer ≥ 0) and intersect
    /// its frame. If there's no such window (e.g. Finder showing only the desktop), or frontmostPID is
    /// nil or ownPID, falls back to .screen(displayUnderPointer).
    public static func resolve(frontmostPID: Int32?, ownPID: Int32, windows: [WindowInfo],
                               displayUnderPointer: UInt32) -> InstantWindowTarget
    /// Heuristic, because macOS exposes no parent link for another process's windows: `candidate` is a
    /// sheet of `parent` when they share a PID, `candidate` is narrower than `parent`, lies inside its
    /// frame, is horizontally centred on it (±3 pt) and hangs from its top edge (top ≤ 120 pt below).
    public static func isSheet(_ candidate: WindowInfo, of parent: WindowInfo) -> Bool
}

// DisplayGeometry.swift
public struct DisplayInfo: Equatable, Hashable, Sendable {
    public var displayID: UInt32
    public var frame: CGRect          // global CG points
    public var scale: CGFloat         // backing scale factor (2 on Retina)
    public var isPrimary: Bool
    public init(displayID: UInt32, frame: CGRect, scale: CGFloat, isPrimary: Bool)
}
public struct DisplaySegment: Equatable, Sendable {
    public var displayID: UInt32
    public var sourcePixelRect: CGRect     // in that display's image pixels (top-left origin), integral
    public var destinationPixelRect: CGRect // in the output image pixels (top-left origin); segments tile the canvas
    public var drawPixelRect: CGRect       // where the WHOLE sourcePixelRect is drawn in the output: exactly
                                           // outputScale/displayScale × its size at an integral offset (1:1 on a
                                           // display at the output scale); always covers destinationPixelRect,
                                           // which clips it (the rounding surplus is clipped, never scaled)
}
public enum DisplayGeometry {
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo?
    /// The display the CapturePanel goes on: contains the pointer, else primary, else first.
    public static func panelDisplay(pointer: CGPoint, displays: [DisplayInfo]) -> DisplayInfo?
    public static func union(of displays: [DisplayInfo]) -> CGRect
    /// The output scale for a rect = max scale of the displays it intersects.
    public static func outputScale(for rect: CGRect, displays: [DisplayInfo]) -> CGFloat
    /// Output image size in pixels: rect.size × scale, rounded. (`scale` = outputScale(for:displays:))
    public static func outputPixelSize(for rect: CGRect, scale: CGFloat) -> CGSize
    /// Splits a global rect into the pieces needed to stitch the image from per-display images
    /// at outputScale without resampling. Each display image is placed on the canvas at one integral offset
    /// (its pixel (0, 0), rounded), so a selection at a fractional origin (y = 337.5) is shifted by at most
    /// half a pixel, never stretched. The stitch canvas must be
    /// `outputPixelSize(for: rect, scale: outputScale(...))`; destination rects tile exactly that canvas.
    /// The stitcher draws `sourcePixelRect` into `drawPixelRect`, clipped to `destinationPixelRect`.
    public static func segments(for rect: CGRect, displays: [DisplayInfo]) -> [DisplaySegment]
    /// The display that shows most of a window: largest intersection area with `frame`; ties → lowest
    /// displayID; nil when the frame intersects no display. Assigns each window to exactly one display
    /// (Window Picker), including windows whose centre is off every display.
    public static func displayShowingMost(of frame: CGRect, displays: [DisplayInfo]) -> DisplayInfo?
}

// DirectionalNavigation.swift — arrow-key moves between displays (Screen mode) or Window Picker cells
public enum DirectionalNavigation {
    /// Nearest candidate whose centre is more than 1 pt away from `current`'s in the arrow's direction,
    /// lowest `along + 2 × across` wins (ties → earlier candidate); nil when nothing lies that way.
    public static func nearest<ID>(from current: CGRect, in candidates: [(ID, CGRect)],
                                   direction: ArrowDirection) -> ID?
}

// WindowOrdering.swift
public enum WindowOrdering {
    /// Sorts front to back by `zOrder` (window ID → index in the system's front-to-back list). Unknown IDs last;
    /// ties keep input order.
    public static func frontToBack<T>(_ items: [T], windowID: (T) -> UInt32, zOrder: [UInt32: Int]) -> [T]
}

// WindowPickerLayout.swift
public enum WindowPickerLayout {
    /// Overview-style grid: aspect ratio preserved, never scaled above 1, `spacing` between cells,
    /// rows centred inside `area`. Returns one rect per input size, in input order.
    public static func layout(sizes: [CGSize], in area: CGRect, spacing: CGFloat) -> [CGRect]
}

// Hotkeys.swift
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public static let command, shift, option, control
}
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32        // Carbon virtual key code (kVK_*)
    public var modifiers: KeyModifiers
    public init(keyCode: UInt32, modifiers: KeyModifiers)
    public var displayString: String  // Apple modifier order ⌃⌥⇧⌘ then the key, e.g. "⌃⇧⌘2", "F13"
}
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case openScreenshotUI, instantScreen, instantWindow, screencast
}
public struct HotkeyBindings: Codable, Equatable, Sendable {
    public var bindings: [HotkeyAction: KeyCombo]
    /// ⇧⌘2 / ⌃⇧⌘2 / ⌥⇧⌘2  (kVK_ANSI_2 = 0x13), ⌥⇧⌘R for .screencast (kVK_ANSI_R = 0x0F).
    /// Decoding stored bindings that lack `.screencast` (written before it existed) gives it its default;
    /// a user who cleared it is stored as an explicit `null` and stays cleared.
    public static let defaults: HotkeyBindings
    /// Fixed Print-key aliases (PC keyboards send F13, kVK_F13 = 0x69):
    /// F13 → openScreenshotUI, ⇧F13 → instantScreen, ⌥F13 → instantWindow.
    public static let printKeyAliases: [KeyCombo: HotkeyAction]
    /// Actions bound to the same combo as another action (to warn in Settings).
    public func conflicts() -> [KeyCombo: [HotkeyAction]]
}

// ImageMetadata.swift
public enum ImageMetadata {
    /// 72 × scale (144 on Retina).
    public static func dpi(forScale scale: CGFloat) -> CGFloat
}
```

## App-target interfaces

All of these are `@MainActor` unless noted otherwise. `AppCoordinator` owns one instance of each.

```swift
// Capture/FrozenFrame.swift
//   Every display and window is captured ONCE, without the pointer. One pointer sample (position + glyph:
//   image and hot spot) is recorded by the caller synchronously when the UI is requested, and the
//   `imageWithPointer` variants are composited from it by ImageOps.compositePointer, the only place that
//   draws a pointer. The overlay (display image, Window Picker thumbnails) and the final capture read the
//   same variant through image(showingPointer:), so the preview is the output and toggling Show Pointer
//   changes nothing but the pointer.
struct DisplaySnapshot: Sendable { let info: DisplayInfo; let image: CGImage; let imageWithPointer: CGImage }
struct WindowSnapshot: Sendable { let info: WindowInfo; let image: CGImage; let imageWithPointer: CGImage
                                  let scale: CGFloat; let bounds: CGRect /* image extent, global CG points */ }
struct FrozenFrame: Sendable { let displays: [DisplaySnapshot]; let windows: [WindowSnapshot]
                               let pointer: CGPoint; let pointerGlyph: PointerGlyph? }
// Capture/PointerGlyph.swift: PointerGlyph (image, size, hotSpot); PointerSample (location + glyph, read
//   together on the main actor before any await).

// Capture/ScreenCapturer.swift  (not MainActor; an actor or Sendable final class)
//   freezeFrame(includeShadows:pointer:) – every display (showsCursor false), plus every on-screen layer-0
//     window of the current Space (excluding PrtSc's own windows), shadow per setting, each captured once.
//   Window captures set ignoreGlobalClipSingleWindow so a window extending past (or spanning) displays is
//     captured whole. A window image's `bounds` is the window frame, or with shadows SCK's contentRect when
//     it is in global coordinates (exact margins), else the extra size split evenly around the frame
//     (exact only for symmetric shadows).
//   captureDisplay(_:showsPointer:) and captureWindow(_:attached:includeShadow:) for Instant Captures.
//     With attached windows every component honours includeShadow and is composited by its own image
//     bounds (ImageOps.composite), so shadows line up.
//   Stitching a cross-display Selection uses DisplayGeometry.segments (ImageOps.stitch).

// Output/CapturedImage + OutputService
struct CapturedImage: Sendable { let image: CGImage; let scale: CGFloat }
@MainActor protocol CaptureSink: AnyObject { func deliver(_ capture: CapturedImage) async }
//   OutputService: CaptureSink. In order: copy to the pasteboard (PNG + TIFF), write the PNG via ImageIO to
//   FilenameBuilder.uniqueURL in the SaveFolder (create it if missing; colour profile = the image's
//   colour space; DPI = ImageMetadata.dpi; add to recent documents), play "Screen Capture.aif" from
//   /System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/ only if
//   the user's UI sound effects are enabled, then post the CaptureNotification (title "Screenshot
//   Captured", body "You can paste the image from the clipboard", thumbnail attachment — copy the file
//   to a temp location first because attachments move files; clicking opens the file; "Show in Finder" action).
//   Deliveries run strictly one at a time in request order (SerialTaskQueue), so the newest capture is
//   the last to reach the clipboard. The TIFF is sized in points (ImageEncoding.tiffData: pixels / scale)
//   so Retina captures paste at their natural size.
//   deliverScreencast(_ url: URL): for a finished Screencast: only the Capture Notification (no clipboard, no
//   sound); the recorder has already added the file to recent documents. screencastFolderURL.

// Settings/SettingsStore.swift  (@Observable, UserDefaults-backed)
//   saveFolderPath: String?   screencastFolderPath: String?   includeWindowShadow: Bool = false   launchAtLogin: Bool = true (SMAppService.mainApp)
//   hideMenuBarIcon: Bool = false   hotkeys: HotkeyBindings = .defaults   (automatic updates live in Sparkle's own defaults)
//   recordSystemAudio: Bool = false   recordMicrophone: Bool = false   screencastPreferH264: Bool = false
// Settings/SessionState.swift (@Observable, not persisted)
//   showPointer: Bool = false   rememberedSelection: CGRect?   lastCaptureMode: CaptureMode = .selection
//   lastCaptureType: CaptureType = .screenshot

// ScreenshotUI/ScreenshotUIController.swift
//   init(capturer: ScreenCapturer, output: CaptureSink, settings: SettingsStore, session: SessionState)
//   var isPresented: Bool;  func toggle(captureType: CaptureType? = nil)  (⇧⌘2 while open, or while still
//   opening, closes/cancels it; a non-nil type opens in that Capture Type for this opening only, nil uses
//   SessionState.lastCaptureType; while open in the *other* type it switches instead of closing);
//   func dismiss()  (also cancels an opening in progress)
//   var onFailure: (@MainActor (Error) -> Void)?  — freezing the screen failed, or macOS didn't activate PrtSc
//   var onRecord: (@MainActor (ScreencastTarget, _ showsPointer: Bool) -> Void)?  — the record button (Screencast
//     mode): called AFTER the overlay has been closed; the owner starts the ScreencastRecorder.
//   Opening is a session with a generation token: freeze → activate PrtSc and wait (≤ 1 s) for
//   NSApp.isActive → present. Any step after an await checks the token, so a dismissed, cancelled or
//   display-changed (didChangeScreenParameters is observed from the start) session never presents.

// Capture/InstantCaptureService.swift
//   init(capturer:output:settings:); func captureScreen() async; func captureWindow() async
//   One capture at a time (a second trigger while one runs is ignored). Never includes the pointer.
//   The pointer position and frontmost PID are read synchronously when the shortcut fires, before any await.
//   var onFailure: (@MainActor (Error) -> Void)? — AppCoordinator sets it (and the Screenshot UI's) to
//   `handleCaptureFailure`: beep, then the Welcome window if Screen Recording is missing, else an NSAlert.

// Capture/ScreencastRecorder.swift  (@MainActor @Observable) — see "Screencast" below.
//   enum ScreencastTarget { selection(rect:display:), display(id:), window(id:) }
//   struct ScreencastOptions { folder, showsPointer, recordSystemAudio, recordMicrophone, preferH264 }
//   state: idle | starting | recording(startDate:) | stopping;  isRecording, isBusy
//   func start(target:options:) async throws;  func stop() async;  func stopAndWaitUntilIdle() async
//   var onFinished: (@MainActor (URL) -> Void)?;  var onFailure: (@MainActor (Error) -> Void)?
//   (ScreencastError.interrupted carries `savedFile` when a playable part was kept.)

// Hotkeys/HotkeyManager.swift
//   func register(_ bindings: HotkeyBindings, handler: @escaping @MainActor (HotkeyAction) -> Void)
//   Registers bindings + HotkeyBindings.printKeyAliases. Re-register when settings change.

// Permissions/PermissionsService.swift
//   var hasScreenRecording: Bool (CGPreflightScreenCaptureAccess); func requestScreenRecording();
//   func openScreenRecordingSettings(); notification authorization status / request / open settings.

// MenuBar/MenuBarController.swift — NSStatusItem with the menu:
//   Take Screenshot… (⇧⌘2) · Capture Screen (⌃⇧⌘2) · Capture Window (⌥⇧⌘2) · Record Screencast… (⌥⇧⌘R) · ─ · Open Save Folder ·
//   Settings… (⌘,) · Check for Updates… · ─ · Quit PrtSc. Shortcut hints reflect the current bindings: shown as native
//   key equivalents (AppKit draws them in Apple's ⌃⌥⇧⌘ order) or, for keys a menu can't express, as
//   `KeyCombo.displayString` text. "Check for Updates…" is disabled while Sparkle isn't configured.
//   While recording the status item is the Recording Indicator (setRecording(startDate:)): click stops,
//   right-click/⌃-click opens the menu, whose first item is then "Stop Screencast" (Take Screenshot… is
//   disabled, Record Screencast… hidden). Hidden when hideMenuBarIcon (but the indicator still shows
//   while recording); relaunching the app while running (applicationShouldHandleReopen) opens Settings.

// Onboarding — WelcomeWindow on first launch and whenever the Screen Recording permission is missing at
//   launch or when a hotkey fires: explains both permissions, shows ⇧⌘2, buttons open System Settings.
```

## Screenshot UI behaviour (summary; GNOME Shell `main` semantics)

1. On open: `ScreenCapturer.freezeFrame` runs **before** any PrtSc window is shown, then PrtSc is made the active app and the panels are shown only once activation is confirmed (otherwise the open fails via `onFailure`). Then one borderless, key-capable overlay panel appears per display, at `.screenSaver` level with `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, showing that display's frozen image (with or without the pointer, depending on Show Pointer).
2. The CapturePanel is a Liquid Glass capsule near the bottom of `DisplayGeometry.panelDisplay`. It holds the mode buttons (Selection/Screen/Window), a large round capture button and a Show Pointer toggle. A separate close button sits at the top-left. The Capture Type toggle (Screenshot | Screencast) sits at the capsule's left end; see "Screencast" below.
3. Keys: S/C/W switch mode, P toggles the pointer, Return/Space/⌘C capture, Esc closes. In Selection mode: arrows, ⌥, ⌘, ⇧ and R per SelectionEditor. In Screen/Window mode the arrows move focus between displays/windows. Window mode is disabled (and falls back to Selection) when there are no windows.
4. Selection mode: the area outside the Selection is dimmed, with handles at the corners and edges. The rect is remembered in SessionState.
5. Screen mode: each display shows a selectable frame; the display under the pointer is preselected.
6. Window mode: WindowPicker per display using `WindowPickerLayout` (each window on the display that shows most of it, `DisplayGeometry.displayShowingMost`), windows rendered from their unobscured snapshots (with the pointer when Show Pointer is on), the frontmost window preselected with a check-mark badge, click or arrows to change.
7. Capture → close the overlay → build a `CapturedImage` from the frozen frame (crop or stitch; display/window image ± pointer, the same variant the overlay shows) → `output.deliver`. Dismissing gives focus back with cooperative activation: `NSApp.yieldActivation(to: previous)`, then `previous.activate(from:options:)`.
8. Closes on `NSApplication.didChangeScreenParametersNotification` and when PrtSc stops being the active app (⌘Tab), so a screen-wide overlay never gets left behind.
9. Accessibility: every control has a label; mode changes and the Selection size ("640 by 480") are announced with `NSAccessibility.post(…, .announcementRequested)`.

## Screencast

Decided 2026-11-18. It follows GNOME Shell with these deliberate differences: Window recording is allowed, audio is optional, files are HEVC/H.264 rather than WebM, and recordings go to `~/Movies` because macOS has no `~/Videos`.

**Starting a Screencast**
- The CapturePanel gains the Capture Type toggle (Screenshot | Screencast, using the SF Symbols `camera` and `video`) at its left end, as in GNOME.
- **V** toggles the Capture Type.
- The new hotkey action `HotkeyAction.screencast`, default **⌥⇧⌘R** (`kVK_ANSI_R`), opens the Screenshot UI in Screencast mode, or stops the running Screencast. It is rebindable like the others. There is no Print-key alias.
- In Screencast mode all three Capture Modes work: Selection, Screen (one display) and Window (one window, followed as it moves via `SCContentFilter(desktopIndependentWindow:)`).
- Show Pointer sets `SCStreamConfiguration.showsCursor`.
- The capture button turns into a red record button. Pressing it closes the overlay right away (so the overlay isn't recorded) and starts recording.

**While recording**
- The menu bar item becomes the Recording Indicator: a red dot and the elapsed time (`m:ss`, or `h:mm:ss` after an hour). Clicking it stops the recording.
- While recording, the menu bar menu's first item is "Stop Screencast".
- Opening the Screenshot UI during a recording is not allowed. ⇧⌘2 does nothing apart from a beep, and the hotkey/menu path for Screencast stops the recording instead.
- Instant Captures still work during a recording.

**Recording settings**
- `SCStream` with `SCRecordingOutput` (macOS 15+) writes an `.mp4` directly.
- Codec: **HEVC** by default (`AVVideoCodecType.hevc`); H.264 when the "Most compatible format (H.264)" setting is on.
- Native pixel resolution of the source and 60 fps (`minimumFrameInterval = 1/60`).
- Selection: `sourceRect` on that display. A Selection spanning displays is clamped to the display that shows most of it; the checklist notes this as a known limitation.
- Audio is off by default. Settings has "Record system audio" (`capturesAudio`, excluding PrtSc's own sounds) and "Record microphone" (`captureMicrophone`). Turning on the microphone requests microphone permission, which needs `NSMicrophoneUsageDescription` in Info.plist.

**Output**
- File: `ScreencastFolderResolver` → `~/Movies/Screencasts` (configurable; falls back to `~/Movies`, then home). Name: `FilenameBuilder.uniqueURL(prefix: "Screencast", …, pathExtension: "mp4")` → `Screencast from 2026-11-18 01-30-00.mp4`, with the same `-1`, `-2` conflict suffixes.
- The video is not copied to the clipboard (as in GNOME).
- On finish: the Capture Notification titled "Screencast Recorded", body "Click here to view the video", with a thumbnail of the first frame (`AVAssetImageGenerator`). Clicking opens the video; the "Show in Finder" action works as for screenshots.
- On failure (stream stopped by the system, disk full, permission revoked): stop cleanly, keep whatever was written if the file is playable, and show an alert with the reason.
- When the target goes away mid-recording (the window closes or the display is unplugged), stop and save. Displays changing don't cancel a running recording unless its own display disappears.

**Types**
- PrtScCore: `CaptureType` (screenshot, screencast; `forKey("v")` toggles), `HotkeyAction.screencast` with its default, `FilenameBuilder` gaining a `prefix` parameter (default "Screenshot", keeping existing call sites), `ScreencastFolderResolver`, `RecordingClock.format(elapsed:)`. All tested.
- App: `Capture/ScreencastRecorder` (`@MainActor @Observable`; state idle, starting, recording(startDate:) or stopping; `start(target:options:) async throws`; `stop() async`; `onFinished(URL)`; `onFailure(Error)`). `ScreencastTarget` is one of selection(rect, display), display(id) or window(id). The settings gain `screencastFolderPath`, `recordSystemAudio`, `recordMicrophone` and `screencastPreferH264`. `SessionState.lastCaptureType` remembers the last type until quit.
- Also in PrtScCore: `RecordingGeometry` (even pixel sizes, pixel-aligned `sourceRect` for a Selection clamped to one display), tested.

**Implementation notes (where this document left room)**
- The file is written directly under its final unique name in the Screencast Folder (no temp name and move); an unplayable stub is deleted when a recording fails, a playable partial file is kept.
- Starting needs the overlay gone first: the Screenshot UI calls `onRecord` after `dismiss()`, and the stream's content filter excludes PrtSc's own application anyway.
- Sizes: output pixels are points × scale rounded **down to even** (encoders need even dimensions); a Selection's `sourceRect` is snapped to whole pixels so the video is a 1:1 crop (`RecordingGeometry`). A Window recording keeps its size from the start (`scalesToFit`), so resizing the window while recording scales its content.
- The stream's stop reasons: the user stopping from the system (`SCStreamError.userStopped`), the window closing (`streamDidBecomeInactive`, then confirmed against `SCShareableContent` after 1.5 s because a minimized window reports the same signal), or the recording's own display disappearing (`didChangeScreenParametersNotification`) all stop and save normally. Any other `didStopWithError` or a failed recording output (disk full is `SCStreamError.insufficientStorage`, -3822) keeps a playable file and goes to `onFailure` as `ScreencastError.interrupted`.
- Microphone: `start` re-checks microphone authorization and fails with an explanation if it was revoked. Under the hardened runtime the app needs the `com.apple.security.device.audio-input` entitlement as well as `NSMicrophoneUsageDescription`.
- The Recording Indicator is the status item itself: while recording it has no menu (a click stops); right-click or ⌃-click borrows the menu for one tracking session.
- Quitting during a recording (`applicationShouldTerminate` → `.terminateLater`) stops and finalizes the file first.
- The open hotkey (⇧⌘2) opens in the *last used* Capture Type; the Screencast hotkey (⌥⇧⌘R) opens in Screencast mode for that opening only and does not change the remembered type.

## Testing

- `swift test` in `Packages/PrtScCore`, using Swift Testing (`import Testing`, `@Test`, `#expect`). Logic is written test-first.
- The app target is checked by `xcodebuild -scheme PrtSc build`, plus `docs/manual-test-checklist.md`.
