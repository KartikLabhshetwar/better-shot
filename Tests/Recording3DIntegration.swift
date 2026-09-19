import AppKit
import AVFoundation
import CoreImage
import SwiftUI
@testable import BetterShot

@MainActor
func check3DShots(movie: URL, directory: URL) async throws {
    let compact = StudioTimelineMetrics.scrollingLanesHeight(showsMaskLane: false, showsCutLane: false, shows3DLane: true)
    let withCuts = StudioTimelineMetrics.scrollingLanesHeight(showsMaskLane: false, showsCutLane: true, shows3DLane: true)
    precondition(withCuts - compact == 36, "No cut-marker gutter may remain when there are no cuts")
    let withMasks = StudioTimelineMetrics.scrollingLanesHeight(showsMaskLane: true, showsCutLane: false, shows3DLane: true)
    precondition(withMasks - compact == 44, "Masks retain their own row without resurrecting the cut gutter")
    let session = RecordingSession(directoryURL: directory.appendingPathComponent("3D.bettershotrec"))
    try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: movie, to: session.screenURL)
    let creationModel = RecordingStudioModel(url: session.directoryURL)
    await creationModel.load()
    precondition(creationModel.isLoaded && creationModel.timeline3D.shots.isEmpty)
    creationModel.add3DShot(at: 0)
    precondition(creationModel.shots3D.count == 1 && creationModel.selected3DShot != nil)
    creationModel.undo()
    precondition(creationModel.shots3D.isEmpty)
    creationModel.redo()
    precondition(creationModel.shots3D.count == 1)
    creationModel.saveProject()
    creationModel.teardown()
    // Reopen with a fresh undo stack: the command-line harness has no user event boundaries.
    let model = RecordingStudioModel(url: session.directoryURL)
    await model.load()
    defer { model.teardown() }
    let original = model.shots3D[0]
    model.select3DShot(id: original.id)
    model.begin3DShotEdit()
    var edited = original
    edited.apply(.perspective)
    edited.transition = 0
    model.update3DShot(edited)
    model.end3DShotEdit()
    try await Task.sleep(for: .milliseconds(30))
    model.undo()
    precondition(model.shots3D == [original], "Pose drag is one undo operation")
    model.redo()
    precondition(model.shots3D == [edited])
    model.saveProject()
    precondition(session.loadEditDocument()?.shots3D == [edited])
    let saved = session.loadEditDocument()!
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
    legacy.removeValue(forKey: "shots3D"); legacy["formatVersion"] = 5
    let legacyDocument = try JSONDecoder().decode(RecordingEditDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyDocument.shots3D == nil, "Old projects remain flat")
    let reopen = RecordingStudioModel(url: session.directoryURL)
    await reopen.load()
    precondition(reopen.shots3D == [edited] && !reopen.hasUnsavedChanges)
    reopen.teardown()
    model.select3DShot(id: edited.id)
    model.beginVideoCrop()
    precondition(model.preview3DPose(at: 0.5) == .identity)
    model.cancelVideoCrop()
    precondition(model.preview3DPose(at: 0.5) == edited.pose(at: 0.5))
    model.toggleMaskTool(.blur)
    precondition(model.preview3DPose(at: 0.5) == .identity)
    model.endMaskEditing()
    model.select3DShot(id: edited.id)
    model.apply3DScene([.glide, .unfold, .center], wholeMovie: true)
    precondition(model.timeline3D.shots.count == 3)
    var bounded = model.selected3DShot!
    let end = bounded.end
    bounded.start = -100; bounded.end = 100
    model.update3DShot(bounded)
    precondition(model.selected3DShot?.start == 0 && model.selected3DShot?.end == end,
                 "Timing edits must not overlap adjacent shots")
    model.play3DShot()
    try await Task.sleep(for: .seconds(1))
    precondition(!model.isPlaying && abs(model.currentTime - end) < 0.03,
                 "Play Shot must stop before the remainder of the movie")
    let authored = model.shots3D
    model.setClipSpeed(2, forClipID: model.clipTimeline.segments[0].id)
    precondition(model.shots3D == authored, "Shortening a clip must retain authored shots for undo")
    precondition(model.timeline3D.shots.allSatisfy { $0.end <= model.duration })
    model.setClipSpeed(1, forClipID: model.clipTimeline.segments[0].id)
    precondition(model.timeline3D.shots.count == 3)
    await model.discardChanges()
    precondition(model.shots3D == [edited] && !model.hasUnsavedChanges)
    model.select3DShot(id: edited.id)
    model.play3DShot()
    try await Task.sleep(for: .seconds(2.3))
    precondition(!model.isPlaying, "Play Shot stops at the end")
    if ProcessInfo.processInfo.environment["BETTERSHOT_CHECK_3D_WINDOWS"] == "1" {
        try await check3DWindows(model: model)
    }
    print("PASS 3D model editing, undo/redo, save/reopen, legacy projects, crop/mask editing, clip speeds, discard, and Play Shot")

    let size = CGSize(width: 320, height: 180)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    func buffer(width: Int = 320, height: Int = 180, source: Bool = false) -> CVPixelBuffer {
        var result: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &result) == kCVReturnSuccess)
        let value = result!
        if source {
            CVPixelBufferLockBaseAddress(value, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(value), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(value), space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
            CVPixelBufferUnlockBaseAddress(value, [])
        }
        return value
    }
    let ci = CIContext()
    func color(_ value: CVPixelBuffer, at point: CGPoint) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        ci.render(CIImage(cvPixelBuffer: value), toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: point.x.rounded(.down), y: CGFloat(CVPixelBufferGetHeight(value)) - point.y.rounded(.down) - 1, width: 1, height: 1),
            format: .RGBA8, colorSpace: colorSpace)
        return bytes
    }
    var style = RecordingStudioStyle()
    style.background = .solid(AnnotationBackgroundColor("green", title: "Green", red: 0, green: 1, blue: 0))
    style.padding = 0; style.shadow = 0; style.cornerRadius = 0
    let source = buffer(source: true), output = buffer()
    func compositor(_ timeline: Recording3DTimeline, size: CGSize = CGSize(width: 320, height: 180),
                    masks: [RecordingMaskSegment] = []) -> StudioFrameCompositor {
        StudioFrameCompositor(canvasSize: size, style: style, viewportTimeline: .identity,
            pointerTimeline: nil, showsPressEffects: false, keystrokeTimeline: nil,
            keystrokePlacement: .bottomCenter, subtitleTimeline: nil, includeBubble: false,
            masks: masks, timeline3D: timeline)
    }
    for preset in Recording3DPreset.allCases {
        var shot = Recording3DShot(start: 0, end: 2); shot.apply(preset); shot.transition = 0
        let timeline = Recording3DTimeline(shots: [shot], duration: 2)
        let renderer = compositor(timeline)
        for time in [0.0, 0.7, 1.5, 0.3] { // Out-of-order seeking with the same decoded source frame.
            try renderer.render(screenFrame: source, cameraFrame: nil, editorTime: time, sourceTime: time, into: output)
            let pose = timeline.pose(at: time)
            for (point, channel) in [(CGPoint(x: 115, y: 90), 0), (CGPoint(x: 205, y: 90), 2)] {
                let projected = pose.project(point, in: size)
                if CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3).contains(projected) {
                    let pixel = color(output, at: projected)
                    precondition(pixel[channel] > 230 && zip(pixel, color(source, at: point)).allSatisfy { abs(Int($0) - Int($1)) <= 3 }, "GPU warp disagrees with preview geometry: \(preset), \(pixel)")
                }
            }
        }
    }
    var still = Recording3DShot(start: 0.25, end: 1.75)
    still.apply(.perspective); still.transition = 0
    let timeline = Recording3DTimeline(shots: [still], duration: 2)
    let renderer = compositor(timeline)
    try renderer.render(screenFrame: source, cameraFrame: nil, editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: CGPoint(x: 5, y: 5))[1] > 240, "Background stays fixed")
    try renderer.render(screenFrame: source, cameraFrame: nil, editorTime: 1.9, sourceTime: 1.9, into: output)
    precondition(color(output, at: CGPoint(x: 5, y: 5))[0] > 240, "Frame reuse must not retain an expired warp")
    print("PASS all 13 looks through GPU rendering, projected source colors, nonsequential seeks, fixed background, and frame reuse")

    // The entire composed plane must move together, including source-space masks/crop and overlays.
    var combinedStyle = style
    combinedStyle.camera.center = CGPoint(x: 0.8, y: 0.75)
    combinedStyle.camera.size = 0.35
    combinedStyle.cursorScale = 3
    var mask = RecordingMaskSegment()
    mask.rect = CGRect(x: 0.35, y: 0.05, width: 0.3, height: 0.9)
    mask.amount = 40
    let pointer = PointerTimeline.build(capture: PointerCaptureFile(travel: [
        PointerTravelSample(time: 0, x: 0.5, y: 0.5)
    ]), duration: 2, clipTimeline: .full(sourceDuration: 2),
        overrideArtwork: PointerArtworkCapture.styledArtwork(.dot))
    func combined(_ track: Recording3DTimeline) -> StudioFrameCompositor {
        StudioFrameCompositor(canvasSize: size, style: combinedStyle,
            viewportTimeline: .identity, pointerTimeline: pointer, showsPressEffects: false,
            keystrokeTimeline: nil, keystrokePlacement: .bottomCenter, subtitleTimeline: nil,
            includeBubble: true, crop: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            masks: [mask], timeline3D: track)
    }
    let flatCombined = buffer(), warpedCombined = buffer()
    try combined(.empty).render(screenFrame: source, cameraFrame: source, editorTime: 1, sourceTime: 1, into: flatCombined)
    try combined(timeline).render(screenFrame: source, cameraFrame: source, editorTime: 1, sourceTime: 1, into: warpedCombined)
    for point in [CGPoint(x: 160, y: 90), CGPoint(x: 150, y: 125), CGPoint(x: 264, y: 135)] {
        let expected = color(flatCombined, at: point)
        let actual = color(warpedCombined, at: still.pose(at: 1).project(point, in: size))
        precondition(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) < 24 },
                     "Cursor, mask, crop, and camera must share the content projection: \(expected), \(actual)")
    }
    print("PASS composed cursor, blur mask, crop, and camera alignment through the 3D warp")

    // Exercise the real encoder at both cadences, then inspect a frame in the active shot.
    for frameRate in [VideoExportFrameRate.fps30, .fps60] {
        var settings = VideoCompressionSettings(); settings.frameRate = frameRate
        let url = try await RecordingStudioExporter().export(.init(screenURL: movie, cameraURL: nil,
            cameraOffset: 0, style: style, viewportTimeline: .identity, pointerTimeline: nil,
            showsPressEffects: false, keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
            subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(), canvasSize: size,
            clipTimeline: .full(sourceDuration: 2), exportSettings: settings, timeline3D: timeline)) { _ in }
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(frames); precondition(reader.startReading())
        var count = 0
        while let sample = frames.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if abs(time - 1) < 0.001 {
                let pixels = CMSampleBufferGetImageBuffer(sample)!
                precondition(color(pixels, at: CGPoint(x: 5, y: 5))[1] > 220, "Encoded video must include 3D framing")
                let red = color(pixels, at: still.pose(at: 1).project(CGPoint(x: 115, y: 90), in: size))
                precondition(Int(red[0]) > Int(red[2]) + 70, "Projected red footage must survive encoding")
            }
            count += 1
        }
        precondition(reader.status == .completed && count == frameRate.framesPerSecond * 2)
        let cached = try session.installFinalVideo(movingFrom: url, renderedFrom: saved)
        precondition(session.freshFinalURL(matching: saved) == cached)
        var changed = saved; changed.shots3D?[0].startPose.tiltY += 1
        precondition(session.freshFinalURL(matching: changed) == nil, "3D changes invalidate cached exports and shares")
    }
    print("PASS 3D encoded output at 30/60 fps and render-cache invalidation")

    if ProcessInfo.processInfo.environment["BETTERSHOT_BENCHMARK_3D"] == "1" {
        let sourceHD = buffer(width: 1920, height: 1080, source: true)
        let outputHD = buffer(width: 1920, height: 1080)
        var moving = still; moving.apply(.glide)
        let movingTrack = Recording3DTimeline(shots: [moving], duration: 2)
        for (label, track) in [("flat", Recording3DTimeline.empty), ("3D", movingTrack)] {
            let renderer = compositor(track, size: CGSize(width: 1920, height: 1080))
            var runs: [Double] = []
            for pass in 0..<4 {
                let start = Date()
                for frame in 0..<120 {
                    let time = 0.3 + Double(frame) / 120
                    try renderer.render(screenFrame: sourceHD, cameraFrame: nil, editorTime: time, sourceTime: time, into: outputHD)
                }
                if pass > 0 { runs.append(Date().timeIntervalSince(start) / 120 * 1000) }
            }
            print("BENCH 1080p \(label) GPU compositor median \(runs.sorted()[1]) ms/frame (120 frames, 3 warm runs)")
        }
    }
}

@MainActor
private func check3DWindows(model: RecordingStudioModel) async throws {
    precondition(CGPreflightScreenCaptureAccess(), "Live 3D checks require existing Screen Recording access")
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let policy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.regular)
    defer { NSApp.setActivationPolicy(policy) }
    for scheme in [ColorScheme.light, .dark] {
        let name = scheme == .light ? "light" : "dark"
        let root = RecordingStudioContent(model: model).environment(\.colorScheme, scheme)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.title = "BetterShot — 3D test fixture"
        window.styleMask = [.titled, .closable, .resizable]
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.setContentSize(CGSize(width: 1100, height: 800))
        window.isReleasedWhenClosed = false
        defer { window.contentViewController = nil; window.close() }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(400))
        model.select3DShot(id: model.shots3D[0].id)
        model.seek(to: 0.8)
        model.play()
        try await Task.sleep(for: .milliseconds(400))
        model.pause()
        try await Task.sleep(for: .milliseconds(300))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("video-3d-live-\(name).png").path]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
    }
    print("PASS displayed 3D editor playback/scrubbing screenshots in light and dark appearances")
}
