# Changelog

All notable changes to Better Shot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.7] - 2026-04-10

### Added

- **Device frames for screenshots**: New predefined device frames panel in the editor — wrap screenshots in iPhone or MacBook frames for polished presentations
- **Global shortcut to open BetterShot**: Press `Cmd+Shift+B` from anywhere to bring the BetterShot window to the foreground

### Fixed

- **MacBook frame proportions**: Adjusted MacBook device frame to match reference proportions, including rework to full laptop silhouette
- **iPhone frame layout**: Reworked iPhone frame to correctly wrap the screenshot and match reference design

### Documentation

- README rewritten for end users using the AIDA framework for clearer onboarding

### Chores

- Removed landing page; updated all project URLs to the fork

## [0.2.6] - 2026-04-09

### Added
- Always open editor after screenshot — every capture (region, fullscreen, window) now navigates directly to the editor screen; the auto-apply background shortcut path has been removed
- Upload photo to edit — new button on the main screen with a permission-explanation dialog; the selected file is sandboxed into a temp workspace before opening in the editor
- macOS autostart support — app can be configured to launch at login
- Homebrew install option added to the download dropdown and documentation
- Annotation resizing support in AnnotationCanvas — annotations can now be resized interactively after placement
- Background-size adjustment controls added to the editor (new `BackgroundSizePanel` component)
- New Tauri commands: `open_image_file_dialog`, `copy_file_to_temp_workspace`, `delete_temp_workspace_file`
- `filenamePrefix` and `saveDir` settings now persist across sessions via the settings store

### Changed
- Editor UI redesigned with dark studio aesthetic and tabbed sidebar — replaced the long scrollable sidebar with an icon nav rail and tabbed panel layout; annotation toolbar moved into a header center pill; Export button relocated into a dedicated Export panel

### Removed
- OCR feature removed — Tesseract.js WASM assets, `ocr.ts`, `OCRResultsDialog`, and related onboarding steps deleted; reduces bundle size significantly
- Auto-apply background toggle removed from the main UI and all related state, store reads/writes, and the `processScreenshotWithDefaultBackground` call

### Fixed
- Temp file cleanup after an upload editing session — uploaded files in `bettershot-uploads/` are deleted on save or cancel
- Path validation in `copy_file_to_temp_workspace` — source path is canonicalized to reject path traversal; `delete_temp_workspace_file` enforces the target is inside `bettershot-uploads/`
- Permission dialog now closes correctly when the user cancels the native file picker
- Trailing underscore removed from the default filename prefix (`"bettershot"` instead of `"bettershot_"`)

## [Unreleased]

### Fixed

- **Background Border at 0px**: Fixed issue where background was still visible when Background Border was set to 0px. Now 0px means no background border at all - the screenshot edges touch the canvas edges directly.

### Added

- **Background Border slider**: New control in the Background Effects panel to adjust the padding around captured screenshots
  - Slider range: 0px (no border) to 200px (maximum border)
  - Smart default: Automatically calculates 5% of the average image dimension, capped at 200px
  - Real-time preview updates during slider drag
  - Full undo/redo support
  - Tooltip explaining the control's purpose
- **Frontend test framework**: Set up Vitest with React Testing Library
  - 19 tests for editor store padding functionality
  - Test coverage for transient/commit actions, undo/redo, and smart defaults
- **Rust unit tests**: Added tests for image processing utilities
  - 8 tests for CropRegion bounds clamping and validation
  - 5 tests for filename generation and directory utilities

### Changed

- Padding is now a configurable setting stored in EditorSettings (previously hardcoded to 100px)
