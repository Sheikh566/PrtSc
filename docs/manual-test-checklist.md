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
- [ ] Hovering any Capture Panel control for about half a second shows a glass tooltip above it with its name and key (Screenshot/Screencast `V`, Selection `S`, Screen `C`, Window `W`, Capture/Record `↩`, Show Pointer `P`); the close button's tooltip (`Esc`) appears below it. Tooltips disappear when the pointer leaves and never block clicks or drags.
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
- [ ] Clicking a notification (or its action) does NOT also open Settings; relaunching PrtSc from Finder while it runs still does.
- [ ] With notifications denied, capture still saves and copies (no crash, no hang).
- [ ] The saved file is added to recent documents (File > Open Recent in Preview).

## Screencast

Needs Screen Recording permission (and Microphone permission for the microphone items). Check the saved files in QuickTime Player or `mdls`/`ffprobe`.

**Starting**
- [ ] The Capture Panel has the Capture Type toggle (camera | video) at its left end; clicking video turns the capture button into a red record button, clicking camera turns it back.
- [ ] V toggles the Capture Type; the change is announced by VoiceOver ("Screencast mode" / "Screenshot mode") and both toggle buttons have labels.
- [ ] ⌥⇧⌘R opens the Screenshot UI directly in Screencast mode (from Safari, Terminal and a full-screen app); with the UI already open in Screenshot mode it switches to Screencast, and with the UI open in Screencast mode it closes the UI.
- [ ] The menu bar item "Record Screencast…" shows ⌥⇧⌘R and opens the UI in Screencast mode.
- [ ] The last Capture Type is remembered until quit: switch to Screencast, close with Esc, press ⇧⌘2: it opens in Screencast mode. ⌥⇧⌘R and then Esc does not change what ⇧⌘2 opens in.
- [ ] Pressing the record button, Return, Space or ⌘C in Screencast mode closes the overlay at once and starts recording; the overlay and the Capture Panel are not in the video.

**Capture Modes** (record 5–10 s each, then play the file)
- [ ] Selection: the video is exactly the selected area, pixel-sharp (no scaling blur), at native resolution (Retina: twice the point size, rounded down to even numbers).
- [ ] Selection that spans two displays: the video covers the part on the display that shows most of the Selection (known limitation: the rest is not recorded).
- [ ] Screen: the display that was selected (arrow keys / click / pointer) is recorded whole, at native resolution; try each display.
- [ ] Window: only that window is recorded, without its shadow, and it follows the window when you move it; a window partly off screen is recorded whole.
- [ ] A window that is resized during the recording keeps the video size (its content is scaled).
- [ ] PrtSc's own windows (Settings, Welcome) never appear in a recording, in any mode.
- [ ] 60 fps: scroll a page or drag a window during a Screen recording; playback is smooth (check with `ffprobe`: ~60 fps).

**Pointer and audio**
- [ ] Show Pointer on: the pointer is in the video (and moves); off: no pointer anywhere in the video.
- [ ] Audio off (default): the file has no audio track.
- [ ] "Record system audio" on, while playing music: the video has the audio; PrtSc's own sounds (the screenshot shutter during an Instant Capture) are not in it.
- [ ] "Record microphone" on: macOS asks for microphone permission the first time; Allow keeps the switch on, Don't Allow puts it back off and shows the message with "Open Microphone Settings". The recording has your voice.
- [ ] With the microphone permission revoked in System Settings afterwards and the switch still on, pressing record shows an alert about the microphone and records nothing.
- [ ] System audio and microphone together: both are in the video.
- [ ] Codec: by default `ffprobe` shows `hevc`; with "Most compatible format (H.264)" on it shows `h264`. Both play in QuickTime Player.

**Recording Indicator and stopping**
- [ ] While recording, the menu bar item shows a red dot and the elapsed time (`0:01`, `0:02`, …; after one hour `1:00:00`), updating every second.
- [ ] Clicking the Recording Indicator stops the recording and saves the file.
- [ ] Right-click (or ⌃-click) on it opens the menu with "Stop Screencast" first; choosing it stops. "Take Screenshot…" is disabled and "Record Screencast…" is not listed during a recording.
- [ ] ⌥⇧⌘R while recording stops it (no UI opens).
- [ ] With "Hide menu bar icon" on, the indicator still appears for the length of a recording and the icon is hidden again afterwards.
- [ ] ⇧⌘2 while recording only beeps: no Screenshot UI opens. The menu's "Take Screenshot…" is disabled.
- [ ] Instant Captures (⌃⇧⌘2, ⌥⇧⌘2) still work while recording, and PrtSc's notification for them appears; they are not in the video.
- [ ] Stopping within a second of starting (double-tap ⌥⇧⌘R) ends cleanly with a playable file or a clear alert; nothing is left recording.
- [ ] Quitting PrtSc from the menu while recording waits a moment and leaves a playable file.

**Output**
- [ ] The file is `Screencast from YYYY-MM-DD HH-MM-SS.mp4` in `~/Movies/Screencasts` (created if missing; falls back to `~/Movies`, then the home folder); nothing is put on the clipboard.
- [ ] Two Screencasts started in the same second (or an existing file with the same name) get `-1`, `-2` suffixes; nothing is overwritten.
- [ ] Changing the Screencast Folder in Settings (Choose…, Reveal, Reset to Default) is used by the next recording.
- [ ] A notification "Screencast Recorded" / "Click here to view the video" appears with a thumbnail of the first frame; clicking it opens the video; its "Show in Finder" action reveals the file.
- [ ] With notifications denied the recording is still saved (no crash, no hang).
- [ ] The saved file is in recent documents (File > Open Recent in QuickTime Player).

**Failure and edge cases**
- [ ] Closing the recorded window mid-recording stops and saves normally (notification, playable file, no error alert); minimizing it does not stop the recording.
- [ ] Unplugging the recorded display (Screen or Selection) mid-recording stops and saves what was recorded; unplugging another display does not affect the recording.
- [ ] Disk full (record to a nearly full volume or a small disk image chosen as the Screencast Folder): the recording stops, an alert explains there is not enough disk space, and the part that was written is kept if it plays (the alert offers "Show in Finder").
- [ ] Revoking Screen Recording permission mid-recording (System Settings) stops cleanly with an alert or the Welcome window; the file is kept when playable.
- [ ] A Screencast Folder that cannot be written to shows an alert instead of failing silently.
- [ ] With Screen Recording missing, ⌥⇧⌘R shows the Welcome window.
- [ ] Reduce Transparency: the Capture Type toggle and the red record button stay legible.

## Settings

- [ ] "Settings…" (⌘, from the menu) opens the window; it is reachable with the menu bar icon hidden (see below).
- [ ] The Shortcuts list includes "Record a Screencast" (⌥⇧⌘R); it can be rebound or cleared, and an old settings file from before Screencast existed shows ⌥⇧⌘R for it.
- [ ] Recording a new hotkey works; the old one stops working, the new one works immediately.
- [ ] Clicking one shortcut row and then another: only the second records (the first goes back to its shortcut); the next key press changes only the second row, and global hotkeys stay off until recording ends.
- [ ] Recording a shortcut, then closing Settings or switching to another app: recording ends and all global hotkeys work again.
- [ ] Two actions bound to the same combo show a conflict warning.
- [ ] A hotkey already taken by the system or another app is handled gracefully (no crash; message if it cannot be registered).
- [ ] The Print-key aliases work: F13 opens the UI, ⇧F13 captures the screen, ⌥F13 captures the window (needs a keyboard with F13, or a remapper).
- [ ] Changing the Save Folder: the next capture goes to the new folder.
- [ ] The Screencast section has the folder chooser, "Record system audio", "Record microphone" and "Most compatible format (H.264)"; they are remembered after relaunch and all start off.
- [ ] Window shadow toggle changes whether Window captures include the shadow.
- [ ] Launch at login toggle shows in System Settings > General > Login Items and works after logout/login.
- [ ] Hide menu bar icon removes the icon; launching PrtSc again while it runs reopens Settings; the hotkeys keep working; un-hiding restores the icon.
- [ ] With the placeholder `SUPublicEDKey`, "Check for Updates…" is disabled and the automatic-updates toggle is off; with a real key and appcast both respond.

## Accessibility

- [ ] VoiceOver: every panel control has a sensible label (including Capture Type and the Record button); mode changes, Capture Type changes and the Selection size ("640 by 480") are announced; the Recording Indicator reads "Recording Screencast, 0:12. Click to stop.".
- [ ] The UI can be driven entirely with the keyboard.
- [ ] System Settings > Accessibility > Display > **Reduce Transparency** on: the Capture Panel and other glass surfaces use a solid background and stay legible.
- [ ] Increase Contrast and Reduce Motion do not break layout.
- [ ] Light and dark appearance both look right.

## Packaging (release builds only)

- [ ] The dmg opens with `PrtSc.app` and an Applications shortcut; dragging installs it.
- [ ] `codesign --verify --deep --strict /Applications/PrtSc.app` passes; `spctl -a -vv` accepts it when notarized.
- [ ] `defaults read /Applications/PrtSc.app/Contents/Info CFBundleShortVersionString` matches the tag.
- [ ] Updating from the previous release via Sparkle works and relaunches into the new version.
