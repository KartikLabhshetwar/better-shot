# Better Shot

[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=for-the-badge&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

> An open-source alternative to CleanShot X. Native Swift app — fast, lightweight, local-first.

## Features

**Capture** — Region (`⌘⇧4`), fullscreen (`⌘⇧3`), window (`⌘⇧5`), repeat last region (`⌃⌘⇧4`). Multi-monitor support.

**Tools** — OCR text + QR code extraction (`⌘⇧O`), color picker with hex copy (`⌘⇧C`), delayed capture with countdown overlay.

**Edit** — Background library (wallpapers, gradients, solid colors), shadow, corner radius, padding, aspect ratio (16:9, 4:3, 1:1, 9:16), 9-point alignment grid. Save settings as default.

**Annotate** — Rectangle, filled rectangle, ellipse, line, arrow (curved), freehand, text, numbered badges, pixelate, blur, spotlight. Option+drag to duplicate. Full keyboard shortcuts.

**Workflow** — Auto-apply default background, floating preview overlay with pin/annotate/copy actions, pinned always-on-top screenshots, toast notifications on export/copy, menu bar app.

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
make build    # Debug build
make run      # Build and launch
```

Or open `BetterShot.xcodeproj` in Xcode and **Product > Build** (`⌘B`).

| Command | Description |
|---|---|
| `make build` | Debug build |
| `make release` | Release build (unsigned) |
| `make run` | Build and launch |
| `make dmg` | Create unsigned DMG for local testing |
| `make clean` | Remove build artifacts |
| `make lint` | Check for compiler warnings |
| `make test-build` | Full clean + release build |
| `make version` | Print current version |

**Requirements**: macOS 14.0+, Xcode 15+

### Required permissions

BetterShot needs two macOS permissions:

1. **Screen Recording** — System Settings > Privacy & Security > Screen Recording > enable BetterShot
2. **Accessibility** — System Settings > Privacy & Security > Accessibility > enable BetterShot

Screen Recording is required for ScreenCaptureKit to capture screen content. Accessibility is required for keyboard shortcuts to override the default macOS screenshot tool.

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
| Repeat Last Region | `⌃⌘⇧4` |
| OCR + QR Scan | `⌘⇧O` |
| Pick Color | `⌘⇧C` |

| Editor Tool | Key |
|---|---|
| Select | `V` |
| Rectangle | `R` |
| Filled Rectangle | `F` |
| Ellipse | `O` |
| Line | `L` |
| Arrow | `A` |
| Freehand | `D` |
| Numbered Circle | `N` |
| Pixelate | `P` |
| Blur | `B` |
| Spotlight | `G` |
| Text | `T` |

| Editor Action | Shortcut |
|---|---|
| Save/Export | `⌘S` |
| Copy to Clipboard | `⇧⌘C` |
| Undo | `⌘Z` |
| Redo | `⇧⌘Z` |
| Delete Annotation | `Delete` |
| Select All | `⌘A` |
| Close Editor | `Esc` |

## Architecture

Native Swift/SwiftUI app. No Electron, no web views.

- **ScreenCaptureKit** — all screenshot capture (`SCScreenshotManager`)
- **CoreGraphics** — image compositing, annotation rendering, beautifier pipeline
- **CoreImage** — Gaussian blur with edge-padding for redaction
- **Vision** — OCR text extraction + QR/barcode detection
- **AppKit** — `NSColorSampler` for color picking, `NSPanel` for floating previews and pins
- **Carbon** — global keyboard shortcut registration via CGEvent tap

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
