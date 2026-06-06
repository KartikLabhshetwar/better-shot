# BetterShot

[![Version](https://img.shields.io/badge/version-0.3.3-blue.svg)](https://github.com/KartikLabhshetwar/better-shot/releases)
[![macOS](https://img.shields.io/badge/macOS-14.0+-black.svg)](https://github.com/KartikLabhshetwar/better-shot)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=flat&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

An open-source alternative to CleanShot X. Native Swift app for macOS — fast, lightweight, local-first. No subscriptions, no cloud, no telemetry.

## What it does

### Capture

| Action | Shortcut |
|---|---|
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Window screenshot | `⌘⇧5` |
| Repeat last region | `⌃⌘⇧4` |
| OCR text + QR scan | `⌘⇧O` |
| Color picker (hex) | `⌘⇧C` |

All shortcuts are customizable in Settings > Capture.

### Edit

- **Backgrounds** — Solid colors, gradients, bundled wallpapers, or your own image
- **Effects** — Padding, corner radius, shadow strength
- **Layout** — Aspect ratio (Auto, 1:1, 4:3, 3:2, 16:9, 9:16), 9-point alignment grid
- **Save as default** — Set your preferred effects and background once, applied to every new capture

### Annotate

Rectangles, filled rectangles, ellipses, lines, curved arrows, freehand, text, numbered badges, pixelate, blur, and spotlight. Each has a single-key shortcut in the editor (`R`, `F`, `O`, `L`, `A`, `D`, `T`, `N`, `P`, `B`, `G`).

### Workflow

- **Click-to-edit** — Click the floating preview to open the editor (like CleanShot X)
- **Pin screenshots** — Pin any capture as an always-on-top floating window
- **Auto-apply** — Automatically apply your default background on every capture
- **Self-timer** — Countdown overlay before capture (3s, 5s, 10s)
- **In-app updates** — Check, download, and install updates without leaving the app

## Install

### Download

1. Go to [Releases](https://github.com/KartikLabhshetwar/better-shot/releases)
2. Download `BetterShot-0.3.3.dmg`
3. Open the DMG, drag BetterShot to Applications
4. Launch and grant permissions when prompted

### Build from source

```bash
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make run
```

This builds a debug version and launches it. See [all make commands](#make-commands) below.

### Permissions

BetterShot needs two macOS permissions on first launch:

1. **Screen Recording** — System Settings > Privacy & Security > Screen Recording
2. **Accessibility** — System Settings > Privacy & Security > Accessibility

Screen Recording lets the app capture your screen. Accessibility lets it override the default macOS screenshot shortcuts with its own.

## Usage

1. Launch BetterShot — it appears in your **menu bar** (top right of screen)
2. Use a keyboard shortcut or click a capture action from the menu
3. The floating preview appears — **click it to open the editor**
4. Adjust background, effects, and add annotations
5. `⌘S` to save, `⇧⌘C` to copy to clipboard

### Editor shortcuts

| Action | Key |
|---|---|
| Select tool | `V` |
| Rectangle | `R` |
| Filled rectangle | `F` |
| Ellipse | `O` |
| Line | `L` |
| Arrow | `A` |
| Freehand | `D` |
| Text | `T` |
| Numbered circle | `N` |
| Pixelate | `P` |
| Blur | `B` |
| Spotlight | `G` |
| Save / Export | `⌘S` |
| Copy to clipboard | `⇧⌘C` |
| Undo / Redo | `⌘Z` / `⇧⌘Z` |
| Delete annotation | `Delete` |
| Select all | `⌘A` |
| Close editor | `Esc` |

### Settings

Open from the menu bar > **Settings** (or `⌘,`).

- **General** — Save location, clipboard behavior, default effects (padding, radius, shadow, background), export format
- **Capture** — Self-timer delay, keyboard shortcuts (click any shortcut to re-record it), overlay position and dismiss timing
- **History** — Browse and delete past captures
- **About** — Version info and in-app update checker

## Make commands

| Command | What it does |
|---|---|
| `make build` | Debug build |
| `make release` | Release build (unsigned) |
| `make run` | Build and launch |
| `make dmg` | Create DMG for local testing |
| `make clean` | Remove build artifacts |
| `make lint` | Check for compiler warnings |
| `make test-build` | Full clean + release build |
| `make version` | Print current version |

## Architecture

Native Swift 6 / SwiftUI. No Electron, no web views, no external dependencies.

| Framework | Used for |
|---|---|
| ScreenCaptureKit | All screenshot capture |
| CoreGraphics | Image compositing, annotation rendering, beautifier pipeline |
| CoreImage | Gaussian blur for redaction |
| Vision | OCR text extraction + QR/barcode detection |
| AppKit | Color sampling, floating panels, pinned windows |
| Carbon | Global keyboard shortcuts via CGEvent tap |

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, project structure, and coding guidelines.

## License

BSD 3-Clause. See [LICENSE](LICENSE).

## Star History

<a href="https://www.star-history.com/#KartikLabhshetwar/better-shot&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=KartikLabhshetwar/better-shot&type=date&legend=top-left" />
 </picture>
</a>
