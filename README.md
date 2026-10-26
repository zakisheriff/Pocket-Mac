# <div align="center">Pocket Mac</div>

<div align="center">
<strong>Turn Your iPhone Into a Tiny Mac — Real Screen Sharing, Zero Setup</strong>
</div>

<br />

<div align="center">

![Swift](https://img.shields.io/badge/Swift-5.0-F05138?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2026-0071e3?style=for-the-badge&logo=apple&logoColor=white)
![VNC](https://img.shields.io/badge/Protocol-RFB%20%2F%20VNC-333333?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

</div>

<br />

> **"Fold your iPhone shut, open your Mac."**
>
> Pocket Mac isn't another remote-desktop app; it's a laptop that lives in your
> pocket. Rotate your iPhone sideways and the screen splits exactly like a
> laptop lid folding open — a real macOS screen on top, a real trackpad and
> keyboard on the bottom — driving your actual Mac over Screen Sharing.

---

## 🌟 Vision

Pocket Mac's mission is to be:

- **A real Mac in your pocket** — not a simulation, an actual Screen Sharing (VNC/RFB) session with your own Mac
- **Zero-setup discovery** — finds Macs with Screen Sharing on over Bonjour, no IP addresses to type
- **A native, laptop-like interface** — rotate to "open the lid" instead of staring at a cramped remote-desktop window

---

## ✨ Why Pocket Mac?

Remote-desktop apps treat the phone as a dumb window onto a desktop UI that
was never designed for touch. Pocket Mac instead mirrors the physical
mental model of a laptop: fold it open, the top half is the screen, the
bottom half is the keyboard and trackpad you already know how to use.

---

## 💻 Laptop-Style Interface

- **Laptop mode**  
  Rotate the phone sideways to "open the lid": the display splits into a
  live macOS screen on top and an input deck on the bottom.

- **Trackpad**  
  Drag to move the cursor (relative tracking, like a real trackpad), tap to
  click, press-and-drag to move windows, two-finger drag to scroll.

- **On-screen Mac keyboard**  
  A full keyboard (letters, numbers, shift, space, return, delete) that
  types directly into whatever field has focus on the Mac.

---

## 🔎 Zero-Setup Discovery

- **Bonjour scanning**  
  Automatically finds every Mac on the local network advertising
  `_rfb._tcp` (Screen Sharing turned on) — no IP address needed.

- **Saved Macs**  
  Remembers Macs you've connected to before for one-tap reconnects.

- **Keychain-backed credentials**  
  Login details are stored in the iOS Keychain, never in plain text.

---

## 🔐 Real VNC/RFB Protocol Support

- **Native RFB client**  
  Hand-written RFB protocol implementation (handshake, framebuffer updates,
  pointer/key events) — no third-party VNC SDK.

- **Apple Remote Desktop (ARD) authentication**  
  Supports macOS's Diffie–Hellman-based ARD auth, with a `BigInt`-backed
  implementation cross-checked for correctness at macOS's 2048/4096-bit key
  sizes.

- **Standard VNC password authentication**  
  Falls back to classic DES-challenge VNC auth for non-macOS RFB servers.

- **ZRLE decoding**  
  Decodes the ZRLE-compressed framebuffer updates macOS Screen Sharing
  sends, tuned to stay smooth on a phone.

---

## 📁 Project Structure

```
Pocket Mac/
├── Sources/PocketMac/
│   ├── App/
│   │   └── PocketMacApp.swift       # App entry point
│   ├── Discovery/
│   │   ├── MacBrowser.swift         # Bonjour discovery of _rfb._tcp Macs
│   │   ├── SavedMacStore.swift      # Remembered Macs
│   │   └── KeychainStore.swift      # Secure credential storage
│   ├── Managers/
│   │   ├── SettingsStore.swift      # App settings
│   │   └── HapticsManager.swift     # Haptic feedback
│   ├── VNC/
│   │   ├── RFBClient.swift          # Core RFB/VNC client
│   │   ├── RFBStream.swift          # Socket framing
│   │   ├── RFBMessages.swift        # Protocol message encode/decode
│   │   ├── RFBFramebuffer.swift     # Framebuffer state
│   │   ├── RFBCursor.swift          # Remote cursor handling
│   │   ├── ZRLEDecoder.swift        # ZRLE tile decoding
│   │   ├── VNCPasswordAuth.swift    # Classic VNC auth
│   │   ├── AppleRemoteDesktopAuth.swift # ARD Diffie–Hellman auth
│   │   ├── MontgomeryModPow.swift   # Fast modular exponentiation
│   │   └── Keysym.swift             # Key code → X keysym mapping
│   ├── Views/
│   │   ├── Connect/                 # Discovery, login, settings sheets
│   │   ├── Session/                 # Remote screen, trackpad, keyboard
│   │   └── ContentView.swift        # Root view
│   └── Resources/
│       └── Assets.xcassets
└── Tests/PocketMacTests/
```

---

## 🚀 Quick Start

### Prerequisites

- **Xcode 16+**
- **iOS 26+** (device or simulator)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — generates the `.xcodeproj`
- A **Mac with Screen Sharing enabled** (System Settings → General → Sharing)

### 1. Clone the Repository

```bash
git clone https://github.com/zakisheriff/Pocket-Mac.git
cd "Pocket Mac"
```

### 2. Generate the Xcode Project

```bash
xcodegen generate
open "Pocket Mac.xcodeproj"
```

### 3. Build & Run

```bash
xcodegen generate
xcodebuild -project "Pocket Mac.xcodeproj" -scheme "Pocket Mac" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### 4. Connect

1. Open Pocket Mac on your iPhone.
2. Pick your Mac from the discovered list (or enter its address).
3. Sign in with your Mac's username/password or Apple Remote Desktop
   credentials.
4. Rotate your iPhone sideways to open the "lid."

---

## 🎯 Key Features

### For Everyday Use

✅ **Laptop mode** — rotate to split into screen + input deck  
✅ **Real trackpad gestures** — drag, click, two-finger scroll  
✅ **Full on-screen keyboard** — types directly into the remote Mac  
✅ **One-tap reconnect** — saved Macs with Keychain-backed logins  
✅ **Fallback pointer rendering** — draws a Mac-style arrow when the host
doesn't send its own cursor  

### Under the Hood

✅ **Zero-config Bonjour discovery** of `_rfb._tcp` services  
✅ **Native RFB/VNC protocol stack** written in Swift, no SDK dependency  
✅ **ARD and classic VNC auth**, verified against `BigInt` at real macOS key
sizes  

---

## 🔧 Tech Stack

- **Swift 5** — core application and protocol implementation
- **SwiftUI** — all views, including the live remote-screen renderer
- **Network / Core Graphics / Core Animation** — sockets, framebuffer
  decoding, GPU-driven screen compositing
- **BigInt** — modular exponentiation for Apple Remote Desktop auth
- **XcodeGen** — declarative, version-controlled Xcode project generation

---

## 🔒 Security Features

✅ **iOS Keychain storage** for saved Mac credentials — never written to disk
in plain text  
✅ **Apple Remote Desktop (Diffie–Hellman) authentication** support, matching
macOS's own Screen Sharing security model  
✅ **Local-network only** — Pocket Mac only ever talks to Macs on the same
network via Bonjour-advertised Screen Sharing, never a remote relay  

---

## Streaming performance

Settings → Streaming applies immediately during a connection:

- **Responsive** (default) prefers Hextile to reduce compression work on the Mac.
  It uses more Wi-Fi bandwidth and benefits from a fast local network.
- **Efficient** prefers ZRLE to reduce network traffic. It can perform better
  when bandwidth is limited. Both modes preserve full colour and resolution.

Remote update rate depends on the Mac's screen capture and encoding, network
transfer, and phone decoding. A 120 Hz phone display or local pointer does not
make the Mac send 120 screen updates per second. The standard VNC path does not
promise sustained 60 or 120 fps, especially at full Retina resolution.

The Xcode console reports **updates/s**, throughput, encoding, average
**read**, **decode** (plus maximum), and **wait** times. Read includes socket
transfer and message parsing; decode measures raw/ZRLE/zlib/CopyRect processing
(Hextile parses directly while reading). Wait runs from an update request to
the next update header, including time when the Mac's screen has not changed;
it is not a pure network round-trip or host-CPU measurement.

The client requests the next update as soon as the previous update's final
payload is received, before decompressing it. Pointer movement is coalesced at
60 Hz to avoid replaying stale drag positions, while button and keyboard events
retain their order and the local pointer follows the phone's display rate.

---

## 🧪 Testing

```bash
xcodegen generate
xcodebuild -project "Pocket Mac.xcodeproj" -scheme "Pocket Mac" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

MIT License — see [LICENSE](LICENSE).

---

<p align="center">
Made by <strong>Zaki Sheriff</strong>
</p>

<p align="center">
<em>Because your Mac should fit in your pocket.</em>
</p>
