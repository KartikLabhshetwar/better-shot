# RECORDING_AREA_RECT.patch.md

`RecordingAreaHighlight.swift` is fully built and ready
(`RecordingAreaHighlightPresenter.shared.show(rect:on:)` / `.hide()`), but nothing in
`Sources/Recording/` can currently drive it with a real rect. `ScreenRecordingManager.startAreaRecording()`
selects the region via a local `RegionSelectionOverlay` and only ever uses the resulting rect as a
local variable to compute the SCK `sourceRect` - it never surfaces the rect (or an "is this an area
recording" flag) as a property, so `RecordingStatusBar.swift` has nothing to read. This file is out of
scope for this task, so apply this by hand instead of me editing it directly.

## Patch

In `Sources/Recording/ScreenRecordingManager.swift`:

1. Add a stored property alongside `elapsedSeconds`:

```swift
private(set) var activeRegionRect: CGRect?
```

2. In `startAreaRecording()`, right after `let selection = ...` succeeds (before building the
   `SCContentFilter`), convert the SCK-flipped `selection.pointsRect` back to AppKit/global screen
   coordinates (bottom-left origin, matching `NSScreen.frame`) and store it:

```swift
let primaryHeight = NSScreen.screens.first?.frame.height ?? selection.pointsRect.height
activeRegionRect = CGRect(
    x: selection.pointsRect.minX,
    y: primaryHeight - selection.pointsRect.minY - selection.pointsRect.height,
    width: selection.pointsRect.width,
    height: selection.pointsRect.height
)
```

3. Clear it wherever a recording ends, in both `stopRecording()` and `cancelRecording()`:

```swift
activeRegionRect = nil
```

## Wiring once the property exists

In `Sources/Recording/RecordingStatusBar.swift`, `RecordingStatusBarController.show(on:)`, after
`panel.orderFrontRegardless()`:

```swift
if let rect = ScreenRecordingManager.shared.activeRegionRect {
    RecordingAreaHighlightPresenter.shared.show(rect: rect, on: preferredScreen)
}
```

`dismiss()` already calls `RecordingAreaHighlightPresenter.shared.hide()` unconditionally, so no
change is needed on the hide side.

## Status without this patch

The highlight overlay never appears (the code that would call `.show(rect:)` isn't there), which is
safe but means this task's "closes a real open issue" goal for the highlight is not actually live
yet. Everything else (the overlay window, its border/dim rendering, capture exclusion) works and is
ready the moment the property lands.
