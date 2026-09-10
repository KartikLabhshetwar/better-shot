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

This describes **0.5.2**, dated September 10, 2026 in the changelog.
Settings buttons adapt to light and dark appearances, with hover feedback and red destructive actions.
See [CHANGELOG.md](CHANGELOG.md) for changes and release history.

- **Capture** regions with macOS's native selector, full screens, and windows; extract text with OCR or pick a color.
- **Record** a display, window, or adjustable region with optional system audio, microphone, camera, and teleprompter.
- **Edit images** with arrows, shapes, text, numbered markers, highlight, Blur, Pixelate, and crop. Clicking an active tool again returns to Select.
- **Edit videos** with cuts, custom clip speeds from 0.25× to 8× (including 1.25×), transitions, crop, zoom, masks, captions, and camera controls. Blur and Pixelate offer Crop Only or Full Frame coverage.
- **Style cursors** in BetterShot recordings: Recorded, Dark, Light, Dot, or the native macOS Hand; size, visibility, Natural/Smooth motion, press/ripple effects, and idle hiding. High-resolution artwork preserves the click point in previews and exports.
- **Frame captures** with padding, corners, shadow, wallpapers, and ten shared soft gradients. Configure the shared image and video look in General settings.
- **Keep a capture deck** of up to five items, with optional save-on-demand, Copy, Pin, Edit, cloud sharing, and drag-out actions. The Standard layout puts Pin at the top left and cloud sharing at the bottom right. Sharing shows processing/upload progress, copies the finished link, and keeps Copy Link/Open actions in the deck. Links are also saved in Media Gallery. Open Settings → Overlay for Standard, Sharing, and Minimal presets, a visual editor for all six tool positions, and advanced margin, dismissal (including Never), and action visibility controls. Click a position to move or hide a tool; tools swap without duplication and Dismiss stays available. Changes apply immediately.
- **Browse media** directly from the clover menu → Media Gallery, or Settings → General → Open Media Gallery. Local shows retained captures, saved edits, and recording projects; Cloud shows links saved by this Mac. Use the sidebar, search, and date sorting to find captures. Preview, edit, reveal files, or open/copy a cloud link from each card. Move local captures and their edits to Trash, or delete a cloud share separately, with confirmation. Unsaved deck captures appear after saving; Cloud does not scan your R2 bucket or sync other devices.
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
Open the disk image, drag **BetterShot** onto **Applications**, then open BetterShot
from Applications. You can eject the disk image after copying finishes.

The introduction walks through **Welcome → Permissions → First Capture**.
Switch between screenshot and recording examples, with optional six-second demos,
then enable screen access and open the capture bar or try a practice image.
Setup starts only for a fresh user profile; updates and existing users skip it.
Skip or close it anytime, with no reopening entry in the menu tray or Settings. Contextual tips teach editing tools when you use them.

The Permissions step shows all five permissions in one list, with screen access
first. Each has a clear purpose, an Allow or Open Settings action, and live macOS
status. Nothing is hidden behind a disclosure:

- **Screen & System Audio Recording:** needed for screenshots and screen recording.
- **Accessibility:** optional global capture shortcuts; the menu bar works without it.
- **Input Monitoring:** precise pointer motion and optional shortcut/special-key overlays. Plain typing is never recorded.
- **Microphone / Camera:** optional narration and face camera. Permission does not switch either input on.

Denied access has a direct System Settings link and retry instructions. If macOS
requires a restart during setup, save your work and reopen BetterShot to return
to Permissions. Capture paths still check permissions when needed. The final step
offers a practice image that opens a separate full-resolution copy in the image
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
Search or filter the action list to configure global capture/recording controls, the
capture deck, image tools, and video editing. Additional actions start unassigned;
existing capture and editor keys stay in place. Each action can be recorded, disabled,
cleared, or reset. Conflicting bindings within the same context are rejected.
Editor shortcuts take priority in their editor, while text fields keep native typing,
copy/paste, and undo.

General also includes **Launch at Login**, **Show in Dock**, and **Show in Menu Bar**.
BetterShot stays reachable: hiding the Dock icon keeps its clover in the menu bar.
Launch at Login reflects macOS registration and provides a System Settings link if
approval is needed. It is off until you enable it.

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

Export and sharing progress appears in a separate toast at the top of the
editor’s display, with completion and retry actions outside the editing canvas.

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
