import AppKit
import Carbon
import SwiftUI
@testable import BetterShot

/// Offscreen view snapshots and real model checks; does not drive the user's desktop.
/// AVPlayer layers and window toolbars require live UI testing and are not captured here.
@MainActor
func checkEditorUI(imageURL: URL, movieURL: URL) async throws {
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
        NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
            let neutral = StudioChrome.accentNSColor.usingColorSpace(.deviceRGB)!
            precondition(abs(neutral.redComponent - neutral.greenComponent) < 0.001
                         && abs(neutral.greenComponent - neutral.blueComponent) < 0.001,
                         "Editor chrome must remain neutral in both appearances")
        }
    }
    let suiteName = "BetterShot-shortcuts-" + UUID().uuidString
    let shortcutDefaults = UserDefaults(suiteName: suiteName)!
    defer { shortcutDefaults.removePersistentDomain(forName: suiteName) }
    let shortcuts = ShortcutService.Shortcut.self
    precondition(shortcuts.defaultRegion.keyCode == UInt32(kVK_ANSI_2))
    precondition(shortcuts.defaultRecording.keyCode == UInt32(kVK_ANSI_5))
    for (oldRegionKey, oldRecordingKey, enabled) in [
        (kVK_ANSI_4, kVK_ANSI_2, true),
        (kVK_ANSI_4, kVK_ANSI_2, false),
        (kVK_ANSI_7, kVK_ANSI_8, true)
    ] {
        shortcutDefaults.removePersistentDomain(forName: suiteName)
        var region = shortcuts.defaultRegion
        region.keyCode = UInt32(oldRegionKey)
        region.enabled = enabled
        var recording = shortcuts.defaultRecording
        recording.keyCode = UInt32(oldRecordingKey)
        recording.enabled = enabled
        try shortcutDefaults.set(JSONEncoder().encode(region), forKey: "bs_hotkey_1")
        try shortcutDefaults.set(JSONEncoder().encode(recording), forKey: "bs_hotkey_6")
        ShortcutService.migrateCaptureShortcuts(defaults: shortcutDefaults)
        let migratedRegion = try JSONDecoder().decode(ShortcutService.Shortcut.self,
            from: shortcutDefaults.data(forKey: "bs_hotkey_1")!)
        let migratedRecording = try JSONDecoder().decode(ShortcutService.Shortcut.self,
            from: shortcutDefaults.data(forKey: "bs_hotkey_6")!)
        precondition(migratedRegion.keyCode == UInt32(oldRegionKey == kVK_ANSI_4 ? kVK_ANSI_2 : oldRegionKey))
        precondition(migratedRecording.keyCode == UInt32(oldRecordingKey == kVK_ANSI_2 ? kVK_ANSI_5 : oldRecordingKey))
        precondition(migratedRegion.enabled == enabled && migratedRecording.enabled == enabled)
        // A later intentional reassignment must survive subsequent launches.
        try shortcutDefaults.set(JSONEncoder().encode(recording), forKey: "bs_hotkey_6")
        ShortcutService.migrateCaptureShortcuts(defaults: shortcutDefaults)
        let reassigned = try JSONDecoder().decode(ShortcutService.Shortcut.self,
            from: shortcutDefaults.data(forKey: "bs_hotkey_6")!)
        precondition(reassigned == recording)
    }
    print("PASS screenshot/recording defaults, migration, custom bindings, and disabled shortcuts")

    let imageModel = AnnotationEditorModel()
    imageModel.previewImage = NSImage(contentsOf: imageURL)!
    imageModel.imageSize = CGSize(width: 1920, height: 1080)
    imageModel.viewportSize = CGSize(width: 1000, height: 600)
    imageModel.displayScale = 2
    imageModel.setZoomPercent(100)
    imageModel.zoomIn()
    precondition(imageModel.zoomPercent == 125)
    imageModel.zoomOut()
    precondition(imageModel.zoomPercent == 100)
    imageModel.setZoomPercent(999)
    precondition(imageModel.zoomPercent == 400)
    imageModel.setZoomPercent(0)
    precondition(imageModel.zoomPercent == 10)
    imageModel.fitCanvas()
    precondition(imageModel.zoomToFit && imageModel.panOffset == .zero)

    var sliderAmount: CGFloat = 1.5
    let sliderHost = NSHostingView(rootView: InspectorSlider("Zoom", value: Binding(
        get: { sliderAmount }, set: { sliderAmount = $0 }), range: 1...4,
        format: .magnification(fractionDigits: 1))
        .environment(\.simpleInspectorControls, true))
    sliderHost.frame = NSRect(x: 0, y: 0, width: 280, height: 64)
    sliderHost.layoutSubtreeIfNeeded()
    func nativeSlider(in view: NSView) -> NSSlider? {
        if let slider = view as? NSSlider { return slider }
        return view.subviews.lazy.compactMap { nativeSlider(in: $0) }.first
    }
    let slider = nativeSlider(in: sliderHost)!
    for (progress, expected) in [(0.0, 1.0), (5.0 / 12, 2.25), (1.0, 4.0)] {
        slider.doubleValue = slider.minValue + progress * (slider.maxValue - slider.minValue)
        slider.sendAction(slider.action!, to: slider.target)
        precondition(abs(sliderAmount - expected) < 0.001,
                     "Native inspector slider must preserve model bounds and precision")
    }
    print("PASS native inspector slider bounds and binding")

    let videoModel = RecordingStudioModel(url: movieURL)
    await videoModel.load()
    defer { videoModel.teardown() }
    precondition(videoModel.isLoaded, "Snapshot recording must load")
    let originalCues = videoModel.zoomCues
    videoModel.addZoomCue(fromEditorTime: 0.25, toEditorTime: 1.25)
    precondition(videoModel.zoomEnabled, "Adding a zoom must enable playback of zooms")
    let cue = videoModel.selectedCue!
    precondition(videoModel.zoomTimelineBlocks.count == 1)
    videoModel.beginZoomCueEdit()
    var edited = cue
    edited.zoom = 2
    videoModel.updateZoomCue(edited)
    videoModel.endZoomCueEdit(actionName: "Edit Zoom")
    precondition(videoModel.selectedCue?.zoom == 2)
    videoModel.undo()
    // The synchronous harness groups creation and editing into one input event.
    precondition(videoModel.zoomCues == originalCues)
    precondition(!videoModel.zoomEnabled, "Undo must restore the imported video's disabled zoom state")
    videoModel.redo()
    precondition(videoModel.zoomCues.first?.zoom == 2)
    precondition(videoModel.zoomEnabled, "Redo must restore zoom playback")

    let clipControl = RecordingClipTimelineControl(frame: NSRect(x: 0, y: 0, width: 600, height: 52))
    clipControl.update(timeline: videoModel.clipTimeline, sourceDuration: videoModel.sourceDuration,
                       thumbnails: videoModel.timelineThumbnails, selectedClipID: nil, playheadTime: 0)
    var splitTime: Double?
    clipControl.splitRequested = { splitTime = $0 }
    clipControl.toggleSplitRequested = { clipControl.isSplitting.toggle() }
    clipControl.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s",
        isARepeat: false, keyCode: 1)!)
    precondition(clipControl.isSplitting && splitTime == nil, "S activates the tool without making a cut")
    clipControl.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 300, y: 26),
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1)!)
    precondition(abs((splitTime ?? -1) - videoModel.duration / 2) < 0.01, "The split tool cuts at the click")
    clipControl.toggleSplitRequested = nil
    print("PASS split tool, zoom editing, and undo/redo")
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var effectToggle = StudioEffectToggleState()
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.45)
    precondition(effectToggle.amount(enabled: false, current: 0.75, defaultValue: 0.45) == 0)
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.75)
    precondition(effectToggle.amount(enabled: false, current: 0, defaultValue: 0.45) == 0)
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.75)
    print("PASS effect toggle defaults and previous amount restoration")
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(RecordingSessionControls().studioGlass(cornerRadius: 16),
                     scheme: scheme, width: 360,
                     to: output.appendingPathComponent("recording-\(name).png"), height: 64)
        try snapshot(RecordingPickerControls().padding(8).studioGlass(cornerRadius: 16)
            .background(EditorChrome.workspace), scheme: scheme, width: 760,
                     to: output.appendingPathComponent("capture-\(name).png"), height: 100)
        try snapshot(
            AnnotationEditorWindow(url: .constant(nil), model: imageModel),
            scheme: scheme, width: 1280, to: output.appendingPathComponent("image-\(name).png"))
        try snapshot(
            RecordingStudioContent(model: videoModel),
            scheme: scheme, width: 1280, to: output.appendingPathComponent("video-\(name).png"))
    }
    try snapshot(AnnotationEditorWindow(url: .constant(nil), model: imageModel),
                 scheme: .light, width: 980, to: output.appendingPathComponent("image-compact.png"))
    try snapshot(RecordingStudioContent(model: videoModel),
                 scheme: .light, width: 1100, to: output.appendingPathComponent("video-compact.png"))
    videoModel.selectedCueID = nil
    videoModel.selectedClipID = nil
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(RecordingStudioContent(model: videoModel), scheme: scheme, width: 1100,
                     to: output.appendingPathComponent("video-effects-\(name).png"))
    }
    let recentMenu = MenuBarContentView(dismissPopover: {}).recentMenuItems()
    precondition(recentMenu.map(\.title) == ["Screenshots", "Recordings"])
    precondition(recentMenu.flatMap { $0.submenu ?? [] }.allSatisfy { !$0.isDestructive },
                 "Recent capture navigation must not delete files")
    print("PASS combined recent menu without bulk deletion")
    print("PASS editor zoom bounds, fit, and light/dark view snapshots: \(output.path)")
}

@MainActor
private func snapshot<V: View>(
    _ view: V, scheme: ColorScheme, width: CGFloat, to url: URL, height: CGFloat = 800
) throws {
    let app = NSApplication.shared
    app.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
    let hosting = NSHostingView(rootView: view
        .environment(\.colorScheme, scheme)
        .background(EditorChrome.workspace)
        .frame(width: width, height: height))
    hosting.appearance = app.appearance
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = app.appearance
    window.contentView = hosting
    defer { window.contentView = nil; window.close() }
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        preconditionFailure("Editor failed to render")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
