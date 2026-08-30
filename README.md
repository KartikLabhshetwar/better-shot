# BetterShot

[![macOS](https://img.shields.io/badge/macOS-26.0+-black.svg)](https://github.com/KartikLabhshetwar/better-shot)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=flat&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

**One app for the whole screen.** Screenshots, screen recording, and a video
editor, native on macOS. An open-source alternative to CleanShot X and Loom:
no subscription, no account, no telemetry. Nothing leaves your Mac unless you
share it, and shares go to storage you own.

## What it does

- **Capture** a region, the full screen, or a single window, plus OCR and an on-screen color picker
- **Record** any display, window, or region to MP4 with system audio, microphone, and a face cam bubble
- **Edit** recordings on a multi-clip timeline: cuts, per-clip speed, transitions, crop, cursor-tracked auto-zoom, a restylable cursor, on-device captions, a keyboard overlay, masks, color grading, and a 3D camera
- **Annotate** screenshots with arrows, shapes, text, numbered badges, blur, and spotlight
- **Beautify** with backgrounds, padding, corner radius, and shadow, applied automatically if you want
- **Share** a link from your own Cloudflare R2 bucket; every upload is compressed first and video always ships as MP4

## Install

```bash
brew install --cask bettershot
```

Or download the latest `.dmg` from [Releases](https://github.com/KartikLabhshetwar/better-shot/releases).

On first launch, grant two permissions in System Settings > Privacy & Security:
**Screen Recording** to capture, and **Accessibility** to take over the default
screenshot shortcuts.

## Shortcuts

| Action | Shortcut |
|---|---|
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Record screen | `⌘⇧2` |
| OCR text scan | `⌘⇧O` |
| Color picker (hex) | `⌘⇧C` |

`⌘⇧2` opens the all-in-one bar: region, window, screen, OCR, color picker and
recording all live on it. Your last region appears as a dashed ghost as soon as
the bar opens; press `A` to capture it again. During region capture the ghost
stays: `Return`, `A`, or a click inside it captures it, `Space` switches to
window selection. All of these are re-bindable in
Settings > Shortcuts. In the editor, every tool carries its
own single-key shortcut on its button, and `⌘S` saves, `⇧⌘C` copies, `⌘Z` undoes.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

Needs macOS 26, Xcode 26 (Swift 6), and XcodeGen. Native Swift and SwiftUI throughout: no
Electron, no web views, and a single Swift package (DockProgress).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
project layout, how the capture and editor flows fit together, and the make
targets.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
