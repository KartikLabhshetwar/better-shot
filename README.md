# BetterShot

[![macOS](https://img.shields.io/badge/macOS-26.0+-black.svg)](https://github.com/KartikLabhshetwar/better-shot)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)
[![X (Twitter)](https://img.shields.io/badge/X-%231DA1F2.svg?style=flat&logo=X&logoColor=white)](https://x.com/code_kartik)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-%23FFDD00.svg?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/code_kartik)

**One app for the whole screen.** Screenshots, screen recording, and a video
editor, native on macOS. An open-source alternative to CleanShot X and Loom
with no subscription, no account, and no telemetry. Nothing leaves your Mac
unless you share it, and shares go to storage you own.

## Features

- **Screenshots:** region, fullscreen, and window capture with macOS's native selector. OCR text extraction and hex color picker included.
- **Screenshot saving:** Copy is clipboard-only for every capture mode and in the editor. Screenshots stay in private working storage until you choose Save or Export; editor Save also works before making edits.
- **Screen recording:** capture a display, window, or adjustable region with system audio, microphone, camera overlay, and teleprompter.
- **Image editor:** arrows, shapes, text, numbered markers, highlight, blur, pixelate, and crop. Background framing with padding, corners, shadow, wallpapers, and ten soft gradients.
- **Video editor:** cuts, clip speeds (0.25x to 8x), transitions, crop, zoom, masks (blur/pixelate with Crop Only or Full Frame), captions, and camera controls. Camera layout presets include Camera Bubble, Overlap, Side-by-Side, Presenter, Camera Only, and Screen Only, with left/right positioning for paired layouts. Layouts apply to the whole video and are saved with the project. Camera Bubble and Overlap start at the compact 0.5.2 size (1:1, 26%); selecting either preset restores that size. Floating cameras offer 1:1, 4:3, 3:4, 16:9, 9:16, and 4:5 frames; set 1:1 with 50% rounding for a circle. Background > Video aspect ratio controls the whole video independently, with Original, 16:9, 16:10, 4:3, 9:16, 1:1, and 4:5 plus Fill/Fit.
- **Cursor styles:** Recorded, macOS (Apple's native arrow), Dark, Light, and Dot. Older projects using Hand keep their saved appearance.
- **Cursor styling:** choose Recorded, Dark, Light, Dot, or native Hand with size, motion, press/ripple effects, and idle hiding. High-resolution artwork preserved in exports.
- **Capture deck:** keep up to five captures in a floating stack with Copy, Save, Pin, Edit, cloud share, and drag-out. Configurable layouts, tool positions, and dismissal timing.
- **Media Gallery:** browse captures, edits, and recordings with search, filters, and cloud link management. Delete locally (Trash) or remotely (R2) with confirmation.
- **Video export:** GPU compositing and hardware encoding, with 30/60 fps, resolution, quality, and MP4/MOV controls. Export and sharing reuse unchanged saved renders.
- **Cloud sharing:** upload to your own Cloudflare R2 bucket. Optimized image compression, MP4 video, native progress, and retry on failure.
- **75 customizable shortcuts:** configure global capture, recording controls, deck actions, image tools, and video editing keys. Conflict detection per scope.
- **URL scheme:** trigger actions from Raycast, Shortcuts, Alfred, or scripts: `bettershot://capture/region`, `bettershot://record`, `bettershot://ocr`, and more.

Both editors use a left inspector with compact controls and frosted chrome. Action
icons use Apple SF Symbols. Full-resolution previews are the default, and original
source files remain editable.

## Install

```bash
brew install --cask bettershot
```

Or grab the `.dmg` from [Releases](https://github.com/KartikLabhshetwar/better-shot/releases).
Drag **BetterShot** into **Applications** and launch it. A three-step introduction
(Welcome, Permissions, First Capture) walks you through setup on first run.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Capture and recording bar | `⌘⇧2` |
| Recording options | `⌘⇧5` |
| OCR text scan | `⌘⇧O` |
| Color picker | `⌘⇧C` |

All shortcuts are customizable in Settings > Shortcuts. Additional actions (area
recording, deck controls, editor tools) start unassigned and can be bound from
the same page.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

Requires macOS 26.0+, Xcode 26+, and XcodeGen. Pure Swift and SwiftUI with a
single dependency ([DockProgress](https://github.com/nicklama/DockProgress)).
No Electron, no web views.

Run `make test` to verify with unsigned builds, regression checks, editor
snapshots, and export integration tests.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the build
workflow, project layout, and submission process. Read [AGENTS.md](AGENTS.md)
for the required UI and interaction rules.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
