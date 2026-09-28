<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo-dark.png">
    <img src="design/logo.png" alt="Hoardly" width="420">
  </picture>
</p>

<p align="center">A fast, native download manager for macOS — works with Safari, Chrome, Helium, Arc, Brave, Edge and Firefox.</p>

## Features

- **Faster downloads** — each file is fetched over up to 32 connections, split IDM-style as connections free up.
- **Resume anything** — pause, lose Wi-Fi, quit, or crash: downloads continue where they stopped.
- **Every browser** — the extension hands matching downloads to Hoardly with the site's cookies, so logged-in downloads work. Hold ⌥ Option while clicking to let the browser keep one.
- **Video grabber** — spots videos on a page and saves HLS streams (including AES-128 encrypted and separate-audio streams) as a single `.mp4`. DRM-protected video is not supported, and the grabber is off on YouTube.
- **Organized** — files sort into Video, Music, Documents, Archives and Programs folders; queue, notifications, menu bar and Dock progress.
- **Private** — no accounts, no analytics. See [PRIVACY.md](PRIVACY.md).

Requires macOS 14 or later.

## Install

1. Download the latest `Hoardly-x.y.z.dmg` from [Releases](https://github.com/haonlabs/hoardly/releases) and drag Hoardly to Applications.
2. Open Hoardly — the welcome window walks you through the browser setup.

## Browser extension

| Browser | Get it |
|---|---|
| Safari | Included with the app: Safari → Settings → Extensions → Hoardly |
| Chrome, Helium, Arc, Brave, Vivaldi, Opera | Chrome Web Store *(listing coming soon)* |
| Microsoft Edge | Edge Add-ons *(coming soon)* |
| Firefox | Firefox Add-ons *(coming soon)* |

Until the store listings are live, load it by hand: open `chrome://extensions` (or `helium://extensions`, `edge://extensions`), turn on **Developer mode**, choose **Load unpacked** and pick the [`extension`](extension) folder. In Firefox use `about:debugging` → **Load Temporary Add-on**.

The first time the extension reaches Hoardly, Hoardly asks you to **Connect** it.

## Building

Open `Hoardly.xcodeproj` in Xcode 26 or later and run the **Hoardly** scheme. Sparkle is fetched by Swift Package Manager.

Checks:

```sh
xcodebuild -project Hoardly.xcodeproj -scheme Hoardly test   # unit tests
node scripts/test-rules.js                                    # extension matching rules
scripts/e2e-resume.sh 1024                                    # kill -9 mid-download, resume, compare SHA-256
scripts/e2e-hls.sh                                            # HLS → .mp4 (TS, AES-128, fMP4 + audio), DRM/live refused
node scripts/e2e-extension.mjs                                # extension in a throwaway Helium profile
scripts/bench.sh URL                                          # Hoardly vs curl
```

Releasing: see the header of [`scripts/release.sh`](scripts/release.sh). Icons are drawn by `swift scripts/make-icons.swift`.

## License

[MIT](LICENSE) © 2026 Haon Labs
