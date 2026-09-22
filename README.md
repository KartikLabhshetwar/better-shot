<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" height="96" alt="BetterShot clover icon">
</p>

# BetterShot

**Capture, edit, and share your screen. Native on macOS.**

BetterShot brings screenshots, screen recording, and image and video editing into
one open-source Mac app. Annotate a bug report, record a walkthrough with your
camera, or turn a capture into something ready to share. No BetterShot account
or subscription required.

[![macOS](https://img.shields.io/badge/macOS-26.0+-black.svg)](https://formulae.brew.sh/cask/bettershot)
[![Build](https://github.com/KartikLabhshetwar/better-shot/actions/workflows/build.yml/badge.svg)](https://github.com/KartikLabhshetwar/better-shot/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)

[Download](https://github.com/KartikLabhshetwar/better-shot/releases/latest) ·
[Website](https://bettershot.site) · [Changelog](CHANGELOG.md) ·
[Contribute](CONTRIBUTING.md) ·
[Report a bug](https://github.com/KartikLabhshetwar/better-shot/issues)

![BetterShot image editor with editable annotations and background controls](bettershot-landing/public/features/screenshot-editor-dark.webp)

## Install

Requires **macOS 26 or later**.

With [Homebrew](https://formulae.brew.sh/cask/bettershot):

```bash
brew install --cask bettershot
```

Or download the `.dmg` for your Mac from
[Releases](https://github.com/KartikLabhshetwar/better-shot/releases/latest), drag
**BetterShot** into **Applications**, and open it. First launch walks you through
permissions and your first capture.

## What you can do

- **Capture anything on screen.** Take region, window, or fullscreen screenshots;
  extract text with OCR; pick a color as a hex value.
- **Annotate and frame images.** Add arrows, shapes, text, numbered markers, and
  highlights. Blur or pixelate sensitive details, crop, rotate, and flip. Add a
  wallpaper or soft gradient with adjustable padding, corners, and shadows.
- **Record a walkthrough.** Capture a display, window, or adjustable area with
  optional system audio, microphone, camera, and teleprompter. Pause and resume
  from the compact recording bar.
- **Edit the recording.** Cut clips, adjust speed from 0.25× to 8×, add zooms,
  transitions, captions, and blur or pixelate masks. Arrange screen and camera
  in a bubble, overlapping frame, side-by-side layout, or presenter view.
- **3D video shots.** Use the timeline’s **+ Add > 3D Shot** menu, then choose
  from eight camera moves and five drifting angles in Effects. Adjust camera
  orbit, screen fold, distance, and lens, or generate a scene. The same menu adds
  zoom segments. **Auto Scene** previews a sequence before applying it, keeps
  generated shots at least one second long, and snaps nearby boundaries to clip cuts.
  Looks, Camera, Depth Blur, Keyframes, and Timing stay expanded in separate cards,
  with fixed shortcuts to jump straight to each section. Fold and lens controls
  are directly visible, and animated properties have one-click curve selection.
  Compare Start/End thumbnails, drag the orbit preview, and refine exact angles
  with the tilt sliders. Scene cards show their shot counts; depth blur has a
  separate enable switch and focus selection.
  Controls include radial/directional/tilt-shift focus, bokeh highlights, and editable
  Bézier curves. Preview and export share
  the GPU compositor. Zoom enlarges the whole 3D card; separate entry/exit controls
  ease the camera into and out of its shot.
- **Make the cursor easier to follow.** Choose Recorded, Arrow, Dark, Light, or
  Dot, with size, smoothing, click effects, and idle hiding. Cursor restyling
  requires a recorded pointer track; it cannot replace a cursor baked into
  imported footage.
- **Keep captures within reach.** Copy, save, pin, edit, share, or drag from the
  floating capture deck. Find screenshots, recordings, and saved share links in
  Media Gallery's searchable icon and list views.
- **Export or share.** Export video as MP4 or MOV at 30 or 60 fps, with resolution
  and quality controls. Optional cloud sharing uploads to your own Cloudflare
  R2 bucket and copies a link.

Set a reusable **Default Look** in Settings > General for new screenshots and
videos, or choose **No Background** to keep them unframed. Original captures and
source movies remain available for editing, with undo and redo in both editors.

<details>
<summary>See the video editor</summary>

![BetterShot video editor with zoom controls, a clip timeline, and cut markers](bettershot-landing/public/features/video-editor-dark.webp)

</details>

## Your first capture

1. Open BetterShot and allow screen capture when prompted. Enable Accessibility
   to use global shortcuts.
2. Press **⌘⇧4** and select a region, or **⌘⇧2** to open the capture and recording bar.
3. Use the floating preview to **Copy**, **Save**, **Pin**, or **Edit** your capture.
   **Share** becomes available after you configure cloud sharing.

### Default shortcuts

| Action | Shortcut |
| --- | --- |
| Region screenshot | `⌘⇧4` |
| Fullscreen screenshot | `⌘⇧3` |
| Capture and recording bar | `⌘⇧2` |
| Recording options | `⌘⇧5` |
| OCR text scan | `⌘⇧O` |
| Color picker | `⌘⇧C` |

Customize bindings in **Settings > Shortcuts**, including editor tools and
additional capture and recording actions. Some actions start unassigned.

### Where screenshots go

Captures start in BetterShot's private working storage. **Copy** puts an image on
the clipboard without creating a file in your configured save folder. Editing,
pinning, and sharing also keep their working files inside the app.

**Save** writes a file to your configured folder. In the image editor, it works
before you make any edits and updates the associated file on subsequent saves.
**Export** lets you choose a new destination.

Automatic screenshot saving is **off by default**. Enable it under
**Settings > General > Saving** to save normal captures while keeping the preview
or editor available. Explicit Capture & Copy, Edit, and Pin shortcuts bypass it.
The same settings section lets you customize file names with templates such as
`standup-{date}-{counter:3}`. A screenshot is named when it is taken; Copy,
Save, Export, Share, and drag-out all use that name.

### Permissions

BetterShot explains each permission during setup. You can manage access later in
**System Settings > Privacy & Security**.

| Permission | Used for |
| --- | --- |
| Screen & System Audio Recording | Screenshots, screen recording, and optional system audio |
| Accessibility | Global shortcuts from other apps |
| Input Monitoring | Precise cursor effects and shortcut overlays; plain typing is not recorded |
| Microphone | Optional voice recording |
| Camera | Optional camera recording |

If capture or shortcuts still do not work after granting access, save your work,
quit BetterShot, and reopen it. Check **Settings > Shortcuts** for disabled or
conflicting bindings.

## Cloud sharing

Capturing and editing work locally. Sharing is optional and uses a Cloudflare
account and R2 storage that you manage.

1. Create an R2 bucket with a public address, and an
   [R2 API token](https://developers.cloudflare.com/r2/api/tokens/) with
   **Object Read & Write** permission scoped to that bucket.
2. In **Settings > Sharing**, enter your Account ID, Access Key ID, Secret Access
   Key, Bucket, and HTTPS Public Bucket URL.
3. Click **Test Connection**. A successful test enables **Upload when I share**.
4. Choose **Share** from a capture or editor to upload and copy its link.

Credentials are stored in your Mac's login Keychain. Shared media is served from
your bucket. By default, links open a viewer on `bettershot.site`; enable
**Copy direct file links** for the raw file URL, useful in Markdown or embeds.
Shared links are publicly accessible to anyone who has the link.

The app also contacts GitHub to check for updates and download releases.

## Automate captures

Use the `bettershot://` URL scheme from Shortcuts, Raycast, Alfred, or a shell:

```bash
open 'bettershot://capture/region'
```

Supported actions: `capture/region`, `capture/fullscreen`, `capture/window`,
`ocr`, `color-picker`, `record`, and `settings`.

## Build from source

Requires **macOS 26+**, **Xcode 26+** with its command-line tools selected, and
**XcodeGen**.

```bash
brew install xcodegen
git clone https://github.com/KartikLabhshetwar/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

`make release` builds unsigned and does not require the maintainer's signing
identity. The app uses SwiftUI and AppKit, with
[DockProgress](https://github.com/sindresorhus/DockProgress) and a locally adapted
[TourKit](Vendor/TourKit/BETTERSHOT.md) Swift package. The website is a separate Next.js project.

See [CONTRIBUTING.md](CONTRIBUTING.md) for Xcode setup, the code map, tests, and
submission guidance.

### Guided setup and update notes

New installs open a short TourKit guide, followed by optional permissions and a
practice capture. Use **Settings → About → Take the Tour** to revisit it.
After an update, **What’s New** shows the bundled changelog once, including releases
you skipped. It also stays available in Settings → About. Closing update notes
continues your usual capture-bar startup preference; completed setup is preserved.

Hover over empty space in the video editor’s 3D timeline to see where a shot will
fit before clicking. The dashed preview shows its duration; hovering never saves
an effect. The **+ Add** menu remains available for Zoom and 3D Shot.

The Scenes buttons show each scene’s camera sequence and shot count before
replacing the selected shot. Both editors support the green window button for
native full screen; **Settings → General → Open editors in full screen** controls
whether new editor windows enter it automatically.


## Help and contribute

Found a bug or have an idea? [Open an issue](https://github.com/KartikLabhshetwar/better-shot/issues)
with your macOS and BetterShot versions, what you expected, and steps to reproduce.
Screenshots or short recordings help; remove private information before posting.

Code, documentation, reproducible bug reports, and accessibility feedback are all
welcome. Start with the [contributor guide](CONTRIBUTING.md) and follow our
[Code of Conduct](CODE_OF_CONDUCT.md).

Built by [Kartik Labhshetwar](https://x.com/code_kartik) and
[contributors](https://github.com/KartikLabhshetwar/better-shot/graphs/contributors).
If BetterShot helps you, you can [support its development](https://www.buymeacoffee.com/code_kartik).

## License

[BSD 3-Clause](LICENSE) for original BetterShot code; adapted Cap rendering uses
AGPLv3; the notch also includes GPLv3 Boring Notch adaptations. See [third-party notices](Resources/Licenses/NOTICE.md) for distribution
terms and the bundled TourKit MIT license.

### Optional notch mode (v0.5.6)

In **Settings > General > Capture Mode**, choose **Normal Mode** (the default)
or **Notch Mode**. Notch mode puts image/video previews, saved shelf items,
quick editing, and related status at the top of the capture display.
The expanded notch is a horizontal shelf with **All, Text, Images, Videos, and Colors**
filters in a compact 560-point panel without capture or recording tools. Hold Control (or your chosen modifier) and drag to capture an area; drawing directly on the frozen screen is an optional alternative. Pressing the modifier alone does not open the notch. The folder menu provides the gallery plus Save All and Dismiss All for pending previews.
The **All** filter orders screenshots, recordings, text, and colors together by recency, with a pending capture first.
OCR text and picked colors are copied automatically and remain on the shelf
with Copy and Dismiss actions until removed from history. Notch Mode shows no
toast notifications: Copy confirms on its button, and failures appear as inline
instructions. Text is selectable; colors show their hex code and swatch. Text and colors captured in Notch Mode are retained locally across launches. Normal Mode does not add to this history.
Scroll sideways to browse the cards. Click an image for the quick editor, or a video for the video editor;
rounded media cards show a title at rest and reveal Copy, Save, Edit, Pin, Cloud Share, and pending-capture Dismiss on hover or keyboard focus.
Drag image previews into compatible editors. Drag a text card’s text or title to insert text, or a color card’s hex label/title to insert its color code. Color cards show the sampled color with a readable hex label and Copy button.
Use your **Recording options** shortcut (default **⌘⇧5**) to open the compact floating recording strip in either capture mode. Choose Display, Window, or Area to start, and toggle Camera, Mic, Audio, or Script directly in the popover. The shared Timer menu configures both screenshot and recording delays. Recording controls never move into the notch.
The media card’s **Edit** hover action opens the full editor. Quick Edit opens a small native panel beneath the notch with drawing, arrow, blur, crop, background, and undo controls. **Done** retains a lossless image and editable annotations in BetterShot’s private library; **Save** explicitly exports a file.
The notch uses an opaque black surface to match the camera cutout, with native
macOS controls and readable dark-appearance labels in either system appearance.

Switching to Notch Mode opens the preview shelf immediately, including its empty state. Dismissing the last active preview returns it to the compact resting notch. While content is active, moving away collapses
the notch after a short delay and hover expands it. Brief transitions respect
Reduce Motion.
Preview menus and confirmations stay open while you use them. Click
remains available for keyboard/accessibility use. Other displays use a floating
panel that collapses to compact preview status. The shelf combines pending captures and recent library images/videos without
duplicate cards. Open Gallery shows the full library. Pending
captures remain until you act on them. Switching back restores your normal overlay
layout and timing. Capture exclusion and private staging work in both modes.


**Hold-key capture**

With Notch Mode and Accessibility access enabled, hold Control and drag to select a rectangular screenshot area. Pressing Control alone leaves the notch hidden. Release the mouse to capture; release the key early or press Escape to cancel. No annotations are drawn on the screen. The shutter sound follows **General > Play Sound**.

Choose Control, Option, Shift, or Command under **Settings > Shortcuts > Notch Capture Gesture**. **Hold action** defaults to **Select an area**. **Draw on screen** is an explicit alternative for red freehand annotations: hold the key briefly, draw, then release to save editable strokes. Assigning Option pauses the optional Option voice gesture; voice remains available in the quick editor. Standard region shortcuts still use the macOS screenshot selector.

**Copied colors** are collected automatically while Notch Mode is active: copy a standalone `#RGB` or `#RRGGBB` code and it appears as a swatch under All and Colors, with Copy and drag-out. Turn this off with **Keep copied colors in Notch Mode**. Ordinary clipboard text remains separately opt-in, and private clipboard markers are respected. Normal Mode collects neither.

**Local voice screenshots and copied text**

- Open an image’s quick editor and choose the microphone to draw and speak. **Done** transcribes on your Mac and keeps the annotated image and text together on the shelf. Microphone permission is requested only when starting voice capture. Speech uses macOS 26’s on-device SpeechAnalyzer; supported Apple silicon/languages and an initial system language-model download are required. There is no cloud transcription fallback.
- **Hold Option for voice annotation** is off by default so Option remains available to apps such as Wispr Flow. You can opt in under **Settings > Shortcuts > Notch Capture Gesture**. With Accessibility and Microphone access, hold Option briefly without another key, annotate over the captured screen, and release to finish. The annotated image and local transcript stay together as one shelf item. Voice sessions stop at two minutes; the microphone is stopped before transcription begins.
- Copy a voice card to put image, file, and transcript representations on the clipboard. The receiving app chooses which representation to paste; use the card’s context menu **Copy transcript** to paste text separately. The voice note’s **Open image** returns to editing.
- **Keep copied text in Notch Mode** is an independent, opt-in setting. While Notch Mode is active, it stores up to 50 text/color/voice entries locally (100 KB per text), skips clipboard content marked concealed/transient/generated by the source app, and starts with your next copy. Unmarked sensitive text can still be saved. Turning it off pauses collection; **Clear Shelf Text** removes retained text and transcripts without deleting screenshots. Clipboard image/file monitoring and keyboard sounds are not included.
- OCR and sampled colors are saved in Notch Mode without enabling clipboard monitoring. Voice audio is temporary: it is removed after successful completion or explicit discard. If transcription fails, the editor retains the audio for retry and offers **Keep image without voice**. Closing an unsaved quick edit asks before discarding it.

Notch UI and hover interactions include code from [Boring Notch](https://github.com/TheBoredTeam/boring.notch), credited to TheBoredTeam and its contributors. See [source and license notices](Resources/Licenses/NOTICE.md).

Window screenshots use the native macOS window picker. Choose a window and click
**Share This Window** to take one screenshot; BetterShot does not start a recording.
Cancel leaves the current capture unchanged.
