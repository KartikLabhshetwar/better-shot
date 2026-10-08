# Frozen region capture validation

The selector images in this directory use a generated blue/orange fixture, not
desktop content. They render the production `RegionSelectionOverlay` at 2x scale
with a 400 × 240 point selection. `selection-light.png` shows the drag before
capture-on-release; `selection-dark.png` shows the adjustable selection before
Return. The selected area reveals the original frozen frame while the surrounding
frame remains dimmed.

A temporary AppKit driver exercised the production overlay with injected frames,
isolated preference collaborators, and synthesized mouse/key events. It checked
capture-on-release, confirmation with Return, cancellation with Escape, switching
to native window selection with Space, selected coordinates/display ID, and
closure of overlay windows. This does not establish physical global shortcut
delivery, ScreenCaptureKit capture permissions, or the full app's settings UI.

`Tests/FrozenScreenFrameCheck.swift`, run through `scripts/run-checks.sh`, uses
production crop/PNG code to check 1x and 2x dimensions, negative display origins,
AppKit-to-display conversion, fractional edges, crop orientation, bounds rejection,
and lossless PNG pixels.

Before marking the feature ready, build with Xcode 26+ and run `make test`, then
check these interactions in a signed development app:

- With freezing enabled, start region capture over a playing video; wait before
  confirming and verify that the exported image matches the displayed still.
- Repeat with capture-on-release, a remembered region, resizing, and Escape.
- Invoke capture by keyboard over a context menu or hover popup; verify it is
  present in the frozen frame and that focus returns after capture/cancellation.
- Verify the countdown completes before freezing, and Space opens live native
  window selection.
- On displays with different scales and negative origins, verify selection,
  preview, and exported pixels. Disconnect/rearrange a display during selection;
  a changed or unavailable display must produce an error instead of a later frame.
- Verify excluded BetterShot windows remain excluded, and the existing opt-in
  to include app windows still works.
- Verify freezing off, previous-region, OCR, scrolling, and recording selectors
  preserve their existing behavior; Restore Capture Defaults disables freezing.
- Deny screen capture permission or cancel its prompt; verify an actionable error
  and successful retry after restoring permission.

Local full-app build is unavailable because the host has Command Line Tools but
no full Xcode or XcodeGen. The production capture files passed targeted type
checking at macOS 26 deployment with Swift 5 language mode and MainActor default
isolation, using isolated preference collaborators for unavailable app dependencies.
