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

This describes the current **0.5.0 development version**, which is not released
yet. See [CHANGELOG.md](CHANGELOG.md) for pending changes and release history.

- **Capture** regions with macOS's native selector, full screens, and windows; extract text with OCR or pick a color.
- **Record** a display, window, or adjustable region with optional system audio, microphone, camera, and teleprompter.
- **Edit images** with arrows, shapes, text, numbered markers, highlight, Blur, Pixelate, and crop. Clicking an active tool again returns to Select.
- **Edit videos** with cuts, custom clip speeds from 0.25× to 8× (including 1.25×), transitions, crop, zoom, masks, captions, and camera controls. Blur and Pixelate offer Crop Only or Full Frame coverage.
- **Style cursors** in BetterShot recordings: Recorded, Dark, Light, Dot, or the native macOS Hand; size, visibility, Natural/Smooth motion, press/ripple effects, and idle hiding. High-resolution artwork preserves the click point in previews and exports.
- **Frame captures** with padding, corners, shadow, wallpapers, and ten shared soft gradients. Configure the shared image and video look in General settings.
- **Keep a capture deck** of up to five items, with optional save-on-demand, Copy, Pin, Edit, and drag-out actions.
- **Share** through your own Cloudflare R2 bucket. Image sharing optimizes size; shared videos use MP4. Native progress cards show completion or retry actions.

Both editors use a left inspector, compact controls, and classic frosted chrome.
Editor scrollbars stay hidden while scrolling remains available. Image color palettes
show every preset and a custom color control without horizontal scrolling.
Settings and both editors share the 0.4.0 scrubber: a label inside the track
and an exact editable value on the right, without duplicate labels.
Action icons use Apple SF Symbols; BetterShot retains its own clover app and menu-tray
identity. Full-resolution screenshot previews are the default, and original source
files remain available for editable projects.

## Install

```bash
brew install --cask bettershot
```

Or download the latest `.dmg` from [Releases](https://github.com/KartikLabhshetwar/better-shot/releases).

The 0.5.0 introduction walks through **Screenshots → Video → Permissions → Ready**.
Learn image annotations, redaction, and backgrounds; video capture, editing, and
cursor effects; then set up access before your first capture. The expanded guide
appears for new and existing users, including people who saw the earlier brief
introduction. Skip or close it anytime; reopen **Getting Started** in the clover
menu or Settings > About.

The Permissions step includes individual requests and live macOS status:

- **Screen & System Audio Recording:** needed for screenshots and screen recording.
- **Accessibility:** optional global capture shortcuts; the menu bar works without it.
- **Input Monitoring:** precise pointer motion and optional shortcut/special-key overlays. Plain typing is never recorded.
- **Microphone / Camera:** optional narration and face camera. Permission does not switch either input on.

Denied access has a direct System Settings link and retry instructions. If macOS
requires a restart during setup, save your work and reopen BetterShot to return
to Permissions. Capture paths still check permissions when needed. The final step
offers two practice photos that use separate full-resolution copies in the image
editor, without screen access or changes to your captures.

## Shortcuts

| Action | Shortcut |
|---|---|
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Capture & recording bar | `⌘⇧2` |
| Recording options | `⌘⇧5` |
| OCR text scan | `⌘⇧O` |
| Color picker (hex) | `⌘⇧C` |

After the introduction has been dismissed, the shared bar appears at launch. `⌘⇧2` reopens it; `⌘⇧5` opens its Recording
section. `⌘⇧4` starts native screenshot selection directly. Customize these
bindings in Settings > Shortcuts.

In the image editor, `⌘S` saves the editable image, `⇧⌘C` copies, and `⌘Z` undoes.
Scissors in the video timeline starts off. Click it or press `S` to enable
repeated cuts; click again or press `S` to deselect. Cut badges below the filmstrip
show removed durations where applicable; hover to preview the original footage.

## Editor defaults

**Images and videos:** Settings > General > Default Look controls background,
padding, corner radius, and shadow for new edits. The tray's Record button opens
Recording options, matching `⌘⇧5` (or your customized shortcut).

Choose Blush, Peach, Mint, Powder Blue, Butter, Lilac, Sage, Coral, Aqua, and
Mauve gradients, along with colors and wallpapers. Existing project settings stay
with their projects. Video cursor restyling requires a BetterShot recording with
separate cursor data; it cannot replace a cursor already baked into imported footage.

Local exports reuse unchanged video frame work and repeated full-resolution PNG
renders. Effects and 60 fps video are preserved. See the
[local export measurements](docs/export-performance.md) for workloads and limits.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

Needs macOS 26.0+, Xcode 26+, and XcodeGen. Native Swift and SwiftUI throughout: no
Electron, no web views, and a single Swift package (DockProgress).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
project layout, how the capture and editor flows fit together, and the make
targets. Read [AGENTS.md](AGENTS.md) for the required UI patterns;
[CLAUDE.md](CLAUDE.md) imports the same rules for Claude Code.

Run `make test` for the unsigned build, regression checks, editor snapshots, and
export integration tests. See the contributor guide for signing and live UI checks.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
