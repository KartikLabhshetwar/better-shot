# Contributing to Better Shot

Thank you for your interest in contributing to Better Shot! This document provides guidelines and instructions for contributing to the project.

## Getting Started

1. **Fork the repository** and clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/better-shot.git
   cd better-shot
   ```

2. **Install XcodeGen** (used to generate the Xcode project from `project.yml`):

   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project:**

   ```bash
   xcodegen generate
   ```

4. **Open in Xcode:**

   ```bash
   open BetterShot.xcodeproj
   ```

5. **Grant permissions** when prompted: Screen Recording and Accessibility access are required for capture and global shortcuts.

### Requirements

- **macOS**: 14.0 or higher
- **Xcode**: 16.0 or higher
- **Swift**: 6.0 (strict concurrency)
- **XcodeGen**: Latest version (`brew install xcodegen`)

### Building

```bash
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot build
```

Or just hit Cmd+B in Xcode.

## Project Structure

```text
better-shot/
├── Sources/
│   ├── App/
│   │   └── BetterShotDelegate.swift      # App delegate, menu bar setup
│   ├── Capture/
│   │   ├── CaptureOrchestrator.swift      # Coordinates capture flows
│   │   └── ScreenCapture.swift            # ScreenCaptureKit integration
│   ├── Editor/
│   │   ├── EditorModel.swift              # Editor state, annotation interaction pipeline
│   │   ├── EditorCanvasView.swift         # Live annotation canvas with drag gestures
│   │   ├── EditorInspectorView.swift      # Side panel: tools, style, text, background, effects
│   │   ├── EditorWindowView.swift         # Root editor window (canvas + inspector + toolbar)
│   │   ├── EditorWindowController.swift   # NSWindow management
│   │   ├── AnnotationItemView.swift       # SwiftUI rendering for each annotation
│   │   ├── AnnotationDrawing.swift        # CoreGraphics renderer for final export
│   │   ├── AnnotationRedactionImageProcessor.swift  # Pixelate/blur preview generation
│   │   ├── AnnotationKeyboard.swift       # Keyboard shortcuts (Delete, Cmd+Z, tool keys)
│   │   └── AnnotationEditorInteractionState.swift   # Interaction enums, undo/redo history
│   ├── Models/
│   │   ├── AnnotationItem.swift           # AnnotationItem, AnnotationTool, AnnotationSwatch, geometry
│   │   ├── BackgroundStyle.swift          # Background style enum and presets
│   │   ├── AppPreferences.swift           # User preferences (save dir, format, shortcuts)
│   │   ├── BundledBackgrounds.swift       # Bundled wallpaper/gradient assets
│   │   └── CaptureRecord.swift            # Capture history records
│   ├── Services/
│   │   ├── BeautifierRenderer.swift       # CoreGraphics background + shadow + annotation compositing
│   │   ├── ShortcutService.swift          # Global keyboard shortcut registration
│   │   └── AppUpdater.swift               # GitHub releases update checker
│   ├── Settings/
│   │   └── PreferencesView.swift          # Settings window
│   └── Views/
│       └── MenuBarContentView.swift       # Menu bar dropdown UI
├── Resources/
│   ├── Assets.xcassets/                   # App icon, menu bar icon
│   ├── Backgrounds/                       # Bundled wallpaper images
│   ├── Info.plist
│   └── BetterShot.entitlements
├── project.yml                            # XcodeGen project definition
├── version.json                           # Release version tracking
├── CHANGELOG.md
└── CONTRIBUTING.md
```

## Architecture

BetterShot is a native macOS menu bar app built with Swift 6 and SwiftUI.

### Key architectural decisions:

- **Menu bar app**: Runs as an accessory app (no Dock icon) with an NSPopover menu bar dropdown. Switches to regular activation policy when the editor window is open.
- **Annotation system**: Annotations use normalized coordinates (0..1) for resolution independence. The canvas renders annotations as live SwiftUI views for interactive editing, while `AnnotationDrawing` uses CoreGraphics for final export.
- **BeautifierRenderer**: Composites background + shadow + corner radius + image + annotations into a final CGImage for export.
- **Strict concurrency**: Swift 6 concurrency throughout. `@MainActor` on all UI-facing types.

### Editor data flow:

```
EditorModel (state)
  ├── EditorCanvasView (renders image + annotation views, handles DragGesture)
  │     ├── AnnotationItemView (per-item SwiftUI view: shapes, text, redaction)
  │     └── AnnotationMarqueeSelectionView
  ├── EditorInspectorView (side panel: tools, style, text, background, effects)
  └── AnnotationKeyCommandHandler (keyboard shortcuts via NSEvent monitor)
```

## Coding Standards

### Swift Guidelines

- **Swift 6 strict concurrency**: All code must compile with strict concurrency checking
- **No code comments** unless explaining a non-obvious constraint
- **`@Observable`** for model classes, `@Bindable` in views
- **Minimize file size**: Keep files focused; split when it improves clarity
- **SOLID principles**: Single responsibility, prefer composition

### Performance

- Avoid unnecessary re-renders. Use `@State` and `@Bindable` correctly.
- Debounce expensive operations (e.g., BeautifierRenderer calls).
- Use `autoreleasepool` in tight CoreGraphics loops.
- Cache redaction previews (RedactionImageProcessor uses NSCache).

### UI/UX

- Follow native macOS patterns (NSPopover for menu bar, NSWindow for editor)
- Use system colors (`NSColor.controlBackgroundColor`, etc.)
- Support dark mode automatically
- Keep the app fast and snappy — no blocking the main thread

## Common Tasks

### Adding a New Annotation Tool

1. Add the case to `AnnotationTool` enum in `Sources/Models/AnnotationItem.swift`
2. Add `systemImage` and `title` for the tool
3. Handle rendering in `AnnotationItemView.swift` (live preview)
4. Handle rendering in `AnnotationDrawing.swift` (export)
5. Handle draft creation in `EditorModel.beginDraftItem`
6. Handle draft update in `EditorModel.updateDraftItem`
7. Add keyboard shortcut in `AnnotationKeyboard.swift`

### Adding a New Background Style

1. Add the case to `BackgroundStyle` enum in `Sources/Models/BackgroundStyle.swift`
2. Handle rendering in `BeautifierRenderer.drawBackground`
3. Add UI in `BackgroundPickerSection` in `EditorInspectorView.swift`

### Modifying the Inspector

The inspector is defined in `Sources/Editor/EditorInspectorView.swift`. Sections:
- Tools grid (annotation tool picker)
- Style (color, stroke, redaction density)
- Text (font, size, bold/italic/underline, alignment)
- Background (solid colors, gradients, bundled images, custom wallpaper)
- Effects (padding, corner radius, shadow sliders)

## Pull Request Process

1. Create a feature branch: `git checkout -b feat/feature-name`
2. Make focused changes (one feature or fix per PR)
3. Ensure it builds: `xcodebuild -scheme BetterShot build`
4. Test manually in the app
5. Submit PR with a clear title and description

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
