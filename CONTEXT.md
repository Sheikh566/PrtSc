# PrtSc

PrtSc is a macOS menu bar app that copies the behaviour of the GNOME Shell screenshot UI (GNOME 42+, Ubuntu 22.04+) and uses a native macOS look. It copies GNOME's behaviour; it does not copy GNOME's appearance.

## Language

**Screenshot UI**:
The full-screen interactive layer that opens when you press the open hotkey. It freezes the screen and shows the capture controls.
_Avoid_: Overlay, capture window, picker

**Capture Panel**:
The floating capsule in the Screenshot UI. It holds the Capture Type toggle, the Capture Mode buttons, the capture button (a record button for a Screencast) and the Show Pointer toggle, and appears on the display with the pointer.
_Avoid_: Toolbar, control bar, HUD

**Capture Mode**:
What the next capture will cover: one of **Selection**, **Screen** or **Window**.
_Avoid_: Capture area, capture type

**Selection**:
A rectangle you draw in the Screenshot UI. A capture in this mode covers only that rectangle.
_Avoid_: Area, region, crop

**Screen**:
The Capture Mode that covers one whole display.
_Avoid_: Monitor, full screen, desktop

**Window**:
The Capture Mode that covers one application window, chosen in the Screenshot UI.
_Avoid_: App shot

**Show Pointer**:
A toggle in the Screenshot UI that controls whether the mouse pointer appears in the capture.
_Avoid_: Include cursor, cursor toggle

**Frozen Frame**:
The snapshot of every display taken the moment the Screenshot UI opens. Every Selection, Screen and Window capture made in the UI is cut from it.
_Avoid_: Freeze, background image

**Window Picker**:
The part of the Screenshot UI in Window mode that spreads out the current Space's windows, unobscured, so you can choose one.
_Avoid_: Exposé, window highlighter

**Instant Capture**:
A capture triggered straight from a hotkey without opening the Screenshot UI. It is either an Instant Screen capture or an Instant Window capture.
_Avoid_: Quick shot, silent capture

**Capture Type**:
What the Screenshot UI produces: either a **Screenshot** (a still image) or a **Screencast** (a video). The Capture Panel has a toggle for it.
_Avoid_: Photo/video mode, output type

**Screencast**:
A video recording of a Selection, a Screen or a Window. It starts from the Screenshot UI and runs until you stop it.
_Avoid_: Screen recording, video capture, movie

**Recording Indicator**:
The menu bar item shown while a Screencast is running. It displays a red dot and the elapsed time, and clicking it stops the recording.
_Avoid_: Recording badge, timer, stop button

## Output

**Save Folder**:
The folder where every screenshot is written as a file. The default is `~/Pictures/Screenshots`.
_Avoid_: Output directory, destination

**Screencast Folder**:
The folder where every Screencast is written. The default is `~/Movies/Screencasts`.
_Avoid_: Videos folder, recordings directory

**Capture Notification**:
The notification shown after each screenshot or Screencast. It has a thumbnail, opens the file when clicked, and has a "Show in Finder" action.
_Avoid_: Toast, preview, floating thumbnail
