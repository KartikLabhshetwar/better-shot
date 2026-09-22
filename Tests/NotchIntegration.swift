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
                "bs_overlayDismissDelay", "bs_saveDirectory", "bs_overlayFollowsMouse",
                AppPreferences.overlayAlwaysShowActionsKey]
    let saved = keys.map { defaults.object(forKey: $0) }
    let configuration = ProcessInfo.processInfo.environment["BETTERSHOT_BUILD_CONFIGURATION"] ?? "Debug"
    let derived = ProcessInfo.processInfo.environment["BETTERSHOT_DERIVED_DATA"] ?? ".build/tests"
    let bundle = Bundle(url: URL(fileURLWithPath: derived).appendingPathComponent("Build/Products/\(configuration)/BetterShot.app"))!
    let logo = bundle.image(forResource: "MenuBarIcon")!
    logo.setName("MenuBarIcon")
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
        notch.captureIssue = nil
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
    bar.hide()
    overlay.dismiss()
    notch.captureIssue = nil
    notch.ocrText = nil
    notch.colorHex = nil
    notch.transfers.removeAll()
    notch.transferOrder.removeAll()
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(notch.isVisible && notch.expanded,
                 "Switching to Notch Mode must immediately open the preview shelf")
    notch.refresh()
    precondition(notch.isVisible && !notch.expanded,
                 "An empty Notch Mode shelf must settle into its compact resting state")
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: .control, modifierChanged: true)
    precondition(!notch.expanded && !NotchVoiceCapture.shared.holdIndicatorActive,
                 "Pressing the capture modifier alone must not expand the notch")
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: [], modifierChanged: true)
    precondition(!notch.expanded, "Releasing an unused capture modifier must keep the notch compact")
    HistoryStore.shared.referenceCapture(at: imageURL, kind: .screenshot)
    HistoryStore.shared.referenceCapture(at: movieURL, kind: .recording)
    bar.showPicker(activate: false)
    precondition(notch.isVisible && !notch.expanded,
                 "The floating capture bar must not expand the preview-only notch")
    overlay.show(url: imageURL)
    overlay.show(url: movieURL)
    precondition(notch.isVisible && bar.isVisible && overlay.isPresented)
    precondition(overlay.items == [imageURL, movieURL])
    precondition(!NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.CaptureOverlay" && $0.isVisible })
    guard let window = notch.window else { preconditionFailure("Missing DynamicNotchKit panel") }
    // Hover is driven explicitly below; keep the user's real pointer out of fixture state.
    window.ignoresMouseEvents = true
    // Cancel any leave scheduled before pointer isolation took effect.
    notch.updateHoverState(true)
    precondition(window.sharingType == (PreviewWindowCaptureExclusion.includesAppWindowsInCaptures ? .readOnly : .none))
    precondition(window.canBecomeKey, "Notch controls must accept keyboard focus")
    // Allow the 140 ms presentation transition to settle before measuring geometry.
    try await Task.sleep(for: .milliseconds(350))
    precondition(overlay.items.count == 2, "Notch previews stay available until acted on")
    window.contentView?.layoutSubtreeIfNeeded()
    if let frame = notch.contentFrame, let screen = window.screen {
        precondition(frame.width >= 552 && frame.height > 100, "Expanded notch frame: \(frame)")
        precondition(frame.width < screen.frame.width && frame.height < screen.frame.height)
        precondition(frame.midX > screen.frame.minX && frame.midX < screen.frame.maxX)
    }
    if let hosting = window.contentView {
        hosting.layoutSubtreeIfNeeded()
        precondition(hosting.hitTest(CGPoint(x: 1, y: 1)) == nil, "Transparent margins must pass clicks through")
        let originalAppearance = window.appearance
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(80))
            hosting.layoutSubtreeIfNeeded()
            try snapshotNativeNotch(notch, to: output.appendingPathComponent("notch-native-\(appearance.rawValue).png"))
            if appearance == .darkAqua {
                try snapshotNativeNotch(notch, to: output.appendingPathComponent("notch-native-window.png"))
            }
        }
        window.appearance = originalAppearance
    }
    notch.collapse()
    try await Task.sleep(for: .milliseconds(200))
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: .control, modifierChanged: true)
    try await Task.sleep(for: .milliseconds(100))
    precondition(!notch.expanded && !NotchVoiceCapture.shared.holdIndicatorActive,
                 "Pressing the capture modifier alone must not expand compact content")
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: [], modifierChanged: true)
    notch.collapse()
    try await Task.sleep(for: .milliseconds(350))
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
        precondition(!notch.expanded, "Recording confirmations must stay in the floating recording bar")
        bar.recordingConfirmation = nil
    }
    notch.show()
    notch.updateHoverState(true)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(350))
    precondition(!notch.expanded && notch.isVisible, "Leaving the notch must collapse without a click (menu tracking: \(notch.menuTrackingCount), modal: \(NSApp.modalWindow != nil), children: \(window.childWindows?.count ?? 0))")
    notch.updateHoverState(true)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(350))
    precondition(!notch.expanded, "A brief pass across the notch must settle closed")
    notch.updateHoverState(true)
    try await Task.sleep(for: .milliseconds(350))
    precondition(notch.expanded, "Hover must open the whole compact surface")
    notch.updateHoverState(false)
    notch.updateHoverState(true)
    try await Task.sleep(for: .milliseconds(350))
    precondition(notch.expanded, "Returning before close must cancel pending dismissal")
    notch.menuTrackingCount = 2
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(350))
    precondition(notch.expanded, "Native menu tracking must keep the notch open")
    notch.menuTrackingCount -= 1
    notch.resumeHoverDismissal()
    try await Task.sleep(for: .milliseconds(350))
    precondition(notch.expanded, "Closing a submenu must preserve its parent menu")
    notch.menuTrackingCount -= 1
    notch.resumeHoverDismissal()
    try await Task.sleep(for: .milliseconds(350))
    precondition(!notch.expanded, "Dismiss after the menu closes with the pointer outside")
    notch.show()
    let child = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 80, height: 80),
        styleMask: .borderless, backing: .buffered, defer: false)
    child.isReleasedWhenClosed = false
    window.addChildWindow(child, ordered: .above)
    child.orderFront(nil)
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(350))
    precondition(notch.expanded, "An attached popover must prevent premature collapse")
    window.removeChildWindow(child)
    child.close()
    // Closing native windows can synthesize hover events at the real pointer.
    // Send the intended leave after AppKit has finished removing the child.
    try await Task.sleep(for: .milliseconds(80))
    notch.updateHoverState(false)
    try await Task.sleep(for: .milliseconds(350))
    precondition(!notch.expanded, "Leaving after a popover closes must collapse the notch")
    notch.updateHoverState(true)
    notch.suspendForCapture()
    try await Task.sleep(for: .milliseconds(350))
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
    precondition(!R2CredentialStore.shared.isConfigured, "Tests must not access R2 credentials")
    overlay.remove(movieURL)
    overlay.share(movieURL)
    precondition(overlay.items.contains(movieURL) && overlay.transferStatus(for: movieURL) != nil,
                 "Sharing recent media must enter the shared transfer flow and show setup guidance")
    overlay.dismissShareStatus(for: movieURL)
    precondition(NotchRecentCaptures.items().count <= 4)
    let shelf = NotchRecentCaptures.mediaURLs(pending: [imageURL, movieURL, imageURL], filter: .all)
    precondition(shelf.prefix(2) == [imageURL, movieURL], "Newest pending captures lead, with no duplicate recent cards")
    precondition(Set(shelf).count == shelf.count)
    precondition(NotchRecentCaptures.mediaURLs(pending: [imageURL, movieURL], filter: .images).allSatisfy { !PreviewOverlay.isVideo($0) })
    precondition(NotchRecentCaptures.mediaURLs(pending: [imageURL, movieURL], filter: .videos).allSatisfy { PreviewOverlay.isVideo($0) })
    precondition(NotchRecentCaptures.mediaURLs(pending: [imageURL], filter: .text).isEmpty)
    precondition(NotchRecentCaptures.mediaURLs(pending: [imageURL], filter: .colors).isEmpty)
    let oldText = NotchShelfStore.Entry(text: "Older text", date: .distantPast)
    let mixed = NotchRecentCaptures.shelfItems(pending: [imageURL], entries: [oldText], filter: .all)
    guard let first = mixed.first, case .media = first else {
        preconditionFailure("All must put the newest pending capture before older text")
    }
    let newText = NotchShelfStore.Entry(text: "Newest text", date: .distantFuture)
    let textFirst = NotchRecentCaptures.shelfItems(pending: [], entries: [newText], filter: .all)
    guard let first = textFirst.first, case .result(let entry) = first, entry.id == newText.id else {
        preconditionFailure("All must order every capture type by recency")
    }
    let voice = NotchShelfStore.Entry(text: "Make this smaller", imageURL: imageURL)
    let combinedVoice = NotchRecentCaptures.shelfItems(pending: [imageURL], entries: [voice], filter: .all)
    precondition(combinedVoice.contains { $0.id == "result-\(voice.id)" }
                    && !combinedVoice.contains { $0.id == "media-\(imageURL.standardizedFileURL.path)" },
                 "A voice annotation must keep its image and transcript in one shelf item")
    print("PASS recent media filters, shared gallery actions, and chronological All ordering")
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(NotchContent().environment(\.colorScheme, .dark).padding(16).background(.black), scheme: scheme, width: 592,
                     to: output.appendingPathComponent("notch-captures-\(name).png"), height: 700)
        try snapshot(NotchContent(filter: .images).environment(\.colorScheme, .dark).padding(16).background(.black), scheme: scheme, width: 592,
                     to: output.appendingPathComponent("notch-recents-\(name).png"), height: 360)
        let sample = OnboardingSample.coast.sourceURL(in: bundle).flatMap { NSImage(contentsOf: $0) } ?? NSImage(contentsOf: imageURL)!
        for actions in [false, true] {
            defaults.set(actions, forKey: AppPreferences.overlayAlwaysShowActionsKey)
            try snapshot(HStack(spacing: 16) {
                PreviewCardView(overlay: overlay, url: imageURL, thumbnail: sample,
                                usesNotchActions: true, notchCardSize: CGSize(width: 184, height: 160))
                PreviewCardView(overlay: overlay, url: movieURL, thumbnail: sample,
                                usesNotchActions: true, notchCardSize: CGSize(width: 184, height: 160))
            }.padding(20).background(.black), scheme: scheme, width: 424,
                to: output.appendingPathComponent("notch-media-\(actions ? "actions" : "idle")-\(name).png"), height: 200)
        }
        defaults.set(false, forKey: AppPreferences.overlayAlwaysShowActionsKey)
        try snapshot(PreferencesView(selection: .general), scheme: scheme, width: 780,
                     to: output.appendingPathComponent("notch-settings-\(name).png"), height: 620)
        try snapshot(OverlayLayoutEditor(layout: .constant(.standard)), scheme: scheme, width: 298,
                     to: output.appendingPathComponent("notch-overlay-controls-\(name).png"), height: 228)
    }
    try await checkLocalShelfFeatures(imageURL: imageURL, directory: saveFolder, output: output)
    let quickPanel = NotchQuickEditor.shared
    quickPanel.open(imageURL)
    precondition(quickPanel.panel?.canBecomeKey == true && quickPanel.panel!.frame.width <= 640)
    quickPanel.requestClose()
    precondition(!quickPanel.isOpen)
    if let screen = NSScreen.main {
        let oldRegion = AppPreferences.lastRegionRect
        defer { AppPreferences.lastRegionRect = oldRegion }
        let selector = RegionSelectionOverlay()
        var outcome: RegionSelectionOutcome?
        let origin = CGPoint(x: screen.frame.minX + 60, y: screen.frame.minY + 60)
        selector.beginControlDrag(at: origin) { outcome = $0 }
        selector.updateControlDrag(at: CGPoint(x: origin.x + 200, y: origin.y + 120), ended: true)
        guard case .region(let region) = outcome else { preconditionFailure("Control drag must select a region on mouse release") }
        precondition(region.pointsRect.size == CGSize(width: 200, height: 120))
        selector.beginControlDrag(at: origin) { outcome = $0 }
        selector.cancelControlDrag()
        guard case .cancelled = outcome else { preconditionFailure("Releasing Control early must cancel") }
    }
    print("PASS Control-drag rectangle geometry and cancellation")
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
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.RecordingBar" && $0.isVisible })
    ToastWindow.shared.show(message: "Normal mode toast", duration: 30)
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.Toast" && $0.isVisible })
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(!NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.Toast" && $0.isVisible },
                 "Switching to Notch Mode must remove an already visible toast")
    precondition(notch.isVisible && overlay.items.count == 2)
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.RecordingBar" && $0.isVisible },
                 "Mode switching must not move or recreate the floating capture bar")
    for _ in 0..<6 {
        defaults.set("normal", forKey: AppPreferences.presentationModeKey)
        notch.refreshMode()
        precondition(!notch.isVisible && bar.isVisible)
        defaults.set("notch", forKey: AppPreferences.presentationModeKey)
        notch.refreshMode()
        precondition(notch.isVisible && bar.isVisible)
    }
    notch.collapse()
    ToastWindow.shared.show(message: "Saved", duration: 30)
    precondition(!notch.expanded && notch.captureIssue == nil,
                 "Success notifications must not expand or add content to the notch")
    ToastWindow.shared.show(isError: true, title: "Couldn’t save capture", message: "Check the save folder and try Save again.")
    precondition(notch.captureIssue?.title == "Couldn’t save capture" && notch.expanded)
    precondition(!NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.Toast" && $0.isVisible })
    try snapshot(NotchContent().environment(\.colorScheme, .dark).padding(16).background(.black),
        scheme: .dark, width: 592, to: output.appendingPathComponent("notch-inline-error.png"), height: 500)
    notch.suspendForCapture()
    precondition(notch.captureIssue == nil, "Trying a capture again clears stale failure feedback")
    print("PASS no notch toasts, no success expansion, immediate mode-switch dismissal, and inline failure recovery")
    precondition(!notch.isVisible && overlay.items.count == 2)
    // Updates arriving during capture must not bring the notch back into the image.
    ToastWindow.shared.show(message: "Saved", duration: 30)
    precondition(!notch.isVisible)
    notch.resumeAfterCapture()
    notch.window?.ignoresMouseEvents = true
    precondition(notch.isVisible)
    ToastWindow.shared.dismiss(animated: false)

    // Recording stays in its floating bar while the notch remains preview-only.
    bar.showRecording(displayID: window.screen.flatMap(ActiveDisplayResolver.displayID(for:)))
    precondition(bar.mode == .recording && notch.isVisible)
    defaults.set("normal", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(bar.mode == .recording && bar.isVisible && !notch.isVisible)
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    precondition(bar.mode == .recording && notch.isVisible)
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.RecordingBar" && $0.isVisible })
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(NotchContent().environment(\.colorScheme, .dark).padding(16).background(.black), scheme: scheme, width: 592,
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
    await Task.yield()
    precondition(notch.isVisible && !notch.expanded,
                 "Dismissing the last preview must return the notch to its compact resting state")
    bar.showRecording(displayID: window.screen.flatMap(ActiveDisplayResolver.displayID(for:)))
    precondition(bar.mode == .recording && notch.isVisible && !notch.expanded,
                 "Recording controls must never expand the preview-only notch")
    precondition(NSApp.windows.contains { $0.identifier?.rawValue == "BetterShot.RecordingBar" && $0.isVisible })
    bar.hide()
    precondition(notch.isVisible && !notch.expanded)

    // Closing the final card must retire its hosting panel after the button event,
    // rather than deallocating the SwiftUI control while its action is executing.
    defaults.set("normal", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()
    overlay.show(url: imageURL, automaticallyDismiss: false)
    guard let closingPanel = NSApp.windows.first(where: {
        $0.identifier?.rawValue == "BetterShot.CaptureOverlay" && $0.isVisible
    }) else { preconditionFailure("Missing normal preview panel") }
    overlay.perform(.dismiss, for: imageURL)
    precondition(closingPanel.isVisible)
    await Task.yield()
    precondition(!closingPanel.isVisible, "Closing a preview must defer panel teardown past the action event")
    defaults.set("notch", forKey: AppPreferences.presentationModeKey)
    notch.refreshMode()

    let clipboard = NSPasteboard(name: .init("BetterShot.NotchResultTests.\(UUID().uuidString)"))
    defer { clipboard.releaseGlobally() }
    let captures = CaptureOrchestrator.shared
    captures.completeTextCapture("First line\nSecond line", action: .ocr, pasteboard: clipboard)
    precondition(notch.ocrText == "First line\nSecond line")
    precondition(clipboard.string(forType: .string) == notch.ocrText)
    captures.completeTextCapture("First line\nSecond line", action: .ocrSingleLine, pasteboard: clipboard)
    precondition(notch.ocrText == "First line Second line")
    captures.completeTextCapture("#27A5E8", action: .colorPicker, pasteboard: clipboard)
    precondition(notch.colorHex == "#27A5E8" && clipboard.string(forType: .string) == notch.colorHex)
    ToastWindow.shared.dismiss(animated: false)
    notch.collapse()
    notch.show()
    precondition(notch.ocrText == "First line Second line" && notch.colorHex == "#27A5E8")
    precondition(CaptureOrchestrator.copyText(notch.ocrText!, to: clipboard))
    precondition(clipboard.string(forType: .string) == "First line Second line")
    captures.completeTextCapture(" \n ", action: .ocr, pasteboard: clipboard)
    precondition(notch.ocrText == "First line Second line", "Empty OCR must preserve the last useful result")
    precondition(clipboard.string(forType: .string) == "First line Second line")
    precondition(notch.captureIssue?.title == "No text found")
    notch.captureIssue = nil
    ToastWindow.shared.dismiss(animated: false)
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(NotchContent().environment(\.colorScheme, .dark).padding(16).background(.black),
            scheme: scheme, width: 592, to: output.appendingPathComponent("notch-text-results-\(scheme == .light ? "light" : "dark").png"), height: 440)
    }
    notch.updateHoverState(true)
    try await Task.sleep(for: .milliseconds(250))
    try snapshotNativeNotch(notch, to: output.appendingPathComponent("notch-native-results.png"))
    notch.ocrText = nil
    notch.colorHex = nil
    print("PASS OCR/color auto-copy, single-line normalization, persistent notch results, repeat copy, and empty OCR")

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
    print("PASS notch defaults, mode migration, preview-only content, capture suspension, save/share recovery, transfer cleanup, compact light/dark snapshots")
}

@MainActor
func checkLocalShelfFeatures(imageURL: URL, directory: URL, output: URL) async throws {
    let oldMode = UserDefaults.standard.object(forKey: AppPreferences.presentationModeKey)
    let oldOptionGesture = UserDefaults.standard.object(forKey: NotchVoiceCapture.gestureKey)
    UserDefaults.standard.set("notch", forKey: AppPreferences.presentationModeKey)
    defer {
        if let oldMode { UserDefaults.standard.set(oldMode, forKey: AppPreferences.presentationModeKey) }
        else { UserDefaults.standard.removeObject(forKey: AppPreferences.presentationModeKey) }
        if let oldOptionGesture { UserDefaults.standard.set(oldOptionGesture, forKey: NotchVoiceCapture.gestureKey) }
        else { UserDefaults.standard.removeObject(forKey: NotchVoiceCapture.gestureKey) }
    }
    UserDefaults.standard.removeObject(forKey: NotchVoiceCapture.gestureKey)
    precondition(!NotchVoiceCapture.optionGestureEnabled, "Option voice capture must be opt-in")
    UserDefaults.standard.set(true, forKey: NotchVoiceCapture.gestureKey)
    precondition(NotchVoiceCapture.optionGestureEnabled, "Users must be able to enable the Option gesture")
    let oldAction = UserDefaults.standard.object(forKey: NotchVoiceCapture.actionKey)
    defer {
        if let oldAction { UserDefaults.standard.set(oldAction, forKey: NotchVoiceCapture.actionKey) }
        else { UserDefaults.standard.removeObject(forKey: NotchVoiceCapture.actionKey) }
    }
    for action in [nil, "area", "unknown", "draw"] as [String?] {
        if let action { UserDefaults.standard.set(action, forKey: NotchVoiceCapture.actionKey) }
        else { UserDefaults.standard.removeObject(forKey: NotchVoiceCapture.actionKey) }
        precondition(NotchVoiceCapture.drawsOnHold == (action == "draw"), "Screen drawing must be explicitly selected; area capture is the default")
    }
    UserDefaults.standard.set("area", forKey: NotchVoiceCapture.actionKey)
    var gesture = NotchControlGesture()
    _ = gesture.update(flags: .control, modifierChanged: true)
    precondition(gesture.armed)
    _ = gesture.update(flags: .control, modifierChanged: false)
    precondition(!gesture.armed, "Control-key chords must cancel capture")
    _ = gesture.update(flags: [], modifierChanged: true)
    _ = gesture.update(flags: [.control, .shift], modifierChanged: true)
    _ = gesture.update(flags: .control, modifierChanged: true)
    precondition(!gesture.armed, "Releasing another modifier must not arm a held Control")
    _ = gesture.update(flags: [], modifierChanged: true)
    _ = gesture.update(flags: .control, modifierChanged: true)
    precondition(gesture.armed)
    _ = gesture.update(flags: [], modifierChanged: true)
    precondition(!gesture.armed)

    for key in NotchCaptureHoldKey.allCases {
        var configured = NotchControlGesture()
        _ = configured.update(flags: key.modifier, modifierChanged: true, holdKey: key)
        precondition(configured.armed, "The selected hold key must arm capture")
        _ = configured.update(flags: key.modifier, modifierChanged: false, holdKey: key)
        precondition(!configured.armed, "Typing a shortcut must cancel capture")
        _ = configured.update(flags: [], modifierChanged: true, holdKey: key)
        let other: NSEvent.ModifierFlags = key == .control ? .shift : .control
        _ = configured.update(flags: other, modifierChanged: true, holdKey: key)
        precondition(!configured.armed, "An unassigned modifier must not arm capture")
        _ = configured.update(flags: key.modifier.union(other), modifierChanged: true, holdKey: key)
        _ = configured.update(flags: key.modifier, modifierChanged: true, holdKey: key)
        precondition(!configured.armed, "Releasing a chord must not arm capture")
    }
    let oldHoldKey = UserDefaults.standard.object(forKey: NotchVoiceCapture.holdKey)
    let oldControlEnabled = UserDefaults.standard.object(forKey: NotchVoiceCapture.controlKey)
    UserDefaults.standard.set(true, forKey: NotchVoiceCapture.controlKey)
    UserDefaults.standard.set("option", forKey: NotchVoiceCapture.holdKey)
    precondition(NotchVoiceCapture.optionUsedForCapture, "Area capture must take priority over Option voice")
    UserDefaults.standard.set("unknown", forKey: NotchVoiceCapture.holdKey)
    precondition(NotchVoiceCapture.captureHoldKey == .control, "Unknown preferences must retain the default gesture")
    UserDefaults.standard.set(oldHoldKey, forKey: NotchVoiceCapture.holdKey)
    UserDefaults.standard.set(oldControlEnabled, forKey: NotchVoiceCapture.controlKey)
    print("PASS customizable hold keys, chord cancellation and Option voice conflict")

    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    // Bounded clipboard history and private pasteboard markers, using an isolated store/pasteboard.
    let shelfDirectory = directory.appendingPathComponent("shelf")
    let shelf = NotchShelfStore(directory: shelfDirectory)
    let clipboard = NSPasteboard(name: .init("BetterShotShelfTests-\(UUID())"))
    defer { clipboard.releaseGlobally() }
    CaptureOrchestrator.copyText("first", to: clipboard)
    shelf.readClipboard(clipboard)
    precondition(shelf.entries.map(\.text) == ["first"])
    clipboard.clearContents()
    clipboard.setString("secret", forType: .string)
    clipboard.setString("", forType: .init("org.nspasteboard.ConcealedType"))
    shelf.readClipboard(clipboard)
    precondition(shelf.entries.count == 1, "Concealed clipboard content must never enter history")
    shelf.add(text: String(repeating: "x", count: 100_001))
    shelf.add(text: "   ")
    precondition(shelf.entries.count == 1)
    for index in 0..<55 { shelf.add(text: "item \(index)") }
    shelf.add(text: "item 10")
    precondition(shelf.entries.count == 50 && shelf.entries.first?.text == "item 10")
    precondition(NotchShelfStore(directory: shelfDirectory).entries == shelf.entries)
    let voiceEntry = NotchShelfStore.Entry(text: "Make this button smaller.", imageURL: imageURL)
    let voiceCopied = try NotchShelfStore.copy(voiceEntry, to: clipboard)
    precondition(voiceCopied)
    precondition(clipboard.string(forType: .string) == voiceEntry.text)
    precondition(clipboard.data(forType: .png) != nil && clipboard.string(forType: .fileURL) != nil)
    shelf.readClipboard(clipboard)
    precondition(shelf.entries.count == 50 && shelf.entries.first?.text == "item 10")
    let clipboardBeforeFailure = clipboard.changeCount
    do {
        _ = try NotchShelfStore.copy(.init(text: "missing", imageURL: directory.appendingPathComponent("missing.png")), to: clipboard)
        preconditionFailure("Missing images must fail without replacing the clipboard")
    } catch { precondition(clipboard.changeCount == clipboardBeforeFailure) }
    shelf.add(text: "#FF8800", isColor: true)
    precondition(NotchShelfStore(directory: shelfDirectory).entries.first?.isColor == true)
    let countInNotch = shelf.entries.count
    UserDefaults.standard.set("normal", forKey: AppPreferences.presentationModeKey)
    shelf.add(text: "must not save")
    CaptureOrchestrator.copyText("normal clipboard", to: clipboard)
    shelf.readClipboard(clipboard)
    precondition(shelf.entries.count == countInNotch && !shelf.entries.contains { $0.text == "must not save" || $0.text == "normal clipboard" })
    UserDefaults.standard.set("notch", forKey: AppPreferences.presentationModeKey)
    shelf.clear()
    precondition(NotchShelfStore(directory: shelfDirectory).entries.isEmpty)
    for value in ["#F80", "#aBcDeF", " #123456\n"] { precondition(NotchShelfStore.isHexColor(value)) }
    for value in ["123456", "#GGG", "color: #ffffff", "#12", "#💚💚💚"] { precondition(!NotchShelfStore.isHexColor(value)) }
    CaptureOrchestrator.copyText("#8B5CF6", to: clipboard)
    shelf.readClipboard(clipboard, includeText: false)
    precondition(shelf.entries.first?.isColor == true)
    precondition(NotchShelfStore(directory: shelfDirectory).entries.first?.isColor == true)
    CaptureOrchestrator.copyText("not a color", to: clipboard)
    shelf.readClipboard(clipboard, includeText: false)
    precondition(shelf.entries.count == 1, "Color-only collection must not retain ordinary text")
    CaptureOrchestrator.copyText("#F80", to: clipboard)
    shelf.readClipboard(clipboard, includeColors: false)
    precondition(shelf.entries.count == 1, "Disabled color collection must not retain new swatches")
    shelf.clear()
    print("PASS local clipboard persistence, size limits, deduplication, private markers, clear, and image/transcript copy")

    let quickModel = AnnotationEditorModel()
    quickModel.load(url: imageURL)
    quickModel.backgroundSettings = AnnotationBackgroundSettings()
    if quickModel.selectedTool != .freehand { quickModel.selectTool(.freehand) }
    let imageFrame = CGRect(origin: .zero, size: quickModel.imageSize)
    quickModel.beginInteraction(at: CGPoint(x: 30, y: 30), imageFrame: imageFrame, boundaryFrame: imageFrame)
    quickModel.updateInteraction(to: CGPoint(x: 120, y: 100), imageFrame: imageFrame, boundaryFrame: imageFrame)
    quickModel.endInteraction(at: CGPoint(x: 150, y: 100), imageFrame: imageFrame, boundaryFrame: imageFrame)
    precondition(!quickModel.shapes.isEmpty)
    let originalPixels = try Data(contentsOf: imageURL)
    let quickResult = try await NotchQuickEditor.commit(quickModel)
    let preservedPixels = try Data(contentsOf: imageURL)
    precondition(originalPixels == preservedPixels, "Quick edits must retain the untouched source")
    precondition(ScreenshotImageLoader.imageSize(at: quickResult) == quickModel.imageSize)
    let reopenedQuick = AnnotationEditorModel()
    reopenedQuick.load(url: quickResult)
    precondition(reopenedQuick.shapes == quickModel.shapes, "Quick edits must stay editable in the full editor")
    let quick = NotchQuickEditor.shared
    quick.model.load(url: quickResult)
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(NotchQuickEditorView(editor: quick), scheme: scheme, width: 640,
                     to: output.appendingPathComponent("notch-quick-editor-\(scheme == .dark ? "dark" : "light").png"), height: 460)
    }
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: .control, modifierChanged: true)
    try snapshot(NotchQuickEditorView(editor: quick, fullScreen: true), scheme: .dark, width: 960,
                 to: output.appendingPathComponent("notch-screen-annotation.png"), height: 540)
    _ = NotchVoiceCapture.shared.controlGesture.update(flags: [], modifierChanged: true)
    quick.model.releaseEditorResources()
    quickModel.releaseEditorResources()
    reopenedQuick.releaseEditorResources()
    if let screen = NSScreen.main {
        let heldURL = directory.appendingPathComponent("held-drawing-fixture.png")
        try originalPixels.write(to: heldURL)
        let before = Set(PreviewOverlay.shared.items)
        let gesture = NotchVoiceCapture.shared
        _ = gesture.controlGesture.update(flags: .control, modifierChanged: true)
        quick.open(heldURL, on: screen, fullScreen: true)
        gesture.beginDrawingSession()
        precondition(quick.model.selectedTool == .freehand && !quick.hasVoice && gesture.holdIndicatorActive)
        func sendStroke(_ type: CGEventType, point: CGPoint, flags: CGEventFlags = .maskControl) -> Bool {
            let event = CGEvent(source: nil)!
            event.type = type
            event.flags = flags
            event.location = CGPoint(x: screen.frame.minX + point.x,
                y: CGDisplayBounds(CGMainDisplayID()).height - screen.frame.maxY + point.y)
            return gesture.handleControlEvent(type: type, event: event)
        }
        precondition(sendStroke(.leftMouseDown, point: CGPoint(x: 80, y: 100)))
        precondition(sendStroke(.leftMouseDragged, point: CGPoint(x: 160, y: 150)))
        _ = sendStroke(.flagsChanged, point: .zero, flags: [])
        precondition(quick.isOpen, "Releasing the key during a stroke must wait for mouse-up")
        precondition(sendStroke(.leftMouseUp, point: CGPoint(x: 200, y: 100), flags: []))
        for _ in 0..<60 {
            if !quick.isOpen { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(!quick.isOpen && !gesture.holdIndicatorActive)
        let saved = PreviewOverlay.shared.items.filter { !before.contains($0) }
        precondition(saved.count == 1, "One held drawing saves one annotated screenshot")
        let restored = AnnotationEditorModel()
        restored.load(url: saved[0])
        precondition(restored.shapes.count == 1, "The final stroke must remain editable")
        restored.releaseEditorResources()
        saved.forEach { PreviewOverlay.shared.remove($0) }
    }
    print("PASS held drawing events, deferred mouse-up save, microphone-free annotations and editable persistence")
    print("PASS quick-edit full-resolution render, editable annotations, and compact light/dark layouts")

}

@MainActor
private func snapshotNativeNotch(_ notch: NotchPresenter, to url: URL) throws {
    guard let window = notch.window, let hosting = window.contentView, let frame = notch.contentFrame,
          let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
    // Cache the full hosting view: drawing a nonzero-origin subrect flips some SwiftUI text layers.
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let bounds = hosting.convert(window.convertFromScreen(frame), from: nil)
    let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
    let top = hosting.isFlipped ? bounds.minY : hosting.bounds.height - bounds.maxY
    let pixels = CGRect(x: bounds.minX * scale, y: top * scale,
                        width: bounds.width * scale, height: bounds.height * scale)
    guard let cropped = bitmap.cgImage?.cropping(to: pixels) else { return }
    try NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])?.write(to: url)
}
