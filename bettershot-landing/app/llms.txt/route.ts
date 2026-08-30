export const dynamic = "force-static"

export async function GET() {
  const llmsContent = `# Better Shot

> The free, open-source alternative to Loom and CleanShot X for macOS. Record polished screen videos with cursor auto-zoom, face cam, on-device captions, and a full editor. No account, no subscription, no watermark.

Better Shot is a native macOS app built with Swift 6 and SwiftUI. It lives in the menu bar and provides capture, screen recording, annotation, video editing, and beautification without subscriptions or a vendor cloud. Files stay on your Mac unless you turn on share links, which upload to a Cloudflare R2 bucket you own.

## Core Resources

[Homepage]: https://bettershot.site - Features, comparison table, and download links
[Changelog]: https://bettershot.site/changelog - Every release, version by version
[Blog]: https://bettershot.site/blog - Comparisons and workflow guides
[Loom Alternative]: https://bettershot.site/blog/loom-alternative - Why Better Shot is the best free Loom alternative for Mac
[CleanShot X Alternative]: https://bettershot.site/blog/cleanshot-x-alternative - Better Shot vs CleanShot X feature comparison
[CleanShot X, CapCut, and Loom comparison]: https://bettershot.site/blog/cleanshot-x-capcut-loom-alternative - How Better Shot replaces each paid tool, with pricing
[Download]: https://bettershot.site/download - Apple Silicon, Intel, and Homebrew install options
[Privacy]: https://bettershot.site/privacy - What is stored locally and what is never sent
[Terms]: https://bettershot.site/terms - BSD 3 Clause license terms and usage
[GitHub Repository]: https://github.com/KartikLabhshetwar/better-shot - Source code, issues, and releases
[Contributing Guide]: https://github.com/KartikLabhshetwar/better-shot/blob/main/CONTRIBUTING.md - Setup, architecture, and contribution guidelines

## Key Features

### Capture
- Region, fullscreen, and window screenshots via the native macOS screencapture CLI
- Screenshot deck: successive captures stack into a floating deck (up to five cards), each with copy, delete, pin, annotate, and drag-out actions
- Keep-until-saved mode: captures stay in the deck until explicitly saved, copied, or discarded
- Screen recording with ScreenCaptureKit: pause, resume, restart, discard
- Crash-safe fragmented MP4 writes every frame as it arrives
- Cursor auto-zoom that follows pointer activity and zooms in on what you are doing (30 Hz sampling)
- Face cam bubble from any connected camera, positioned over the recording
- Microphone capture alongside system audio
- Configurable recording: FPS (24/30/60), cursor visibility, display or window scope
- OCR text extraction (Apple Vision framework)
- Color picker: sample any on-screen pixel, copies hex to the clipboard
- Self-timer countdown overlay (3s, 5s, 10s)
- Customizable global keyboard shortcuts (Cmd+Shift+3, Cmd+Shift+4, Cmd+Shift+5, Cmd+Shift+2, Cmd+Shift+O, Cmd+Shift+C)

### Edit and beautify
- Backgrounds: 12 solid color presets, 16 gradient presets, bundled macOS wallpapers, custom images
- Effects: padding, corner radius, shadow strength, all rendered live
- Layout: aspect ratio (Auto, 1:1, 4:3, 3:2, 16:9, 9:16) and a 9-point alignment grid
- Video editor: multi-clip timeline, split, trim, crop, reorder, and delete clips
- Per-clip playback speed from 0.25x to 4x
- Transitions: crossfade and fade-through-black between clips
- 3D camera tilt and color grading
- Export as PNG or JPEG for screenshots, MP4 for recordings, with no watermark

### Annotate
- Tools: rectangle, filled rectangle, ellipse, line, curved arrow, freehand, text, numbered badge, blur, spotlight
- Single-key shortcuts for each tool (R, F, O, L, A, D, T, N, B, G)
- Text annotations with font selection, size, bold, italic, underline, alignment
- Blur and pixelate redaction with adjustable density

### Video overlays
- On-device captions: transcription runs locally via Apple's speech framework, editable per line
- Keystroke overlay: records keystrokes and renders them under the video, collapsing typing into words
- Blur, pixelate, and spotlight masks as timeline lanes with start and end times
- Hide masks destroy pixels on export so sensitive content never ships in the file

### Share and workflow
- Optional share links uploaded directly from your Mac to your own Cloudflare R2 bucket
- No Better Shot server sits in the upload path, and credentials live in the macOS Keychain
- Floating preview overlay after capture, click to open the editor
- Pin screenshots as always-on-top floating windows
- Capture history to browse and re-open past captures
- In-app updates: check, download, and install from the About tab

## How It Compares

- vs CleanShot X ($29 plus $8/mo for cloud, as published August 2026): Better Shot is free and open source, and share links go to storage you own. CleanShot X still wins on scrolling capture.
- vs Loom ($18/seat/mo Business, as published August 2026): Better Shot records locally with auto-zoom and a face cam and has no recording length caps or watermarks. Loom still wins on viewer analytics, comments, and transcripts.
- vs CapCut ($19.99/mo Pro, as published August 2026): Better Shot trims, splits, and re-times screen recordings without a watermark or an account. CapCut still wins on multi-track editing, music libraries, and auto captions.

## Technical Details

- **Language**: Swift 6 with strict concurrency
- **UI Framework**: SwiftUI with AppKit integration
- **Frameworks**: ScreenCaptureKit (recording), AVFoundation (video editing and export), CoreGraphics (compositing), CoreImage (blur), Vision (OCR), AppKit (capture and panels), Carbon (global shortcuts)
- **Architecture**: Menu bar app using a custom NSPanel popover, not MenuBarExtra
- **Data**: Preferences in UserDefaults, capture history as JSON in Application Support, R2 credentials in the Keychain
- **No external dependencies**: No Electron, no web views, no third-party packages
- **Requirements**: macOS 14.0 or later, Apple Silicon or Intel
- **Install**: Homebrew (\`brew install --cask bettershot\`) or a direct DMG download
- **License**: BSD 3-Clause
- **Price**: Free, with no paid tier, no account, and no telemetry
`

  return new Response(llmsContent, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
    },
  })
}
