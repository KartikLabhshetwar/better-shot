import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@testable import BetterShot

@main
struct ExportIntegration {
    @MainActor static func main() async throws {
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
        let source = directory.appendingPathComponent("source.png")
        let destination = CGImageDestinationCreateWithURL(
            source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
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
                cameraOffset: 0, style: style, viewportTimeline: viewport, pointerTimeline: nil,
                showsPressEffects: false, keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
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
