# Contributing to BetterShot

Start with [AGENTS.md](AGENTS.md), which defines the required UI, interaction,
quality, and persistence rules for contributors and coding agents.
[CLAUDE.md](CLAUDE.md) imports the same guidance for Claude Code.

## Build and run

Requirements: macOS 26.0+, Xcode 26+ with its command-line tools selected, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

`make release` is the unsigned build used by CI and works without the maintainer's
Developer ID certificate. `make build` and `make run` use the signing settings
in `project.yml`; on a fork, select your own team or Sign to Run Locally in Xcode.
Do not commit personal signing changes. Run `make generate` before opening
`BetterShot.xcodeproj`; it regenerates the project from `project.yml`.

The project uses a modern Swift toolchain, but the app currently sets
`SWIFT_VERSION: "5.0"` with main-actor default isolation and approachable
concurrency. The standalone checks compile in Swift 6 mode. Read the project
settings rather than assuming the app and check runner use identical modes.

`make run` stops a running BetterShot process and opens the exact Debug app path
with `open -n`. Finish or save active work before running it. If Finder still
opens an older installed copy, check its path and version; do not delete user
preferences, capture history, or recordings to fix a launch-path issue.

### Permissions

Grant Screen Recording and Accessibility in System Settings > Privacy & Security.
Camera, Microphone, and Input Monitoring are requested when their features need
them. The keystroke overlay captures shortcuts and special keys, never plain typing.

### Make targets

| Command | Purpose |
|---|---|
| `make generate` | Read version/build from `version.json`, update `project.yml`, regenerate Xcode project |
| `make build` | Debug build using configured signing |
| `make release` | Unsigned Release build, also used by CI |
| `make run` | Debug build, stop the old process, launch this checkout's app |
| `make test` | Unsigned Debug build, standalone checks, editor snapshots, export integration |
| `make test-build` | Clean and build Release |
| `make dmg` | Create an unsigned local-test DMG |
| `make clean` | Remove build artifacts |
| `make lint` | Print compiler diagnostics; use a real build/test result as the build gate |
| `make version` | Print the version from `version.json` |
| `make ship` | Maintainer's signed/notarized release workflow; not a development check |

## Project map

| Location | Responsibility |
|---|---|
| `Sources/App/` | App scenes and AppKit-to-SwiftUI editor presentation |
| `Sources/Capture/` | Native screenshot capture, adjustable recording region control, OCR, color picker, countdown |
| `Sources/Preview/` | Capture deck, pinned images, unsaved capture staging |
| `Sources/History/` | Capture records, retention, raw/export path mapping |
| `Sources/Models/` | Preferences, capture records, shared gradient definitions |
| `Sources/Services/` | Shortcuts, screenshot framing, updater, grading, silence detection |
| `Sources/Settings/` | General, Capture, Recording, Shortcuts, Sharing, About |
| `Sources/Sharing/` | R2 credentials, request signing, uploads and manifests |
| `Sources/Views/` | Menu tray/popover, glass surfaces, toasts, transfer feedback |
| `Sources/BetterShot/` | Image editor, recording capture/studio, renderers, geometry and supporting models |
| `Resources/Assets.xcassets/` | BetterShot's clover `AppIcon` and template `MenuBarIcon` |
| `Resources/Backgrounds/` | Bundled background images; new gradient presets are defined in Swift |
| `Tests/` | Standalone checks and editor/export integration programs |
| `bettershot-landing/` | Separate Next.js website, with its own dependencies and lockfile |

`Sources/BetterShot/` groups files by prefix: `Anno*`/`Annotation*` for image
editing, `Recording*` for capture/studio, and `Teleprompter*` for the script overlay.
Search these existing implementations before adding another helper or component.

## Current UI contract

The full requirements live in [AGENTS.md](AGENTS.md). For a UI change, start here:

| Surface | Existing implementation to reuse |
|---|---|
| App/menu-tray identity | Bundled clover assets; `MenuBarPopoverController` restores `MenuBarIcon` after drag feedback |
| Action icons | Native `Label`, `Image(systemName:)`, and AppKit SF Symbols; no third-party icon mapping |
| Classic frosted editor chrome | `EditorChrome.swift`: `EditorButtonStyle`, `studioGlass`, `studioEffectCard` |
| Inspector spacing and fields | `AnnotationInspectorStyle.swift`: `InspectorMetrics` and shared inspector components |
| Amount controls | `AnnotationInspectorSlider.swift`: `InspectorSlider`, 0.4.0 label-in-track style and right-hand editable value across Settings and both editors |
| Capture/recording bars | `RecordingBarPresenter`, `RecordingPickerBar`, `RecordingBarChrome`; 64 pt / 38 pt heights |
| Image editor | `AnnotationEditorWindow` / `AnnotationEditorModel`; one tool row and left inspector |
| Video inspector | `StudioInspectorTabs` and `RecordingStudioWindow`; left rail, expanded effect cards |
| Timeline | `RecordingStudioWindow` and timeline models; zoom blocks above filmstrip, scissors/cut badges below |
| Export/share feedback | `TransferStatusCard`; compact corner card with native progress and short fades |
| Shared backgrounds | `GradientPreset.presets`, `GradientBackgroundView`, `AnnotationBackgroundStageFill` |

Keep slider field labels hidden inside Forms so the numeric value stays centered
in its right-hand field. Reuse `InspectorSlider` everywhere, including JPEG quality,
preview margin/dismissal, and timeline zoom. Preserve steps, units, exact entry,
and the Never dismissal option.

Keep Blur and Pixelate visible, hide editor scroll indicators without disabling
scrolling, and preserve tool toggling. Image tools return to Select on a second
click. Video Crop cancels its draft on a second click. Scissors starts off and
stays on across cuts until explicitly deselected. Crop Only refers to mask
coverage within the selected rectangle, not an export format or destructive crop.

## Capture and recording flows

### Screenshots

`ShortcutService` → `CaptureOrchestrator` → `ScreenCapture` → history/staging →
`BeautifierRenderer` → preview deck or image editor.

Region screenshots use `/usr/sbin/screencapture -i` and macOS's selection UI.
Fullscreen and window captures use the same native command. Source capture is
PNG; the user's export-format setting controls saved deliverables. Preserve raw
pixel dimensions and integer placement during framing. Full-resolution editor
previews are the default; exported content must always come from the full source.

When Keep screenshots in the deck until saved is enabled, `DeckStaging` holds
captures until Save, Copy, drag, Pin, or Edit promotes them. Preserve failure
recovery and the raw image so subsequent editing does not flatten twice.

`LastRegionGhostPresenter` can show an existing BetterShot remembered region when
the bar opens, and A recaptures it. The native screenshot selector does not write
BetterShot's remembered-region preference; do not document its keyboard behavior
as if it were `RegionSelectionOverlay`.

### Recordings

`⌘⇧2` opens the shared bar; `⌘⇧5` opens its Recording section. Source selection
flows through `RecordingCaptureEntry` to `ScreenRecordingManager`, then the
compact session bar provides Stop, Pause, Restart, and Discard.

Area recordings use `RecordingAreaSelectionPresenter` and the adjustable AppKit
`RegionSelectionOverlay` with the system crosshair. This is not Apple's system
recording picker. Keep correct display coordinates, Return/double-click
confirmation, cancellation, and capture-window exclusion.

The screen, camera, pointer events, and optional keys are kept separately.
`RecordingStudioModel` drives the live player, viewport/cursor timelines, masks,
and editing state. `RecordingStudioExporter` renders the composition with
`AVAssetWriter`; `RecordingSessionRenderer` also renders saved sessions for sharing.
Export containers include MOV and MP4; shared video is MP4.

### Editing and persistence

Image shapes live in source-image pixel coordinates. `AnnoShapeDrawing` is shared
by the live canvas and annotation export. `AnnotationRenderer` adds backgrounds
and effects. Use `ScreenshotHistoryStore.annotationEditorURL` to reopen the
editable document and untouched base rather than re-editing flattened output.

Recording packages contain `screen.mov`, optional `camera.mov`, `input.json`,
`capture.json`, explicit `edit.json`, autosaved `edit.draft.json`, `render.json`,
`poster.jpg`, and a flattened deliverable. Keep source movies intact. Changes to
cursor, crop, masks, zoom, and gradients must survive save/reopen and match exports.

Dark, Light, and Dot cursors are generated from vector paths into cached transparent PNGs.
Hand uses `NSCursor.pointingHand` through the same highest-resolution capture helper.
Their logical size and click hotspot are separate from raster dimensions. Keep
high-resolution representations, contrast outlines, and preview/export agreement.
Imported footage with its cursor already baked into the pixels cannot be restyled.

The ten soft gradients share stop positions, colors, and radial highlights through
`GradientPreset`. `StoredGradient` preserves these in projects. Keep old project
decoding supported even when the available preset palette changes.

Image defaults are in General > Default Look. Video defaults are in Recording >
Default Video Background, backed by `RecordingStudioDefaults.preferredBackground`.
Per-project video edits must not replace an explicitly configured default.

The native Settings sidebar has General, Capture, Recording, Shortcuts, Sharing,
and About. Recent captures are accessed from the menu; do not reintroduce removed
Settings library tabs as part of an unrelated change.

## Validation

```bash
make test
```

This builds without certificate signing, runs `scripts/run-checks.sh`, then
`Tests/run-exports.sh`. Test executables use `BETTERSHOT_TESTING=1` to prevent real
R2 Keychain access. Never request a login password or weaken credential storage
for tests. Test actual cloud sharing separately in the running app.

For a focused iteration, run the relevant standalone check or, after an unsigned
Debug build with `ENABLE_TESTABILITY=YES`, run `bash Tests/run-exports.sh`.
For a new nontrivial branch or geometry rule, add a small regression check against
production code. Use `Tests/NameCheck.sources` for required source files; do not
copy the implementation into a test that can drift independently.

Editor snapshots appear in `.build/editor-snapshots/`. Check light/dark and narrow
layouts. Offscreen snapshots do not validate live AVPlayer layers, native window
toolbars, global shortcuts, capture selection, or permission prompts. For relevant
changes, manually check these in the app and report remaining gaps honestly.

For website changes, use the existing `pnpm-lock.yaml` and run the relevant
commands from `bettershot-landing/`, such as `pnpm lint` and `pnpm build`.

## Submitting changes

1. Keep a focused branch and inspect the existing state before editing.
2. Follow [AGENTS.md](AGENTS.md), preserve user data, and retain native accessibility.
3. Run the relevant checks; CI currently runs `make release` via `.github/workflows/build.yml`.
4. For UI changes, include useful screenshots and describe the interaction tested.
5. Explain the concrete problem, final behavior, validation, and any material limits in the PR.
6. Update [CHANGELOG.md](CHANGELOG.md) and [README.md](README.md) when behavior changes.

`version.json` is the version source (`version`, `build`, `minimumOS`).
`make generate` syncs version/build into the project. Current pending changes belong
under **0.5.0 — Unreleased**; do not create a 0.4.3 release or mark 0.5.0 shipped
without an explicit release request. Keep historical entries and contributor credit.

Use short, descriptive commit messages, for example `fix: preserve cursor hotspot
in Retina exports`. Do not commit signing credentials, generated builds, or local
machine configuration.

## License

Contributions are licensed under the project's [BSD 3-Clause License](LICENSE).
