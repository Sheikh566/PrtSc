# Copy the GNOME Shell screenshot UI, not the gnome-screenshot app

Two GNOME programs carry the name "screenshot". The standalone `gnome-screenshot` app (GNOME/gnome-screenshot) is unmaintained; its last functional release was 41.0 in 2021, and the default GNOME session no longer uses it. On GNOME 42+ (Ubuntu 22.04+), pressing Print opens the GNOME Shell screenshot UI (`js/ui/screenshot.js` in GNOME/gnome-shell). That is the behaviour users actually miss, so we copy the Shell UI, following its current `main` branch, and do not copy the old app.

## Consequences

- The old app's features are out of scope: the interactive options dialog, the delay timer, the "Save As" dialog and the `gnome-screenshot` CLI flags. Any of them comes back only as a deliberate extra.
- The behaviour is copied, but not the look: the UI uses the native macOS 26 Liquid Glass style instead of libadwaita.
