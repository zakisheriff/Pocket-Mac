# Changelog

## 1.0.0

Initial release.

- Direct mode: full-screen simulated macOS desktop on a regular iPhone,
  driven by direct touch, with a floating keyboard sheet and an optional
  floating trackpad.
- Duo mode: landscape split into a desktop half and a physical
  trackpad + keyboard deck, simulating the fictional "iPhone Duo" fold.
- Window manager with drag, resize, minimize, close and fullscreen/zoom,
  all reachable both by direct touch and by indirect trackpad hit-testing.
- Menu bar with a live clock and an adaptive layout for narrow widths.
- Dock with launch bounce, running-app indicators and Launchpad.
- Spotlight-style search overlay.
- Bundled apps: Finder (with a filterable sidebar), Notes, Safari (a real
  WKWebView browser), Calculator, Terminal, Photos, Trash, Settings and
  About This Mac.
- Settings for layout mode, desktop picture and trackpad tracking speed.
- Unit tests for window lifecycle/hit-testing, cursor tracking and
  keyboard input.
