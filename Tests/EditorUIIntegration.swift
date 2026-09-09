import AppKit
import Carbon
import SwiftUI
@testable import BetterShot

/// Offscreen snapshots and model checks, plus a brief native transfer-toast lifecycle check.
/// AVPlayer layers and window toolbars require live UI testing and are not captured here.
@MainActor
func checkEditorUI(imageURL: URL, movieURL: URL) async throws {
    try await checkMediaGallery(imageURL: imageURL, movieURL: movieURL)
    checkTransferToastPresentation(movieURL: movieURL)
    try await checkGeneralEditorDefaults(movieURL: movieURL)
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
    precondition(shortcuts.defaultRegion.keyCode == UInt32(kVK_ANSI_4))
    precondition(shortcuts.defaultRecording.keyCode == UInt32(kVK_ANSI_2))
    precondition(shortcuts.defaultRecordingOptions.keyCode == UInt32(kVK_ANSI_5))
    for (oldRegionKey, oldRecordingKey, enabled) in [
        (kVK_ANSI_2, kVK_ANSI_5, true),
        (kVK_ANSI_2, kVK_ANSI_5, false),
        (kVK_ANSI_7, kVK_ANSI_8, true)
    ] {
        shortcutDefaults.removePersistentDomain(forName: suiteName)
        shortcutDefaults.set(true, forKey: "bs_captureShortcuts050Migrated")
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
        precondition(migratedRegion.keyCode == UInt32(oldRegionKey == kVK_ANSI_2 ? kVK_ANSI_4 : oldRegionKey))
        precondition(migratedRecording.keyCode == UInt32(oldRecordingKey == kVK_ANSI_5 ? kVK_ANSI_2 : oldRecordingKey))
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

    for tool in AnnotationTool.allCases where tool != .select {
        imageModel.selectTool(.select)
        imageModel.selectTool(tool)
        precondition(imageModel.selectedTool == tool)
        imageModel.selectTool(tool)
        precondition(imageModel.selectedTool == .select, "Second tool click returns to selection")
    }
    precondition(GradientPreset.presets.count == 10)
    precondition(AnnotationBackgroundGradient.presets.map(\.id) == GradientPreset.presets.map(\.id))
    for gradient in AnnotationBackgroundGradient.presets {
        let stored = StoredGradient(gradient)
        let restored = try JSONDecoder().decode(StoredGradient.self, from: JSONEncoder().encode(stored))
        precondition(restored.backgroundGradient == gradient, "Gradient stops and highlights persist")
        let preset = gradient.preset!
        precondition(preset.locations?.count == 3 && preset.highlights?.count == 2)
    }
    print("PASS tool deselection and ten shared gradient definitions / saved highlights")

    var cursorStyle = RecordingStudioStyle()
    cursorStyle.cursor.appearance = .hand
    cursorStyle.cursor.hideWhenIdle = true
    let cursorData = try JSONEncoder().encode(StoredRecordingStudioStyle(cursorStyle))
    let restoredStyle = try JSONDecoder().decode(StoredRecordingStudioStyle.self, from: cursorData)
    precondition(restoredStyle.value.cursor == cursorStyle.cursor, "Cursor settings survive project save and reopen")
    var legacyStyle = try JSONSerialization.jsonObject(with: cursorData) as! [String: Any]
    legacyStyle.removeValue(forKey: "cursor")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyStyle)
    let legacyCursor = try JSONDecoder().decode(StoredRecordingStudioStyle.self, from: legacyData).value.cursor
    precondition(legacyCursor == RecordingCursorOptions(), "Older projects retain the recorded cursor and existing motion")
    for appearance in [RecordingCursorAppearance.dark, .light, .dot] {
        let artwork = PointerArtworkCapture.styledArtwork(appearance)!
        let bitmap = NSBitmapImageRep(data: artwork.imageData)!
        precondition(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 1280,
                     "Custom cursors must retain enough pixels for enlarged Retina / 4K output")
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "Cursor background stays transparent")
        precondition(bitmap.colorAt(x: (appearance == .dot ? 16 : 10) * 32, y: 20 * 32)!.alphaComponent > 0.99,
                     "Cursor artwork must contain an opaque, visible shape")
        precondition(artwork.referenceSize.width == 32 && artwork.referenceSize.height == 40)
        let expectedAnchor = appearance == .dot ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 5.0 / 32, y: 0.1)
        precondition(artwork.normalizedAnchor == expectedAnchor, "High-resolution artwork must preserve its click hotspot")
        precondition(artwork == PointerArtworkCapture.styledArtwork(appearance), "Cursor artwork is cached")
    }
    let hand = PointerArtworkCapture.styledArtwork(.hand)!
    let nativeHand = PointerArtworkCapture.capture(NSCursor.pointingHand, id: "bettershot-cursor-hand")!
    precondition(hand == nativeHand, "Hand uses the actual macOS artwork, full raster, logical size, and hotspot")
    precondition(hand == PointerArtworkCapture.styledArtwork(.hand), "Native hand artwork is cached")
    let delayFormat = InspectorValueFormat.seconds(never: CGFloat(AppPreferences.overlayDismissNever))
    precondition(delayFormat.displayString(for: 5) == "5s")
    precondition(delayFormat.displayString(for: 16) == "Never")
    precondition(delayFormat.parse(" never ") == 16 && delayFormat.parse("5s") == 5)
    precondition(delayFormat.parse("invalid") == nil && delayFormat.parse("NaN") == nil)
    precondition(InspectorValueFormat.points.parse("24 pt") == 24 && InspectorValueFormat.points.step == 4)
    precondition(InspectorValueFormat.percent(step: 0.05).step == 0.05)
    print("PASS native hand capture/cache, cursor project persistence, and settings slider units / Never input")
    let multiResolutionCursor = NSImage(size: NSSize(width: 16, height: 20))
    for scale in [1, 4] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16 * scale, pixelsHigh: 20 * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = multiResolutionCursor.size
        multiResolutionCursor.addRepresentation(rep)
    }
    let captured = PointerArtworkCapture.capture(NSCursor(image: multiResolutionCursor,
        hotSpot: NSPoint(x: 1, y: 2)), id: "retina-check")!
    let capturedBitmap = NSBitmapImageRep(data: captured.imageData)!
    precondition(capturedBitmap.pixelsWide == 64 && capturedBitmap.pixelsHigh == 80,
                 "Recorded cursors must keep their largest bitmap representation")
    precondition(captured.referenceSize.width == 16 && captured.anchorPoint.x == 1 && captured.anchorPoint.y == 2)
    precondition(NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil) != nil)
    print("PASS high-resolution cursor PNGs, transparency, hotspots, Retina capture, and native menu symbol")
    let stillCapture = PointerCaptureFile(travel: (0...24).map {
        PointerTravelSample(time: Double($0) / 4, x: 0.5, y: 0.5)
    })
    var cursorOptions = RecordingCursorOptions()
    cursorOptions.hideWhenIdle = true
    let idlePointer = PointerTimeline.build(capture: stillCapture, duration: 6, options: cursorOptions)
    precondition(idlePointer.frame(at: 5)!.opacity < 0.01, "Stationary keep-alive samples do not prevent idle hiding")
    cursorOptions.isVisible = false
    let hiddenPointer = PointerTimeline.build(capture: stillCapture, duration: 6, options: cursorOptions)
    precondition(hiddenPointer.frame(at: 0)!.opacity == 0 && hiddenPointer.frame(at: 5)!.press == nil)
    cursorOptions.isVisible = true
    cursorOptions.smoothMotion = false
    cursorOptions.pressEffect = false
    cursorOptions.rippleEffect = true
    let clickCapture = PointerCaptureFile(travel: [
        PointerTravelSample(time: 0, x: 0.1, y: 0.1),
        PointerTravelSample(time: 0.5, x: 0.8, y: 0.6)
    ], presses: [PointerPressEvent(time: 0.6, x: 0.8, y: 0.6, button: 0, phase: .down)])
    let styledArtwork = PointerArtworkCapture.styledArtwork(.hand)!
    let naturalPointer = PointerTimeline.build(capture: clickCapture, duration: 1, options: cursorOptions,
                                               overrideArtwork: styledArtwork)
    let clickFrame = naturalPointer.frame(at: 0.65)!
    precondition(clickFrame.location == CGPoint(x: 0.8, y: 0.6) && clickFrame.tiltDegrees == 0)
    precondition(clickFrame.artworkID == styledArtwork.artworkID && abs(clickFrame.magnification - 1) < 0.001)
    precondition(clickFrame.press?.impactEnabled == false && clickFrame.press?.rippleEnabled == true)
    print("PASS cursor styles, saved/legacy settings, natural motion, separate click effects, and idle visibility")

    let videoModel = RecordingStudioModel(url: movieURL)
    await videoModel.load()
    defer { videoModel.teardown() }
    videoModel.beginVideoCrop()
    precondition(videoModel.isCroppingVideo)
    videoModel.beginVideoCrop()
    precondition(!videoModel.isCroppingVideo && videoModel.cropDraft == videoModel.cropRect)
    videoModel.toggleMaskTool(.pixelate)
    precondition(videoModel.isEditingMasks && videoModel.selectedMask?.effect == .pixelate)
    videoModel.setSelectedMaskCropOnly(false)
    precondition(videoModel.selectedMask?.rect == RecordingVideoCrop.unit)
    videoModel.setSelectedMaskCropOnly(true)
    precondition(abs(videoModel.selectedMask!.rect.width - 0.35) < 0.0001)
    videoModel.toggleMaskTool(.pixelate)
    precondition(!videoModel.isEditingMasks)
    videoModel.toggleMaskTool(.blur)
    precondition(videoModel.selectedMask?.effect == .blur)
    videoModel.deleteSelectedMask()
    videoModel.endMaskEditing()
    print("PASS video crop toggle, blur / pixelate selection, and Crop Only scope")

    precondition(videoModel.isLoaded, "Snapshot recording must load")
    let speedClipID = videoModel.clipTimeline.segments[0].id
    for (rate, expectedDuration) in [(0.5, 4.0), (1.25, 1.6), (1.5, 4.0 / 3), (2.5, 0.8)] {
        videoModel.setClipSpeed(rate, forClipID: speedClipID)
        precondition(abs(videoModel.duration - expectedDuration) < 0.000_001)
        precondition(videoModel.clipTimeline.segments[0].speed == rate)
    }
    videoModel.setClipSpeed(1, forClipID: speedClipID)
    print("PASS custom fractional clip speeds update the editor timeline")
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

    let cutTimeline = RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceStart: 1, sourceEnd: 5, speed: 2),
        RecordingClipSegment(sourceStart: 7, sourceEnd: 9)
    ])
    precondition(cutTimeline.cutMarkers(sourceDuration: 10) == [
        .init(sourceStart: 0, sourceEnd: 1, editorTime: 0),
        .init(sourceStart: 5, sourceEnd: 7, editorTime: 2),
        .init(sourceStart: 9, sourceEnd: 10, editorTime: 4)
    ], "Removed footage markers cover leading, middle, and trailing cuts at edited playback times")
    precondition(RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceStart: 0, sourceEnd: 5),
        RecordingClipSegment(sourceStart: 5, sourceEnd: 10)
    ]).cutMarkers(sourceDuration: 10) == [.init(sourceStart: 5, sourceEnd: 5, editorTime: 5)],
                 "A split alone shows scissors without a removed duration")
    precondition(cutTimeline.cutMarkers(sourceDuration: .nan).isEmpty)
    let previewMarker = RecordingClipTimeline.CutMarker(sourceStart: 0.2, sourceEnd: 0.8, editorTime: 0.2)
    let cutFrame = try await StudioTimelineCutPreview.frame(sourceURL: movieURL, marker: previewMarker)
    precondition(cutFrame.width > 0 && cutFrame.width <= 480 && cutFrame.height <= 270,
                 "Cut hover preview loads a bounded source frame")
    print("PASS cut badges, removed durations, speed-aware positions, and source preview")

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
    precondition(clipControl.isSplitting, "Scissors stays selected after a cut")
    clipControl.update(timeline: videoModel.clipTimeline, sourceDuration: videoModel.sourceDuration,
                       thumbnails: videoModel.timelineThumbnails, selectedClipID: nil, playheadTime: 0)
    clipControl.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 450, y: 26),
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1,
        clickCount: 1, pressure: 1)!)
    precondition(clipControl.isSplitting && abs((splitTime ?? -1) - videoModel.duration * 0.75) < 0.01,
                 "Repeated cuts and timeline updates keep scissors selected")
    clipControl.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s",
        isARepeat: false, keyCode: 1)!)
    precondition(!clipControl.isSplitting, "S explicitly deselects scissors")
    clipControl.toggleSplitRequested = nil
    print("PASS split tool, zoom editing, and undo/redo")
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let buildConfiguration = ProcessInfo.processInfo.environment["BETTERSHOT_BUILD_CONFIGURATION"] ?? "Debug"
    let appBundle = Bundle(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/Build/Products/\(buildConfiguration)/BetterShot.app"))!
    let practiceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: practiceDirectory) }
    for sample in OnboardingSample.allCases {
        let source = sample.sourceURL(in: appBundle)!
        let original = try Data(contentsOf: source)
        let first = try sample.makeWorkingCopy(in: practiceDirectory, bundle: appBundle)
        let second = try sample.makeWorkingCopy(in: practiceDirectory, bundle: appBundle)
        precondition(first != second, "Repeated practice preserves earlier edits")
        let copied = try Data(contentsOf: first)
        precondition(copied == original, "Practice starts from the full original PNG")
        try Data("edited".utf8).write(to: first, options: .atomic)
        let unchanged = try Data(contentsOf: source)
        precondition(unchanged == original, "Practice never edits bundled artwork")
        do {
            _ = try sample.makeWorkingCopy(in: first, bundle: appBundle)
            preconditionFailure("An unwritable destination must report failure")
        } catch {}
    }
    precondition(OnboardingPermissionStatus.media(.authorized) == .allowed)
    precondition(OnboardingPermissionStatus.media(.notDetermined) == .notEnabled)
    precondition(OnboardingPermissionStatus.media(.denied) == .denied)
    precondition(OnboardingPermissionStatus.media(.restricted) == .restricted)
    let permissionState = OnboardingPermissions()
    permissionState.refresh()
    for permission in OnboardingPermission.allCases {
        await permissionState.request(permission)
        precondition(permissionState.status(permission) == .notEnabled && permissionState.attempted.isEmpty,
                     "The test runner must never request real permissions or persist setup attempts")
        precondition(permission.settingsURL.scheme == "x-apple.systempreferences")
    }
    for scheme in [ColorScheme.light, .dark] {
        for step in OnboardingView.Step.allCases {
            for width: CGFloat in [520, 760] {
                try snapshot(OnboardingView(step: step, resourceBundle: appBundle),
                    scheme: scheme, width: width,
                    to: output.appendingPathComponent("onboarding-\(step)-\(scheme)-\(Int(width)).png"),
                    height: width == 520 ? 560 : 680)
            }
        }
        try snapshot(VStack(spacing: 12) {
            OnboardingPermissionRow(permission: .screen, status: .notEnabled, attempted: true,
                request: {}, openSettings: {})
            OnboardingPermissionRow(permission: .camera, status: .denied, request: {}, openSettings: {})
            OnboardingPermissionRow(permission: .microphone, status: .restricted, request: {}, openSettings: {})
            OnboardingPermissionRow(permission: .accessibility, status: .allowed, request: {}, openSettings: {})
        }.padding(16), scheme: scheme, width: 520,
            to: output.appendingPathComponent("onboarding-permission-recovery-\(scheme).png"), height: 900)
    }
    print("PASS onboarding artwork copies, permission status mapping/testing guard, recovery states, and all four steps in compact/light/dark snapshots")
    try snapshot(LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
        ForEach(GradientPreset.presets) { preset in
            VStack {
                GradientBackgroundView(preset: preset).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(preset.name).font(.caption)
            }
        }
    }.padding(), scheme: .light, width: 900, to: output.appendingPathComponent("shared-gradients.png"), height: 360)
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(RecordingSettingsTab(), scheme: scheme, width: 580,
                     to: output.appendingPathComponent("recording-settings-\(name).png"), height: 1100)
        try snapshot(GeneralSettingsTab(), scheme: scheme, width: 580,
                     to: output.appendingPathComponent("general-settings-\(name).png"), height: 1300)
        try snapshot(MenuBarContentView(dismissPopover: {}), scheme: scheme, width: 296,
                     to: output.appendingPathComponent("tray-recording-\(name).png"), height: 640)
    }
    try snapshot(HStack(spacing: 24) {
        ForEach([RecordingCursorAppearance.dark, .light, .dot, .hand], id: \.self) { appearance in
            VStack {
                HStack(spacing: 0) {
                    ForEach([Color.white, Color.black], id: \.self) { background in
                        Image(nsImage: NSImage(data: PointerArtworkCapture.styledArtwork(appearance)!.imageData)!)
                            .resizable().interpolation(.high).scaledToFit()
                            .padding(12).frame(width: 120, height: 150).background(background)
                    }
                }
                Text(appearance.title)
            }
        }
    }.padding(), scheme: .light, width: 1100, to: output.appendingPathComponent("cursor-quality.png"), height: 220)
    var effectToggle = StudioEffectToggleState()
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.45)
    precondition(effectToggle.amount(enabled: false, current: 0.75, defaultValue: 0.45) == 0)
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.75)
    precondition(effectToggle.amount(enabled: false, current: 0, defaultValue: 0.45) == 0)
    precondition(effectToggle.amount(enabled: true, current: 0, defaultValue: 0.45) == 0.75)
    print("PASS effect toggle defaults and previous amount restoration")
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        try snapshot(AnnotationScreenshotBorderInspector(
            settings: .constant(AnnotationScreenshotBorderSettings()), onEditorAction: {}
        ).padding(InspectorMetrics.horizontalPadding), scheme: scheme, width: 260,
                     to: output.appendingPathComponent("border-controls-\(name).png"), height: 210)
        try snapshot(Form {
            Section {
                InspectorSlider("Padding", value: .constant(0.15), range: 0...0.45, format: .percent())
                InspectorSlider("Corner Radius", value: .constant(0.011), range: 0...0.12,
                                format: .percent(fractionDigits: 1))
                InspectorSlider("Shadow", value: .constant(0.3), range: 0...1, format: .percent())
            }
        }.formStyle(.grouped), scheme: scheme, width: 580,
                     to: output.appendingPathComponent("settings-sliders-\(name).png"), height: 200)
        try snapshot(CaptureSettingsTab(), scheme: scheme, width: 580,
                     to: output.appendingPathComponent("capture-settings-\(name).png"), height: 800)
        for (label, status) in [
            ("upload", TransferStatus.working(stage: .uploading, progress: 0.42)),
            ("render", .working(stage: .rendering, progress: nil)),
            ("invalid-progress", .working(stage: .uploading, progress: .nan)),
            ("link", .linkReady(url: URL(string: "https://example.com/capture/test")!)),
            ("export", .exported(url: movieURL)),
            ("error", .failed(headline: "Upload failed", message: "Check your connection and try again.", canRetry: true))
        ] {
            try snapshot(TransferStatusCard(status: status), scheme: scheme, width: 360,
                         to: output.appendingPathComponent("transfer-\(label)-\(name).png"), height: 112)
        }
        try snapshot(RecordingSessionControls().studioGlass(cornerRadius: BarMetrics.cornerRadius, opacity: 0.78),
                     scheme: scheme, width: 360,
                     to: output.appendingPathComponent("recording-\(name).png"), height: 64)
        try snapshot(RecordingPickerControls().padding(.horizontal, BarMetrics.horizontalPadding)
            .frame(height: BarMetrics.height).studioGlass(cornerRadius: BarMetrics.cornerRadius, opacity: 0.78)
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
    videoModel.splitClip(at: videoModel.duration / 2)
    var firstClip = videoModel.clipTimeline.segments[0]
    firstClip.sourceStart += 0.2
    videoModel.trimClip(firstClip)
    var lastClip = videoModel.clipTimeline.segments[1]
    lastClip.sourceStart += 0.2
    lastClip.sourceEnd -= 0.2
    videoModel.trimClip(lastClip)
    precondition(videoModel.clipTimeline.cutMarkers(sourceDuration: videoModel.sourceDuration).count == 3)
    try snapshot(RecordingStudioContent(model: videoModel), scheme: .dark, width: 1100,
                 to: output.appendingPathComponent("video-cuts-dark.png"))
    try snapshot(StudioTimelineCutPreview(marker: previewMarker, sourceURL: movieURL),
                 scheme: .dark, width: 270, to: output.appendingPathComponent("cut-preview-dark.png"), height: 220)
    videoModel.resetClips()
    precondition(videoModel.clipTimeline.cutMarkers(sourceDuration: videoModel.sourceDuration).isEmpty,
                 "Restoring the original recording clears removed footage markers")
    videoModel.selectedCueID = nil
    videoModel.setClipSpeed(1.25, forClipID: videoModel.clipTimeline.segments[0].id)
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        videoModel.selectedClipID = nil
        try snapshot(RecordingStudioContent(model: videoModel), scheme: scheme, width: 1100,
                     to: output.appendingPathComponent("video-fractional-speed-\(name).png"), interact: {
            videoModel.selectClip(id: videoModel.clipTimeline.segments[0].id)
        })
    }

    let recentMenu = MenuBarContentView(dismissPopover: {}).recentMenuItems()
    precondition(recentMenu.map(\.title) == ["Screenshots", "Recordings"])
    precondition(recentMenu.flatMap { $0.submenu ?? [] }.allSatisfy { !$0.isDestructive },
                 "Recent capture navigation must not delete files")
    print("PASS combined recent menu without bulk deletion")
    print("PASS editor zoom bounds, fit, and light/dark view snapshots: \(output.path)")
}

@MainActor
private func checkGeneralEditorDefaults(movieURL: URL) async throws {
    let defaults = UserDefaults.standard
    let keys = ["bs_defaultBeautifierConfig", "recordingStudio.defaultBackground.v1",
                "recordingStudio.lastUsedBackground.v1"]
    let previous = keys.map { defaults.object(forKey: $0) }
    defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
    defaults.set(try JSONEncoder().encode(StoredBackgroundStyle.solid(StoredColor(.black))),
                 forKey: "recordingStudio.defaultBackground.v1")
    var custom = BeautifierConfig()
    custom.style = .gradient(GradientPreset.presets[0])
    custom.padding = 0.15
    custom.cornerRadius = 0.04
    custom.shadowStrength = 0.7
    for config in [BeautifierConfig.default, custom] {
        AppPreferences.defaultBeautifierConfig = config
        let session = RecordingSession(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bettershotrec"))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: session.directoryURL) }
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        for url in [session.directoryURL, movieURL] {
            let model = RecordingStudioModel(url: url)
            await model.load()
            precondition(model.isLoaded)
            let imageDefaults = config.annotationBackgroundSettings
            precondition(model.style.background == imageDefaults.style
                         && model.style.padding == imageDefaults.padding
                         && model.style.cornerRadius == imageDefaults.cornerRadius
                         && model.style.shadow == imageDefaults.shadow,
                         "New videos and images must share General's default look, including Reset Defaults")
            model.style.background = .solid(.black)
            precondition(AppPreferences.defaultBeautifierConfig == config,
                         "Project edits must not overwrite General defaults")
            model.teardown()
        }
        session.removeDraftDocument()
        let savedStyle = RecordingStudioStyle(background: .solid(.white), padding: 0.03,
                                               cornerRadius: 0.01, shadow: 0.2)
        try session.writeEditDocument(RecordingEditDocument(style: savedStyle, zoomEnabled: false,
            zoomCues: [], clipTimeline: .full(sourceDuration: 2)))
        let reopened = RecordingStudioModel(url: session.directoryURL)
        await reopened.load()
        precondition(reopened.style == savedStyle, "Saved projects keep their own look")
        reopened.teardown()
    }
    print("PASS General defaults for new recordings/imports, image look parity, reset, and saved project preservation")
}

@MainActor
private func snapshot<V: View>(
    _ view: V, scheme: ColorScheme, width: CGFloat, to url: URL, height: CGFloat = 800,
    interact: () -> Void = {}
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
    interact()
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        preconditionFailure("Editor failed to render")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor
private func checkTransferToastPresentation(movieURL: URL) {
    guard let screen = NSScreen.main else { preconditionFailure("Toast checks require a display") }
    let owner = NSWindow(contentRect: CGRect(x: screen.visibleFrame.minX + 20,
        y: screen.visibleFrame.minY + 20, width: 400, height: 240),
        styleMask: [.titled], backing: .buffered, defer: false)
    owner.isReleasedWhenClosed = false
    owner.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
    owner.orderFrontRegardless()
    defer { owner.close() }
    let anchor = TransferToastAnchorView(frame: .zero)
    owner.contentView!.addSubview(anchor)
    let previousKeyWindow = NSApp.keyWindow
    anchor.update(card: TransferStatusCard(status: .working(stage: .exporting, progress: 0.2)))
    guard let toast = NSApp.windows.first(where: {
        $0.identifier?.rawValue == "BetterShot.TransferToast" && $0.isVisible
    }) else { preconditionFailure("Transfer feedback must appear in its own native window") }
    precondition(toast !== owner && toast.parent == nil)
    precondition(toast.appearance === owner.appearance,
                 "System appearance must remain automatic when the editor has no override")
    precondition(abs(toast.frame.midX - screen.visibleFrame.midX) < 1
                 && abs(toast.frame.maxY - (screen.visibleFrame.maxY - 12)) < 1,
                 "Transfer toast must use the screen's top-center toast position")
    precondition(!owner.frame.intersects(toast.frame), "Compact editor must not contain the transfer card")
    precondition(NSApp.keyWindow === previousKeyWindow, "Showing progress must preserve keyboard focus")
    anchor.update(card: TransferStatusCard(status: .exported(url: movieURL)))
    precondition(toast.isVisible, "Completion must update the existing panel")
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        owner.appearance = NSAppearance(named: name)
        anchor.update(card: TransferStatusCard(status: .failed(
            headline: "Export failed", message: "Retry the export.", canRetry: true)))
        precondition(toast.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name)
    }
    anchor.update(card: nil)
    precondition(!toast.isVisible, "Dismissal must remove the floating card")
    anchor.update(card: TransferStatusCard(status: .working(stage: .exporting, progress: nil)))
    owner.close()
    precondition(!NSApp.windows.contains(where: {
        $0.identifier?.rawValue == "BetterShot.TransferToast" && $0.isVisible
    }), "Closing the editor must clean up its transfer panel")
    anchor.removeFromSuperview()
    print("PASS external transfer toast placement, progress/completion, focus, appearances, dismissal, and close cleanup")
}


@MainActor
private func checkMediaGallery(imageURL: URL, movieURL: URL) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let history = HistoryStore(storageDirectory: root.appendingPathComponent("history"))
    let raw = history.referenceCapture(at: imageURL)!
    let session = RecordingSession(directoryURL: root.appendingPathComponent("Demo.bettershotrec", isDirectory: true))
    try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
    history.referenceCapture(at: session.screenURL, kind: .recording)
    let project = RecordingProjectSummary(session: session, displayName: "Demo", createdAt: Date(),
        duration: 2, pixelSize: CGSize(width: 1920, height: 1080), isSaved: false,
        hasUnsavedDraft: true, sizeOnDisk: 0, lastOpenedAt: nil)
    let image = ScreenshotHistoryItem(id: UUID(), createdAt: Date(), updatedAt: Date(),
        fileName: UUID().uuidString + ".png", pixelWidth: 1920, pixelHeight: 1080,
        cloudURL: "https://example.com/s/image", hasEdits: true, sourceCapturePath: imageURL.path)
    let video = ScreenshotHistoryItem(id: UUID(), createdAt: Date(), updatedAt: Date(),
        fileName: "Demo.mov", pixelWidth: 1920, pixelHeight: 1080, kind: .video,
        cloudURL: "https://example.com/s/video", recordingSessionPath: session.directoryURL.path)
    let entries = MediaGalleryItem.collect(history: history, edits: [image, video], projects: [project])
    precondition(entries.count == 2, "Capture, edited history, and package must not duplicate media")
    precondition(entries.first { $0.kind == .recording }!.editorURL == session.directoryURL,
                 "Videos must reopen their editable project")
    precondition(entries.first { $0.kind == .screenshot }!.localURL == imageURL,
                 "A missing shared copy must not hide an available original")
    precondition(!entries.contains { $0.id == raw.id.uuidString })
    let recovered = MediaGalleryItem.collect(history: HistoryStore(storageDirectory: root.appendingPathComponent("empty")),
        edits: [], projects: [project])
    precondition(recovered.count == 1 && recovered[0].editorURL == session.directoryURL,
                 "Projects outside recent history must remain discoverable")
    precondition(MediaGalleryItem.filtered(entries, kind: .recording, cloud: false, search: " demo ").count == 1)
    precondition(MediaGalleryItem.filtered(entries, kind: .screenshot, cloud: true, search: "").count == 1)
    precondition(MediaGalleryItem.filtered(entries, kind: nil, cloud: true, search: "no match").isEmpty)
    precondition(ScreenshotHistoryStore.shouldKeep(image), "Missing files must retain cloud links on reload")
    var missing = image
    missing.cloudURL = nil
    precondition(!ScreenshotHistoryStore.shouldKeep(missing))
    for value in ["file:///tmp/file", "javascript:alert(1)", "https://", "not a link"] {
        precondition(MediaGalleryItem.cloudLink(value) == nil)
    }
    let cloudOnly = MediaGalleryItem(id: "cloud-only", title: "Cloud screenshot", createdAt: Date(),
        kind: .screenshot, localURL: root.appendingPathComponent("missing.png"),
        editorURL: root.appendingPathComponent("missing.png"), cloudURL: URL(string: "https://example.com/s/missing"))
    precondition(MediaGalleryItem.filtered([cloudOnly], kind: nil, cloud: false, search: "").isEmpty)
    precondition(MediaGalleryItem.filtered([cloudOnly], kind: nil, cloud: true, search: "").count == 1)
    for item in entries {
        precondition(HistoryStore.decodeThumbnail(.init(url: item.localURL, kind: item.kind), maxSize: 480) != nil,
                     "Both screenshot and video gallery sources must decode")
    }
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        for width: CGFloat in [540, 740] {
            NSApplication.shared.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let hosting = NSHostingView(rootView: MediaGalleryContent(items: entries)
                .environment(\.colorScheme, scheme).background(EditorChrome.workspace)
                .frame(width: width, height: 520))
            hosting.appearance = NSApplication.shared.appearance
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 520),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            window.contentView = hosting
            defer { window.contentView = nil; window.close() }
            hosting.layoutSubtreeIfNeeded()
            // Yield the main actor so the real card tasks can decode their thumbnails.
            try await Task.sleep(for: .milliseconds(300))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: output.appendingPathComponent("gallery-\(scheme)-\(Int(width)).png"))
        }
        try snapshot(MediaGalleryCard(item: cloudOnly, cloud: true), scheme: scheme, width: 240,
            to: output.appendingPathComponent("gallery-cloud-\(scheme).png"), height: 250)
        try snapshot(MediaGalleryContent(items: []), scheme: scheme, width: 540,
            to: output.appendingPathComponent("gallery-empty-\(scheme).png"), height: 520)
    }
    print("PASS gallery source merging, project reopening, local/cloud/type/search filters, missing local shares, and compact/light/dark layouts")
}
