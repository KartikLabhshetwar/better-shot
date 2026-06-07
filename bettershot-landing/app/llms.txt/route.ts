export const dynamic = "force-static"

export async function GET() {
  const llmsContent = `# Better Shot

> An open-source alternative to CleanShot X for macOS. Capture, annotate, and beautify screenshots — local-first, no account, no cloud, no telemetry.

Better Shot is a free, native macOS screenshot tool built with Swift 6 and SwiftUI. It lives in the menu bar and provides professional-grade capture, annotation, and beautification without subscriptions or cloud dependencies.

## Core Resources

[Homepage]: https://bettershot.site - Landing page with features, screenshots, and download links
[GitHub Repository]: https://github.com/KartikLabhshetwar/better-shot - Source code, issues, and releases
[Contributing Guide]: https://github.com/KartikLabhshetwar/better-shot/blob/main/CONTRIBUTING.md - Setup, architecture, and contribution guidelines

## Key Features

### Capture
- Region, fullscreen, and window screenshot via native macOS screencapture CLI
- OCR text extraction (Apple Vision framework)
- Color picker — sample any on-screen pixel, copies hex to clipboard
- Self-timer countdown overlay (3s, 5s, 10s)
- Customizable global keyboard shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5, ⌘⇧O, ⌘⇧C)

### Beautify
- Backgrounds: 12 solid color presets, 16 gradient presets, bundled macOS wallpapers, custom images
- Effects: padding, corner radius, shadow strength — all rendered live
- Layout: aspect ratio (Auto, 1:1, 4:3, 3:2, 16:9, 9:16), 9-point alignment grid with smart corner radius
- Export as PNG or JPEG with configurable quality

### Annotate
- Tools: rectangle, filled rectangle, ellipse, line, curved arrow, freehand, text, numbered badge, blur, spotlight
- Single-key shortcuts for each tool (R, F, O, L, A, D, T, N, B, G)
- Text annotations with font selection, size, bold, italic, underline, alignment
- Blur/pixelate redaction with adjustable density

### Workflow
- Floating preview overlay after capture — click to open editor
- Pin screenshots as always-on-top floating windows
- Capture history — browse and re-open past captures
- In-app updates — check, download, and install from the About tab
- Toast notifications for save, copy, OCR, and color picker feedback
- Configurable overlay position and auto-dismiss timing

## Technical Details

- **Language**: Swift 6 with strict concurrency
- **UI Framework**: SwiftUI with AppKit integration
- **Frameworks**: CoreGraphics (compositing), CoreImage (blur), Vision (OCR), AppKit (capture/panels), Carbon (global shortcuts)
- **Architecture**: Menu bar app using custom NSPanel popover, not MenuBarExtra
- **Data**: All preferences via UserDefaults, capture history stored as JSON in Application Support
- **No external dependencies**: No Electron, no web views, no third-party packages
- **Install**: Homebrew (\`brew install --cask bettershot\`) or direct DMG download (Apple Silicon + Intel)
- **License**: BSD 3-Clause
`

  return new Response(llmsContent, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
    },
  })
}
