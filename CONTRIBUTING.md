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
pixels and previews inside BetterShot. Save/Export, the explicit capture-and-save
shortcut, or opt-in automatic saving writes to the configured save folder.
General > Saving enables automatic saving for normal captures; explicit Copy,
Edit, and Pin shortcuts bypass it. The new `afterCapture.screenshot.save` key
defaults off and deliberately ignores dormant legacy `autoSaveScreenshots` values.
Successful automatic saves retain the preview/editor and associate the export
with the untouched source; failures keep the card open for Save retry. The deck
retention preference controls dismissal, not automatic saving.

### Recordings

`RecordingCaptureEntry` > `ScreenRecordingManager` > compact session bar
(Stop, Pause, Restart, Discard).

Area recordings use `RecordingAreaSelectionPresenter` with the adjustable AppKit
`RegionSelectionOverlay` and system crosshair. Screen, camera, pointer events,
and keys are kept as separate tracks.

### Gallery and Settings

Media Gallery uses `NavigationSplitView` and a native toolbar with compact icon/list views.
Keep section titles and search in the detail column, with the system sidebar toggle
and resizable sidebar. Icon previews fit within 64 pt without cropping; filenames
carry the blue selection highlight. Grid keyboard movement must use the same
column width, spacing, and insets as the displayed grid.
On this Mac and Cloud Shares each expose All Media, Screenshots, and Videos;
local availability and a saved cloud link are independent, so an item can appear
in both. Use the shared file-type resolver for legacy/imported videos and resolve
recording previews from the package when flattened exports change.
Keep single-click selection, double-click opening, keyboard access, contextual
actions, and local/cloud deletion confirmations consistent across both views.
Gallery list view uses SwiftUI Table with native column sorting. Settings uses the
same native navigation columns with its title above the detail pane, a
searchable sidebar, neutral SF Symbols, one native toolbar title, and grouped
native forms; preserve existing preference bindings and the shared InspectorSlider
controls.

### Editing and persistence

Both editor scenes use minimum-content sizing with no content-derived maximum.
The shared window modifier enables native full screen even when automatic
full-screen opening is off, and focuses windows opened from overlays. The menu
tray monitors same-app and other-app clicks, passes editor clicks through, and
closes synchronously before capture or recording-picker actions. Remove both
event monitors when the tray closes.

Image annotations live in source-pixel coordinates. Rotation and flips write a private
full-resolution PNG through `AnnotationImageTransform`, preserving the capture.
Reflect shapes through `pageTransform` so text, arrows, and redactions follow
the same pixels; missing `mirrored` values in older documents mean no reflection.
Image-change snapshots retain the engine’s undo/redo stacks, and new annotation
edits invalidate image redo. Keep transform actions in the existing image toolbar
and preserve the shared save/copy/export/share rendering path.

`AnnoShapeDrawing` is shared between the canvas and export. Recording packages
contain `screen.mov`, optional
`camera.mov`, input/capture/edit JSON, and a flattened deliverable. Source movies
are never modified.

Saving annotations (Cmd+S) works for untouched screenshots too. It commits to
internal history, creates the first export in the configured folder, and updates
the associated export via atomic replace on later saves. Copy and Share do not
create or update that export. Export opens an NSSavePanel for a new destination.

General > Default Look supplies background, padding, corner radius, and shadow
for new images and videos. Saved projects retain their own settings.

`ScreenshotFileNaming` names every deliverable from the template stored under
`bs_fileNameTemplate`. `currentFileName` is the only path that advances
`{counter}`, so Settings can preview a template without spending a number.
Recording packages keep their own `BetterShot_<timestamp>_<id>.bettershotrec`
directory name because that name is the project's identity in the gallery; only
the copy leaving for the save folder is renamed. The renderer is pure and
Foundation-only so `Tests/FileNamingCheck.swift` can compile it on its own.

The Arrow cursor choice uses a stemless black arrow with a white outline and a
2.5× starting size. `PointerArtworkCapture` caches the 32× raster and arrow-tip
hotspot for preview/export; the `macOS` storage key remains compatible.

Padding accepts 0% in General and both editors. No Background removes decorative
framing without erasing saved padding/corner/shadow values, so selecting a fill
restores them. Untouched screenshots keep their pixels; explicit image effects
still render on transparency. MP4 has no alpha channel: any areas uncovered by
reframing or camera layouts remain black, consistently in preview and export.

Color picking uses a retained `NSColorSampler`. Convert to sRGB before reading
components, reject unsupported/non-finite colors, and clamp to six-digit hex.
Cancellation leaves the clipboard unchanged. Toast panels own their measured
size with hosting sizing options disabled to avoid recursive window constraints.

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

With existing Screen Recording permission, run
`BETTERSHOT_CHECK_LIBRARY_WINDOWS=1 make test` to also display and capture the
gallery icon/list and Settings windows at compact and wide sizes in both
appearances. These test-only windows use fixture media and isolated credentials.
Use their `*-window-*-780.png` / `*-window-*-1080.png` images to review native
materials: offscreen `cacheDisplay` snapshots cannot render the system sidebar
and search surfaces reliably.

Run `BETTERSHOT_CHECK_EDITOR_WINDOWS=1 make test` to display the production
image/video editor views and check overlay opening, focus, automatic/manual full
screen, exit from full screen, same-app tray dismissal, Escape, and recording
picker handoff. With existing Screen Recording permission, this also performs
full-screen screenshots into isolated test storage while each editor is open.
It does not automate region selection or start a microphone/camera recording.

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
