# Manual test checklist

What unit tests (`swift test` in `Packages/PrtScCore`) cannot cover. Run it against a **Release** build before every release, on macOS 26 or later. Ideally have a second display (one Retina, one non-Retina or a different scale) and a Space or full-screen app available.

Reset between runs if needed: `tccutil reset ScreenCapture io.github.sheikh566.PrtSc`, `defaults delete io.github.sheikh566.PrtSc`.

## First run and permissions

- [ ] First launch shows the Welcome window explaining Screen Recording and notifications, and shows the ⇧⌘2 shortcut.
- [ ] The Welcome buttons open the right System Settings panes.
- [ ] With Screen Recording missing, pressing ⇧⌘2 shows the Welcome window instead of failing silently.
- [ ] After granting permission (and restarting if macOS asks), ⇧⌘2 opens the Screenshot UI.
- [ ] No Dock icon; the menu bar icon is present with the expected menu items and shortcut hints.

## Opening and closing

- [ ] ⇧⌘2 opens the Screenshot UI; pressing ⇧⌘2 again closes it (toggle).
- [ ] Esc closes it. The close button (top left) closes it.
- [ ] Nothing of PrtSc itself (overlay, panel) shows up in any capture.
- [ ] The frozen frame matches the screen at the moment of opening (play a video or run a clock to confirm it is frozen).
- [ ] The overlay appears only once PrtSc has keyboard focus: right after ⇧⌘2, S/C/W/Esc work immediately (try from Safari, Terminal and a full-screen app), and typing never reaches the app underneath.
- [ ] Pressing ⇧⌘2 twice quickly (while the frame is still being taken) leaves nothing open; pressing it once more opens normally.
- [ ] Plugging or unplugging a display right after pressing ⇧⌘2 never leaves a stale overlay behind.
- [ ] After Esc, the previously active app is key again: typing and ⌘V go to it without clicking.

## Modes

- [ ] S, C, W keys and the three panel buttons switch Selection, Screen and Window; the panel highlights the active mode.
- [ ] Selection: Return, Space, ⌘C and the capture button each capture.
- [ ] Screen: each display shows a frame; the display under the pointer is preselected; arrows move between displays; click selects; capture grabs that whole display.
- [ ] Window: see Window Picker below.
- [ ] The last Selection rectangle is remembered next time the UI opens (within the session).

## Selection keys

- [ ] Arrow keys resize (→ and ↓ grow, ← and ↑ shrink) in 5 pt steps.
- [ ] ⌥+arrow moves the Selection instead.
- [ ] ⌘+arrow uses 1 pt steps (also with ⌥ for a 1 pt move).
- [ ] ⇧+arrow uses large steps (primary display width/height).
- [ ] The Selection never leaves the screen union and never gets smaller than 1×1.
- [ ] R resets to the default centred rectangle.
- [ ] A plain click (no drag) makes a small square around the pointer.
- [ ] Dragging a handle or edge resizes; dragging inside moves; dragging outside starts a new Selection.
- [ ] Right-drag always starts a new Selection, even starting inside the current one.
- [ ] The area outside the Selection is dimmed; the size is shown and announced.

## Show Pointer

- [ ] P and the panel toggle switch Show Pointer; the pointer appears or disappears in the live preview.
- [ ] With it on, the captured image includes the pointer at the right spot, in Selection, Screen and Window modes.
- [ ] Toggling P with a video or clock on screen changes only the pointer: the scene stays frozen and the pointer stays where it was when the UI opened.
- [ ] In Window mode the Window Picker thumbnails show the pointer (on the window it was over) when Show Pointer is on, matching the delivered image.
- [ ] The setting is not remembered after relaunch (session only).

## Window Picker

- [ ] Window mode spreads the current Space's windows, unobscured (windows hidden behind others show completely).
- [ ] The frontmost window is preselected with the check-mark badge; click and arrow keys change the choice.
- [ ] Capturing a window gives only that window (with or without shadow per Settings), including transparency at rounded corners.
- [ ] A window partly off the edge of a display, or spanning two displays, still has a cell and is captured whole (nothing clipped at the display edge).
- [ ] With no capturable windows (empty Space), the Window button is disabled and the UI falls back to Selection.
- [ ] Windows of PrtSc itself (Settings, Welcome) are not listed.

## Multiple displays

- [ ] The panel appears on the display that contains the pointer when ⇧⌘2 is pressed (try from each display).
- [ ] An overlay covers every display, each showing its own frozen image.
- [ ] A Selection spanning two displays with different scale factors captures correctly: no seams, the output uses the larger scale, nothing stretched.
- [ ] A Selection with a fractional origin (e.g. dragged so it starts at a half point on a 1× display, or on a 1× + 2× pair) is pixel-sharp: zoom in on the saved PNG and check text edges are not blurred or a row shorter/taller than the size label says.
- [ ] Displays arranged with negative coordinates (a display left of or above the main one) work for Selection, Screen and Window.
- [ ] Unplugging or plugging in a display, or changing resolution, while the UI is open closes the UI cleanly.

## Spaces and full-screen apps

- [ ] The Screenshot UI opens over a full-screen app (Safari, Terminal) and over a Space other than the first.
- [ ] Switching Spaces with ⌃←/⌃→ is not hijacked (⌃ is not used by Selection keys; fine steps use ⌘).
- [ ] Window mode lists only the windows of the current Space.
- [ ] Instant captures work from a full-screen app.

## Instant captures

- [ ] ⌃⇧⌘2 captures the display under the pointer without opening the UI.
- [ ] ⌥⇧⌘2 captures the front-most window of the active app, including its sheets and popovers.
- [ ] ⌥⇧⌘2 with a sheet open (e.g. Save dialog, Safari's Settings sheet) captures the parent window with the sheet in place, not just the sheet.
- [ ] ⌥⇧⌘2 with a popover open and the shadow setting on includes the shadows of both the window and the popover, correctly aligned.
- [ ] Moving the pointer to another display, or switching apps, immediately after pressing an Instant Capture hotkey still captures what was targeted when the key was pressed.
- [ ] ⌥⇧⌘2 with Finder showing only the desktop falls back to the display under the pointer.
- [ ] ⌥⇧⌘2 never captures PrtSc itself.
- [ ] Instant captures never include the pointer (like GNOME's Shift+Print / Alt+Print); an Instant Window capture honours the window shadow setting.
- [ ] If an Instant Capture (or opening the UI) fails, you get a beep and an alert with the reason; with Screen Recording missing the Welcome window opens instead.
- [ ] Pressing an Instant Capture hotkey twice quickly produces one capture, not two.

## Output

- [ ] Every capture is on the clipboard (paste into Preview, Notes, and a chat app).
- [ ] A PNG is saved in the Save Folder as `Screenshot from YYYY-MM-DD HH-MM-SS.png` (24-hour clock).
- [ ] Two captures within the same second get a `-1` suffix instead of overwriting.
- [ ] Two captures delivered back to back (e.g. a huge Screen capture, then a tiny Selection right after): both files exist, and the clipboard holds the second one.
- [ ] On a Retina display, pasting into an app that prefers TIFF (e.g. Preview > File > New from Clipboard, or Pixelmator) gives the capture at point size (half the pixel size), not double.
- [ ] The Save Folder is created if it is missing (default `~/Pictures/Screenshots`; falls back to the home folder when `~/Pictures` does not exist).
- [ ] On a Retina display the file is 144 DPI with the display's colour profile (check with Preview > Tools > Show Inspector, or `sips -g dpiWidth -g profile`).
- [ ] The capture sound plays only when "Play sound effects" is enabled in System Settings > Sound, and stays silent when it is off.
- [ ] A notification "Screenshot Captured" appears with a thumbnail.
- [ ] Clicking the notification opens the image; its "Show in Finder" action reveals the file.
- [ ] With notifications denied, capture still saves and copies (no crash, no hang).
- [ ] The saved file is added to recent documents (File > Open Recent in Preview).

## Settings

- [ ] "Settings…" (⌘, from the menu) opens the window; it is reachable with the menu bar icon hidden (see below).
- [ ] Recording a new hotkey works; the old one stops working, the new one works immediately.
- [ ] Clicking one shortcut row and then another: only the second records (the first goes back to its shortcut); the next key press changes only the second row, and global hotkeys stay off until recording ends.
- [ ] Recording a shortcut, then closing Settings or switching to another app: recording ends and all global hotkeys work again.
- [ ] Two actions bound to the same combo show a conflict warning.
- [ ] A hotkey already taken by the system or another app is handled gracefully (no crash; message if it cannot be registered).
- [ ] The Print-key aliases work: F13 opens the UI, ⇧F13 captures the screen, ⌥F13 captures the window (needs a keyboard with F13, or a remapper).
- [ ] Changing the Save Folder: the next capture goes to the new folder.
- [ ] Window shadow toggle changes whether Window captures include the shadow.
- [ ] Launch at login toggle shows in System Settings > General > Login Items and works after logout/login.
- [ ] Hide menu bar icon removes the icon; launching PrtSc again while it runs reopens Settings; the hotkeys keep working; un-hiding restores the icon.
- [ ] With the placeholder `SUPublicEDKey`, "Check for Updates…" is disabled and the automatic-updates toggle is off; with a real key and appcast both respond.

## Accessibility

- [ ] VoiceOver: every panel control has a sensible label; mode changes and the Selection size ("640 by 480") are announced.
- [ ] The UI can be driven entirely with the keyboard.
- [ ] System Settings > Accessibility > Display > **Reduce Transparency** on: the Capture Panel and other glass surfaces use a solid background and stay legible.
- [ ] Increase Contrast and Reduce Motion do not break layout.
- [ ] Light and dark appearance both look right.

## Packaging (release builds only)

- [ ] The dmg opens with `PrtSc.app` and an Applications shortcut; dragging installs it.
- [ ] `codesign --verify --deep --strict /Applications/PrtSc.app` passes; `spctl -a -vv` accepts it when notarized.
- [ ] `defaults read /Applications/PrtSc.app/Contents/Info CFBundleShortVersionString` matches the tag.
- [ ] Updating from the previous release via Sparkle works and relaunches into the new version.
