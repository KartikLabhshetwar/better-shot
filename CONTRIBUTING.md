# Contributing to BetterShot

Thanks for considering contributing. This guide covers everything you need to get started.

## Quick start

```bash
# 1. Fork and clone
git clone https://github.com/YOUR_USERNAME/better-shot.git
cd better-shot

# 2. Install XcodeGen (one time, the Makefile regenerates the project on every build)
brew install xcodegen

# 3. Build and run
make run
```

> **Alternative**: run `make generate` once, then open `BetterShot.xcodeproj` in Xcode and press `⌘R`.

### Requirements

- macOS 26.0+
- Xcode 26+ (Swift 6 language mode, main-actor default isolation)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Code signing on a fork

`project.yml` pins the maintainer's Developer ID team, so `make build` and `make run`
fail at the signing step on any machine without that certificate. Two ways around it:

- `make release` builds unsigned (this is what CI runs), then `open .build/Build/Products/Release/BetterShot.app`
- In Xcode, Signing & Capabilities > switch the team to your own or "Sign to Run Locally"

Don't commit the resulting `project.yml` or `project.pbxproj` signing changes.

### Permissions

On first launch, grant both:

1. **Screen Recording**: System Settings > Privacy & Security > Screen Recording
2. **Accessibility**: System Settings > Privacy & Security > Accessibility

Recording with a camera, microphone, or the keystroke overlay asks for Camera, Microphone, and Input Monitoring on first use.

## Project structure

```
Sources/
  App/                   @main App (window scenes) and NSApplicationDelegate
  Capture/               Screenshot capture, region selection, color picker, countdown, last-region ghost
  History/               Capture history (JSON in Application Support)
  Models/                Beautifier backgrounds, CaptureRecord, AppPreferences
  Preview/               Floating preview deck, pinned screenshots, unsaved-deck staging
  Services/              Beautifier renderer, global shortcuts, app updater, color grading, silence detection
  Settings/              Preferences window (sidebar navigation), Sharing tab
  Sharing/               Cloudflare R2 credentials, SigV4 signing, uploads, share manifest
  Views/                 Menu bar popover, toasts, glass surfaces, transfer status card
  BetterShot/            Annotation editor (Anno*/Annotation*), recording studio (Recording*),
                         screen recording manager, teleprompter, 2D geometry and stroke pipeline
Resources/
  Assets.xcassets/       App icon, menu bar icon
  Backgrounds/           Bundled wallpaper and gradient images
  Info.plist
  BetterShot.entitlements
Tests/                   Standalone swiftc checks, run by scripts/run-checks.sh
scripts/                 run-checks.sh, release.sh, generate-icons.py
bettershot-landing/      Website (separate Node project)
```

`Sources/BetterShot/` is flat and large. File name prefixes are the grouping:
`Anno*` and `Annotation*` for the screenshot editor, `Recording*` for capture
and the studio, `Teleprompter*`, and the unprefixed geometry files
(`Vec`, `Mat`, `GeoPaths`, `StrokeOutline`, `PerfectDash`, ...).

### Key files

| File | What it does |
|---|---|
| `App/BetterShotApp.swift` | Declares the Annotate and Recording Editor `WindowGroup`s and wires the AppKit side (preview card, menu bar, recording finish) to `openWindow` |
| `Capture/CaptureOrchestrator.swift` | Screenshot pipeline: capture > sound > history > beautify > save > preview or editor |
| `Capture/ScreenCapture.swift` | Region, fullscreen, window capture and OCR |
| `Capture/RegionSelectionOverlay.swift` | BetterShot's own region picker with resize handles and the last-region ghost |
| `Services/ShortcutService.swift` | Global keyboard shortcuts via CGEvent tap, user rebinding |
| `Services/BeautifierRenderer.swift` | Composites background + padding + radius + shadow for the auto-beautified export |
| `Preview/PreviewOverlay.swift` | Floating deck of capture cards after a screenshot or recording |
| `History/HistoryStore.swift` | Capture records, retention trimming, beautified path mapping |
| `BetterShot/AnnotationEditorWindow.swift` | Annotation editor window: canvas, inspector, toolbar, save/copy/upload |
| `BetterShot/AnnotationEditorModel.swift` | Editor state: tool, selection, undo/redo, crop, interaction entry points |
| `BetterShot/AnnoEditorInteraction.swift` | Mouse-down/drag/up per tool: creating and editing shapes |
| `BetterShot/Shape.swift` | `AnnoShape` data model and per-kind props (geo, arrow, text, redaction, ...) |
| `BetterShot/AnnoShapeDrawing.swift` | The single CoreGraphics drawing path shared by the live canvas and the export |
| `BetterShot/AnnotationRenderer.swift` | Flattens a document (background, mockup effects, shapes) to an image for save/copy |
| `BetterShot/AnnotationDocument.swift` | Codable sidecar so an annotated screenshot reopens with its layers intact |
| `BetterShot/AnnotationBackground.swift` | Background, screenshot border, 3D camera, progressive blur, watermark settings |
| `BetterShot/ScreenRecordingManager.swift` | ScreenCaptureKit capture of a display, window, or area; audio, camera, pointer, pause/resume |
| `BetterShot/RecordingSession.swift` | A recording is a `.bettershotrec` folder: screen, camera, pointer sidecar, edit document |
| `BetterShot/RecordingPickerBar.swift` | The all-in-one floating bar `⌘⇧2` opens (screenshot actions + recording sources) |
| `BetterShot/RecordingStudioModel.swift` | Studio state: clip timeline, zoom cues, style, transcript, playback, undo/redo |
| `BetterShot/RecordingStudioWindow.swift` | Studio UI: canvas, inspector, timeline lanes, transport |
| `BetterShot/RecordingStudioExporter.swift` | Frame-by-frame export of the styled composition to MP4 |
| `BetterShot/RecordingProjectStore.swift` | Lists, renames, deletes, and opens recording projects |
| `Settings/PreferencesView.swift` | Settings sidebar: General, Capture, Recording, Shortcuts, Sharing, Screenshots, Recordings, About |
| `Models/AppPreferences.swift` | `bs_`-prefixed UserDefaults: save folder, export format, overlay, timer, retention, recording defaults |
| `BetterShot/BetterShotPreferences.swift` | Editor and recording-side UserDefaults, plus `ScreenshotFileActions` (copy, save, replace export) |
| `Sharing/R2Uploader.swift` | SigV4-signed uploads to the user's Cloudflare R2 bucket |

## How the code works

### Capture flow

```
User presses ⌘⇧4 (or picks Region on the bar)
  → ShortcutService (CGEvent tap intercepts the keypress, captures origin screen)
  → CaptureOrchestrator.performCapture(.region, on: screen)
  → ScreenCapture.captureRegion() (RegionSelectionOverlay, then screen capture)
  → HistoryStore.importCapture() (raw original into Application Support)
  → BeautifierRenderer.render() with the default config, saved to the save folder
  → PreviewOverlay.show(on: screen)  or  the Annotate window if "open editor after capture" is on
```

With **Keep screenshots in the deck until saved** on, the capture is staged in
`DeckStaging` instead of history and only promoted to the save folder when the
user saves, copies, drags, pins, or opens it.

All windows (editors, settings, preview deck, toasts, pinned screenshots) open
on the screen where the action originated, not the primary display.

### Recording flow

```
User presses ⌘⇧2 → RecordingPickerBar (screen / window / area / screenshot actions)
  → RecordingCaptureEntry.recordFullscreen / recordWindow / recordArea
  → optional countdown → ScreenRecordingManager.startRecording(source:)
     (SCStream for the screen, AVCapture for camera and mic, pointer + keystroke sidecars)
  → RecordingBarPresenter floating status bar (pause, stop, restart, discard)
  → stop → ScreenRecordingManager.onFinishRecording(session)
  → ScreenshotHistoryStore.importRecordingSession → RecordingProjectStore.reload
  → PreviewOverlay.show()  or  the Recording Editor window
  → RecordingStudioModel edits are autosaved to edit.draft.json
  → RecordingStudioExporter renders the final MP4 (or share upload)
```

### Storage

Everything lives under `~/Library/Application Support/BetterShot/`:

- Screenshots keep their untouched original there (`CaptureRecord.filename`);
  the beautified export goes to the user's save folder (`CaptureRecord.beautifiedPath`).
  `CaptureOrchestrator.resolveRawSource` maps an export back to its original so
  the editor reloads unflattened pixels. Re-exporting updates `beautifiedPath`
  in place instead of creating a second record.
- Annotated screenshots store an `AnnotationDocument` sidecar so layers survive reopening.
- Recordings are `Recordings/<name>.bettershotrec/` packages: `screen.mov`,
  `camera.mov`, `input.json` (pointer and keys), `capture.json`, `edit.json`
  (explicit save), `edit.draft.json` (autosave), `render.json`, `poster.jpg`,
  and the flattened deliverable. Sources are never modified; the studio
  re-renders non-destructively.

History keeps the most recent 100 captures by default (Settings > General,
up to 500 or unlimited). Trimming deletes only originals BetterShot owns, never
files in the save folder. `BetterShot/bases/` is a legacy directory; it is read
for old captures and pruned at launch.

### Annotation editor

```
AnnotationEditorModel (state, undo/redo, crop)
  ├── AnnotationInspector*      Right panel: tool style, background, border, camera, effects
  ├── AnnotationCanvas          Hosts the image, the CALayer canvas, crop and text overlays
  │     └── AnnoCanvasLayerView  Draws every shape through AnnoShapeDrawing
  ├── AnnoEditorInteraction     Per-tool mouse handling (create, move, resize, bind arrows)
  └── AnnotationKeyboard        Single-key tool shortcuts and editing commands
```

Shapes (`AnnoShape`) live in image pixel coordinates. The canvas and the export
both call `AnnoShapeDrawing.draw(document, in:target:)`, so there is one drawing
implementation to keep correct. `AnnotationRenderer` wraps that with the
background, mockup effects, and watermark for the flattened image.

### Recording studio

`RecordingStudioModel` owns a `RecordingEditDocument` (clips, speed, transitions,
crop, zoom cues, mask, style, camera bubble, captions). `RecordingStudioWindow`
renders the preview via `RecordingSessionRenderer` and the timeline lanes;
`RecordingStudioExporter` replays the same document frame by frame into an
`AVAssetWriter`. Style presets are stored by `RecordingStudioStylePresetStore`.

### Settings

`SettingsWindowController` hosts `PreferencesView` in an `NSWindow`. The sidebar
tabs are General, Capture, Recording, Shortcuts, Sharing, Screenshots,
Recordings, About. Screenshots and Recordings are the two library tabs, each
with On This Mac and Shared Links scopes.

Preferences are split across two enums: `AppPreferences` (`bs_` keys, the
capture pipeline and history) and `BetterShotPreferences` (editor, preview,
recording devices, teleprompter). Add to whichever the feature already reads from.

### Menu bar

`MenuBarPopoverController` creates a custom `NSPanel` (not `MenuBarExtra`) for
full control over appearance and animation and hosts `MenuBarContentView`.

## Common tasks

### Adding a new annotation tool

1. Add the case, `title`, and `systemImage` to `AnnotationTool` in `BetterShot/AnnotationTool.swift`
2. Add the shape kind and its props to `BetterShot/Shape.swift` (`AnnoShapeKind`, a `*Props` struct)
3. Handle creation and editing in `BetterShot/AnnoEditorInteraction.swift`
4. Draw it in `BetterShot/AnnoShapeDrawing.swift` (this covers both the live canvas and export)
5. Expose its style controls in `BetterShot/AnnotationInspector.swift`
6. Add the single-key shortcut in `BetterShot/AnnotationKeyboard.swift`
7. If the tool has defaults worth remembering, add them to `AnnotationPresetStore`

### Adding a new background type

1. Add the case to `BackgroundStyle` in `Models/BackgroundStyle.swift` (auto-beautify) and `AnnotationBackgroundStyle` in `BetterShot/AnnotationBackground.swift` (editor)
2. Handle rendering in `BeautifierRenderer.drawBackground` and `AnnotationBackgroundRenderer`
3. Add the picker UI in `AnnotationBackgroundInspector.swift` and `DefaultBackgroundPicker` in `Settings/PreferencesView.swift`
4. Make it round-trip through `StoredBackgroundStyle` in `AnnotationDocument.swift`

### Adding a new preference

1. Add the key and accessor to `Models/AppPreferences.swift` or `BetterShot/BetterShotPreferences.swift`
2. Add the control, with its one-line description, to the matching tab in `Settings/PreferencesView.swift`

### Adding a check

Tests are plain `main.swift`-style programs compiled with `swiftc`, no XCTest.
Create `Tests/YourThingCheck.swift`, `assert` or `precondition` what matters, and
print a one-line summary on success. If it needs real source files, list them
one per line in `Tests/YourThingCheck.sources`. Most checks copy the logic they
cover into the file instead, so they compile without AppKit.

## Code style

- **Swift 6 strict concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION` is `MainActor`; mark background work `nonisolated` or run it in `Task.detached`
- **`@Observable`** for model classes, `@Bindable` in views
- **No comments** unless explaining something non-obvious (a hidden constraint, a workaround)
- **No abstractions for their own sake**: three similar lines is better than a premature helper
- **System colors**: use `NSColor.controlBackgroundColor`, `.separatorColor`, etc. for native look
- **No new dependencies**: DockProgress is the only package

## Submitting a pull request

1. Create a branch: `git checkout -b feat/what-it-does` or `fix/what-it-fixes`
2. Keep changes focused, one feature or fix per PR
3. Make sure it builds: `make release` (what CI runs on every PR)
4. Run the checks: `scripts/run-checks.sh`
5. Test manually in the app
6. Write a clear PR title and description

### Make targets

| Command | What it does |
|---|---|
| `make generate` | Sync version from `version.json` into `project.yml` and regenerate the Xcode project |
| `make build` | Debug build (needs the maintainer's signing identity) |
| `make release` | Unsigned release build |
| `make run` | Debug build and launch |
| `make dmg` | Unsigned DMG for local testing |
| `make clean` | Remove build artifacts |
| `make lint` | Check for compiler warnings |
| `make test-build` | Full clean plus release build |
| `make version` | Print the current version |
| `make ship` | Signed, notarized release DMGs (maintainer only) |

### Commit messages

Use short, descriptive messages:

```
feat: add blur strength slider to redaction tools
fix: window capture failing on secondary monitors
chore: update dependencies
```

## Versioning

`version.json` is the single source of truth (`version`, `build`, `minimumOS`).
`make generate` copies it into `project.yml` and regenerates the Xcode project,
so never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand.
`CHANGELOG.md` documents what changed in each version.

## License

By contributing, you agree that your contributions will be licensed under the project's [BSD 3-Clause License](LICENSE).
