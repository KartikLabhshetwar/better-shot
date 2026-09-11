# Contributing to BetterShot

Read [AGENTS.md](AGENTS.md) before making changes. It defines the required UI
patterns, interaction rules, and persistence behavior for contributors and
coding agents. [CLAUDE.md](CLAUDE.md) imports the same rules for Claude Code.

## Build and run

**Requirements:** macOS 26.0+, Xcode 26+ with command-line tools, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/better-shot.git
cd better-shot
make release
open .build/Build/Products/Release/BetterShot.app
```

`make release` produces an unsigned build (used by CI). `make build` and
`make run` use the signing settings in `project.yml`. On a fork, select your
own team or Sign to Run Locally in Xcode. Do not commit personal signing
changes. Run `make generate` before opening `BetterShot.xcodeproj` to
regenerate the project from `project.yml`.

The app sets `SWIFT_VERSION: "5.0"` with main-actor default isolation and
approachable concurrency. Standalone checks compile in Swift 6 mode. Read the
project settings rather than assuming identical modes.

`make run` stops a running BetterShot process and opens the Debug build with
`open -n`. Finish active work before running it.

### Make targets

| Command | Purpose |
|---|---|
| `make generate` | Sync version/build from `version.json`, regenerate Xcode project |
| `make build` | Debug build with configured signing |
| `make release` | Unsigned Release build (CI) |
| `make run` | Debug build, stop old process, launch |
| `make test` | Unsigned build, standalone checks, editor snapshots, export integration |
| `make test-build` | Clean Release build |
| `make dmg` | Unsigned local-test DMG |
| `make clean` | Remove build artifacts |
| `make lint` | Print diagnostics (use a real build as the gate) |
| `make version` | Print version from `version.json` |
| `make ship` | Maintainer's signed/notarized release (not a dev check) |

### DMG installer

Install `create-dmg` with `brew install create-dmg`. Packaging needs a
logged-in desktop session with Finder automation permission.

```bash
make dmg
```

Or preview with an existing build:

```bash
bash scripts/create-dmg.sh .build/Build/Products/Release/BetterShot.app release/BetterShot-installer-preview.dmg
bash Tests/check-dmg.sh release/BetterShot-installer-preview.dmg .build/Build/Products/Release/BetterShot.app
```

`scripts/dmg-background.swift` draws the 660 x 440 pt background at 1x and 2x.
The clover volume icon comes from the built app. Verify the background and icon
positions survive remounting, and check the Applications link in both appearances.

## Project map

| Location | Responsibility |
|---|---|
| `Sources/App/` | App lifecycle, URL scheme handler, onboarding |
| `Sources/Capture/` | Screenshot capture, region selection, OCR, color picker |
| `Sources/Preview/` | Capture deck, pinned images, overlay layout |
| `Sources/History/` | Capture records, retention, path mapping |
| `Sources/Models/` | Preferences, capture records, gradients, onboarding state |
| `Sources/Services/` | Shortcut catalog/actions, framing, updater, grading |
| `Sources/Settings/` | General, Capture, Overlay, Recording, Shortcuts, Sharing, About |
| `Sources/Sharing/` | R2 credentials, request signing, uploads |
| `Sources/Views/` | Menu tray, glass surfaces, toasts, onboarding UI |
| `Sources/BetterShot/` | Image editor, video studio, renderers, geometry |
| `Resources/Assets.xcassets/` | Clover `AppIcon` and template `MenuBarIcon` |
| `Tests/` | Standalone checks and integration programs |
| `bettershot-landing/` | Separate Next.js website |

`Sources/BetterShot/` groups files by prefix: `Anno*`/`Annotation*` for image
editing, `Recording*` for video capture/studio, and `Teleprompter*` for the
script overlay.

## Key flows

### Screenshots

`ShortcutService` > `CaptureOrchestrator` > `ScreenCapture` > history/staging >
`BeautifierRenderer` > preview deck or image editor.

Region screenshots use `/usr/sbin/screencapture -i`. Source capture is PNG;
the export-format setting controls saved deliverables. Full-resolution editor
previews are the default.

Every screenshot starts in `DeckStaging`, regardless of capture mode or editor
preferences. Copy writes to the clipboard only, retaining a private temporary
file for file-based paste targets. Edit, Pin, Share, and drag-out retain source
pixels and previews inside BetterShot. Only Save/Export (or the explicit
capture-and-save shortcut) writes to the configured save folder. The deck
retention preference controls dismissal, not automatic saving.

### Recordings

`RecordingCaptureEntry` > `ScreenRecordingManager` > compact session bar
(Stop, Pause, Restart, Discard).

Area recordings use `RecordingAreaSelectionPresenter` with the adjustable AppKit
`RegionSelectionOverlay` and system crosshair. Screen, camera, pointer events,
and keys are kept as separate tracks.

### Editing and persistence

Image annotations live in source-pixel coordinates. `AnnoShapeDrawing` is shared
between the canvas and export. Recording packages contain `screen.mov`, optional
`camera.mov`, input/capture/edit JSON, and a flattened deliverable. Source movies
are never modified.

Saving annotations (Cmd+S) works for untouched screenshots too. It commits to
internal history, creates the first export in the configured folder, and updates
the associated export via atomic replace on later saves. Copy and Share do not
create or update that export. Export opens an NSSavePanel for a new destination.

General > Default Look supplies background, padding, corner radius, and shadow
for new images and videos. Saved projects retain their own settings.

The macOS cursor choice uses the classic Apple Poof artwork in `Resources/Cursors`
with a 2.5× starting size. Current AppKit returns an X badge for that system cursor,
so the bundled original preserves the cloud design. `PointerArtworkCapture` caches
the transparent source and click hotspot for preview/export. The standalone
integration runner copies the same resources beside its executable.

Screen/camera layout presets live in `RecordingStudioLayout` and apply to the
whole edited video. The Camera inspector exposes floating Bubble and Overlap,
Side-by-Side, Presenter, Camera Only, and Screen Only. Paired layouts can place
the camera on either side. Presenter fits the screen beside a full-height camera;
Side-by-Side respects the video Fill/Fit setting. Floating camera ratio/size/
rounding controls remain available. Selecting Bubble or Overlap restores the
compact 0.5.2 camera defaults (1:1, 26% size, 25% rounding), including reselection
of the active preset; undo restores the previous camera settings. Missing layout fields retain the legacy
bubble, and unavailable/hidden camera footage falls back to the screen. Preview,
export, project persistence, render-cache invalidation, and undo share the style.

### Shortcuts

`ShortcutCatalog.swift` is the source for action IDs, groups, scopes, and
defaults. Never renumber persisted IDs. New actions have no default binding.
Editor and global scopes may reuse keys; the active editor takes priority.
Global bindings require Command, Control, or Option.

### URL scheme

`CaptureURLAction` parses `bettershot://` URLs and routes them through
`BetterShotDelegate.application(_:open:)`. Supported paths: `capture/region`,
`capture/fullscreen`, `capture/window`, `ocr`, `color-picker`, `record`, and
`settings`. Unknown or malformed URLs are silently ignored. The recording guard
prevents stacking on an active session.

## Validation

```bash
make test
```

Builds unsigned, runs `scripts/run-checks.sh`, then `Tests/run-exports.sh`.
Tests use `BETTERSHOT_TESTING=1` to prevent real R2 Keychain access.

For the screenshot capture/Copy/Save regression checks alone (plus the build and
standalone checks), run `BETTERSHOT_CHECK_SCREENSHOT_SAVING=1 make test`. The
fixture drives the production post-capture pipeline without requesting screen
capture permission and isolates its history, deck, and save folder.

After a Debug test build, run just the compositor and encoded-video checks with
`BETTERSHOT_CHECK_VIDEO_EXPORTS=1 bash Tests/run-exports.sh`. This covers decoded
colors, masks, camera ratios, cached frames, both frame rates, audio, saved-render
invalidation, and cancellation with GPU frames in flight.

For an export performance comparison, use optimized objects and run the benchmark
without concurrent builds. It exports synthetic two-minute clips at 1080p60
(plain and heavy effects) plus a heavy-effects 30 fps variant, with test-only audio
and upload preparation. It does not upload or read R2 credentials.

```bash
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  SWIFT_COMPILATION_MODE=incremental build
BETTERSHOT_BUILD_CONFIGURATION=Release BETTERSHOT_BENCHMARK=1 bash Tests/run-exports.sh
```

Export cadence and the motion-blur shutter use the same frame-rate setting.
Missing frame-rate fields in older projects resolve to 60 fps. The shared
compositor keeps decoded media and filtered masks on the GPU through NV12
encoder buffers; Quartz supplies static decoration, cursor artwork, and text.
See [export-performance.md](docs/export-performance.md) for measurements.

For focused iteration, run the relevant standalone check directly. For a new
geometry rule or nontrivial branch, add a small regression check against
production code using `Tests/NameCheck.sources`.

Editor snapshots appear in `.build/editor-snapshots/`. Check light/dark and
narrow layouts. Offscreen snapshots cannot validate live AVPlayer layers,
native toolbars, global shortcuts, capture selection, or permissions. For
relevant changes, check these manually and report gaps honestly.

For website changes, run `pnpm lint` and `pnpm build` from `bettershot-landing/`.

## Submitting changes

1. Read the existing code before editing. For maintainer work, commit and push
   directly to `main` as requested; do not create a PR unless explicitly asked.
   External contributors should use a focused branch and PR.
2. Follow [AGENTS.md](AGENTS.md). Preserve user data and native accessibility.
3. Run `make test`. CI runs `make release` via `.github/workflows/build.yml`.
4. For UI changes, include screenshots and describe the interactions tested.
5. Explain the problem, solution, validation, and any limits in the PR.
6. Update [CHANGELOG.md](CHANGELOG.md) and [README.md](README.md) when behavior changes.

`version.json` is the version source (`version`, `build`, `minimumOS`).
`make generate` syncs it into the project. Do not publish binaries or mark a
version shipped without an explicit release request. Keep historical changelog
entries and contributor credit.

Use short, descriptive commit messages: `fix: preserve cursor hotspot in Retina
exports`. Do not commit signing credentials, generated builds, or local config.

## License

Contributions are licensed under the project's [BSD 3-Clause License](LICENSE).
