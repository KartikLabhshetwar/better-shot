# Changelog

All notable changes to Better Shot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-06-03

### Fixed

- **Window capture not working**: The window picker used a plain `NSWindow` with borderless style, which can't become key — mouse and keyboard events were unreliable. Replaced with a custom `PickerWindow` subclass that overrides `canBecomeKey`/`canBecomeMain`, matching how the region selection overlay works.
- **Window picker hit-test**: Replaced NSScreen-based coordinate conversion with `CGEvent.location` for reliable cursor-to-window matching across all monitors.
- **Window capture stale reference**: After the picker closes, the app now re-fetches `SCShareableContent` and looks up the selected window by ID to get a fresh `SCWindow` reference before capturing.

## [0.3.0] - 2026-06-03

### Added

- **In-app update checker**: Check for Updates button in Preferences > About that queries GitHub releases API and links to the latest download
- **Version tracking**: `version.json` file at project root for release management
- **Professional annotation system**: Complete rewrite of annotation tools
  - **Interactive canvas**: Annotations render as live SwiftUI views — click to select, drag to move, handles to resize
  - **Selection system**: Single select, multi-select (Shift/Cmd+click), marquee drag selection, select all (Cmd+A)
  - **Curved arrows**: Quadratic Bézier arrows with draggable curve control handle and snap-to-straight
  - **Live text editing**: Text annotations use inline NSTextView with full font family, size, bold/italic/underline, and alignment controls
  - **Numbered circles**: Auto-incrementing numbered badges with proper outline and contrast text
  - **Redaction tools**: Pixelate and blur with adjustable density slider and cached preview generation
  - **Resize handles**: Corner handles for shapes, endpoint handles for lines/arrows, curve handle for arrows
  - **Color picker**: 10 named color presets with popover selector + custom ColorPicker
  - **Stroke width picker**: Visual popover with 5 presets (2/4/6/8/12px)
- **Aspect-ratio locking**: Hold Shift while drawing rectangles/ellipses to constrain to square/circle
- **Arrow snap-to-straight**: Arrow curves snap to a straight line when dragged near the start-end axis
- **Color Picker** (Cmd+Shift+C): Uses macOS native `NSColorSampler` for pixel-perfect color picking on any monitor. After picking, a floating HUD shows the color swatch and hex code (#RRGGBB) near the cursor. Hex is copied to clipboard.
- **OCR with QR/Barcode detection**: The OCR capture action now runs both `VNRecognizeTextRequest` and `VNDetectBarcodesRequest` together. Detects QR codes, barcodes, and text in a single pass. QR/barcode payloads appear first in the copied result.
- **Delayed Screenshot countdown overlay**: When the self-timer is set, a fullscreen translucent overlay shows large countdown numbers (3, 2, 1) with scale-down and fade animation. The overlay dismisses before the screenshot fires so it never appears in the capture.
- **Spotlight annotation tool** (G): Darkens everything outside a selected rectangular region to draw focus. Adjustable opacity via the density slider. Uses even-odd fill for both SwiftUI preview and CGContext export rendering.
- **Pinned Floating Screenshots**: Pin any capture as a borderless, always-on-top floating window. Drag to move anywhere, scroll wheel to resize (0.25x–4.0x), hover to reveal close button. Pin from the floating preview card or from the editor. "Unpin All" appears in the menu bar when pins exist.
- **Layout controls**: New LAYOUT section in the editor inspector with aspect ratio dropdown (Auto, 1:1, 4:3, 3:2, 16:9, 9:16) and a visual 3x3 alignment grid picker. Canvas expands to fit the selected ratio without cropping the image.
- **Canvas Expansion**: Annotations can now be drawn into the padding area beyond the screenshot boundaries, enabling margin annotations and callouts outside the image.
- **Repeat Area Capture** (Ctrl+Cmd+Shift+4): Re-captures the exact same screen region as your last region capture without reselecting. Falls back to normal region selection if no previous region exists.
- **Image Overlay** (Cmd+Shift+V): Paste any image from clipboard onto the current screenshot. The pasted image is composited at center, scaled to fit within 80% of the canvas.
- **Option+Drag to Duplicate**: Hold Option and drag any annotation to create a copy. The original stays in place while the duplicate moves with the cursor.
- **Persistent Tool Selection**: The text tool now stays armed after committing a text annotation — you can immediately click to place another text box without reselecting the tool.
- **Expanded keyboard shortcuts**: V (select), R (rectangle), F (filled rectangle), O (ellipse), L (line), A (arrow), D (freehand), N (numbered circle), P (pixelate), B (blur), G (spotlight), T (text)
- **Toast notifications**: Editor shows a brief HUD when exporting ("Exported"), copying ("Copied to clipboard"), or saving defaults ("Saved as default"). Auto-dismisses after 1.5 seconds.
- **Save as Default**: Button in the Effects section saves current padding, corner radius, shadow, background, alignment, and aspect ratio as the default for all new captures.
- **Export preserves in history**: Exported images (with annotations baked in) are added to Recent Captures so reopening shows the final result, not the raw capture.
- **Save directory picker**: Replaced the raw text field with a native macOS folder picker (`NSOpenPanel`) in Preferences.

### Fixed

- **Menu bar icon template rendering**: Changed `template-rendering-intent` from `"original"` to `"template"` so the icon adapts to light mode, dark mode, and high-contrast accessibility settings — matching how native macOS system utilities render menu bar icons
- **Keyboard shortcut override**: Fixed the accessibility permission flow — the CGEvent tap now only registers after accessibility permission is confirmed, with polling to detect when the user grants permission
- **Annotation coordinate system**: Gesture tracking now normalizes against the actual image display rect (accounting for aspect-fit letterboxing), not the full view bounds
- **Blur edge darkening**: Export-time Gaussian blur now pads the crop rect by `ceil(radius * 2)` on all sides before applying the filter, eliminating fringe artifacts at region boundaries
- **Export redaction performance**: Replaced per-item `ctx.makeImage()` (full canvas snapshot for each blur/pixelate region) with a single shared canvas snapshot, reducing export time proportionally to the number of redaction annotations
- **Spotlight export positioning**: Rewrote `AnnotationDrawing` to use explicit `imageRect`/`fullCanvasRect` parameters instead of context translation. Spotlight overlay now correctly covers the full canvas while the cutout aligns with the image position.
- **Annotation export positioning**: All annotations now render at the correct position within the canvas padding area, not offset by the image origin.
- **Multi-monitor capture**: Fullscreen and region capture now correctly identify the display under the cursor using `CGEvent.location` and `CGDisplayBounds` instead of NSScreen coordinate conversion.
- **Settings reactivity**: Capture settings (self timer, overlay position, dismiss delay, export format/quality) now use `@AppStorage` so changes reflect immediately in the UI.
- **Alignment Y-axis**: Fixed inverted Y-axis in the export renderer — clicking "bottom" in the alignment grid now correctly places the image at the bottom of the canvas.

### Changed

- **Menu bar UI redesigned**: Grouped by intent — "Open Last Capture" quick access at top, capture modes (Region, Full Screen, Window), utilities (OCR, Color Picker), contextual actions (Unpin All when pins exist), Recent Captures submenu (up to 8 items). Removed "Check for Updates" from menu (lives in Preferences > About). Shortened labels.
- **Inspector panel redesigned**: Sidebar with sections for Tools, Style, Text, Effects, Layout, and Background — each with proper spacing, section headers, and dividers
- **Canvas rendering**: Annotations now render directly as SwiftUI views on the canvas (not baked into a preview image), enabling real-time interaction without re-render delays
- **Live beautifier preview**: Canvas shows the full rendered preview (background, padding, shadow, corner radius) with a 30ms debounced render pipeline. Redundant re-renders are skipped when config hasn't changed.
- **Performance optimizations**: Cached font family list (static lazy), TransparencyGrid rasterized via `.drawingGroup()`, arrow hit-test sampling halved (32→16 points), text style dirty-check guards redundant `setAttributes` calls, GPU memory cleanup after blur export
- Version bumped to 0.3.0
- Deployment target remains macOS 14.0
- Simplified BetterShotDelegate — removed all video recording callback and frame extraction code

### Removed

- **Screen recording**: Removed ScreenRecorder, VideoProcessor, RecordingControlPanel, and the bundled videokit binary — video features will return in a future release
- **Old annotation system**: Replaced `ColorSwatch`, `StrokeWidth` enum, `AnnotationGestureView`, and basic `AnnotationItem` with the full interactive model

## [0.2.0] - 2026-06-02

### Added

- **Native Swift/SwiftUI rewrite**: Complete rewrite from Electron/Rust to pure Swift/SwiftUI + Go for video processing
- **Screen recording**: Full screen and window recording via ScreenCaptureKit
  - Floating control pill with pause/resume, stop, and discard controls
  - Pulsing red dot indicator with MM:SS timer
  - HEVC encoding at 60fps Retina resolution
  - Post-recording compression via videokit (FFmpeg)
  - Recordings saved to user's configured save directory
- **Preview overlay with editor access**: Floating preview card appears after capture
  - Hover to reveal actions: edit (pencil), delete, dismiss
  - Copy and Save pill buttons
  - Draggable thumbnail
  - Clicking pencil icon opens the annotation editor
- **Annotation editor window**: Opens from preview overlay with full beautifier controls
  - Switches app to regular activation policy (visible in Dock/Cmd-Tab) while editing
- **Override macOS screenshot shortcuts**:
  - Cmd+Shift+3 = Capture Screen
  - Cmd+Shift+4 = Capture Region
  - Cmd+Shift+5 = Capture Window
  - Cmd+Shift+6 = Toggle Screen Recording
  - Cmd+Shift+O = OCR Region
- **Bundled background images**: Wallpapers, mesh gradients, and macOS assets now ship inside the app bundle
- **videokit bundled**: Go-based FFmpeg wrapper included in the app for video compression

### Fixed

- **Background images not loading in editor**: Resources weren't being copied into the app bundle; fixed project config and file lookup to use direct path construction
- **Screenshot sound**: Now plays the actual macOS screenshot sound (`Screen Capture.aif`) instead of the generic "Blow" sound
- **Editor image caching**: Added `.onChange(of: imageURL)` and `.id()` to prevent stale images when editor window is reused

### Changed

- App target deployment raised to macOS 14.0
- Swift 6 strict concurrency throughout

## [0.1.0] - Previous

### Added

- **Background Border slider**: Adjustable padding around screenshots (0–200px)
- **Frontend test framework**: Vitest with React Testing Library (19 tests)
- **Rust unit tests**: CropRegion bounds, filename generation (13 tests)

### Fixed

- Background visible at 0px border setting

### Changed

- Padding now stored in EditorSettings (previously hardcoded to 100px)
