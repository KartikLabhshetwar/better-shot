# BetterShot Triage, 2026-08-25

Full pass over all **26 open issues** and **13 open PRs**, verified against `main` at `e1ddee5`.

## The headline

| | |
|---|---|
| `main` (version.json) | **4.0.0**, build 11 |
| Latest published release | **v0.3.7**, 2026-06-07 |

`main` is many months of work ahead of anything a user can download. Most of the open bug reports describe **v0.3.7 behaviour that `main` already fixes**. Cutting a 4.0.0 release is the single highest-value action on this list: it closes ~9 issues by itself.

Every PR except #70 is **CONFLICTING/DIRTY** against `main` for the same reason: they were branched off a tree that has since moved a long way.

> The `Vercel = FAILURE` check on all 13 PRs is the `bettershot-landing` preview deploy failing on forks. It is not a code signal, ignore it.

---

## 1. Fixed in this pass

Baseline `xcodebuild -configuration Debug` passed before and after every change. Diff: **+121 / −81 across 18 files**.

| Issue | Fix | Files |
|---|---|---|
| **#97** (+ likely **#75**) | Beautifier composited into `CGColorSpaceCreateDeviceRGB()`, discarding the display's P3 profile and emitting untagged PNGs. Canvas now inherits the source's RGB colour space, falling back to sRGB. `drawBackground` is deliberately still handed sRGB. `GradientPreset.cgGradient` supplies raw components authored as sRGB, so a P3 canvas space would shift every preset. | `BeautifierRenderer.swift` |
| **#98.2** | `eventTapCallback` is a C function pointer on an arbitrary thread and was calling `NSEvent.mouseLocation` / `NSScreen.screens`, main-actor-only AppKit. Now reads `event.location` (safe, Quartz top-left) and resolves the screen inside the `@MainActor` hop. | `ShortcutService.swift`, `ActiveDisplayResolver.swift` |
| **#98.3** | `unregisterAll()` dropped the mach port without invalidating it, so ports leaked on every settings save. Added `CFRunLoopRemoveSource` + `CFMachPortInvalidate`. | `ShortcutService.swift` |
| **#100.1** | Scroll-to-resize looked the panel up by type, so with two pins it resized the wrong one. The panel is now bound at construction via an `onResize` closure, mirroring the existing `onClose`. Deleted `resizeWindow(to:)` and `findHostingWindow()`. | `PinnedScreenshot.swift` |
| **#100.2** | Redaction cache key. The report named the `ObjectIdentifier(source).hashValue` path; the sibling CGImage path keyed on `"cg-\(width)x\(height)"`, which collides for **any** two same-size screenshots, a strictly worse version of the same bug. Both now key on a per-load `EditorModel.sourceToken` UUID. | `EditorModel.swift`, `EditorCanvasView.swift`, `AnnotationItemView.swift`, `AnnotationRedactionImageProcessor.swift` |
| **#100.4** | The real bug was already fixed (`EditorWindowView` uses `hostWindow?.close()`), but `EditorWindowController.close(window:)` still carried the `NSApp.keyWindow ?? windows.last` footgun with **zero callers**. Deleted. | `EditorWindowController.swift` |
| **#100.5** | **Security.** `installUpdate` copied the mounted `.app` over the running bundle with no verification. Now requires `SecStaticCodeCheckValidity(.checkAllArchitectures ∪ .checkNestedCode)` against `anchor apple generic and certificate leaf[subject.OU] = "8JL39GK2DC"` before the copy. | `AppUpdater.swift` |
| **#96.1 / #74** | Capture pipeline rendered + PNG-encoded a ~78 MB canvas on the main actor. `galleryApplyAndSave` now decodes, renders and writes in a detached task; only `HistoryStore` and the toast return to main. `EditorModel.renderFinal()` is `async` and hops off-main, covering export, share and copy-to-clipboard. | `CaptureOrchestrator.swift`, `EditorModel.swift`, `EditorWindowView.swift` |
| **#94** | Mostly fixed before this pass: an earlier commit dropped a stray `*30` from the bitrate (1440p was asking for ~442 Mbps, about 3.3 GB/min). What was left was `max(20_000_000, w*h*4)`, whose 20 Mbps **floor** still overspent on small windows and whose lack of a ceiling left 5K/6K unbounded. Now `min(40_000_000, max(4_000_000, w*h*4))`: an 800x600 window drops from 20 to 4 Mbps, 1600x1200 from 20 to 7.7 Mbps, 1440p is unchanged at 14.7 Mbps, 4K is 33.2 Mbps, and 5K/6K cap at 40 Mbps instead of running free. 40 Mbps HEVC still sits well above QuickTime's screen recording. | `RecordingSession.swift` |
| **#77** | Dead keys. `AnnotationKeyboard` was not at fault. `AnnotationTextBoxView.updateNSView` does `textView.string = text` on binding round-trip **and** `applyStyle` resets `font`/`textColor`/`typingAttributes`, and both discard pending marked text mid-composition. Both are now guarded on `textView.hasMarkedText()`. | `AnnotationItemView.swift` |
| **#66** | Preview auto-dismiss could not be turned off. Slider extended to `AppPreferences.overlayDismissNever` (16), which renders as "Never" and makes `scheduleDismiss()` return early. A sentinel beats a second pref key plumbed through three files. | `AppPreferences.swift`, `PreviewOverlay.swift`, `PreferencesView.swift` |
| **#70** (adopted) | Download host pinned to `https://github.com/<owner>/<repo>/releases/download/`; `relaunchApp` and the delegate's restart now pass paths as `$0` argv instead of interpolating into `sh -c`; six `"latest"` deps in `bettershot-landing/package.json` pinned to their already-locked versions. | `AppUpdater.swift`, `BetterShotDelegate.swift`, `package.json` |

**Not fixed, deliberately:** every remaining item is a feature request. Product scope is yours, not mine, so those are recommendations below rather than commits.

---

## 2. Issues, verdicts

### Close now: already fixed on `main`

| # | Title | Evidence |
|---|---|---|
| **#71** | Auto-open editor after screenshot | `AppPreferences.openEditorAfterCapture` ships with a Preferences toggle |
| **#73** | Record selected window | `RecordingSource.window(CGWindowID)` + `startWindowRecording` + `RecordingPickerBar`. The "relative shortcut" half is not done: `ShortcutService.Action` has one `.recording` case that opens the picker. Close as done, or split the shortcut out. |
| **#78** | Visible area when recording | `Sources/Recording/RecordingAreaHighlight.swift` |
| **#69** | Zooms when recording | `Sources/Recording/ZoomCue.swift` + a zoom lane in `CapTimelineView` |
| **#89** | Area recording captures fullscreen | `startAreaRecording` builds a proper `SCContentFilter`; **#95**'s `filter.pointPixelScale` fixed the scale half |
| **#95** | First display + hardcoded 2x | All four filter paths use `max(1, CGFloat(filter.pointPixelScale))`; `ActiveDisplayResolver` picks the display |
| **#98.1** | `_streamSession` pointer race | `ScreenCaptureStream` is `nonisolated … @unchecked Sendable` with an `NSLock` over `_stream` / `_handlers` |
| **#96.2** | Wallpapers decoded in `body` | All five named sites route through `ImageCache`; no raw `NSImage(contentsOfFile:)` remains at any of them |
| **#100.3** | Recording timer stalls in menu tracking | `RunLoop.main.add(timer, forMode: .common)` + a `ContinuousClock` anchor |
| **#53** | Share instantly | `Sources/Sharing/ShareService.swift`, wired into both editors |
| **#48** | ⌘⇧⌥ shortcuts saved incorrectly | Recorder (`PreferencesView:953-957`) and tap (`ShortcutService:151-155`) now build the identical Carbon mask from the identical raw key code |
| **#29** | Ctrl key cannot be recorded | Same fix. `.control` to `controlKey` is present on both sides |

### Close after this pass ships

**#97, #98, #100, #96, #94, #77, #66, #75, #74**: all fixed above. #75 has no repro attached; the P3 fix is the likely cause, so ask the reporter to confirm on 4.0.0 before closing.

### Needs the reporter

| # | Title | Action |
|---|---|---|
| **#87** | BetterShot not opening | Not a bug. `LSUIElement = true`, so it is menu-bar-only, so "nothing happens" on launch is expected, and there is **no onboarding anywhere in `Sources/`**. This is a first-run UX gap, and **PR #84** is precisely the fix. Reply explaining the menu bar, then land #84. |

### Open feature requests, nothing on `main` yet

| # | Title | Note |
|---|---|---|
| **#103** | Drag-and-drop onto the menu bar icon opens the editor | Cheapest win on the board. No `registerForDraggedTypes` anywhere; `EditorWindowController.shared.open(url:)` already exists, so this is a `NSDraggingDestination` on the status item button and one call. |
| **#49** | Adjustable selection handles before capture | `RegionSelectionOverlay.swift` has no handle logic at all (339 lines, zero matches for handle/resize) |
| **#33** | Scrolling capture | **PR #82** implements it (+598) |
| **#76** | Persistent floating deck (CleanShot X style) | Partial: `PinnedScreenshot` pins one. **PR #83** stacks preview cards. |
| **#86** | URL scheme for Raycast / automation | No `CFBundleURLTypes` in `Resources/Info.plist` |
| **#61** | Watermark / branding | Nothing in `Sources/` |

### Close as won't-fix

| # | Title | Why |
|---|---|---|
| **#39** | Linux support | AppKit + ScreenCaptureKit + Carbon throughout. Not portable. Close politely. |

---

## 3. PRs, verdicts

Mergeability forced on GitHub (it computes lazily; the first query always returns `UNKNOWN`).

| # | Author | Mergeable | Verdict |
|---|---|---|---|
| **#70** | Owen-Interruptive | **MERGEABLE** | The only clean PR, and it was right. Its substance is now on `main`: host pinning, `$0` argv, and dep pinning adopted verbatim; its signature check replaced with a stronger one. **Credit the author in the commit and close as adopted**, because the PR shells out to `/usr/bin/codesign --verify --deep` and pins to the *running* app's Team ID string, which a self-signed bundle can forge; the in-process designated requirement pins the Apple anchor too. Merging it now would conflict with those edits. |
| **#80** | iOSDevSK | CONFLICTING | **Close as resolved.** `xcodebuild -configuration Debug` on `main` succeeds under Swift 6 strict concurrency, before any of my changes. The build errors it fixes no longer exist. |
| **#101** | Antheurus | CONFLICTING | **Close as superseded.** Mic capture shipped: `MicrophoneCatalog.swift`, `RecordingAudioPlan.swift`, `RecordingSession(includeMicrophone:)`. |
| **#68** | AnKh99 | CONFLICTING | **Close as superseded**, same feature as #101, same reason. |
| **#67** | AnKh99 | CONFLICTING | **Close as superseded.** `ActiveDisplayResolver` + `RecordingBarPresenter.togglePicker(on: mouseScreen)` already select the screen under the cursor. |
| **#83** | iOSDevSK | CONFLICTING | Partly superseded: "optional manual dismiss" is **#66**, now fixed. The **stacked** preview cards are still novel and answer **#76**. Ask for a rebase on just that half. |
| **#84** | iOSDevSK | CONFLICTING | **Highest-value PR still open.** Directly fixes **#87** and there is no onboarding on `main`. Only 2 files. Worth rebasing yourself. |
| **#82** | iOSDevSK | CONFLICTING | Only implementation of **#33**. +598, 5 files. Wants a rebase and a real review. |
| **#104** | reallukedev | CONFLICTING | Genuinely new (copy-only captures, space-to-window). Request rebase. |
| **#88** | Fletcher-Alderton | CONFLICTING | Two unrelated things in one PR (+958/15 files): WebP export, and a window-capture hotkey fix that `main` has likely already absorbed. Ask to split; review WebP on its own. |
| **#79** | letr007 | CONFLICTING | Simplified Chinese, 22 files. Blocked on a decision you have not made: **is BetterShot getting a localisation infrastructure?** Answer that first, or it will rot. |
| **#81** | iOSDevSK | CONFLICTING | Paste clipboard images into terminals via ⌘V. Niche and it hooks the global paste path. Decide scope before asking for a rebase. |
| **#85** | e3o8o | CONFLICTING | Local REST API for the beautifier (+861). Opens a network listener in a screenshot app, that is a security surface, not a feature. **#86**'s URL scheme is the cheaper, safer answer to the same automation need. Recommend closing in favour of #86. |

---

## 4. Recommended order

1. **Ship 4.0.0.** Nine issues close on release day.
2. Close #80, #101, #68, #67 as superseded; close #70 as adopted with credit.
3. Land **#84** (onboarding), then answer and close **#87**.
4. Reply on **#75** asking for confirmation against 4.0.0.
5. Implement **#103**, the smallest feature on the list.
6. Decide the two blocked questions: localisation (**#79**), and automation surface (**#85** vs **#86**).
7. Ask #82, #83, #104 for rebases.

## 5. Verification

```
bash scripts/run-checks.sh     # 41 passed, 0 failed
xcodegen generate
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot -configuration Debug -derivedDataPath .build build
** BUILD SUCCEEDED **
```

### Checks written for this pass

| Check | Covers | What it would catch |
|---|---|---|
| `UpdaterTrustCheck` | #100.5, #70 | 2 genuine release URLs accepted, 8 spoofed ones rejected (`githubb.com`, `github.com.evil.tld`, wrong owner, wrong repo, wrong path, `http`, `file://`), plus a bundle that is unsigned, missing, or signed by another team |
| `RenderColorSpaceCheck` | #97, #75 | A Display P3 screenshot silently converted to an untagged device canvas, a non-RGB source falling back to unmanaged instead of sRGB, and the saved PNG losing its profile. Includes the pre-fix device canvas as a control, to prove the conversion really moved pixels |
| `RedactionCacheKeyCheck` | #100.2 | A new screenshot of the same size reusing the previous blur bitmap, plus tool, density, scale and crop all failing to invalidate |
| `RecordingGeometryCheck` | #94 | Floor, ceiling and mid-range bitrates. Previously duplicated the formula and had gone stale, so it now imports `RecordingSession.averageBitRate` |
| `TextCompositionCheck` | #77 | A SwiftUI refresh overwriting a live dead-key composition, driven through a real `NSTextView` IME session: `caf` + accent + `e` must commit as `cafe` with an acute |
| `PointerScreenCheck` | #98.2 | The Quartz to AppKit vertical flip, including displays stacked above and below the primary, plus a live probe of every attached screen and the off-screen fallback |
| `PinnedResizeCheck` | #100.1 | Scroll-zoom losing the top-left anchor, and 40 zooms in and back out drifting the window off screen |
| `OverlayDismissCheck` | #66 | The Never sentinel failing to round-trip through UserDefaults, and an off-by-one that would make Never unreachable at the top of the slider |

Every one of these was mutation tested: the fix was reverted, the check was confirmed to fail, and the fix restored.

### Verified against a real artifact

`AppUpdater` now refuses any bundle not signed by `8JL39GK2DC` under the Apple anchor. Local `make release` builds use `CODE_SIGNING_REQUIRED=NO`, so the accept path cannot be proven with a dev build. The shipped **v0.3.7 arm64 DMG** was downloaded from GitHub Releases, mounted, and confirmed to carry `TeamIdentifier=8JL39GK2DC` and satisfy the pinned requirement. The reject path is covered by `UpdaterTrustCheck`.

### Still manual only

| Item | Why | How to check |
|---|---|---|
| #98.2 mach port leak | `CGEvent.tapCreate` needs Accessibility permission, which an ad-hoc test binary does not have | Toggle shortcuts repeatedly in Settings, watch the port count in Instruments |
| #96.1 responsiveness | Strict Swift 6 concurrency proves the isolation at compile time, but "the UI no longer hangs" is observational | Beautify a large screenshot from the gallery and confirm the window keeps drawing |
| #103, #79, #85, #86 | Not implemented in this pass | n/a |
