<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" height="96" alt="BetterShot clover icon">
</p>

<h1 align="center">BetterShot</h1>

<p align="center">
  <strong>Capture, edit, and share your screen. Native on macOS.</strong>
</p>

<p align="center">
  <a href="https://formulae.brew.sh/cask/bettershot"><img src="https://img.shields.io/badge/macOS-26.0+-black.svg" alt="macOS 26 or later"></a>
  <a href="https://github.com/KartikLabhshetwar/better-shot/actions/workflows/build.yml"><img src="https://github.com/KartikLabhshetwar/better-shot/actions/workflows/build.yml/badge.svg" alt="Build status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD%203--Clause-green.svg" alt="BSD 3-Clause license"></a>
</p>

<p align="center">
  <a href="https://github.com/KartikLabhshetwar/better-shot/releases/latest">Download</a> ·
  <a href="https://bettershot.site">Website</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> ·
  <a href="https://github.com/KartikLabhshetwar/better-shot/issues">Report a bug</a>
</p>

BetterShot is an open-source Mac app for screenshots, screen recordings, and
image and video editing. No account or subscription required.

![BetterShot image editor with editable annotations and background controls](bettershot-landing/public/features/screenshot-editor-dark.webp)

## Install

Requires macOS 26 or later.

```bash
brew install --cask bettershot
```

Or download the Apple silicon or Intel `.dmg` from
[Releases](https://github.com/KartikLabhshetwar/better-shot/releases/latest),
drag BetterShot into Applications, and open it. A short tour walks you through
permissions and your first capture.

## Features

**Screenshots**
- Region, window, and fullscreen capture. Extract text with OCR or pick a color as hex.
- Annotate with arrows, shapes, text, numbered markers, highlights, blur, and pixelate.
- Crop, rotate, and flip without losing editable annotations.
- Frame captures on a wallpaper or soft gradient with padding, rounded corners, and shadow.
- Save as PNG, JPEG, or WebP.

**Recordings**
- Record a display, window, or adjustable area with optional system audio, microphone, camera, and teleprompter.
- Pause, restart, or discard from the compact recording bar.

**Video editor**
- Cut clips, change speed from 0.25x to 8x, and add zooms, transitions, captions, and blur or pixelate masks.
- Arrange screen and camera as Camera Bubble, Overlap, Side-by-Side, Presenter, Camera Only, or Screen Only.
- Restyle the cursor (Recorded, Arrow, Dark, Light, Dot) with size, smoothing, click effects, and idle hiding.
- Add 3D shots: eight camera moves, five drifting angles, Auto Scene, depth blur, and keyframed Bézier curves.
- Export MP4 or MOV at 30 or 60 fps.

**Everything else**
- Copy, save, pin, edit, share, or drag captures from the floating preview.
- Browse screenshots, recordings, and share links in the Media Gallery.
- Share to your own Cloudflare R2 bucket with one click.
- Optional [Notch Mode](#notch-mode) keeps previews and a capture shelf at the top of the screen.

Original captures and source movies are never modified. Both editors support
undo, redo, and native full screen.

<details>
<summary>See the video editor</summary>

![BetterShot video editor with zoom controls, a clip timeline, and cut markers](bettershot-landing/public/features/video-editor-dark.webp)

</details>

## Getting started

1. Open BetterShot and allow screen capture. Enable Accessibility for global shortcuts.
2. Press `⌘⇧4` to capture a region, or `⌘⇧2` to open the capture and recording bar.
3. Use the floating preview to Copy, Save, Pin, or Edit.

| Action | Shortcut |
| --- | --- |
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Capture and recording bar | `⌘⇧2` |
| Recording options | `⌘⇧5` |
| OCR text scan | `⌘⇧O` |
| Color picker | `⌘⇧C` |

Change or add bindings in **Settings > Shortcuts**. Extra actions, such as
Capture Region & Pin or Edit Clipboard Image, start unassigned.

Set the background, padding, corner radius, and shadow for new captures in
**Settings > General > Default Look**.

### Scrolling capture

Capture a page or list that is taller or wider than the screen. Choose
**Scrolling Capture** in the menu bar popover or **Scroll** in the capture bar
(`⌘⇧2`), or assign a shortcut in **Settings > Shortcuts**. Drag over the
scrollable content, then scroll through it as usual in one direction: down, or
horizontally. The floating panel counts the stitched frames and the image's
length. Click **Stop**, or trigger Scrolling Capture again, to send the image to
the capture preview. **Cancel** discards it.

Scroll at a steady pace so consecutive frames overlap. Fixed headers and
scrollbars are detected and left out of the joins. A capture finishes on its own at
30,000 pixels.

### Where files go

Captures stay in BetterShot's private storage until you save them.

- **Copy** puts the image on the clipboard. No file lands in your save folder.
- **Save** writes to your configured folder. In the editor, later saves update the same file.
- **Export** asks for a new destination.

Automatic saving is off by default. Turn it on in **Settings > General > Saving**,
where you can also set file name templates such as `standup-{date}-{counter:3}`.

### Permissions

| Permission | Used for |
| --- | --- |
| Screen & System Audio Recording | Screenshots, recordings, and system audio |
| Accessibility | Global shortcuts and Notch Mode hold-to-capture |
| Input Monitoring | Cursor effects and shortcut overlays. Plain typing is never recorded. |
| Microphone | Voice in recordings and voice notes |
| Camera | Camera recording |

Manage access in **System Settings > Privacy & Security**. If capture or
shortcuts still fail after granting access, quit and reopen BetterShot.

## Notch Mode

Turn it on in **Settings > General > Capture Mode**. Normal Mode stays the default.

- **Shelf.** Previews, recordings, OCR text, and picked colors appear in a black shelf at the top of the screen, filtered by All, Text, Images, Videos, or Colors.
- **Hold to capture.** Hold Control and drag to screenshot an area. Change the key or switch to Draw on screen in **Settings > Shortcuts > Notch Capture Gesture**.
- **Quick edit.** Click an image to draw, blur, crop, or add a background right below the notch.
- **Voice notes.** Tap the microphone in the quick editor to talk while you annotate. Transcription runs on your Mac with no cloud fallback.
- **History.** Copied hex colors are kept by default. Copied text is opt-in under **Settings > General > Notch Shelf**, capped at 50 entries, and skips content that apps mark as private.

Recording controls always stay in the floating bar. On Macs without a notch,
the shelf appears as a floating panel at the top center of the screen.

## Cloud sharing

Sharing is optional and uses a Cloudflare R2 bucket you own.

1. Create an R2 bucket with a public URL and an
   [API token](https://developers.cloudflare.com/r2/api/tokens/) with
   Object Read & Write access to that bucket.
2. Enter your credentials in **Settings > Sharing** and click **Test Connection**.
3. Click **Share** on any capture to upload it and copy the link.

Credentials are stored in your login Keychain. Links open a viewer on
`bettershot.site` by default. Turn on **Copy direct file links** to get the raw
file URL instead. Anyone with a link can view it. Outside of sharing, BetterShot
only goes online to check GitHub for updates.

## Automation

Trigger captures from Shortcuts, Raycast, Alfred, or the terminal:

```bash
open 'bettershot://capture/region'
```

Routes: `capture/region`, `capture/fullscreen`, `capture/window`,
`capture/scroll`, `ocr`, `color-picker`, `record`, `settings`.

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

`make release` builds unsigned, so no signing identity is needed. See
[CONTRIBUTING.md](CONTRIBUTING.md) for Xcode setup, the code map, and tests.

## Contributing

Bug reports, fixes, docs, and accessibility feedback are all welcome. When
[opening an issue](https://github.com/KartikLabhshetwar/better-shot/issues),
include your macOS and BetterShot versions and steps to reproduce. Read the
[contributor guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md)
before opening a pull request.

Built by [Kartik Labhshetwar](https://x.com/code_kartik) and
[contributors](https://github.com/KartikLabhshetwar/better-shot/graphs/contributors).
If BetterShot helps you, consider [supporting its development](https://www.buymeacoffee.com/code_kartik).
