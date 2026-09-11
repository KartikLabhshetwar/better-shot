import AVFoundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@testable import BetterShot

@main
struct ExportIntegration {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through Tests/run-exports.sh to keep the real Keychain isolated")
        precondition(R2CredentialStore.shared.keychainAccess == .empty)
        defer { try? FileManager.default.removeItem(at: ScreenshotHistoryStore.applicationSupportDirectory) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 960, y: 0, width: 960, height: 1080))
        let image = context.makeImage()!
        if ProcessInfo.processInfo.environment["BETTERSHOT_BENCHMARK_IMAGES"] == "1" {
            try benchmarkImageExports(image: image, directory: directory)
            return
        }
        if ProcessInfo.processInfo.environment["BETTERSHOT_BENCHMARK"] == "1" {
            try await benchmarkExports(image: image, directory: directory)
            return
        }
        if ProcessInfo.processInfo.environment["BETTERSHOT_CHECK_VIDEO_EXPORTS"] == "1" {
            let movie = directory.appendingPathComponent("source.mov")
            try await makeMovie(at: movie, image: image)
            try checkFrameReuse(image: image)
            try await checkVideoExports(movie: movie, directory: directory)
            return
        }
        // A one-pixel stripe image catches subpixel resampling of captured text edges.
        let sharpContext = CGContext(data: nil, width: 31, height: 31, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<31 {
            sharpContext.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 0 : 1, alpha: 1))
            sharpContext.fill(CGRect(x: x, y: 0, width: 1, height: 31))
        }
        var sharpConfig = BeautifierConfig()
        sharpConfig.cornerRadius = 0
        sharpConfig.shadowStrength = 0
        let sharpImage = BeautifierRenderer.render(image: sharpContext.makeImage()!, config: sharpConfig)!
        precondition(sharpImage.width == 36 && sharpImage.height == 36)
        let sharpBytes = CFDataGetBytePtr(sharpImage.dataProvider!.data!)!
        for x in 3..<34 {
            let offset = 16 * sharpImage.bytesPerRow + x * 4
            precondition(sharpBytes[offset] == 0 || sharpBytes[offset] == 255,
                         "Native pixels must not blur into gray during framing")
        }
        print("PASS native pixel dimensions and sharp screenshot framing")
        let source = directory.appendingPathComponent("source.png")
        let destination = CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        try benchmarkImageExports(image: image, directory: directory)
        try await checkCaptureStorage(image: image, source: source, directory: directory)
        try await checkScreenshotCopyAndSave(source: source, directory: directory)
        if ProcessInfo.processInfo.environment["BETTERSHOT_CHECK_SCREENSHOT_SAVING"] == "1" { return }
        try await checkAnnotationExport(image: image, source: source, directory: directory)
        let exported = directory.appendingPathComponent("export.png")
        let start = Date()
        try AnnotationRenderer.render(
            sourceURL: source, shapes: [], destinationURL: exported, contentType: .png)
        let sourceData = try Data(contentsOf: source)
        precondition(
            (try? Data(contentsOf: exported)) == sourceData, "Unedited PNG must be byte-identical")
        try AnnotationRenderer.render(
            sourceURL: source, shapes: [], destinationURL: source, contentType: .png)
        precondition(
            (try? Data(contentsOf: source)) == sourceData, "Export over source must preserve it")
        do {
            try AnnotationRenderer.render(
                sourceURL: directory.appendingPathComponent("missing.png"), shapes: [],
                destinationURL: exported, contentType: .png)
            preconditionFailure("Invalid source must fail")
        } catch {
            precondition(
                (try? Data(contentsOf: exported)) == sourceData,
                "Failed render destroyed previous export")
        }
        print("PASS image copy and atomic overwrite (\(Date().timeIntervalSince(start))s)")

        var background = AnnotationBackgroundSettings()
        background.style = .solid(
            AnnotationBackgroundColor("test", title: "Test", red: 0.15, green: 0.15, blue: 0.15))
        background.progressiveBlur.isEnabled = true
        let effectsStart = Date()
        try AnnotationRenderer.render(
            sourceURL: source, shapes: [], backgroundSettings: background, destinationURL: exported,
            contentType: .png)
        let rendered = CGImageSourceCreateWithURL(exported as CFURL, nil)!
        let outputImage = CGImageSourceCreateImageAtIndex(rendered, 0, nil)!
        precondition(outputImage.width > image.width && outputImage.height > image.height)
        print(
            "PASS image background + progressive blur (\(Date().timeIntervalSince(effectsStart))s)")

        let defaults = UserDefaults.standard
        let preferenceKeys = [
            "bs_openEditorAfterCapture", AppPreferences.openEditorAfterRecordingKey, "bs_playSound",
        ]
        let previousPreferences = preferenceKeys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(preferenceKeys, previousPreferences) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "bs_openEditorAfterCapture")
        defaults.removeObject(forKey: AppPreferences.openEditorAfterRecordingKey)
        AppPreferences.migrateEditorPreferences()
        defaults.set(false, forKey: "bs_openEditorAfterCapture")
        AppPreferences.migrateEditorPreferences()
        precondition(
            AppPreferences.openEditorAfterRecording && !AppPreferences.openEditorAfterCapture)
        defaults.set(false, forKey: "bs_playSound")
        precondition(!BetterShotPreferences.playSounds)
        print("PASS preference migration, independent editors, shared sound setting")

        let movie = directory.appendingPathComponent("source.mov")
        try await makeMovie(at: movie, image: image)
        precondition(HistoryStore.decodeThumbnail(.init(url: movie, kind: .recording)) != nil,
                     "Standalone recordings must produce preview thumbnails")
        let previewSession = RecordingSession(directoryURL: directory.appendingPathComponent("Preview.bettershotrec"))
        try FileManager.default.createDirectory(at: previewSession.directoryURL, withIntermediateDirectories: true)
        try Data().write(to: previewSession.screenURL)
        let poster = CGImageDestinationCreateWithURL(previewSession.posterURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(poster, image, nil)
        precondition(CGImageDestinationFinalize(poster))
        precondition(HistoryStore.decodeThumbnail(.init(url: previewSession.screenURL, kind: .recording)) != nil,
                     "A recording poster must remain available when video decoding fails")
        try FileManager.default.removeItem(at: previewSession.posterURL)
        precondition(HistoryStore.decodeThumbnail(.init(url: previewSession.screenURL, kind: .recording)) == nil,
                     "An unreadable movie must return a failure for the visible fallback card")
        print("PASS recording thumbnails, cached posters, and unreadable-video fallback")
        try await checkEditorUI(imageURL: source, movieURL: movie)
        try checkFrameReuse(image: image)
        try await checkVideoExports(movie: movie, directory: directory)
    }

    @MainActor static func checkVideoExports(movie: URL, directory: URL) async throws {
        let clips = RecordingClipTimeline.full(sourceDuration: 2)
        let viewport = ViewportTimeline.build(
            cues: [
                ZoomCue(
                    start: 0.2, end: 1.25, zoom: 2.5,
                    anchorMode: .pinnedAnchor, pinnedPoint: CGPoint(x: 0.65, y: 0.5))
            ],
            capture: PointerCaptureFile(), clipTimeline: clips)
        var style = RecordingStudioStyle()
        style.background = .solid(
            AnnotationBackgroundColor("test", title: "Test", red: 0.1, green: 0.1, blue: 0.1))
        let pointer = PointerTimeline.build(
            capture: PointerCaptureFile(travel: [
                PointerTravelSample(time: 0, x: 0.2, y: 0.3),
                PointerTravelSample(time: 1, x: 0.7, y: 0.6)
            ], presses: [PointerPressEvent(time: 1.1, x: 0.7, y: 0.6, button: 0, phase: .down)]),
            duration: 2, clipTimeline: clips,
            overrideArtwork: PointerArtworkCapture.styledArtwork(.light))
        let soundtrack = directory.appendingPathComponent("soundtrack.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
        audio.frameLength = 96_000
        audio.floatChannelData![0].initialize(repeating: 0, count: 96_000)
        do { try AVAudioFile(forWriting: soundtrack, settings: format.settings).write(from: audio) }
        let session = RecordingSession(
            directoryURL: directory.appendingPathComponent("Cache.bettershotrec"))
        try FileManager.default.createDirectory(
            at: session.directoryURL, withIntermediateDirectories: true)
        let colorContext = CIContext()
        func color(_ buffer: CVPixelBuffer, x: Int) -> [Int] {
            var rgba = [UInt8](repeating: 0, count: 4)
            colorContext.render(CIImage(cvPixelBuffer: buffer), toBitmap: &rgba, rowBytes: 4,
                                bounds: CGRect(x: x, y: 540, width: 1, height: 1), format: .RGBA8,
                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            return rgba.prefix(3).map(Int.init)
        }
        let referenceAsset = AVURLAsset(url: movie)
        let referenceReader = try AVAssetReader(asset: referenceAsset)
        let referenceTrack = try await referenceAsset.loadTracks(withMediaType: .video).first!
        let referenceOutput = AVAssetReaderTrackOutput(track: referenceTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        referenceReader.add(referenceOutput)
        precondition(referenceReader.startReading())
        let referenceBuffer = CMSampleBufferGetImageBuffer(referenceOutput.copyNextSampleBuffer()!)!
        let referenceColors = [480, 1440].map { color(referenceBuffer, x: $0) }
        referenceReader.cancelReading()
        let legacySettings = Data(#"{"quality":"Medium","speed":"Fast","codec":"H.264","resolution":"Original","removeAudio":false}"#.utf8)
        let decodedSettings = try JSONDecoder().decode(VideoCompressionSettings.self, from: legacySettings)
        precondition(decodedSettings.effectiveFrameRate == .fps60)
        for (speed, frameRate) in [(VideoCompressionSpeed.fast, VideoExportFrameRate.fps60),
                                   (.slow, .fps60), (.ultrafast, .fps60), (.fast, .fps30)] {
            let withOverlays = speed == .ultrafast
            var settings = VideoCompressionSettings()
            settings.speed = speed
            settings.frameRate = frameRate
            settings.container = withOverlays ? .mp4 : .mov
            settings.codec = withOverlays ? .hevc : .h264
            var mask = RecordingMaskSegment()
            mask.rect = CGRect(x: 0.425, y: 0.25, width: 0.15, height: 0.5)
            let configuration = RecordingStudioExporter.Configuration(
                screenURL: movie, cameraURL: withOverlays ? movie : nil,
                cameraOffset: 0, style: style, viewportTimeline: viewport,
                pointerTimeline: withOverlays ? pointer : nil,
                showsPressEffects: withOverlays, keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(),
                canvasSize: CGSize(width: 1920, height: 1080),
                clipTimeline: clips, exportSettings: settings,
                audioReplacementURL: withOverlays ? soundtrack : nil,
                crop: withOverlays
                    ? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) : RecordingVideoCrop.unit,
                masks: withOverlays ? [mask] : [])
            let start = Date()
            let url = try await RecordingStudioExporter().export(configuration) { _ in }
            defer { try? FileManager.default.removeItem(at: url) }
            let elapsed = Date().timeIntervalSince(start)
            let asset = AVURLAsset(url: url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            precondition(audioTracks.count == (withOverlays ? 1 : 0), "Audio missing from export")
            let track = try await asset.loadTracks(withMediaType: .video).first!
            let size = try await track.load(.naturalSize)
            precondition(size == CGSize(width: 1920, height: 1080))
            let duration = try await asset.load(.duration).seconds
            precondition(abs(duration - 2) < 0.04)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
            reader.add(output)
            precondition(reader.startReading())
            var count = 0
            while let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                if count == 0 {
                    CVPixelBufferLockBaseAddress(buffer, .readOnly)
                    let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(
                        to: UInt8.self)
                    let row = CVPixelBufferGetBytesPerRow(buffer) * 540
                    precondition(
                        bytes[row + 480 * 4 + 2] > bytes[row + 480 * 4] + 50,
                        "Left half must stay red")
                    precondition(
                        bytes[row + 1440 * 4] > bytes[row + 1440 * 4 + 2] + 50,
                        "Right half must stay blue")
                    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                    for (x, expected) in zip([480, 1440], referenceColors) {
                        let actual = color(buffer, x: x)
                        precondition(zip(actual, expected).allSatisfy { abs($0 - $1) <= 12 },
                                     "Encoded colors changed at \(x): \(actual), expected \(expected)")
                    }
                }
                count += 1
            }
            precondition(
                reader.status == .completed && count == frameRate.framesPerSecond * 2, "Export cadence changed: \(count)")
            print("PASS \(speed.rawValue) video: \(count) frames, 1080p, 2s in \(elapsed)s")
            let document = RecordingEditDocument(
                style: style, zoomEnabled: true, zoomCues: [], clipTimeline: clips,
                exportSettings: settings
            )
            let cached = try session.installFinalVideo(movingFrom: url, renderedFrom: document)
            precondition(session.freshFinalURL(matching: document) == cached)
            var differentCadence = document
            differentCadence.exportSettings?.frameRate = frameRate == .fps30 ? .fps60 : .fps30
            precondition(session.freshFinalURL(matching: differentCadence) == nil,
                         "Changing frame rate must invalidate the cached deliverable")
            if withOverlays {
                for (rate, expectedDuration) in [(0.5, 4.0), (1.25, 1.6), (1.5, 4.0 / 3), (2.5, 0.8)] {
                    let timeline = RecordingClipTimeline(segments: [
                        RecordingClipSegment(sourceStart: 0, sourceEnd: 2, speed: rate)
                    ])
                    let retimed = try RecordingCompositionBuilder.makeAsset(
                        from: AVURLAsset(url: cached), timeline: timeline, sourceDuration: 2)
                    let videoTracks = try await retimed.loadTracks(withMediaType: .video)
                    let audioTracks = try await retimed.loadTracks(withMediaType: .audio)
                    let tracks = videoTracks + audioTracks
                    precondition(tracks.count == 2)
                    for track in tracks {
                        let range = try await track.load(.timeRange)
                        precondition(abs(range.duration.seconds - expectedDuration) < 0.04,
                                     "Recorded audio and video must share the fractional clip timing")
                    }
                    let fractionalExport = try await RecordingStudioExporter().export(.init(
                        screenURL: cached, cameraURL: nil, cameraOffset: 0, style: style,
                        viewportTimeline: .identity, pointerTimeline: nil, showsPressEffects: false,
                        keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                        subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(),
                        canvasSize: CGSize(width: 480, height: 270), clipTimeline: timeline,
                        exportSettings: settings
                    )) { _ in }
                    defer { try? FileManager.default.removeItem(at: fractionalExport) }
                    let fractionalAsset = AVURLAsset(url: fractionalExport)
                    let duration = try await fractionalAsset.load(.duration).seconds
                    let audio = try await fractionalAsset.loadTracks(withMediaType: .audio)
                    precondition(abs(duration - expectedDuration) < 0.04 && audio.count == 1,
                                 "Export must preserve fractional timing and recorded audio")
                }
                print("PASS fractional playback/export timing for recorded video and audio")
            }
            var changed = document
            changed.exportSettings?.resolution = .p720
            precondition(
                session.freshFinalURL(matching: changed) == nil,
                "Edits must invalidate the cached render")
            let cancelled = Task {
                try await RecordingStudioExporter().export(configuration) { _ in }
            }
            cancelled.cancel()
            do {
                _ = try await cancelled.value
                preconditionFailure("Cancelled export succeeded")
            } catch is CancellationError {} catch RecordingStudioExporter.ExportError.cancelled {}
            if frameRate == .fps30 {
                do {
                    _ = try await RecordingStudioExporter().export(configuration) { _ in
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    preconditionFailure("Export cancelled with GPU frames in flight succeeded")
                } catch is CancellationError {} catch RecordingStudioExporter.ExportError.cancelled {}
            }
        }
        print("PASS camera + audio + crop + mask, cache invalidation, and cancellation")
    }

    @MainActor static func checkFrameReuse(image: CGImage) throws {
        let size = CGSize(width: 320, height: 180)
        func buffer(image: CGImage? = nil) -> CVPixelBuffer {
            var result: CVPixelBuffer?
            precondition(CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA,
                nil, &result) == kCVReturnSuccess)
            let resultBuffer = result!
            CVPixelBufferLockBaseAddress(resultBuffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(resultBuffer),
                width: 320, height: 180, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(resultBuffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            if let image {
                context.draw(image, in: CGRect(origin: .zero, size: size))
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 12, y: 12, width: 20, height: 20))
            }
            CVPixelBufferUnlockBaseAddress(resultBuffer, [])
            return resultBuffer
        }
        func pixels(_ buffer: CVPixelBuffer) -> Data {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            var data = Data()
            for row in 0..<180 {
                data.append(CVPixelBufferGetBaseAddress(buffer)!.advanced(
                    by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self), count: 320 * 4)
            }
            return data
        }
        let source = buffer(image: image)
        var plainStyle = RecordingStudioStyle()
        plainStyle.background = .none
        plainStyle.padding = 0
        plainStyle.cornerRadius = 0
        plainStyle.shadow = 0
        var timedMask = RecordingMaskSegment()
        timedMask.rect = CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8)
        timedMask.amount = 80
        timedMask.start = 0.5
        timedMask.end = 1
        let timedCompositor = StudioFrameCompositor(canvasSize: size, style: plainStyle,
            viewportTimeline: .identity, pointerTimeline: nil, showsPressEffects: false,
            keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
            subtitleTimeline: nil, includeBubble: false, masks: [timedMask])
        let sourcePixels = pixels(source)
        for time in [0.0, 0.75, 1.25] {
            let rendered = buffer()
            try timedCompositor.render(screenFrame: source, cameraFrame: nil,
                                       editorTime: time, sourceTime: time, into: rendered)
            let renderedPixels = pixels(rendered)
            if time == 0.75 {
                precondition(renderedPixels != sourcePixels, "An active blur must change the exported pixels")
            } else {
                precondition(zip(renderedPixels, sourcePixels).allSatisfy { abs(Int($0) - Int($1)) <= 2 },
                             "GPU output must preserve source colors, orientation, and inactive mask timing")
            }
        }
        print("PASS GPU colors/orientation and timed redaction pixels")
        let changedSource = buffer(image: image.cropping(to: CGRect(x: 960, y: 0, width: 960, height: 1080))!)
        var cameraRenders = Set<Data>()
        for ratio in RecordingCameraAspectRatio.allCases {
            var style = RecordingStudioStyle()
            style.camera.aspectRatio = ratio
            style.camera.center = CGPoint(x: 0.25, y: 0.5)
            style.camera.size = 0.45
            let compositor = StudioFrameCompositor(canvasSize: size, style: style,
                viewportTimeline: .build(cues: [], capture: PointerCaptureFile(),
                    clipTimeline: .full(sourceDuration: 2)),
                pointerTimeline: nil, showsPressEffects: false,
                keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                subtitleTimeline: nil, includeBubble: true)
            let rendered = buffer()
            try compositor.render(screenFrame: source, cameraFrame: changedSource,
                                  editorTime: 0, sourceTime: 0, into: rendered)
            precondition(cameraRenders.insert(pixels(rendered)).inserted,
                         "Each camera ratio must produce a distinct exported frame")
        }
        print("PASS all six face-camera ratios through the production export compositor")
        var layoutRenders = Set<Data>()
        for preset in RecordingLayoutPreset.allCases {
            for cameraOnLeft in [false, true] {
                var style = RecordingStudioStyle()
                style.layoutPreset = preset
                style.cameraOnLeft = cameraOnLeft
                if preset == .overlap {
                    style.camera.aspectRatio = .vertical
                    style.camera.size = 0.55
                    style.camera.roundness = 0.08
                }
                let compositor = StudioFrameCompositor(canvasSize: size, style: style,
                    viewportTimeline: .identity, pointerTimeline: nil, showsPressEffects: false,
                    keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                    subtitleTimeline: nil, includeBubble: true)
                let rendered = buffer()
                try compositor.render(screenFrame: source, cameraFrame: changedSource,
                                      editorTime: 0, sourceTime: 0, into: rendered)
                let first = pixels(rendered)
                if !cameraOnLeft || preset.positionsCamera {
                    precondition(layoutRenders.insert(first).inserted, "Every layout and mirrored position must render distinctly")
                }
                if preset == .cameraOnly {
                    try compositor.render(screenFrame: changedSource, cameraFrame: changedSource,
                                          editorTime: 0, sourceTime: 0, into: rendered)
                    precondition(first == pixels(rendered), "Camera Only must exclude the screen track")
                } else if preset == .screenOnly {
                    try compositor.render(screenFrame: source, cameraFrame: source,
                                          editorTime: 0, sourceTime: 0, into: rendered)
                    precondition(first == pixels(rendered), "Screen Only must exclude the camera track")
                }
                let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build/editor-snapshots/layout-export-\(preset.rawValue)-\(cameraOnLeft ? "left" : "right").png")
                let renderedImage = CIContext().createCGImage(CIImage(cvPixelBuffer: rendered), from: CGRect(origin: .zero, size: size))!
                let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, renderedImage, nil)
                precondition(CGImageDestinationFinalize(destination))
            }
        }
        print("PASS all screen/camera layouts, positions, and exclusive track visibility through the production compositor")
        let clips = RecordingClipTimeline.full(sourceDuration: 2)
        let viewport = ViewportTimeline.build(cues: [ZoomCue(start: 0.4, end: 1.1, zoom: 2)],
            capture: PointerCaptureFile(), clipTimeline: clips)
        let pointer = PointerTimeline.build(capture: PointerCaptureFile(travel: [
            PointerTravelSample(time: 0, x: 0.2, y: 0.5),
            PointerTravelSample(time: 2, x: 0.8, y: 0.5)
        ]), duration: 2, clipTimeline: clips,
            overrideArtwork: PointerArtworkCapture.styledArtwork(.macOS))
        var blur = RecordingMaskSegment()
        blur.rect = CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8)
        blur.start = 0.05; blur.end = 0.9
        var pixelate = blur
        pixelate.effect = .pixelate
        pixelate.start = 0.5; pixelate.end = 1.5
        // Deliberately shared IDs: distinct array entries still have different effects.
        func compositor() -> StudioFrameCompositor {
            StudioFrameCompositor(canvasSize: size, style: RecordingStudioStyle(),
                viewportTimeline: viewport, pointerTimeline: pointer, showsPressEffects: true,
                keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                subtitleTimeline: nil, includeBubble: true,
                crop: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), masks: [blur, pixelate])
        }
        let reused = compositor()
        for (index, time) in [0.0, 1.0 / 60, 0.06, 0.5, 0.7, 0.91, 1.25, 1.6, 1.7, 1.9].enumerated() {
            let screen = index < 7 ? source : changedSource
            let camera = index.isMultiple(of: 2) ? source : changedSource
            let actual = buffer(), expected = buffer()
            try reused.render(screenFrame: screen, cameraFrame: camera,
                editorTime: time, sourceTime: time, into: actual)
            try compositor().render(screenFrame: screen, cameraFrame: camera,
                editorTime: time, sourceTime: time, into: expected)
            // Cached half-float GPU intermediates can round one 8-bit level
            // differently from a freshly fused graph at filtered edges.
            precondition(zip(pixels(actual), pixels(expected)).allSatisfy { abs(Int($0) - Int($1)) <= 1 },
                "Reused frames differ from fresh rendering at \(time): source, zoom, mask timing, or overlays went stale")
        }
        print("PASS reused/fresh frame pixels across source, zoom, mask timing, pointer, and camera changes")
    }

    /// Full-resolution PNG exports through the same path used by Copy, Save, and Export.
    @MainActor static func benchmarkImageExports(image: CGImage, directory: URL) throws {
        let source = directory.appendingPathComponent("image-benchmark.png")
        let destination = CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        var background = AnnotationBackgroundSettings()
        background.progressiveBlur.isEnabled = true
        let output = directory.appendingPathComponent("image-output.png")
        var first: Data?
        for index in 0..<3 {
            let start = Date()
            try AnnotationRenderer.render(sourceURL: source, shapes: [],
                backgroundSettings: background, destinationURL: output, contentType: .png)
            let seconds = Date().timeIntervalSince(start)
            let data = try Data(contentsOf: output)
            if let first { precondition(data == first, "Repeated PNG exports must preserve bytes") }
            else { first = data }
            print("BENCH image-\(index): \(image.width)x\(image.height) source; render=\(seconds)s; bytes=\(data.count)")
        }
        background.padding += 0.2
        try AnnotationRenderer.render(sourceURL: source, shapes: [],
            backgroundSettings: background, destinationURL: output, contentType: .png)
        let changedEdits = try Data(contentsOf: output)
        precondition(changedEdits != first, "Changed edits must invalidate image reuse")
        // Replace the source at the same path; content, not just the path, identifies a render.
        let replacement = CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(replacement, image.cropping(to: CGRect(x: 0, y: 0, width: 960, height: 540))!, nil)
        precondition(CGImageDestinationFinalize(replacement))
        background.padding -= 0.2
        try AnnotationRenderer.render(sourceURL: source, shapes: [],
            backgroundSettings: background, destinationURL: output, contentType: .png)
        let changedSource = try Data(contentsOf: output)
        precondition(changedSource != first, "Replacing a source must invalidate image reuse")
        let wallpaper = directory.appendingPathComponent("wallpaper.png")
        try Data(contentsOf: source).write(to: wallpaper)
        background.style = .customWallpaper(AnnotationCustomWallpaper(url: wallpaper))
        try AnnotationRenderer.render(sourceURL: source, shapes: [],
            backgroundSettings: background, destinationURL: output, contentType: .png)
        let firstWallpaper = try Data(contentsOf: output)
        let wallpaperWriter = CGImageDestinationCreateWithURL(
            wallpaper as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(wallpaperWriter,
            image.cropping(to: CGRect(x: 960, y: 0, width: 960, height: 540))!, nil)
        precondition(CGImageDestinationFinalize(wallpaperWriter))
        try AnnotationRenderer.render(sourceURL: source, shapes: [],
            backgroundSettings: background, destinationURL: output, contentType: .png)
        let changedWallpaper = try Data(contentsOf: output)
        precondition(changedWallpaper != firstWallpaper,
                     "Replacing wallpaper contents must invalidate image reuse")
        try FileManager.default.removeItem(at: source)
        let goodOutput = try Data(contentsOf: output)
        do {
            try AnnotationRenderer.render(sourceURL: source, shapes: [],
                backgroundSettings: background, destinationURL: output, contentType: .png)
            preconditionFailure("A cached export must not hide a missing source")
        } catch {
            precondition((try? Data(contentsOf: output)) == goodOutput)
        }
        print("PASS image render reuse, edits, source/wallpaper replacement, and missing-source recovery")
    }

    /// Opt-in two-minute workload; measures production rendering and upload preparation without R2 access.
    @MainActor static func benchmarkExports(image: CGImage, directory: URL) async throws {
        let movie = directory.appendingPathComponent("benchmark.mov")
        try await makeMovie(at: movie, image: image, duration: 120)
        let clips = RecordingClipTimeline.full(sourceDuration: 120)
        let capture = PointerCaptureFile(travel: (0..<240).map {
            PointerTravelSample(time: Double($0) / 2, x: Double($0 % 10) / 12 + 0.1, y: 0.5)
        }, presses: (0..<60).map {
            PointerPressEvent(time: Double($0) * 2, x: 0.5, y: 0.5, button: 0, phase: .down)
        })
        let viewport = ViewportTimeline.build(cues: (0..<12).map {
            ZoomCue(start: Double($0) * 10 + 1, end: Double($0) * 10 + 7, zoom: 2.5)
        }, capture: capture, clipTimeline: clips)
        let pointer = PointerTimeline.build(capture: capture, duration: 120, clipTimeline: clips,
            overrideArtwork: PointerArtworkCapture.styledArtwork(.light))
        let masks = (0..<4).map { index in
            var mask = RecordingMaskSegment()
            mask.rect = CGRect(x: Double(index % 2) * 0.5, y: Double(index / 2) * 0.5, width: 0.3, height: 0.3)
            mask.effect = index.isMultiple(of: 2) ? .blur : .pixelate
            mask.amount = 24
            return mask
        }
        let soundtrack = directory.appendingPathComponent("benchmark.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 5_760_000)!
        audio.frameLength = audio.frameCapacity
        audio.floatChannelData![0].initialize(repeating: 0, count: Int(audio.frameLength))
        try AVAudioFile(forWriting: soundtrack, settings: format.settings).write(from: audio)
        for (label, effects, speed, frameRate) in [("plain-fast", false, VideoCompressionSpeed.fast, VideoExportFrameRate.fps60),
            ("effects-fast", true, .fast, .fps60), ("effects-ultrafast", true, .ultrafast, .fps60),
            ("effects-fast-30fps", true, .fast, .fps30)] {
            var style = RecordingStudioStyle()
            if !effects { style.background = .none; style.padding = 0; style.cornerRadius = 0; style.shadow = 0 }
            var settings = VideoCompressionSettings()
            settings.speed = speed
            settings.frameRate = frameRate
            settings.resolution = .p1080
            settings.container = .mp4
            let configuration = RecordingStudioExporter.Configuration(
                screenURL: movie, cameraURL: effects ? movie : nil, cameraOffset: 0,
                style: style, viewportTimeline: effects ? viewport : .identity,
                pointerTimeline: effects ? pointer : nil, showsPressEffects: effects,
                keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
                subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(),
                canvasSize: CGSize(width: 1920, height: 1080), clipTimeline: clips,
                exportSettings: settings, audioReplacementURL: soundtrack,
                crop: effects ? CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9) : RecordingVideoCrop.unit,
                masks: effects ? masks : [])
            print("BENCH starting \(label)")
            let start = Date()
            let output = try await RecordingStudioExporter().export(configuration) { _ in }
            defer { try? FileManager.default.removeItem(at: output) }
            let renderSeconds = Date().timeIntervalSince(start)
            let duration = try await AVURLAsset(url: output).load(.duration).seconds
            precondition(abs(duration - 120) < 0.04)
            let preparationStart = Date()
            let upload = await CloudUploader.compressedVideo(at: output, into: directory)
            let preparationSeconds = Date().timeIntervalSince(preparationStart)
            print("BENCH \(label): 120s 1080p\(frameRate.framesPerSecond); render=\(renderSeconds)s; upload-preparation=\(preparationSeconds)s; render-bytes=\(ShareImageCompressor.byteCount(output)); upload-bytes=\(ShareImageCompressor.byteCount(upload))")
        }
    }

    @MainActor static func makeMovie(at url: URL, image: CGImage, duration: Double = 2) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: image.width,
                AVVideoHeightKey: image.height,
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: image.width,
                kCVPixelBufferHeightKey as String: image.height,
            ])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<Int(duration * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixelBuffer = buffer!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer), width: image.width,
                height: image.height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: (frame * 13) % image.width, y: image.height / 3, width: 96, height: 96))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            precondition(
                adaptor.append(
                    pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}

@MainActor
private func checkAnnotationExport(image: CGImage, source: URL, directory: URL) async throws {
    let history = HistoryStore(storageDirectory: directory.appendingPathComponent("annotation-history"))
    let record = history.importCapture(from: source, deleteSource: false)!
    let raw = history.urlForRecord(record)
    let rawData = try Data(contentsOf: raw)
    precondition(history.annotationExportURL(for: raw) == nil)
    let output = directory.appendingPathComponent("annotation-export.png")
    try FileManager.default.copyItem(at: source, to: output)
    precondition(history.setBeautifiedPath(output.path, for: record.id))
    precondition(history.annotationExportURL(for: raw) == output)
    precondition(history.annotationExportURL(for: output) == output)
    precondition(history.annotationExportURL(for: source) == nil)
    let edited = CaptureOrchestrator.saveImage(
        image.cropping(to: CGRect(x: 0, y: 0, width: 32, height: 32))!, in: directory.path)!
    try ScreenshotFileActions.replaceExistingExport(from: edited, at: history.annotationExportURL(for: raw)!, compressionQuality: 0.9)
    let savedData = try Data(contentsOf: output)
    precondition(savedData != rawData)
    precondition((try? Data(contentsOf: raw)) == rawData)
    do {
        try ScreenshotFileActions.replaceExistingExport(
            from: directory.appendingPathComponent("missing.png"), at: output, compressionQuality: 0.9)
        preconditionFailure("Expected reading the source to fail")
    } catch {}
    precondition((try? Data(contentsOf: output)) == savedData)
    for type in [UTType.jpeg, .heic] {
        let encoded = directory.appendingPathComponent("annotation-export.\(type.preferredFilenameExtension!)")
        try await Task.detached {
            try ScreenshotFileActions.replaceExistingExport(from: edited, at: encoded, compressionQuality: 0.9)
        }.value
        let encodedSource = CGImageSourceCreateWithURL(encoded as CFURL, nil)!
        precondition(CGImageSourceGetType(encodedSource) as String? == type.identifier)
        let decoded = CGImageSourceCreateImageAtIndex(encodedSource, 0, nil)!
        precondition(decoded.width == 32 && decoded.height == 32)
    }
    precondition(history.records.count == 1)
    print("PASS annotation saves update the associated export and preserve the source and previous export on failure")
}

/// Exercises production persistence in an isolated directory; never alters the user's captures.
@MainActor
private func checkScreenshotCopyAndSave(source: URL, directory: URL) async throws {
    let originalData = try Data(contentsOf: source)
    let saveFolder = directory.appendingPathComponent("explicit-saves")
    try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
    let oldFolder = AppPreferences.saveDirectory
    let oldCopy = AppPreferences.copyAfterSave
    let oldEditor = AppPreferences.openEditorAfterCapture
    let oldKeep = AppPreferences.keepInDeckUntilSaved
    let oldHandler = PreviewPanelPresenter.shared.onAnnotate
    let oldRecords = Set(HistoryStore.shared.records.map(\.id))
    var editorURL: URL?
    PreviewPanelPresenter.shared.onAnnotate = { editorURL = ScreenshotHistoryStore.shared.annotationEditorURL(for: $0) }
    AppPreferences.saveDirectory = saveFolder.path
    AppPreferences.copyAfterSave = true
    defer {
        PreviewOverlay.shared.clearAll()
        DeckStaging.purge()
        for record in HistoryStore.shared.records where !oldRecords.contains(record.id) {
            HistoryStore.shared.deleteRecord(record)
        }
        AppPreferences.saveDirectory = oldFolder
        AppPreferences.copyAfterSave = oldCopy
        AppPreferences.openEditorAfterCapture = oldEditor
        AppPreferences.keepInDeckUntilSaved = oldKeep
        PreviewPanelPresenter.shared.onAnnotate = oldHandler
    }
    func capture(_ action: ShortcutService.Action = .region) async throws -> URL {
        let temporary = directory.appendingPathComponent("capture-\(UUID().uuidString).png")
        try originalData.write(to: temporary)
        await CaptureOrchestrator.shared.processCapturedImage(temporary, action: action)
        return CaptureOrchestrator.shared.lastCaptureURL!
    }
    func savedFiles() -> [URL] {
        try! FileManager.default.contentsOfDirectory(at: saveFolder, includingPropertiesForKeys: nil)
    }
    for keep in [false, true] {
        AppPreferences.keepInDeckUntilSaved = keep
        for opensEditor in [false, true] {
            AppPreferences.openEditorAfterCapture = opensEditor
            for action in [ShortcutService.Action.region, .timedRegion, .fullscreen, .window, .regionCopy, .regionEdit] {
                editorURL = nil
                let staged = try await capture(action)
                precondition(savedFiles().isEmpty, "Capture and opening the editor must never export automatically")
                if let editorURL {
                    precondition((try? Data(contentsOf: editorURL)) == originalData, "The editor opens untouched source pixels")
                    precondition(HistoryStore.shared.annotationExportURL(for: editorURL) == nil)
                } else {
                    precondition(DeckStaging.isStaged(staged) == keep)
                    let previewData = try Data(contentsOf: staged)
                    PreviewOverlay.shared.copy(staged)
                    precondition(NSPasteboard.general.data(forType: .png) == previewData)
                    let clipboardURL = URL(string: NSPasteboard.general.string(forType: .fileURL)!)!
                    precondition(!DeckStaging.isStaged(clipboardURL)
                        && (try? Data(contentsOf: clipboardURL)) == previewData,
                        "Clipboard file pastes must survive dismissing the card")
                    precondition(FileManager.default.fileExists(atPath: staged.path) != keep,
                                 "Normal captures stay available for Restore Last Capture; staged cards are discarded")
                    try FileManager.default.removeItem(at: clipboardURL)
                }
                PreviewOverlay.shared.clearAll()
                precondition(savedFiles().isEmpty, "Deck Copy is clipboard-only")
            }
        }
    }
    AppPreferences.openEditorAfterCapture = false
    AppPreferences.copyAfterSave = false
    let clipboardChangeCount = NSPasteboard.general.changeCount
    let staged = try await capture()
    precondition(NSPasteboard.general.changeCount == clipboardChangeCount, "Disabling automatic Copy preserves the clipboard")
    let retained = DeckStaging.retain(staged)
    precondition(!DeckStaging.isStaged(retained) && savedFiles().isEmpty,
                 "Edit/Pin/Share/drag-out retain privately without exporting")
    PreviewOverlay.shared.remove(staged)
    precondition(FileManager.default.fileExists(atPath: retained.path), "Retained media survives card dismissal")
    let raw = ScreenshotHistoryStore.shared.annotationEditorURL(for: retained)
    let saved = try ScreenshotFileActions.saveCapture(from: raw)
    precondition(saved.deletingLastPathComponent().resolvingSymlinksInPath().path == saveFolder.resolvingSymlinksInPath().path
                 && savedFiles().count == 1,
                 "Explicit editor Save expected \(saveFolder.path), got \(saved.path); files: \(savedFiles().map(\.lastPathComponent))")
    let savedData = try Data(contentsOf: saved)
    let rendered = directory.appendingPathComponent("editor-render.png")
    var background = AnnotationBackgroundSettings()
    background.style = .solid(.black)
    try AnnotationRenderer.render(sourceURL: raw, shapes: [], backgroundSettings: background,
                                  destinationURL: rendered, contentType: .png)
    let editedData = try Data(contentsOf: rendered)
    precondition(editedData != savedData, "The editor fixture must actually change the image")
    try ScreenshotFileActions.copyPNGToClipboard(from: rendered)
    precondition(savedFiles().count == 1 && (try? Data(contentsOf: saved)) == savedData,
                 "Editor Copy must not create or update an export")
    let savedAgain = try ScreenshotFileActions.saveCapture(from: rendered, for: raw)
    precondition(savedAgain == saved && savedFiles().count == 1)
    precondition((try? Data(contentsOf: saved)) == editedData)
    precondition((try? Data(contentsOf: raw)) == originalData, "Saving preserves the editable source")

    let toSave = try await capture()
    PreviewOverlay.shared.save(toSave)
    precondition(savedFiles().count == 2 && !PreviewOverlay.shared.items.contains(toSave))
    _ = try await capture(.regionSave)
    precondition(savedFiles().count == 3, "Capture-and-save remains an explicit Save action")
    let retry = try await capture()
    let blockedFolder = directory.appendingPathComponent("not-a-directory")
    try Data("block".utf8).write(to: blockedFolder)
    AppPreferences.saveDirectory = blockedFolder.path
    PreviewOverlay.shared.save(retry)
    precondition(PreviewOverlay.shared.items.contains(retry)
                 && FileManager.default.fileExists(atPath: retry.path), "Failed Save preserves the card for retry")
    AppPreferences.saveDirectory = saveFolder.path
    PreviewOverlay.shared.save(retry)
    precondition(savedFiles().count == 4 && !PreviewOverlay.shared.items.contains(retry))
    print("PASS all screenshot capture modes, clipboard-only deck/editor Copy, private retention, explicit Save, and retry")
}

@MainActor
private func checkCaptureStorage(image: CGImage, source: URL, directory: URL) async throws {
    let history = HistoryStore(storageDirectory: directory.appendingPathComponent("history"))
    let first = history.importCapture(from: source, deleteSource: false)!
    let second = history.importCapture(from: source, deleteSource: false)!
    precondition(first.filename != second.filename)
    precondition(history.importCapture(from: directory.appendingPathComponent("missing.png")) == nil)
    precondition(history.records.count == 2, "A failed import must not insert a capture")
    let childDirectory = directory.appendingPathComponent("project")
    let siblingDirectory = directory.appendingPathComponent("project-copy")
    for folder in [childDirectory, siblingDirectory] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("image.png")
        try FileManager.default.copyItem(at: source, to: url)
        history.referenceCapture(at: url)
    }
    let siblingURL = siblingDirectory.appendingPathComponent("image.png")
    let sibling = history.referenceCapture(at: siblingURL)!
    let alias = siblingDirectory.appendingPathComponent("../project-copy/image.png")
    precondition(history.referenceCapture(at: alias)?.id == sibling.id,
                 "Equivalent paths must not create duplicate history entries")
    history.removeRecords(underDirectory: childDirectory)
    precondition(history.records.contains { $0.id == sibling.id },
                 "Removing project must not remove project-copy")
    precondition(FileManager.default.fileExists(atPath: siblingURL.path))
    history.deleteRecord(first)
    precondition(!history.setBeautifiedPath(source.path, for: first.id),
                 "Late rendering must not revive a deleted capture")
    let reloaded = HistoryStore(storageDirectory: directory.appendingPathComponent("history"))
    precondition(reloaded.records.map(\.id) == history.records.map(\.id))

    let smallImage = image.cropping(to: CGRect(x: 0, y: 0, width: 32, height: 32))!
    let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<24 {
            group.addTask {
                guard let output = CaptureOrchestrator.saveImage(smallImage, in: directory.path) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return output
            }
        }
        var urls: [URL] = []
        for try await url in group { urls.append(url) }
        return urls
    }
    precondition(Set(outputs).count == 24, "Concurrent saves need unique destinations")
    for output in outputs {
        let imageSource = CGImageSourceCreateWithURL(output as CFURL, nil)!
        precondition(CGImageSourceCreateImageAtIndex(imageSource, 0, nil)?.width == 32)
    }
    precondition(CaptureOrchestrator.saveImage(smallImage, in: directory.appendingPathComponent("missing").path) == nil)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    precondition(!leftovers.contains { $0.hasPrefix(".bettershot_") }, "Staging files must be cleaned up")
    print("PASS capture collisions, failed saves/imports, deleted capture guard, path identity, and history persistence")
}
