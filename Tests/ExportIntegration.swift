import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@testable import BetterShot

@main
struct ExportIntegration {
    @MainActor static func main() async throws {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through Tests/run-exports.sh to keep the real Keychain isolated")
        precondition(R2CredentialStore.shared.keychainAccess == .empty)
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
        try await checkCaptureStorage(image: image, source: source, directory: directory)
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
        for speed in [VideoCompressionSpeed.fast, .slow, .ultrafast] {
            let withOverlays = speed == .ultrafast
            var settings = VideoCompressionSettings()
            settings.speed = speed
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
                }
                count += 1
            }
            precondition(
                reader.status == .completed && count == 120, "60 fps cadence changed: \(count)")
            print("PASS \(speed.rawValue) video: 120 frames, 1080p, 2s in \(elapsed)s")
            let document = RecordingEditDocument(
                style: style, zoomEnabled: true, zoomCues: [], clipTimeline: clips,
                exportSettings: settings
            )
            let cached = try session.installFinalVideo(movingFrom: url, renderedFrom: document)
            precondition(session.freshFinalURL(matching: document) == cached)
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
        }
        print("PASS camera + audio + crop + mask, cache invalidation, and cancellation")
    }

    @MainActor static func makeMovie(at url: URL, image: CGImage) async throws {
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
        for frame in 0..<60 {
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

/// Exercises production persistence in an isolated directory; never alters the user's captures.
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
