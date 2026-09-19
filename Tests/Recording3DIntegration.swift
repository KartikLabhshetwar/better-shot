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
    try FileManager.default.copyItem(at: movie, to: session.cameraURL)
    let creationModel = RecordingStudioModel(url: session.directoryURL)
    await creationModel.load()
    precondition(creationModel.isLoaded && creationModel.timeline3D.shots.isEmpty)
    let proposed = creationModel.timeline3D.insertionRange(at: 0, duration: creationModel.duration)!
    let wasDirty = creationModel.hasUnsavedChanges
    let revision = creationModel.previewRenderRevision
    creationModel.hoverPreviewTime = 0.2
    creationModel.hoverPreviewTime = nil
    precondition(creationModel.shots3D.isEmpty && creationModel.hasUnsavedChanges == wasDirty)
    precondition(creationModel.previewRenderRevision == revision, "Hover must not invalidate decoration or author an effect")
    creationModel.seek(to: 0.4)
    creationModel.previewAuto3DScene(count: 6)
    precondition(creationModel.suggested3DScene?.shots.count == 2, "A two-second video must not get six rapid cuts")
    precondition(creationModel.timeline3D.shots.isEmpty && creationModel.shots3D.isEmpty)
    precondition(creationModel.previewTimeline3D.shots.count == 2 && creationModel.hasUnsavedChanges == wasDirty)
    precondition(creationModel.previewRenderRevision == revision, "A suggestion preview must reuse decoration")
    creationModel.saveProject()
    let previewDocument = session.loadEditDocument()
    precondition(previewDocument != nil && (previewDocument?.shots3D ?? []).isEmpty, "Preview suggestions must never be saved or exported")
    creationModel.cancel3DScenePreview()
    precondition(creationModel.suggested3DScene == nil && abs(creationModel.currentTime - 0.4) < 0.001 && !creationModel.isPlaying)
    creationModel.add3DShot(at: 0)
    precondition(creationModel.shots3D[0].start == proposed.lowerBound && creationModel.shots3D[0].end == proposed.upperBound,
                 "The insertion must match its hover ghost exactly")
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
    let backdropRevision = model.previewRenderRevision
    var edited = original
    edited.apply(.perspective)
    edited.transition = 0
    edited.transitionIn = 0.1; edited.transitionOut = 0.2
    edited.blur = .init(mode: .tiltShift, strength: 12, focusSize: 0.1, angle: 45, bokeh: true)
    edited.tracks = [.init(property: .strength, keyframes: [
        .init(position: 0, value: 2, outgoing: .zero),
        .init(position: 1, value: 12, incoming: CGPoint(x: 1, y: 1))
    ])]
    model.update3DShot(edited)
    model.end3DShotEdit()
    precondition(model.previewRenderRevision == backdropRevision, "3D edits must reuse cached preview decoration")
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
    precondition(model.timeline3D.shots.count == 2)
    var bounded = model.selected3DShot!
    let end = bounded.end
    bounded.start = -100; bounded.end = 100
    model.update3DShot(bounded)
    precondition(model.selected3DShot?.start == 0 && model.selected3DShot?.end == end,
                 "Timing edits must not overlap adjacent shots")
    model.play3DShot()
    try await Task.sleep(for: .seconds(end + 0.25))
    precondition(!model.isPlaying && abs(model.currentTime - end) < 0.03,
                 "Play Shot must stop before the remainder of the movie")
    let authored = model.shots3D
    model.setClipSpeed(2, forClipID: model.clipTimeline.segments[0].id)
    precondition(model.shots3D == authored, "Shortening a clip must retain authored shots for undo")
    precondition(model.timeline3D.shots.allSatisfy { $0.end <= model.duration })
    model.setClipSpeed(1, forClipID: model.clipTimeline.segments[0].id)
    precondition(model.timeline3D.shots.count == 2)
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
    let suggestionModel = RecordingStudioModel(url: movie)
    await suggestionModel.load()
    suggestionModel.applyAuto3DScene(count: 6)
    let suggested = suggestionModel.shots3D
    precondition(suggested.count == 2 && suggested.allSatisfy { $0.end - $0.start >= 1 })
    suggestionModel.undo()
    precondition(suggestionModel.shots3D.isEmpty, "Apply Auto Scene is one undo step")
    suggestionModel.redo()
    precondition(suggestionModel.shots3D == suggested)
    suggestionModel.teardown()
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
    let mutableRenderer = compositor(.empty)
    var dynamic = Recording3DShot(start: 0, end: 2); dynamic.apply(.center)
    mutableRenderer.update3DTimeline(.init(shots: [dynamic], duration: 2))
    try mutableRenderer.render(screenFrame: source, cameraFrame: nil, editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: CGPoint(x: 5, y: 5))[1] > 240)
    mutableRenderer.update3DTimeline(.empty)
    try mutableRenderer.render(screenFrame: source, cameraFrame: nil, editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: CGPoint(x: 5, y: 5))[0] > 240, "Timeline edits must update reused GPU source/decorations")
    let edgeOn = Recording3DShot(start: 0, end: 2,
        startPose: .init(camera: .init(rotateX: 90)), endPose: .init(camera: .init(rotateX: 90)), transition: 0)
    try compositor(.init(shots: [edgeOn], duration: 2)).render(screenFrame: source, cameraFrame: nil,
        editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: CGPoint(x: 160, y: 90))[1] > 240, "An edge-on plane renders only the background")
    let horizon = Recording3DShot(start: 0, end: 2,
        startPose: .init(camera: .init(tiltY: 60, distance: 0.5, panX: 0.5)),
        endPose: .init(camera: .init(tiltY: 60, distance: 0.5, panX: 0.5)), transition: 0)
    try compositor(.init(shots: [horizon], duration: 2)).render(screenFrame: source, cameraFrame: nil,
        editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: CGPoint(x: 160, y: 90))[1] > 240,
                 "A ray behind the camera must show background, without moving the authored camera")
    style.padding = 0.2; style.shadow = 1
    let framing = RecordingStudioLayout.make(canvasSize: size, style: style, includeBubble: false)
    let flatCamera = Recording3DCamera(distance: (size.height / size.width) / tan(.pi / 8))
    let floating = Recording3DShot(start: 0, end: 2, startPose: .init(camera: flatCamera), endPose: .init(camera: flatCamera), transition: 0)
    let floatingTrack = Recording3DTimeline(shots: [floating], duration: 2)
    let zoom = ViewportTimeline.build(cues: [.init(start: 0, end: 2, zoom: 2, anchorMode: .pinnedAnchor, skipsEasing: true)],
                                     capture: PointerCaptureFile(), clipTimeline: .full(sourceDuration: 2))
    let zoomed = StudioFrameCompositor(canvasSize: size, style: style, viewportTimeline: zoom,
        pointerTimeline: nil, showsPressEffects: false, keystrokeTimeline: nil,
        keystrokePlacement: .bottomCenter, subtitleTimeline: nil, includeBubble: false, timeline3D: floatingTrack)
    let beyondCard = CGPoint(x: framing.cardRect.minX - 3, y: framing.cardRect.midY)
    try compositor(floatingTrack).render(screenFrame: source, cameraFrame: nil, editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: beyondCard)[1] > 250, "A floating 3D card must not retain its flat drop shadow: \(color(output, at: beyondCard)), point=\(beyondCard), card=\(framing.cardRect)")
    try zoomed.render(screenFrame: source, cameraFrame: nil, editorTime: 1, sourceTime: 1, into: output)
    precondition(color(output, at: beyondCard)[0] > 240, "3D zoom must enlarge the card, not crop the video inside its old bounds")
    style.padding = 0; style.shadow = 0
    // A stripe fixture measures focus preservation and softness independently of camera geometry.
    let stripes = buffer(width: 640, height: 360)
    CVPixelBufferLockBaseAddress(stripes, [])
    let stripeBytes = CVPixelBufferGetBaseAddress(stripes)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(stripes)
    for y in 0..<360 {
        for x in 0..<640 {
            let value: UInt8 = ((x / 8 + y / 8) % 2 == 0) ? 255 : 0
            let offset = y * stride + x * 4
            stripeBytes[offset] = value; stripeBytes[offset + 1] = value; stripeBytes[offset + 2] = value
            stripeBytes[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(stripes, [])
    let context = CIContext(), focusOutput = buffer(width: 640, height: 360)
    let focusCanvas = CGRect(x: 0, y: 0, width: 640, height: 360)
    func focusPixels(_ settings: Recording3DBlur) throws {
        let image = try Recording3DBlurRenderer.apply(settings, to: CIImage(cvPixelBuffer: stripes), canvas: focusCanvas)
        context.render(image, to: focusOutput, bounds: focusCanvas, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    func contrast(_ x: CGFloat, _ y: CGFloat) -> Int {
        abs(Int(color(focusOutput, at: CGPoint(x: x, y: y))[0]) - Int(color(focusOutput, at: CGPoint(x: x + 8, y: y))[0]))
    }
    var focus = Recording3DBlur(mode: .radial, strength: 60, falloff: 0, focusX: 0.5, focusY: 0.5, focusSize: 0.1)
    try focusPixels(focus)
    precondition(contrast(320, 180) > 240 && contrast(40, 180) < 140, "Radial focus keeps the center sharp and softens the edge")
    let gaussianEdge = color(focusOutput, at: CGPoint(x: 40, y: 180))
    focus.bokeh = true
    try focusPixels(focus)
    precondition(contrast(320, 180) > 240 && contrast(40, 180) < 220, "Bokeh retains focus while spreading highlights")
    precondition(color(focusOutput, at: CGPoint(x: 40, y: 180)) != gaussianEdge, "Bokeh must use its disc filter")
    focus.bokeh = false; focus.mode = .directional
    try focusPixels(focus)
    precondition(contrast(40, 180) > 240 && contrast(580, 180) < 140, "Directional blur affects only the chosen side")
    focus.angle = 180
    try focusPixels(focus)
    precondition(contrast(580, 180) > 240 && contrast(40, 180) < 140, "Directional angle reverses the focus side")
    focus.mode = .tiltShift; focus.angle = 0; focus.focusSize = 0.05
    try focusPixels(focus)
    precondition(contrast(320, 180) > 240 && contrast(320, 20) < 140, "Tilt shift keeps a sharp horizontal focus band")
    // A white impulse gives an independent, closed-form check of both kernel weights.
    let impulse = buffer(width: 640, height: 360)
    CVPixelBufferLockBaseAddress(impulse, [])
    let impulseBytes = CVPixelBufferGetBaseAddress(impulse)!.assumingMemoryBound(to: UInt8.self)
    let impulseStride = CVPixelBufferGetBytesPerRow(impulse)
    for y in 0..<360 { for x in 0..<640 {
        let i = y * impulseStride + x * 4
        impulseBytes[i] = 0; impulseBytes[i + 1] = 0; impulseBytes[i + 2] = 0; impulseBytes[i + 3] = 255
    } }
    let center = 180 * impulseStride + 320 * 4
    for c in 0..<3 { impulseBytes[center + c] = 255 }
    CVPixelBufferUnlockBaseAddress(impulse, [])
    let rawContext = CIContext(options: [.workingColorSpace: NSNull()])
    for bokeh in [false, true] {
        let settings = Recording3DBlur(mode: .directional, strength: 18, falloff: 0, position: 0, bokeh: bokeh)
        let result = try Recording3DBlurRenderer.apply(settings, to: CIImage(cvPixelBuffer: impulse), canvas: focusCanvas)
        rawContext.render(result, to: focusOutput, bounds: focusCanvas, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let weightSum = (-6...6).reduce(0.0) { $0 + exp(-Double($1 * $1) / 18) }
        let expected = bokeh ? 255 / 29.0 : 255 / (weightSum * weightSum)
        let actual = Double(color(focusOutput, at: CGPoint(x: 320, y: 180))[0])
        precondition(abs(actual - expected) < 0.55, "Cap kernel weights changed: bokeh=\(bokeh), actual=\(actual), expected=\(expected)")
        if bokeh {
            let ring = Double(color(focusOutput, at: CGPoint(x: 314, y: 180))[0])
            precondition(abs(ring - 255 * 2.5 / 30.5) < 0.55, "Bokeh must retain Cap's ring positions and highlight gain: \(ring)")
        } else {
            for offset in 1...8 {
                let expected = offset <= 6 ? 255 * exp(-Double(offset * offset) / 18) / (weightSum * weightSum) : 0
                let actual = Double(color(focusOutput, at: CGPoint(x: 320 + offset, y: 180))[0])
                precondition(abs(actual - expected) < 0.55, "Paired Gaussian taps must retain reference weights")
            }
        }
    }
    print("PASS Cap Gaussian/ring-disc weights, horizon clipping, whole-card zoom, and floating shadow suppression")
    print("PASS GPU radial/directional/tilt-shift focus, angle reversal, bokeh discs, and sharp-region preservation")
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
        var moving = still; moving.apply(.glide)
        var geometry = moving; geometry.blur = nil
        var gaussian = moving; gaussian.blur?.bokeh = false; gaussian.blur?.strength = 60
        let workloads: [(String, Recording3DTimeline)] = [
            ("flat", .empty),
            ("3D", .init(shots: [geometry], duration: 2)),
            ("3D + Gaussian 60", .init(shots: [gaussian], duration: 2)),
            ("3D + bokeh 19", .init(shots: [moving], duration: 2))
        ]
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let sourceHD = buffer(width: width, height: height, source: true)
            let outputHD = buffer(width: width, height: height)
            for (label, track) in workloads {
                let renderer = compositor(track, size: CGSize(width: width, height: height))
                var runs: [Double] = []
                for pass in 0..<4 {
                    let start = Date()
                    for frame in 0..<120 {
                        let time = 0.3 + Double(frame) / 120
                        try renderer.render(screenFrame: sourceHD, cameraFrame: nil, editorTime: time, sourceTime: time, into: outputHD)
                    }
                    if pass > 0 { runs.append(Date().timeIntervalSince(start) / 120 * 1000) }
                }
                print("BENCH \(height)p \(label) GPU compositor median \(runs.sorted()[1]) ms/frame (120 frames, 3 warm runs)")
            }
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
        func metalPreview(in view: NSView) -> Recording3DMetalView? {
            if let preview = view as? Recording3DMetalView { return preview }
            return view.subviews.lazy.compactMap { metalPreview(in: $0) }.first
        }
        precondition(model.preview3DError == nil, "Displayed GPU preview failed: \(model.preview3DError ?? "")")
        let preview = metalPreview(in: window.contentView!)!
        precondition(preview.renderedFrameCount > 1,
                     "Live check must render decoded frames, not capture an empty Metal view")
        let beforeFrames = preview.renderedFrameCount, beforeCompositors = preview.compositorBuildCount
        let original = model.selected3DShot!
        var moved = original
        moved.startPose.camera?.panX += 0.1; moved.endPose.camera?.panX += 0.1
        model.update3DShot(moved)
        try await Task.sleep(for: .milliseconds(250))
        precondition(preview.renderedFrameCount > beforeFrames && preview.compositorBuildCount == beforeCompositors,
                     "Paused 3D edits must redraw while reusing the compositor")
        model.update3DShot(original)
        try await Task.sleep(for: .milliseconds(150))
        let authored = model.shots3D, originalTime = model.currentTime
        let beforeSuggestionFrames = preview.renderedFrameCount
        model.previewAuto3DScene(count: 2)
        try await Task.sleep(for: .milliseconds(400))
        model.pause()
        precondition(model.suggested3DScene != nil && model.shots3D == authored
                     && model.preview3DError == nil && preview.renderedFrameCount > beforeSuggestionFrames
                     && preview.compositorBuildCount == beforeCompositors,
                     "Auto Scene must render transient shots through the existing GPU compositor")
        model.cancel3DScenePreview()
        precondition(model.suggested3DScene == nil && model.shots3D == authored
                     && abs(model.currentTime - originalTime) < 0.001,
                     "Cancel must restore the authored scene and playhead")
        try await Task.sleep(for: .milliseconds(150))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("video-3d-live-\(name).png").path]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
    }
    print("PASS displayed 3D playback, transient Auto Scene/cancel, compositor reuse, and light/dark screenshots")
}
