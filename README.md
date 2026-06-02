# Better Shot

<img width="3600" height="2025" alt="stage-1768238789948" src="https://github.com/user-attachments/assets/3051266a-5179-440f-a747-7980abd7bac3" />

[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/zThjstVs) 
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=for-the-badge&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

> An open-source alternative to CleanShot X. Native Swift app — fast, lightweight, local-first.

## Features

**Capture** — Region (`⌘⇧4`), fullscreen (`⌘⇧3`), window (`⌘⇧5`), OCR text extraction (`⌘⇧O`), screen recording (`⌘⇧6`).

**Edit** — Background library (wallpapers, gradients, solid colors), shadow, corner radius, padding, alignment.

**Annotate** — Rectangle, ellipse, line, arrow, freehand, text, numbered badges, pixelate, blur.

**Workflow** — Auto-apply default background, floating preview overlay, copy to clipboard, menu bar app.

## Install

### Download

1. Go to [Releases](https://github.com/KartikLabhshetwar/better-shot/releases)
2. Download `BetterShot.dmg`
3. Open the DMG, drag BetterShot to Applications
4. Launch and grant permissions when prompted (see below)

### Build from source

```bash
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
```

Open `BetterShot.xcodeproj` in Xcode, then **Product → Build** (`⌘B`).

**Requirements**: macOS 14.0+, Xcode 15+

### Required permissions

BetterShot needs two macOS permissions:

1. **Screen Recording** — System Settings → Privacy & Security → Screen Recording → enable BetterShot
2. **Accessibility** — System Settings → Privacy & Security → Accessibility → enable BetterShot

Screen Recording is required for ScreenCaptureKit to capture screen content. Accessibility is required for keyboard shortcuts to override the default macOS screenshot tool (`⌘⇧3/4/5`).

## Usage

1. Launch BetterShot — it appears in your menu bar
2. Use a keyboard shortcut or click a menu bar action
3. Edit the screenshot (background, shadow, annotations)
4. `⌘S` to save, `⇧⌘C` to copy to clipboard

### Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Capture Region | `⌘⇧4` |
| Capture Fullscreen | `⌘⇧3` |
| Capture Window | `⌘⇧5` |
| OCR Region | `⌘⇧O` |
| Screen Recording | `⌘⇧6` |
| Cancel | `Esc` |

| Editor | Shortcut |
|---|---|
| Save | `⌘S` |
| Copy to Clipboard | `⇧⌘C` |
| Undo | `⌘Z` |
| Redo | `⇧⌘Z` |
| Delete Annotation | `Delete` |
| Close Editor | `Esc` |

## Architecture

Native Swift/SwiftUI app. No Electron, no web views.

- **ScreenCaptureKit** — all screenshot and recording capture (`SCScreenshotManager`, `SCStream`)
- **CoreGraphics** — image compositing, annotation rendering
- **Vision** — OCR text extraction
- **AVFoundation** — screen recording export (HEVC)
- **Carbon** — global keyboard shortcut registration

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

BSD 3-Clause — see [LICENSE](LICENSE).

## Star history

<a href="https://www.star-history.com/#KartikLabhshetwar/better-shot&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
 </picture>
</a>
