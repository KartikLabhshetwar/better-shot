# BetterShot contributor and agent rules

These rules apply to changes in this repository. Read the relevant implementation
and [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Preserve the current UI and
behavior unless the task explicitly asks to change them. This file is the shared
source of instructions for coding agents; `CLAUDE.md` imports it.

## Stack and scope

- The macOS app in `Sources/` uses SwiftUI, AppKit, CoreGraphics, AVFoundation,
  and ScreenCaptureKit. Use native controls and existing project primitives.
- The deployment target is macOS 26.0. Read `project.yml` for actual compiler
  settings: the app currently uses Swift 5 language compatibility with main-actor
  default isolation and approachable concurrency. Standalone checks use Swift 6.
  Do not change toolchain settings as a side effect of a feature or UI fix.
- `bettershot-landing/` is a separate Next.js/React/Tailwind website. Web libraries
  and CSS rules do not belong in the native app.
- Search for existing callers and shared rendering paths before adding code.
  Fix the shared cause, keep the diff focused, and avoid speculative abstractions
  or new dependencies when existing code or the platform covers the need.

## Required native UI patterns

### Identity and icons

- Preserve BetterShot's bundled clover identity: `AppIcon` for the app and
  `MenuBarIcon` for the menu tray. Do not replace either with a generic camera,
  a website logo file, or a newly generated icon unless explicitly requested.
- Use Apple SF Symbols for action, tool, settings, and navigation icons:
  `Image(systemName:)`, `Label(_:systemImage:)`, or AppKit's
  `NSImage(systemSymbolName:accessibilityDescription:)`.
- Do not reintroduce Nucleo, third-party UI icon packs, or asset-mapping wrappers.
  Choose symbols available on the deployment target; installing the SF Symbols
  design app is not an application dependency.
- Keep cloud sharing recognizable with `icloud.and.arrow.up`. Use the same
  symbol for the same action across editors, menus, settings, and capture bars.

### Layout and chrome

- Both editors keep their inspector on the left. Image tools belong in one
  toolbar; do not duplicate tool, aspect-ratio, or redaction controls in the
  image sidebar.
- Video inspector tabs are Background, Cursor, Camera, Effects, and Zoom & Clips.
  Keep its effect cards expanded with no outer disclosure chevrons. Advanced
  controls may use the existing Advanced section.
- Reuse `EditorChrome`, `EditorButtonStyle`, `studioGlass`, `studioEffectCard`,
  `InspectorMetrics`, and the existing inspector components.
- Preserve classic frosted chrome, subtle borders, and compact spacing. In dark
  appearance, effect cards are lighter grey than the darker sidebar. Use system
  colors, readable disabled states, and the existing blue selection accent.
- Respect both light and dark appearances, Reduce Transparency, and Reduce Motion.
  Do not introduce a new Liquid Glass redesign as an incidental cleanup.
- Use `InspectorSlider` for all app sliders, including Settings and timeline zoom.
  Its 0.4.0 compact track contains
  the label and has a separate editable value on the right. Hide the TextField
  label in Forms to prevent duplicate labels and clipped values. Preserve keyboard input, units,
  bounds, precision, and undo grouping; do not substitute another slider style.
- Hide scroll indicators in both editors while preserving scrolling. Check narrow
  windows so tools, labels, values, and actions are not clipped or unreachable.
- Keep one shared capture bar. Reuse `BarMetrics`: capture height 64 pt, recording
  height 38 pt. The recording row contains Stop/timer, Pause, Restart, and Discard.

### Interactions and accessibility

- A second click on an active image tool returns to Select. Clicking video Crop
  again cancels the uncommitted crop; do not destroy the previously applied crop.
  Blur and Pixelate must be visible and toggle out of mask editing on a second click.
- Video mask scope uses Crop Only for the selected rectangle and Full Frame for
  the whole source frame. Keep preview, export, and project persistence consistent.
- Scissors starts unselected. Once selected, it stays active across repeated cuts
  until deselected by clicking it or pressing S. Preserve cut badges below the
  filmstrip, removed-duration labels, and hover previews of source footage.
- Keep native keyboard/focus behavior for standard controls. Icon-only actions
  need accessible names; tooltips alone are insufficient. Preserve selected and
  disabled states, text entry, copy/paste, and keyboard navigation.
- Confirm destructive actions using the existing native alerts. Show recoverable
  errors beside the action with a useful retry or next step.
- Reuse `TransferStatusCard` for export/share progress, completion, and failures.
  Preserve its compact corner placement, native progress, and Copy/Open/Reveal/Retry actions.
- Do not add animation unless requested. For new interaction feedback, prefer
  opacity or transforms, ease-out, and at most 200 ms. Never animate large blur
  surfaces, make progress dependent on a decorative animation, or add perpetual
  motion. Respect reduced-motion settings. Existing specialized capture/video
  motion is not a reason to redesign unrelated UI.

## Capture, image quality, and recording

- Shortcut defaults: `⌘⇧4` region screenshot, `⌘⇧3` fullscreen screenshot,
  `⌘⇧2` shared capture bar, `⌘⇧5` Recording options, `⌘⇧O` OCR, `⌘⇧C` color picker.
  Use `ShortcutService` as the source for UI labels and settings. Migrations must
  preserve customized bindings and disabled states.
- Region screenshots use macOS's native `screencapture` selector. Recording areas
  use BetterShot's adjustable AppKit selector and system crosshair. Do not describe
  the recording selector as Apple's system recording picker.
- Preserve capture-window exclusion, correct display/coordinate conversion,
  cancellation, and focus restoration. Never start a recording after cancellation.
- Keep untouched capture pixels and editable project sources. Full-resolution
  image previews are the default; an optional low-resolution preview must never
  become the source for saving, copying, or export. Keep screenshot framing aligned
  to integer pixels and preserve lossless PNG behavior.
- Hand artwork uses `NSCursor.pointingHand`, preserving its native hotspot and
  highest-resolution representation through `PointerArtworkCapture`.
- Custom cursor raster resolution is independent of its logical size and hotspot.
  Preserve transparent backgrounds, contrasting outlines, the highest-resolution
  recorded representation, and cached decoding. Do not regenerate cursor PNGs per frame.
- Keep Recorded/Dark/Light/Dot/Hand, visibility, Natural/Smooth motion, press/ripple,
  and idle hiding consistent in preview, export, and saved projects. Imported
  footage with a baked-in cursor cannot be restyled; explain that in the UI.
- Plain typing is not recorded. Do not expand input capture as a shortcut to a
  cursor or keyboard-overlay feature.

## Backgrounds and persistence

- `GradientPreset.presets` in `Sources/Models/BackgroundStyle.swift` is the source
  for the ten approved soft gradients: Blush, Peach, Mint, Powder Blue, Butter,
  Lilac, Sage, Coral, Aqua, and Mauve. Their gradients are media backgrounds,
  not a license to add decorative gradients to controls or chrome.
- Reuse the shared gradient drawing, stop positions, and highlights in Settings,
  both editors, and exports. Do not duplicate palettes or flatten them into thumbnails.
- Preserve old project decoding and stored artwork when replacing available presets.
- General > Default Look supplies background, padding, corner radius, and shadow
  for new images and videos. Do not add a separate video background default or
  let project edits overwrite General's defaults. Saved projects retain their look.
- Preserve raw captures, annotations, source movies, masks, crop, undo/redo, and
  saved share links. Use existing history/project resolvers and atomic writes.

## Verification and documentation

- Run checks appropriate to the change; use `make test` for native logic and
  rendering changes. Use existing standalone checks or editor/export integration
  checks against production code, not a copied implementation.
- Check compact layouts and both appearances for UI changes. Offscreen snapshots
  cannot prove live AVPlayer rendering, native window toolbars, global shortcuts,
  permissions, or interactive capture; report what was actually checked.
- Tests must use `BETTERSHOT_TESTING=1` through the provided runners and must not
  access real R2 credentials. Never log credentials or weaken release signing.
- `version.json` is the version source. Keep pending work in the single unreleased
  0.5.0 changelog section until release is explicitly requested; no 0.4.3 release.
  Preserve historical release entries and contributor credit.
- Update README and contributor guidance when behavior or workflows change.
  Keep `CLAUDE.md` a short import of shared instructions rather than a second rulebook.
- Do not modify unrelated work, commit local signing identities, publish releases,
  or remove installed apps/user data as a side effect of routine editing.

## Website-only rules

For `bettershot-landing/`, use existing Tailwind tokens and the `cn` utility.
Reuse the installed Radix components; do not mix primitive systems within one
surface. Use accessible labels, existing alert dialogs, `h-dvh` and safe-area
insets for full-height/fixed layouts, and tabular numbers for data. Keep headings
balanced and body text readable without arbitrary letter spacing. Use
`motion/react` only when animation is requested; animate opacity/transforms,
respect reduced motion, and avoid layout or backdrop-filter animation. Do not
add effects solely for decoration or copy website branding into native app assets.
