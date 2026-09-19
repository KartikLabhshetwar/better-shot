import AppKit
import SwiftUI
import DynamicNotchKit
import Observation
import Synchronization
@testable import BetterShot

@MainActor
func checkNotchPresentation(imageURL: URL, movieURL: URL) async throws {
    let defaults = UserDefaults.standard
    let keys = [AppPreferences.presentationModeKey, BetterShotPreferences.recordingCameraDeviceIDKey,
                "bs_overlayDismissDelay", "bs_saveDirectory", "bs_overlayFollowsMouse"]
    let saved = keys.map { defaults.object(forKey: $0) }
    let notch = NotchPresenter.shared
    let bar = RecordingBarPresenter.shared
    let overlay = PreviewOverlay.shared
    ToastWindow.shared.dismiss(animated: false)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/editor-snapshots")
    let saveFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
    defer {
        overlay.dismiss()
        bar.hide()
        ToastWindow.shared.dismiss(animated: false)
        defaults.set("normal", forKey: AppPreferences.presentationModeKey)
        notch.refreshMode()
        for (key, value) in zip(keys, saved) {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: saveFolder)
    }
    defaults.removeObject(forKey: AppPreferences.presentationModeKey)
    precondition(AppPreferences.presentationMode == .normal, "Existing installs must keep normal mode")
    defaults.set("future-mode", forKey: AppPreferences.presentationModeKey)
    precondition(AppPreferences.presentationMode == .normal, "Unknown modes must safely fall back")
    defaults.set("", forKey: BetterShotPreferences.recordingCameraDeviceIDKey)
    AppPreferences.overlayFollowsMouse = false
    AppPreferences.overlayDismissDelay = 0.05
    AppPreferences.saveDirectory = saveFolder.path
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    notch.show()
    precondition(notch.expanded, "An empty compact notch must open the New Capture action")
    HistoryStore.shared.referenceCapture(at: imageURL, kind: .screenshot)
    HistoryStore.shared.referenceCapture(at: movieURL, kind: .recording)
    bar.showPicker(activate: false)
    overlay.show(url: imageURL)
    overlay.show(url: movieURL)
    precondition(notch.isVisible && bar.isVisible && overlay.isPresented)
    precondition(overlay.items == [imageURL, movieURL])
    precondition(!NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.CaptureOverlay" && $0.isVisible })
    guard let window = notch.window else { preconditionFailure("Missing DynamicNotchKit panel") }
    // Hover is driven explicitly below; keep the user's real pointer out of fixture state.
    window.ignoresMouseEvents = true
    precondition(window.sharingType == (PreviewWindowCaptureExclusion.includesAppWindowsInCaptures ? .readOnly : .none))
    precondition(window.canBecomeKey, "Notch controls must accept keyboard focus")
    try await Task.sleep(for: .milliseconds(120))
    precondition(overlay.items.count == 2, "Notch previews stay available until acted on")
    window.contentView?.layoutSubtreeIfNeeded()
    if let frame = notch.contentFrame, let screen = window.screen {
        precondition(frame.width > 600 && frame.height > 100)
        precondition(frame.width < screen.frame.width && frame.height < screen.frame.height)
        precondition(frame.midX > screen.frame.minX && frame.midX < screen.frame.maxX)
    }
    if let hosting = window.contentView {
        hosting.layoutSubtreeIfNeeded()
        precondition(hosting.hitTest(CGPoint(x: 1, y: 1)) == nil, "Transparent margins must pass clicks through")
        func hasNativeGlass(_ view: NSView) -> Bool {
            if let effect = view as? NSVisualEffectView,
               effect.material == .popover && effect.blendingMode == .behindWindow { return true }
            return view.subviews.contains(where: hasNativeGlass)
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            precondition(hasNativeGlass(hosting), "Expanded notch must use native behind-window glass")
        }
        let originalAppearance = window.appearance
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(80))
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("notch-native-\(appearance.rawValue).png"))
                if appearance == .darkAqua {
                    try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("notch-native-window.png"))
                }
            }
        }
        window.appearance = originalAppearance
    }
    notch.collapse()
    try await Task.sleep(for: .milliseconds(80))
    if let hosting = window.contentView {
        hosting.layoutSubtreeIfNeeded()
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("notch-compact.png"))
        }
    }
    if window.screen?.safeAreaInsets.top ?? 0 > 0 {
        precondition(!notch.expanded && notch.isVisible)
        bar.recordingConfirmation = .restartRecording
        precondition(notch.expanded, "Recording confirmations must expand a compact notch")
        bar.recordingConfirmation = nil
    }
    notch.show()
    notch.updateHoverState(true)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(180))
    precondition(!notch.expanded && notch.isVisible, "Leaving the notch must collapse without a click")
    notch.updateHoverState(true)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(180))
    precondition(!notch.expanded, "A brief pass across the notch must settle closed")
    notch.updateHoverState(true)
    try await Task.sleep(for: .milliseconds(180))
    precondition(notch.expanded, "Hover must open the whole compact surface")
    notch.updateHoverState(false)
    notch.updateHoverState(true)
    try await Task.sleep(for: .milliseconds(180))
    precondition(notch.expanded, "Returning before close must cancel pending dismissal")
    notch.menuTrackingCount = 2
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(180))
    precondition(notch.expanded, "Native menu tracking must keep the notch open")
    notch.menuTrackingCount -= 1
    notch.resumeHoverDismissal()
    try await Task.sleep(for: .milliseconds(180))
    precondition(notch.expanded, "Closing a submenu must preserve its parent menu")
    notch.menuTrackingCount -= 1
    notch.resumeHoverDismissal()
    try await Task.sleep(for: .milliseconds(180))
    precondition(!notch.expanded, "Dismiss after the menu closes with the pointer outside")
    notch.show()
    let child = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 80, height: 80),
        styleMask: .borderless, backing: .buffered, defer: false)
    child.isReleasedWhenClosed = false
    window.addChildWindow(child, ordered: .above)
    child.orderFront(nil)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(180))
    precondition(notch.expanded, "An attached popover must prevent premature collapse")
    window.removeChildWindow(child)
    child.close()
    // Closing native windows can synthesize hover events at the real pointer.
    // Send the intended leave after AppKit has finished removing the child.
    try await Task.sleep(for: .milliseconds(80))
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(180))
    precondition(!notch.expanded, "Leaving after a popover closes must collapse the notch")
    notch.updateHoverState(true)
    notch.suspendForCapture()
    try await Task.sleep(for: .milliseconds(180))
    precondition(!notch.isVisible, "Capture suspension must hide the hovered notch")
    notch.resumeAfterCapture()
    notch.window?.ignoresMouseEvents = true
    notch.show()
    notch.updateHoverState(true)
    print("PASS native hover open/leave, cancelled dismissal, menu/popover protection, and capture suspension")

    let recentImages = NotchRecentCaptures.items(kind: .screenshot)
    let recentVideos = NotchRecentCaptures.items(kind: .recording)
    precondition(recentImages.contains { $0.previewURL == imageURL })
    precondition(recentVideos.contains { $0.previewURL == movieURL })
    precondition(recentImages.allSatisfy { $0.kind == .screenshot }
        && recentVideos.allSatisfy { $0.kind == .recording })
    overlay.remove(movieURL)
    precondition(recentVideos.first(where: { $0.previewURL == movieURL })!.open(cloud: false) == nil)
    precondition(overlay.items.contains(movieURL), "Recent saved media must reopen the existing preview/actions")
    precondition(NotchRecentCaptures.items().count <= 4)
    print("PASS recent screenshot/video filters and reopening saved media through shared gallery actions")
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(NotchContent(), scheme: scheme, width: 660,
                     to: output.appendingPathComponent("notch-captures-\(name).png"), height: 700)
        try snapshot(PreferencesView(selection: .general), scheme: scheme, width: 780,
                     to: output.appendingPathComponent("notch-settings-\(name).png"), height: 620)
    }
    // Exercise the kit's non-notched fallback on the same screen without changing display settings.
    if let screen = window.screen {
        let floating = DynamicNotch(hoverBehavior: [], style: .floating) { NotchContent() }
        floating.presentImmediately(on: screen)
        defer { floating.dismissImmediately() }
        floating.presentImmediately(on: screen, expanded: false)
        try await Task.sleep(for: .milliseconds(80))
        let compactWidth = floating.contentFrame.width
        floating.presentImmediately(on: screen)
        try await Task.sleep(for: .milliseconds(80))
        precondition(floating.contentFrame.width > compactWidth,
                     "Non-notched displays must have a smaller compact surface")
        try await Task.sleep(for: .milliseconds(80))
        precondition(floating.windowController?.window?.isVisible == true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let fallbackWindow = floating.windowController!.window!
            fallbackWindow.appearance = NSAppearance(named: appearance)
            let hosting = fallbackWindow.contentView!
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("notch-floating-\(appearance.rawValue).png"))
            }
        }
    }
    defaults.set("normal", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(!notch.isVisible && overlay.items.count == 2 && bar.isVisible)
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.CaptureOverlay" && $0.isVisible })
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(notch.isVisible && overlay.items.count == 2)
    notch.suspendForCapture()
    precondition(!notch.isVisible && overlay.items.count == 2)
    await notch.runCountdown(seconds: 1, on: window.screen)
    precondition(notch.countdown == nil && !notch.isVisible, "Countdown must disappear before screenshot capture")
    // Updates arriving during capture must not bring the notch back into the image.
    ToastWindow.shared.show(message: "Saved", duration: 30)
    precondition(!notch.isVisible)
    notch.resumeAfterCapture()
    notch.window?.ignoresMouseEvents = true
    precondition(notch.isVisible)
    ToastWindow.shared.dismiss(animated: false)

    // Exercise the actual shared recording presentation without opening capture devices.
    bar.showRecording(displayID: window.screen.flatMap(ActiveDisplayResolver.displayID(for:)))
    precondition(bar.mode == .recording && notch.isVisible)
    defaults.set("normal", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(bar.mode == .recording && bar.isVisible && !notch.isVisible)
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(bar.mode == .recording && notch.isVisible)
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(NotchContent(), scheme: scheme, width: 660,
                     to: output.appendingPathComponent("notch-recording-\(scheme == .light ? "light" : "dark").png"), height: 700)
    }
    bar.hide()
    precondition(overlay.items.count == 2)
    overlay.perform(.share, for: imageURL)
    guard case .failed(_, _, true) = overlay.transferStatus(for: imageURL) else {
        preconditionFailure("Unconfigured cloud sharing must retain the capture and offer recovery")
    }
    overlay.dismissShareStatus(for: imageURL)
    overlay.perform(.save, for: imageURL)
    precondition(!overlay.items.contains(imageURL) && overlay.items.contains(movieURL))
    let savedFiles = try FileManager.default.contentsOfDirectory(atPath: saveFolder.path)
    precondition(!savedFiles.isEmpty)
    overlay.perform(.dismiss, for: movieURL)
    precondition(overlay.items.isEmpty)

    let owner = NSWindow(contentRect: CGRect(x: 30, y: 30, width: 320, height: 240),
                         styleMask: [.titled], backing: .buffered, defer: false)
    owner.isReleasedWhenClosed = false
    owner.contentView = NSView()
    owner.orderFrontRegardless()
    let anchor = TransferToastAnchorView(frame: .zero)
    owner.contentView!.addSubview(anchor)
    let keyWindow = NSApp.keyWindow
    let invalidations = Mutex(0)
    func trackTransfers() {
        withObservationTracking {
            _ = notch.transfers
            _ = notch.transferOrder
        } onChange: {
            invalidations.withLock { $0 += 1 }
        }
    }
    trackTransfers()
    for _ in 0..<20 { anchor.update(card: nil) }
    precondition(invalidations.withLock { $0 } == 0,
                 "Idle editor updates must not publish missing-transfer removals")
    anchor.update(card: TransferStatusCard(status: .working(stage: .exporting, progress: 0.5)))
    precondition(invalidations.withLock { $0 } == 1, "A new transfer must still publish")
    invalidations.withLock { $0 = 0 }
    trackTransfers()
    var lastAction = ""
    for _ in 0..<20 {
        anchor.update(card: TransferStatusCard(status: .working(stage: .exporting, progress: 0.5),
            onCancel: { lastAction = "cancel" }, onRetry: { lastAction = "retry" },
            onDismiss: { lastAction = "dismiss" }))
    }
    precondition(invalidations.withLock { $0 } == 0,
                 "Unchanged progress must not perpetually invalidate the editor")
    let activeCard = notch.transfers.values.first!
    activeCard.onCancel()
    precondition(lastAction == "cancel", "Deduplicated cards must use the latest actions")
    activeCard.onRetry()
    precondition(lastAction == "retry")
    activeCard.onDismiss()
    precondition(lastAction == "dismiss")
    precondition(notch.transfers.count == 1 && NSApp.keyWindow === keyWindow)
    anchor.update(card: TransferStatusCard(status: .exported(url: movieURL)))
    precondition(notch.transfers.count == 1, "Progress must update the existing transfer")
    precondition(invalidations.withLock { $0 } == 1, "Changed progress/completion must still publish")
    owner.close()
    precondition(notch.transfers.isEmpty, "Closing the owner cleans up notch transfer feedback")
    anchor.removeFromSuperview()
    print("PASS transfer observation settles for idle/unchanged progress, publishes real changes, and retains current callbacks")
    print("PASS notch defaults, mode migration, pending images/video, capture suspension, recording controls, save/share recovery, transfer cleanup, compact light/dark snapshots")
}
