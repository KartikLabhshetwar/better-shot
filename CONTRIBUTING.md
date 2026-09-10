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

The onboarding Permissions step can request Screen Recording, Accessibility,
Input Monitoring, Microphone, and Camera individually after explaining their uses.
Only screen access is required for capture; the remaining permissions enable
optional features. Preserve runtime permission checks and the explicit shortcut
setup in Settings. Do not restore automatic permission prompts during launch.
The keystroke overlay captures shortcuts and special keys, never plain typing.

### Onboarding

`OnboardingState` tracks the introduction independently of app releases. Skip,
the window close button, and completion mark it seen. The three steps are Welcome,
Permissions, and First Capture. `BetterShotApp.init` calls `prepareForLaunch`
before services or migrations write defaults. A fresh profile records pending setup;
existing BetterShot preference keys without a marker are migrated as seen. Any
positive seen version skips setup, so app and onboarding updates never repeat it. There are no menu tray or Settings reopening actions;
`OnboardingWindowController.show` also guards against completed setup.

Welcome uses bundled Hyperframes demo videos and still posters. Playback is
explicit, silent, and never loops; leaving the step stops playback. Keep posters
and text useful without motion or a network connection. Source compositions and
render instructions live in `docs/onboarding-media/` and `docs/onboarding.md`.
Show all five permissions in compact rows, without disclosures. Screen access is
required for capture; the other rows clearly state that they are optional.
Shortcut labels come from `ShortcutService.effectiveShortcut`; preserve custom
and disabled bindings. Permission-related restarts resume the Permissions step,
while explicit dismissal clears that flag. Settings requests never schedule setup.
`OnboardingSample` copies original PNGs to Application Support/BetterShot/Practice
before opening the editor, without inserting samples into capture history.

`Tests/OnboardingStateCheck.swift` covers presentation and preference preservation.
Editor integration verifies sample copies, playable silent demo assets, permission
mapping, retry-versus-Settings routing, and the no-TCC guard. The isolated pilot
labels itself as a preview and disables permission actions; never remove testing
guards to make a preview request real access. It renders all three steps and recording posters in
compact/light/dark layouts, plus permission recovery states. Manually verify
Escape/Return/Tab, video playback, sample editing, and permission grant/relaunch
on a signed app. See [onboarding notes](docs/onboarding.md).

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

### DMG installer

Install the packaging tool with `brew install create-dmg`. DMG packaging needs a
logged-in macOS desktop and permission to automate Finder so it can save the window
layout. Do not skip Finder customization for release builds.

`make dmg` builds the app and calls `scripts/create-dmg.sh`. To preview packaging
with an existing build:

```bash
bash scripts/create-dmg.sh .build/Build/Products/Release/BetterShot.app release/BetterShot-installer-preview.dmg
bash Tests/check-dmg.sh release/BetterShot-installer-preview.dmg .build/Build/Products/Release/BetterShot.app
```

The maintainer's local `scripts/release.sh` uses the same packager before its existing
signing/notarization steps. `scripts/dmg-background.swift` draws the 660 × 440 point
background at 1× and 2×. Keep its arrow aligned with the real Finder icons in
`scripts/create-dmg.sh`; do not paint substitute app or folder icons into the image.
The clover volume icon comes from the built app. Packaging verifies the image before
atomically replacing the output; it does not install or launch BetterShot.

For packaging changes, build and reopen a local DMG, confirm the background and
icon positions survive remounting, and check the Applications link resolves to
`/Applications`. Inspect Finder in light and dark appearances at the saved window
size. App logic tests are not a substitute for these packaging checks.

## Project map

| Location | Responsibility |
|---|---|
| `Sources/App/` | App scenes and AppKit-to-SwiftUI editor presentation |
| `Sources/Capture/` | Native screenshot capture, adjustable recording region control, OCR, color picker, countdown |
| `Sources/Preview/` | Capture deck, pinned images, unsaved capture staging |
| `Sources/History/` | Capture records, retention, raw/export path mapping |
| `Sources/Models/` | Preferences, capture records, shared gradient definitions |
| `Sources/Services/` | Shortcuts, screenshot framing, updater, grading, silence detection |
| `Sources/Settings/` | General, Capture, Overlay, Recording, Shortcuts, Sharing, About |
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
| Export/share feedback | `TransferStatusCard` in `TransferToast`; separate screen-top panel with native progress |
| Shared backgrounds | `GradientPreset.presets`, `GradientBackgroundView`, `AnnotationBackgroundStageFill` |

Settings uses `EditorButtonStyle(bordered: true)` with the system blue accent. Shared
buttons use semantic foreground colors, visible hover/pressed feedback, and red for
`.destructive` roles. Keep disabled actions distinct and preserve native confirmations.

Keep slider field labels hidden inside Forms so the numeric value stays centered
in its right-hand field. Reuse `InspectorSlider` everywhere, including JPEG quality,
preview margin/dismissal, and timeline zoom. Preserve steps, units, exact entry,
and the Never dismissal option.

Keep Blur and Pixelate visible, hide editor scroll indicators without disabling
scrolling, and preserve tool toggling. Image tools return to Select on a second
click. Video Crop cancels its draft on a second click. Scissors starts off and
stays on across cuts until explicitly deselected. Crop Only refers to mask
coverage within the selected rectangle, not an export format or destructive crop.

Reuse `AnnotationSwatchStrip` for image color palettes; its two-row grid keeps all
presets and the custom color action visible, including in compact inspectors.

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
captures until Save, drag, Pin, Share, or Edit promotes them. Copy only writes to
the clipboard and discards the unsaved card; it does not add the capture to the
save folder or Library. Preserve failure
recovery and the raw image so subsequent editing does not flatten twice.

`LastRegionGhostPresenter` can show an existing BetterShot remembered region when
the bar opens, and A recaptures it. The native screenshot selector does not write
BetterShot's remembered-region preference; do not document its keyboard behavior
as if it were `RegionSelectionOverlay`.

Overlay controls live in the dedicated Settings > Overlay page.
Existing size, position, margin, timing, and visibility preference keys are preserved.
Quick Setup supplies Standard, Sharing, and Minimal presets. The visual Tool Positions
editor and the actual capture card share `OverlayToolArrangement` / `OverlayToolLabel`.
`OverlayToolLayout` stores six tool assignments, swaps occupied positions, hides optional
actions, and keeps Dismiss reachable. Decode invalid/duplicate entries safely. The
Advanced section controls timing and visibility; Restore Overlay Defaults affects only
this page, while Restore General Defaults leaves overlay customization intact.
The Standard layout puts Pin upper-left and cloud sharing lower-right. Every placement
routes to the same action handler. Cloud sharing uses `CloudUploader` and resolves
recording deliverables before uploading.
`TransferStatusCard` supplies compact processing, progress, link, and retry states in the
deck, with `TransferToast` providing the same screen-top feedback. Sharing errors and
completed links stay visible until dismissed or evicted by newer captures. Uploads are
cancelled when removed; cancelled preparation cannot proceed into R2. Tests cover these
local states, layout swaps/hiding/persistence/recovery, the compact settings page, and
all three sizes in both appearances, without cloud credentials. Verify
real upload/clipboard completion and keyboard navigation in the signed app.

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

General > Default Look supplies background, padding, corner radius, and shadow
for new images, recordings, and imported videos. `RecordingStudioDefaults.style`
maps the same preferences into the video editor. Saved projects retain their own
settings; project edits never replace General's defaults. Recording retains its
capture and export options, without a separate background default.

The native Settings sidebar has General, Capture, Overlay, Recording, Shortcuts, Sharing,
and About. Recent captures remain accessible from the menu. Media Gallery in the tray
and General > Open Media Gallery open the same resizable gallery window. It
combines retained capture history, edited images, and recording projects, with
Local/Cloud and screenshot/video filters. Reuse the existing editor URL resolvers
and preserve cloud links even when local media is missing; the gallery does not
list the R2 bucket. Local deletion moves source/sidecar files to Trash before changing
metadata and preserves cloud links. Cloud deletion validates the share’s storage origin
and clears links only after R2 confirms deletion. Use native confirmation alerts and
inline retry errors. Gallery checks cover merging, deletion, filters, and light/dark
layouts; test history uses a temporary Application Support directory.

### Startup, visibility, and shortcuts

General uses `SMAppService.mainApp` for Launch at Login; read its actual status rather
than maintaining a second preference flag. Refresh on activation, show registration
errors beside the toggle, and keep `BETTERSHOT_TESTING=1` free of login-item changes.
`AppPreferences.visibility` and `AppActivationPolicy.applyVisibility` govern Dock and
menu-bar visibility across launch and all windows. At least one icon must stay visible;
turning off Show in Dock restores the menu-bar icon. Preserve the bundled clover.

`ShortcutCatalog.swift` is the source for action IDs, groups, scopes, and defaults.
Never renumber persisted IDs. New actions have no default binding; previously shipped
capture/editor bindings remain available and customizable. Use the dedicated
searchable Shortcuts page. Keep reset, clear, disabled state, and same-scope conflict
checks consistent. Editor and global scopes may reuse keys; the active editor takes
priority. Global bindings require Command, Control, or Option.

Route global actions through `ShortcutService.performGlobal` and existing capture,
recording, history, and preview entry points. Per-capture copy/save/edit/pin overrides
must not overwrite General preferences. The timer action uses the configured timer,
with a three-second minimum. Restart, Discard, and unsaved-deck clearing retain native
confirmation. Failed deck saves stay available for retry.

`EditorShortcutHandler` dispatches only in its key window, respects disabled controls
and sheets, and yields to text fields except a Command-modified Save. Use the same
bindings in AppKit timeline input; do not leave hard-coded keys behind after making an
action customizable. Suspend all dispatch while the shortcut recorder has focus.
Export/share shortcuts open the existing options controls before acting.

The editor integration check covers the catalog, persistence, scoped conflicts,
remapping, disable/reset, text focus, visibility combinations, and category snapshots
in light/dark at compact widths. Live global interception, login-item authorization,
Dock/menu-bar changes, and capture/recording need a signed-app manual check; offscreen
snapshots cannot establish those behaviors.

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

For the optional two-minute 1080p export benchmark, build optimized, testable
objects separately so the standalone runner can omit the app entry point:

```bash
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  SWIFT_COMPILATION_MODE=incremental build
BETTERSHOT_BUILD_CONFIGURATION=Release BETTERSHOT_BENCHMARK=1 bash Tests/run-exports.sh
```

For a short image-only benchmark with the same optimized objects, run
`BETTERSHOT_BUILD_CONFIGURATION=Release BETTERSHOT_BENCHMARK_IMAGES=1 bash Tests/run-exports.sh`.
It measures fresh and repeated full-resolution PNG exports and checks edit, source,
and wallpaper invalidation. Normal checks also compare reused video frames with
fresh compositions across source, zoom, mask timing, pointer, and camera changes.

This compares plain and effect-heavy rendering, then runs the production local
upload preparation without credentials or network uploads. The synthetic moving
source is deliberately compressible; report hardware, effect settings, and upload
preparation separately. These timings do not predict internet transfer speed or
all real-world footage. Normal `make test` keeps its short fixtures.

The transfer-toast integration check briefly creates native windows to verify
screen-top placement, preserved keyboard focus, appearance, dismissal, and editor
close cleanup. Manually check full-screen Spaces and moving between displays.

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
`make generate` syncs version/build into the project. Version **0.5.2**, build **19**, is prepared for **2026-09-10**. Preserve the historical **0.5.1** changelog date of **2026-09-10** at the maintainer’s request.
Do not publish binaries or mark another version shipped without an explicit release request. Keep historical entries and contributor credit.

Use short, descriptive commit messages, for example `fix: preserve cursor hotspot
in Retina exports`. Do not commit signing credentials, generated builds, or local
machine configuration.

## License

Contributions are licensed under the project's [BSD 3-Clause License](LICENSE).
