# Contributing to BetterShot

Thanks for helping improve BetterShot. Contributions can be code, documentation,
clear bug reports, or feedback on accessibility and everyday workflows.

This guide covers getting a development build running, finding the right code,
and validating a change. Read [AGENTS.md](AGENTS.md) before editing: it is the
shared source of truth for native UI, capture behavior, persistence, and agent
rules. [CLAUDE.md](CLAUDE.md) imports those same instructions. Our
[Code of Conduct](CODE_OF_CONDUCT.md) applies to project participation.

[Getting started](#getting-started) · [Code map](#code-map) ·
[Making a change](#making-a-change) · [Validation](#validation) ·
[Submitting changes](#submitting-changes)

## Before you start

Search [existing issues](https://github.com/KartikLabhshetwar/better-shot/issues)
for related work. Small fixes and documentation improvements can go straight to
a pull request. For a substantial feature or a change to an established workflow,
open an issue describing the problem and proposed behavior first.

A useful bug report includes:

- BetterShot version, macOS version, and Mac architecture.
- Steps to reproduce, expected behavior, and actual behavior.
- Relevant context, such as multiple displays, capture mode, or export settings.
- A screenshot, short recording, or error message when available, with private
  information removed.

## Getting started

### Requirements

- macOS 26 or later.
- Xcode 26 or later, including its command-line tools. Open Xcode once to finish
  setup and select it under **Xcode > Settings > Locations > Command Line Tools**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), available through Homebrew.

Check the active toolchain with `xcodebuild -version`. Apple's standalone Command
Line Tools installation does not replace the full Xcode app for this project.

### First build

Fork the repository on GitHub, then clone your fork (replace `YOUR_USERNAME`):

```bash
brew install xcodegen
git clone https://github.com/YOUR_USERNAME/better-shot.git
cd better-shot
git switch -c fix/describe-the-change
make release
open .build/Build/Products/Release/BetterShot.app
```

`make release` generates the Xcode project and produces an **unsigned Release
build**. It is the simplest build path for a fork and the one CI uses. No
maintainer signing identity or cloud credentials are needed to build or test.

### Working in Xcode

```bash
make generate
open BetterShot.xcodeproj
```

Choose your own signing team or **Sign to Run Locally** for interactive development.
Keep signing changes local. `make build` and `make run` inherit the signing settings
in [project.yml](project.yml), which reference the maintainer's identity.

Treat `project.yml` as the project configuration source. `make generate` regenerates
the project and syncs version/build values from [version.json](version.json), so
changes made only in the generated project may be overwritten.

The app uses Swift 5 language compatibility with main-actor default isolation and
approachable concurrency. Standalone checks compile in Swift 6 mode. Keep the
existing compiler settings unless changing them is the task itself.

### Everyday commands

Run these from the repository root:

| Command | Purpose |
| --- | --- |
| `make generate` | Sync version/build and regenerate the Xcode project |
| `make release` | Build unsigned Release, as CI does |
| `make build` | Build Debug with configured signing |
| `make run` | Build Debug, stop the running BetterShot process, and launch the new app |
| `make test` | Build unsigned Debug and run standalone, editor, and export checks |
| `make test-build` | Clean and build unsigned Release |
| `make clean` | Remove build artifacts |
| `make version` | Print the version from `version.json` |

**Finish active captures and save your work before `make run`**: it terminates the
running app. `make lint` can display compiler diagnostics, but its recipe can
mask a failed build; use a real build or `make test` as the gate.

### Website development

[bettershot-landing/](bettershot-landing/) is a separate Next.js/React/Tailwind
project. It is not part of the native app build. With Node.js and pnpm installed:

```bash
cd bettershot-landing
pnpm install --frozen-lockfile
pnpm dev
```

Before submitting website changes, run `pnpm lint` and `pnpm build` from that
directory. Follow the website rules in [AGENTS.md](AGENTS.md), including use of
existing Tailwind tokens, `cn`, and installed Radix components. Website-only
changes do not need README or changelog edits unless explicitly requested.

## Code map

| Location | Start here for |
| --- | --- |
| [Sources/App/](Sources/App/) | App lifecycle, onboarding, and URL actions |
| [Sources/Capture/](Sources/Capture/) | Screenshot orchestration, selection, OCR, and color picking |
| [Sources/Preview/](Sources/Preview/) | Floating capture deck, private staging, and pinned images |
| [Sources/History/](Sources/History/) | Capture records, retention, and source/export path resolution |
| [Sources/Models/](Sources/Models/) | Preferences, capture models, backgrounds, and onboarding state |
| [Sources/Services/](Sources/Services/) | Shortcut catalog and dispatch, image framing, and updater |
| [Sources/Settings/](Sources/Settings/) | Native settings and preference bindings |
| [Sources/Sharing/](Sources/Sharing/) | R2 credentials, signed requests, uploads, and share manifests |
| [Sources/Views/](Sources/Views/) | Menu tray, onboarding views, shared surfaces, and status toasts |
| [Sources/BetterShot/](Sources/BetterShot/) | Image editor, recording, video studio, and rendering |
| [Resources/](Resources/) | App/menu icons, backgrounds, entitlements, and onboarding media |
| [Tests/](Tests/) | Standalone regression checks and integration programs |
| [bettershot-landing/](bettershot-landing/) | Website and public share viewer |

Inside `Sources/BetterShot/`, look for `Anno*` and `Annotation*` files for image
editing, `Recording*` for video capture and editing, and `Teleprompter*` for the
script overlay.

## Making a change

Trace the user action through its callers, storage, preview, and export before
editing. Reuse existing helpers and native controls; fix shared behavior where
all affected callers meet. Keep unrelated cleanup out of the diff.

### Capture and saving

The screenshot path runs through `ShortcutService`, `CaptureOrchestrator`,
`ScreenCapture`, private staging/history, and the preview or image editor.
Region screenshots use macOS's native `/usr/sbin/screencapture -i` selector.
Window screenshots use `SCContentSharingPicker` and `SCScreenshotManager.captureImage`
in the app process; preserve picker cancellation, native pixel dimensions, and private PNG staging.
OCR and color results share `CaptureOrchestrator.completeTextCapture`: copy the exact
value and persist typed text/color results only when Notch Mode is active. Empty OCR must not erase the clipboard.
Notch Mode must not show toasts. Mark `ToastWindow.show` failures with `isError: true`
so recovery instructions appear inline; successes stay quiet or update their action
button. Export/share progress continues through the embedded `TransferStatusCard`.
Recording areas use BetterShot's adjustable AppKit selector.
`RecordingPickerControls` and `RecordingOptionsView` are shared by the bar and notch.
Run `BETTERSHOT_CHECK_CAPTURE_UI=1 bash Tests/run-exports.sh` after building for
focused light/dark capture layout checks without generating a video fixture.
The notch shelf uses `NotchRecentCaptures.mediaURLs` to merge pending and recent
media without duplicates. Reuse `PreviewCardView` and `PreviewOverlay.perform` for
card rendering/actions; notch sizing must not change the normal overlay.
`NotchQuickEditor` reuses `AnnotationCanvas`, `AnnotationRenderer`, and editable
history sidecars. Done saves privately; it must not update an exported file.
`NotchVoiceCapture` handles the configurable hold key through the existing `ShortcutService` event tap. Draw on screen is the default: snapshot the display, open the production canvas full-screen with a red freehand tool, and route held strokes through its model. Buffer mouse events during capture preparation; finish on modifier release after the final mouse-up. Drawing alone must not request microphone access. Escape preserves the editor's discard confirmation. Select an area remains available through `RegionSelectionOverlay` and `captureLastRegion`. Keyboard chords cancel arming. Both notch shapes use the kit's outline color for active-hold feedback; keep that stroke non-interactive. The folder menu dispatches OCR/color through `CaptureOrchestrator`, with shortcut labels from `ShortcutService`.
Option voice capture observes modifier state only when enabled and when Option is not the capture hold key; never retain plain keystrokes. Microphone capture ends before on-device transcription, with temporary
audio retained only for retry until completion/discard. Reuse
`RecordingTranscriptionService.transcribeAudio` rather than adding a cloud service.
`NotchShelfStore` keeps bounded OCR/color history only in Notch Mode, plus opt-in clipboard text and separately configurable standalone hex-color collection (on by default), and checks private pasteboard
markers before reading text. Test with isolated pasteboards and storage only.
After building, `BETTERSHOT_CHECK_LOCAL_SHELF=1 bash Tests/run-exports.sh` checks
persistence, copying and quick-edit rendering without live capture. An optional
`BETTERSHOT_SPEECH_FIXTURE` path can supply synthesized speech saying “button” and
“smaller” to validate the actual on-device transcription engine.
Keep source selection separate from starting a recording, preserve permission checks
for camera/microphone, and keep screenshot and recording delays distinct.

Every screenshot starts in `DeckStaging`. Copy only updates the clipboard and
retains a private file for file-based paste targets. Edit, Pin, Share, and drag-out
retain working files internally. Only explicit Save/Export, capture-and-save,
or opt-in automatic saving writes a deliverable to the configured folder.
Automatic saving defaults off, bypasses explicit Copy/Edit/Pin actions, and
retains failed captures for retry. Preserve this distinction across all callers.

Image-editor Save commits to history and creates or atomically replaces the
associated export, even for an untouched image. Copy and Share do not update
that export. Export opens a save panel for a new destination.

[ScreenshotFileNaming](Sources/BetterShot/ScreenshotFileNaming.swift) is the shared,
Foundation-only deliverable name renderer. Preserve sanitization and keep
previews from advancing counters. Recording package directory names identify
projects and must not change with the deliverable template.

### Editing, rendering, and persistence

Image annotations use source-pixel coordinates. `AnnoShapeDrawing` is shared by
the canvas and export; `AnnotationImageTransform` handles full-resolution rotation
and reflection while retaining editable annotations and undo history. A
low-resolution preview must never become an export source.

Recording capture starts at `RecordingCaptureEntry` and `ScreenRecordingManager`.
Packages retain `screen.mov`, optional `camera.mov`, input/capture/edit metadata,
and a flattened deliverable. Source movies remain unchanged. Input capture is
limited to the supported pointer and shortcut events; never record plain typing.

`RecordingStudioLayout`, in
[RecordingStudioStyle.swift](Sources/BetterShot/RecordingStudioStyle.swift), supplies
shared screen/camera geometry. Preview, export, saved projects, undo, and render
cache invalidation must agree on camera layouts, crop, masks, cursor styling,
and effects. Camera frame ratio is independent of canvas ratio. Older projects
must retain compatible defaults and saved artwork, including legacy Hand cursors
and the `macOS` storage key for Arrow.

`GradientPreset.presets` in [BackgroundStyle.swift](Sources/Models/BackgroundStyle.swift)
is the palette source. General > Default Look initializes new media; editing a
saved project must not overwrite those defaults. No Background retains framing
settings for reuse. MP4 has no alpha channel, so uncovered areas render black.

### UI, shortcuts, and automation

Use the shared editor chrome, inspector components, and `InspectorSlider`; keep
both inspectors on the left. Preserve keyboard focus, text editing, accessible
action names, light/dark appearances, and reduced transparency/motion. The full
interaction requirements live in [AGENTS.md](AGENTS.md).

Media Gallery treats local availability and cloud links independently: a shared
item with a local source belongs in both locations. Preserve package-based
resolution when recording exports move or disappear, native table sorting,
single-click selection, double-click opening, and deletion confirmations.
Gallery and Settings use resizable native navigation columns.

[ShortcutCatalog.swift](Sources/Services/ShortcutCatalog.swift) defines action IDs,
groups, scopes, and defaults. Do not renumber persisted IDs. New actions start
unassigned; customized and disabled bindings must survive migration. Active
editor bindings take priority over matching global bindings without intercepting
normal text-field behavior.

[CaptureURLAction.swift](Sources/App/CaptureURLAction.swift) parses the supported
`bettershot://` routes. The app delegate dispatches them. Preserve malformed-URL
rejection and the guard against starting a second recording session.

### 3D video shots

`Recording3DShot.swift` owns pose limits, perspective projection, presets, and the
sorted, binary-searched shot timeline. Times refer to the edited movie, as mask
ranges do; clip trims/speed changes clamp the effective track without deleting
authored shots. Missing `shots3D` fields mean no effect in legacy projects.
`RecordingStudioModel` handles undo, draft/save/discard, and render invalidation.
`Recording3DInspector` and `Recording3DLane` use the existing inspector controls.
The timeline’s **+ Add** menu creates Zoom and 3D Shot segments at the playhead.
Only allocate the cut-marker row when there are cuts; lane backgrounds, edit
content, and total height must use the same visibility rules.

The optional `Recording3DPose.camera` stores independent camera orbit, screen
fold, distance, vertical field of view, and camera-plane pan. Legacy poses omit
it and keep the previous projection. Preset selection writes both endpoints,
linear timing, and zero boundary transition; angles include a slow drift, with
Still available explicitly. Named scenes retain their relative shot durations.

`Recording3DTimeline.autoScene` shares Cap's scene pool, one-second minimum,
weighted boundaries, and nearby clip-cut snapping with named scenes. Short ranges
use a prefix of the scene; manually authored/legacy shots retain their 0.2-second
minimum. Clip boundaries come from cumulative edited durations, including speed.
`suggested3DScene` is transient: only `previewTimeline3D` reads it. Cancel restores
the playhead, Apply writes one undoable edit, and save/export never read suggestions.
Keep Looks, Camera, Depth Blur, Keyframes, and Timing expanded as separate cards. The
fixed section shortcuts above the inspector scroll to their section IDs; do not
hide granular controls behind an Edit menu. Screen fold and lens controls stay
visible with the other camera sliders. Animated-property buttons select the
existing keyframe editor, including its graph and numeric Bézier handles.
Start/End thumbnails select the pose being edited. `Recording3DOrbitPad` changes
only its tilt axes through the same model update and undo group as numeric entry;
disable the pad while either axis has keyframes. Keep exact sliders available
for keyboard and accessibility use. Preset/scene grids adapt to inspector width.

`Recording3DAnimation` stores optional focus settings and per-property keyframes.
Keyframe positions are fractions of a shot, so resizing preserves relative timing.
Tracks are normalized at edit/load time and binary-searched while rendering;
Bézier control points are bounded and inverted with a fixed iteration limit.
Format 8 keeps new fields optional for older projects; independent entry/exit
times fall back to the legacy shared transition. Reversing or flipping
shots also transforms their curves and focus settings.

For projects with 3D shots, `Recording3DPreview` reads AVPlayer video outputs and
uses `StudioFrameCompositor.composedImage` directly in a Metal view. Keep at most
two preview frames in flight and remove the outputs when the view disappears.
The preview player supplies already-masked pixels; the compositor must not apply
those masks a second time. Subtitles stay in SwiftUI, above the effect.

Preview and export share one perspective warp plus `Recording3DBlurRenderer`’s
Gaussian/three-ring disc kernels adapted from Cap. Kernels compile once, and blur
strength scales from
1080p, and the None/flat paths skip the extra passes. The screen, masks, pointer,
and camera share the transform. Keyboard captions stay sharp above blur, while
the background stays in canvas space
and participates in focus blur. Crop and mask editing keep the native flat player
so source-coordinate handles remain usable. No video pixels are read back to CPU.

The inverse warp clips rays behind the camera instead of pulling the camera back.
A transparent full-canvas input prevents texture-edge clamping from filling padded
areas with video. Zoom magnifies this whole plane and recenters its target, while
flat card/camera shadows fade with shot activity. Gaussian taps use bilinear pairs
with unchanged weights; the reference radius cap bounds the loop at 160 pixels.

`Tests/Fixtures/Cap3DReference.json` contains all 13 upstream presets and 248
geometry/zoom/transition cases generated by compiling Cap's actual `camera3d.rs`.
`Cap3DScenes.json` adds 138 auto/named scenes generated by executing the upstream
`three-d.ts`, covering short clips, minimum durations, weighted timing, cut
snapping, and all endpoint/blur values. Both fixtures use the same pinned commit.
Regenerate from a pinned Cap checkout with `python3 scripts/generate-cap-3d-reference.py /path/to/Cap`
(requires Bun and Rust only for regeneration). Normal tests consume the fixture
without network access or an upstream runtime. The GPU checks separately cover
ring positions/highlight gain, Gaussian impulse weights, horizon clipping,
transparent padding, shadow suppression, and whole-card zoom.

Adapted rendering code carries Cap's AGPLv3 attribution and license in
`Resources/Licenses/`, bundled with the application. Keep those notices and the
corresponding-source/build instructions with distributions; see that folder's
`NOTICE.md` and the repository `LICENSE`.

`make test` includes projection/normalization checks, model persistence/undo,
compact light/dark snapshots, production compositor checks, and encoded 30/60 fps
video checks. For focused checks after a build:

```bash
BETTERSHOT_CHECK_3D_ONLY=1 bash Tests/run-exports.sh
# With existing Screen Recording permission, capture displayed player windows:
BETTERSHOT_CHECK_3D_ONLY=1 BETTERSHOT_CHECK_3D_WINDOWS=1 bash Tests/run-exports.sh
# With optimized Release objects, measure warm 1080p/4K transform, Gaussian, and bokeh GPU frame times:
BETTERSHOT_DERIVED_DATA=.build BETTERSHOT_BUILD_CONFIGURATION=Release BETTERSHOT_CHECK_3D_ONLY=1 BETTERSHOT_BENCHMARK_3D=1 bash Tests/run-exports.sh
```

Offscreen snapshots do not validate live AVPlayer layers. The optional window
check plays and seeks the production editor in both appearances using fixture
media. It does not automate pointer dragging or keyboard entry in the controls.

## Validation

### Native changes

```bash
make test
```

This builds unsigned Debug in `.build/tests` with testability enabled, runs
[scripts/run-checks.sh](scripts/run-checks.sh), then
[Tests/run-exports.sh](Tests/run-exports.sh). The runners set
`BETTERSHOT_TESTING=1` so tests use isolated storage and do not access real R2
Keychain credentials. The separate test build directory keeps unsigned tests from replacing
a running signed dev app and invalidating its Screen Recording permission. Quit the dev
app before rebuilding its `.build` bundle. Always use the runners; never substitute production
credentials to make a test pass.

For a logic regression, add a small check against production code. Standalone
checks are `Tests/*Check.swift`; an optional matching `.sources` file lists the
production files to compile. For example, [FileNamingCheck.sources](Tests/FileNamingCheck.sources)
points directly to the production filename renderer. Run the standalone suite
with `bash scripts/run-checks.sh`.

### Focused integration checks

After `make test` has produced Debug objects, these commands reuse them. Rebuild
with `make test` when production code changes.

| Area | Command |
| --- | --- |
| Notch hover, preview actions, and compact/expanded snapshots | `BETTERSHOT_CHECK_NOTCH=1 bash Tests/run-exports.sh` |
| ScreenCaptureKit window pixels, native resolution, staging, and preview in both modes (requires existing Screen Recording permission) | `BETTERSHOT_CHECK_WINDOW_CAPTURE=1 bash Tests/run-exports.sh` |
| Screenshot Copy/Save and private storage | `BETTERSHOT_CHECK_SCREENSHOT_SAVING=1 bash Tests/run-exports.sh` |
| Video compositing and encoded exports | `BETTERSHOT_CHECK_VIDEO_EXPORTS=1 bash Tests/run-exports.sh` |
| Displayed Gallery and Settings windows | `BETTERSHOT_CHECK_LIBRARY_WINDOWS=1 bash Tests/run-exports.sh` |
| Editor focus, full screen, and tray handoff | `BETTERSHOT_CHECK_EDITOR_WINDOWS=1 bash Tests/run-exports.sh` |
| Actual SwiftUI editor scenes, automatic/manual full screen | `BETTERSHOT_CHECK_EDITOR_SCENES=1 bash Tests/run-exports.sh` |

The screenshot check uses the production post-capture path with fixture media;
it does not request capture permission. Video checks cover decoded colors,
masks, camera ratios, cached frames, 30/60 fps, audio, render invalidation, and
cancellation with GPU work in flight.

Editor snapshots are written to `.build/editor-snapshots/`. Review narrow and
wide layouts in both appearances. Displayed-window checks need a logged-in
desktop session; Gallery/Settings screenshots also need existing Screen Recording
permission. Editor-window checks can exercise fullscreen captures with existing
permission, but do not automate region selection or start microphone/camera
recordings.

Offscreen snapshots cannot prove live AVPlayer rendering, native toolbars,
global shortcuts, capture selection, or permissions. Test affected interactions
manually and state what remains unverified.

### Export performance

Build optimized objects, then run the synthetic export benchmark without another
build running alongside it:

```bash
make generate
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  SWIFT_COMPILATION_MODE=incremental build
BETTERSHOT_DERIVED_DATA=.build BETTERSHOT_BUILD_CONFIGURATION=Release BETTERSHOT_BENCHMARK=1 bash Tests/run-exports.sh
```

It measures two-minute 1080p clips with plain and heavy effects, including 60/30 fps
variants and upload preparation. It does not upload or read R2 credentials.
See [export-performance.md](docs/export-performance.md) for workloads, measurements,
and their limits.

### Local installer checks

Install `create-dmg` with `brew install create-dmg`, then run `make dmg` for an
unsigned local-test installer. Packaging needs a logged-in desktop session and
Finder automation permission.

To package an existing Release build and validate the result:

```bash
bash scripts/create-dmg.sh .build/Build/Products/Release/BetterShot.app release/BetterShot-installer-preview.dmg
bash Tests/check-dmg.sh release/BetterShot-installer-preview.dmg .build/Build/Products/Release/BetterShot.app
```

Check the background, bundled clover volume icon, icon positions after remounting,
and Applications link in both appearances.

## Submitting changes

External contributors should open a focused PR from a branch on their fork.
Maintainer tasks go directly to `main` unless a PR is explicitly requested.

Before submitting:

- Explain the concrete problem and resulting behavior; link the relevant issue.
- Run checks appropriate to the change: `make test` for native logic/rendering,
  and `pnpm lint` plus `pnpm build` for the website. For documentation-only edits,
  verify commands and links against the repository; no native rebuild is needed.
- Include screenshots for UI changes and name the appearances, window sizes,
  and interactions actually tested. Report failures or gaps honestly.
- Update user and contributor documentation when behavior or workflows change,
  and add a changelog entry when appropriate. Preserve historical entries and
  contributor credit. Website-only work follows the documentation exception above.
- Review the diff for unrelated edits, personal signing identities, credentials,
  generated build output, and local configuration.

Use short, descriptive commit messages, such as
`fix: preserve cursor hotspot in Retina exports`. A PR description should let a
reviewer understand the problem, change, and validation without reading the
original conversation.

[CI](.github/workflows/build.yml) currently runs `make release` and checks that the
app exists. It does **not** run the full regression suite, so a green CI build
alone does not replace local validation.

[version.json](version.json) is the version source. Do not bump a version or
publish release binaries as part of a routine contribution. `make ship` is a
maintainer-only signed/notarized release workflow that depends on local release
tooling and credentials; it is not a development check. Releases require an
explicit maintainer request.

Contributions are licensed under the project's [BSD 3-Clause License](LICENSE).

### Tour and release notes

TourKit is a local Swift package in `Vendor/TourKit`, pinned to the upstream
revision and MIT license listed in `BETTERSHOT.md`. Its slideshow is hosted in the
existing native onboarding window; keep local appearance/accessibility patches
when updating it. The permission/restart flow and optional video demos remain
owned by BetterShot. Run `BETTERSHOT_TESTING=1 swift test --package-path Vendor/TourKit`
for the upstream package checks, and `make test` for app integration.

`CHANGELOG.md` is bundled directly. Every `version.json` version must have a
`## [x.y.z]` entry. `ReleaseNotes` parses these entries and tracks dismissed versions
separately from onboarding completion; do not reset either marker on upgrades.
The launch flow presents pending setup first, otherwise unread release notes,
then honors the capture-bar startup preference. Offline notes include skipped
versions; Settings → About can reopen the notes or tour.

3D insertion hover and click share `Recording3DTimeline.insertionRange`. Keep the
ghost non-interactive and avoid project mutations/render-cache invalidation while
skimming. Tests cover placement boundaries, undo/persistence, and compact light/dark
snapshots of the ghost, tour pages, and release notes.

### Notch presentation

Cancel pending hover dismissal during capture/mode changes and keep menus and
popovers open while in use.
Recent Captures reuses `MediaGalleryItem` resolution and `MediaGalleryCard` actions
and thumbnail decoding; do not add a second media store.

Settings > General > Capture Mode selects Normal Mode or Notch Mode and applies
immediately. Overlay settings customize normal mode’s floating preview cards.

`NotchPresenter` hosts the existing capture/session controls, preview cards, and
transfer cards. Keep actions in `RecordingBarPresenter` / `PreviewOverlay`; do not
add a second saving, copying, upload, or recording implementation. Normal mode is
the fallback for missing or unknown `bs_presentationMode` values. Mode changes
must preserve pending media, transfers, and active recording state.

Preserve capture exclusion before presentation, immediate capture/mode dismissal,
transparent margin hit testing, display selection, and accessibility. Expanded and
compact surfaces stay opaque black with native dark-appearance controls. Short
interruptible transitions respect Reduce Motion. Capture/Recents tabs reuse the
existing controls and media resolver; compact logo/status never shows a thumbnail
or capture count. `make test` exercises mode switching, hover cancellation,
menu/sheet protection, capture suspension, preview actions, transfer cleanup, and
both appearances. The opt-in window-capture check drives selection and Escape;
live recording and multi-display hardware still need manual checks.

Boring Notch's copied shape and adapted hover button/interaction code retain their
source credits and GPLv3 notices. See `Resources/Licenses/NOTICE.md` for the pinned
revision and exact file mapping; bundle `BoringNotch.txt` with distributions.

For window screenshot changes, also select a window and cancel with Escape in the
signed dev app. Standalone test executables use their terminal’s capture identity
and cannot establish that the installed app’s picker authorization works.
