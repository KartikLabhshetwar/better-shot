# Changelog

All notable changes to Better Shot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-03

### Added

- **In-app update checker**: Check for Updates button in Preferences > About that queries GitHub releases API and links to the latest download
- **Version tracking**: `version.json` file at project root for release management
- **Rebuilt annotation tools**: Rectangle, filled rect, ellipse, line, arrow, freehand, numbered badges, text, pixelate, and blur — all with proper coordinate mapping that correctly handles the aspect-fit image display area

### Fixed

- **Menu bar icon**: Replaced generic circle template icon with the actual BetterShot app icon (orange ring) using original rendering
- **Keyboard shortcut override**: Fixed the accessibility permission flow — the CGEvent tap now only registers after accessibility permission is confirmed, with polling to detect when the user grants permission. Previously the tap was registered before permission was granted, silently failing and letting native macOS screenshot shortcuts fire instead
- **Annotation coordinate system**: Gesture tracking now normalizes against the actual image display rect (accounting for aspect-fit letterboxing), not the full view bounds

### Removed

- **Screen recording**: Removed ScreenRecorder, VideoProcessor, RecordingControlPanel, and the bundled videokit binary — video features will return in a future release
- **Layout section**: Removed alignment grid and aspect ratio picker from the editor inspector (non-functional in previous release)

### Changed

- Version bumped to 0.3.0
- Deployment target remains macOS 14.0
- Simplified BetterShotDelegate — removed all video recording callback and frame extraction code

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
