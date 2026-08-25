# BetterShot

[![macOS](https://img.shields.io/badge/macOS-26.0+-black.svg)](https://github.com/KartikLabhshetwar/better-shot)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=flat&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

Screenshots, screen recording, and a video editor in one native macOS app. An
open-source alternative to CleanShot X and Loom, with no subscription, no
account, and no telemetry. Captures stay on your Mac unless you share them from
storage you own.

**[Download BetterShot for macOS](https://www.bettershot.site)**

## What it does

- **Capture** a region, the full screen, or a single window, plus OCR and an on-screen color picker
- **Record** any display, window, or region to MP4 with system audio, microphone, and a face cam bubble
- **Edit** recordings on a multi-clip timeline: cuts, per-clip speed, transitions, cursor-tracked auto-zoom, captions, a keyboard overlay, masks, and a 3D camera
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
| Window screenshot | `⌘⇧5` |
| Record screen | `⌘⇧2` |
| OCR text scan | `⌘⇧O` |
| Color picker (hex) | `⌘⇧C` |

All of these are re-bindable in Settings > Capture. In the editor, every tool
carries its own single-key shortcut on its button, and `⌘S` saves, `⇧⌘C` copies,
`⌘Z` undoes.

## Build from source

```bash
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make run
```

Needs macOS 26 and Xcode 26 (Swift 6). Native Swift and SwiftUI throughout: no
Electron, no web views, no third-party dependencies.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
project layout, how the capture and editor flows fit together, and the make
targets.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
