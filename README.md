# Pocket Mac

Turn your iPhone into a tiny Mac. Rotate to landscape and Pocket Mac splits the
screen in two: the top half becomes a simulated macOS desktop (menu bar, dock,
draggable windows, wallpaper), and the bottom half becomes a real trackpad and
keyboard you use to drive it — just like folding a laptop shut.

## Features

- **Laptop mode** — rotate the phone sideways to "open the lid": the display
  splits into a macOS-style screen on top and an input deck on the bottom.
- **Trackpad** — drag to move the cursor (relative tracking, like a real
  trackpad), tap to click, press and drag to move windows, two-finger drag to
  scroll.
- **Keyboard** — a full on-screen Mac keyboard (letters, numbers, shift,
  space, return, delete) that types into whatever text field has focus.
- **Menu bar** — live clock, Wi-Fi/battery glyphs, and a menu that changes
  with the frontmost app.
- **Dock** — bouncing launch animation, running-app indicators, magnification
  on touch.
- **Windows** — draggable, closable, minimizable windows with macOS-style
  traffic-light controls.
- **Built-in apps** — Finder, Notes, Safari (real web view), Calculator,
  Terminal, About This Mac, and Settings (wallpaper + appearance).
- **Launchpad & Spotlight** — a full-screen app grid and a quick search
  overlay.

## Requirements

- Xcode 16+
- iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`

## Building

```bash
xcodegen generate
open "Pocket Mac.xcodeproj"
```

or build from the command line:

```bash
xcodegen generate
xcodebuild -project "Pocket Mac.xcodeproj" -scheme "Pocket Mac" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Testing

```bash
xcodegen generate
xcodebuild -project "Pocket Mac.xcodeproj" -scheme "Pocket Mac" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## License

MIT — see [LICENSE](LICENSE).
