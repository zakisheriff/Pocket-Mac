/// One place for everything search engines, social cards and AI assistants
/// read about Pocket Mac, so the page, the metadata and llms.txt never drift.
export const site = {
  url: "https://pocketmac.theatom.lk",
  name: "Pocket Mac",
  title: "Pocket Mac — Control your Mac from your iPhone",
  tagline: "Your Mac, in your pocket.",
  description:
    "Pocket Mac turns your iPhone into a remote for your real Mac. See your Mac's screen live, move the pointer with a trackpad or tap like a touchscreen, and type on a full Mac keyboard — over macOS Screen Sharing. Free and open source.",
  keywords: [
    "Pocket Mac",
    "control Mac from iPhone",
    "remote desktop for Mac",
    "iPhone Mac remote",
    "Mac screen sharing iPhone",
    "VNC client iPhone",
    "use Mac on iPhone",
    "iPhone trackpad for Mac",
    "macOS Screen Sharing app",
    "remote control Mac",
    "The Atom",
  ],
  downloadUrl: "https://github.com/zakisheriff/Pocket-Mac",
  sourceUrl: "https://github.com/zakisheriff/Pocket-Mac",
  author: { name: "Zaki Sheriff", url: "https://github.com/zakisheriff" },
  publisher: { name: "The Atom", url: "https://theatom.lk" },
  locale: "en_US",
  themeColor: "#f5f5f7",
  ogImage: { url: "/og.png", width: 1200, height: 630, alt: "Pocket Mac showing a Mac's screen on an iPhone 17 Pro" },
  video: {
    url: "/demo.mp4",
    thumbnail: "/demo-poster.jpg",
    duration: "PT33S",
    uploadDate: "2026-10-26",
    name: "Pocket Mac demo: controlling a Mac from an iPhone 17 Pro",
    description:
      "Pocket Mac connects to a MacBook Pro, shows its desktop on an iPhone 17 Pro, uses the trackpad to open Safari from the Dock and loads theatom.lk with the on-screen Mac keyboard.",
  },
  features: [
    "Live view of your Mac's screen on your iPhone",
    "Trackpad mode: slide to move the pointer, tap to click, two-finger scroll",
    "Touch mode: tap, drag and scroll directly on the Mac's screen",
    "Full Mac keyboard with Command, Option, Control, Shift and arrow keys",
    "Pinch to zoom into any part of the Mac's screen",
    "Finds Macs on your Wi-Fi automatically with Bonjour",
    "Logs in with your Mac account; passwords are kept in the iPhone Keychain",
    "iPhone Duo layout: Mac screen on top, keyboard and trackpad below",
  ],
  faq: [
    {
      q: "What is Pocket Mac?",
      a: "Pocket Mac is a free, open-source iPhone app that lets you see and control your real Mac from your iPhone. It shows your Mac's screen live and gives you a trackpad, touch control and a full Mac keyboard.",
    },
    {
      q: "How does Pocket Mac connect to my Mac?",
      a: "It uses macOS Screen Sharing (the VNC/RFB protocol built into every Mac). Turn on Screen Sharing in System Settings › General › Sharing, keep your iPhone and Mac on the same Wi-Fi, and Pocket Mac finds the Mac automatically.",
    },
    {
      q: "Do I need to install anything on my Mac?",
      a: "No. Pocket Mac works with the Screen Sharing feature that is already part of macOS. You only switch it on and log in with your Mac username and password.",
    },
    {
      q: "Is Pocket Mac free?",
      a: "Yes. Pocket Mac is free and open source under the MIT licence. The source code is on GitHub.",
    },
    {
      q: "Can I use my iPhone as a trackpad and keyboard for my Mac?",
      a: "Yes. In Trackpad mode you slide one finger to move the pointer, tap to click and slide two fingers to scroll. Touch mode lets you tap directly on what you see. A full Mac keyboard slides up for typing and shortcuts like Command-C.",
    },
    {
      q: "Which iPhones does Pocket Mac support?",
      a: "Pocket Mac is built for iPhones running iOS 26, including the iPhone 17, iPhone 17 Pro and iPhone 17 Pro Max.",
    },
    {
      q: "Is my Mac password safe?",
      a: "Your password is sent to your Mac using Apple's own Screen Sharing login and, if you choose to remember it, is stored only in your iPhone's Keychain on that device.",
    },
  ],
} as const;

export const absolute = (path: string) => new URL(path, site.url).toString();
