# Contributing to BetterShot

Thanks for considering contributing. This guide covers everything you need to get started.

## Quick start

```bash
# 1. Fork and clone
git clone https://github.com/YOUR_USERNAME/better-shot.git
cd better-shot

# 2. Build and run
make run
```

That's it. The Makefile handles everything. No extra tools needed.

> **Alternative**: Open `BetterShot.xcodeproj` in Xcode and press `⌘R`.

### If you modify `project.yml`

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml`, regenerate the project:

```bash
brew install xcodegen   # one-time
xcodegen generate
```

Most contributions won't need this.

### Requirements

- macOS 14.0+
- Xcode 16.0+ (Swift 6)

### Permissions

On first launch, grant both:

1. **Screen Recording** — System Settings > Privacy & Security > Screen Recording
2. **Accessibility** — System Settings > Privacy & Security > Accessibility

## Project structure

```
Sources/
  App/                   App entry point and delegate
  Capture/               Screenshot capture, region selection, color picker, countdown
  Editor/                Annotation editor: canvas, inspector panel, tools, rendering
  Models/                Data types: annotations, backgrounds, preferences, config
  Preview/               Floating preview overlay and pinned screenshots
  History/               Capture history (JSON in Application Support)
  Recording/             Screen/window recording, video editor, trim timeline, effects export
  Services/              Beautifier renderer, keyboard shortcuts, app updater
  Settings/              Preferences window (sidebar navigation) and settings window controller
  Views/                 Menu bar popover, toast notifications
Resources/
  Assets.xcassets/       App icon, menu bar icon
  Backgrounds/           Bundled wallpaper and gradient images
  Info.plist
  BetterShot.entitlements
```

### Key files

| File | What it does |
|---|---|
| `EditorModel.swift` | All editor state: annotation interactions, undo/redo, config |
| `EditorCanvasView.swift` | Live canvas rendering with drag gestures |
| `EditorInspectorView.swift` | Left panel: tools, colors, text, effects, backgrounds |
| `AnnotationDrawing.swift` | CoreGraphics renderer for final image export |
| `BeautifierRenderer.swift` | Composites background + shadow + radius + annotations |
| `CaptureOrchestrator.swift` | Coordinates capture pipeline: capture > sound > history > preview |
| `ShortcutService.swift` | Global keyboard shortcuts via CGEvent tap |
| `PreviewOverlay.swift` | Floating preview card after capture (screenshots and recordings) |
| `ScreenRecordingManager.swift` | Screen and window recording via ScreenCaptureKit |
| `VideoEditorModel.swift` | Video editor state: trim, effects config, export with AVMutableVideoComposition |
| `VideoEditorView.swift` | Video editor UI: inspector sidebar, preview, timeline, transport controls |
| `RecordingStatusBar.swift` | Floating recording status bar with timer, pause, stop, discard |
| `PreferencesView.swift` | Settings window with sidebar navigation (General, Capture, Recording, History, Videos, About) |
| `SettingsWindowController.swift` | Creates and manages the settings NSWindow (mirrors EditorWindowController) |
| `MenuBarPopoverController.swift` | Custom NSPanel-based menu bar popover with arrow and click-outside dismiss |
| `ToastWindow.swift` | Floating toast notifications (save confirmation, OCR/color picker feedback) |
| `AppPreferences.swift` | All UserDefaults-backed preferences |

## How the code works

### Capture flow

```
User presses ⌘⇧4
  → ShortcutService (CGEvent tap intercepts the keypress)
  → CaptureOrchestrator.performCapture(.region)
  → ScreenCapture.captureRegion() (native screencapture CLI)
  → HistoryStore.importCapture() (saves to Application Support)
  → PreviewOverlay.show() (floating card appears)
  → User clicks preview → EditorWindowController.open()
```

### Recording flow

```
User presses ⌘⇧2 (or clicks Record / Record Window)
  → ShortcutService (CGEvent tap intercepts the keypress)
  → ScreenRecordingManager.startRecording() (full screen)
     or .startWindowRecording() (hover-and-click window picker)
  → RecordingStatusBarController.show() (floating status bar)
  → User clicks stop → HistoryStore.importCapture(kind: .recording)
  → PreviewOverlay.show() (floating card with play icon)
  → User clicks preview → VideoEditorWindowController.open()
  → User edits effects → VideoEditorModel.exportWithEffects()
     (AVMutableVideoComposition + Core Animation layers)
```

### Editor flow

```
EditorModel (all state)
  ├── EditorInspectorView   Left panel: tools, style, text, effects, layout, background
  ├── EditorCanvasView      Renders image + live annotation views, handles gestures
  │     └── AnnotationItemView   One per annotation (shapes, text, redaction)
  └── AnnotationKeyboard    Keyboard shortcuts for tools and actions
```

Annotations use **normalized coordinates** (0.0 to 1.0) so they're resolution-independent. The canvas renders them as SwiftUI views for interactive editing. `AnnotationDrawing` re-renders them with CoreGraphics for the final export.

### Settings

The settings window is managed by `SettingsWindowController`, which creates an `NSWindow` hosting `PreferencesView` in an `NSHostingView`. This mirrors the `EditorWindowController` pattern. The view uses a sidebar list (General, Capture, Recording, History, Videos, About) and a content panel. Preferences are stored via `@AppStorage` and the centralized `AppPreferences` enum. Screenshots and recordings have separate history tabs — History shows only screenshots, Videos shows only recordings.

### Menu bar

The menu bar popover is managed by `MenuBarPopoverController`, which creates a custom `NSPanel` (not SwiftUI's `MenuBarExtra`) for full control over appearance and animation. The panel hosts `MenuBarPanelView` with an arrow indicator and spring animation.

## Common tasks

### Adding a new annotation tool

1. Add the case to `AnnotationTool` in `Models/AnnotationItem.swift`
2. Set its `systemImage` and `title`
3. Add live rendering in `Editor/AnnotationItemView.swift`
4. Add export rendering in `Editor/AnnotationDrawing.swift`
5. Handle creation in `EditorModel.beginDraftItem`
6. Handle updates in `EditorModel.updateDraftItem`
7. Add keyboard shortcut in `Editor/AnnotationKeyboard.swift`

### Adding a new background type

1. Add the case to `BackgroundStyle` in `Models/BackgroundStyle.swift`
2. Handle rendering in `BeautifierRenderer.drawBackground`
3. Add picker UI in `BackgroundPickerSection` in `EditorInspectorView.swift`
4. Add picker UI in `DefaultBackgroundPicker` in `PreferencesView.swift`

### Adding a new preference

1. Add the `@AppStorage` key and property in `Models/AppPreferences.swift`
2. Add the UI control in the appropriate section of `Settings/PreferencesView.swift`

## Code style

- **Swift 6 strict concurrency** — all code must compile without concurrency warnings
- **`@Observable`** for model classes, `@Bindable` in views
- **No comments** unless explaining something non-obvious (a hidden constraint, a workaround)
- **No abstractions for their own sake** — three similar lines is better than a premature helper
- **System colors** — use `NSColor.controlBackgroundColor`, `.separatorColor`, etc. for native look
- **Main actor** — all UI types are `@MainActor`

## Submitting a pull request

1. Create a branch: `git checkout -b feat/what-it-does` or `fix/what-it-fixes`
2. Keep changes focused — one feature or fix per PR
3. Make sure it builds: `make build`
4. Test manually in the app: `make run`
5. Write a clear PR title and description

### Commit messages

Use short, descriptive messages:

```
feat: add blur strength slider to redaction tools
fix: window capture failing on secondary monitors
chore: update dependencies
```

## Versioning

Version is tracked in three places (keep them in sync):

| File | Fields |
|---|---|
| `version.json` | `version`, `build` |
| `project.yml` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` |
| `BetterShot.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` (both Debug and Release) |

The `CHANGELOG.md` documents what changed in each version.

## License

By contributing, you agree that your contributions will be licensed under the project's [BSD 3-Clause License](LICENSE).
