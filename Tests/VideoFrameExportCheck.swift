import AVFoundation
import AppKit
import CoreVideo

@main
enum VideoFrameExportCheck {
    static let fps: Int32 = 30
    static let seconds = 10
    static let sourceWidth = 1280
    static let sourceHeight = 720
    static let pad: CGFloat = 60

    static func makeVideo(at url: URL, width: Int = sourceWidth, height: Int = sourceHeight, blue: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        precondition(writer.startWriting(), "test video writer failed to start")
        writer.startSession(atSourceTime: .zero)

        let total = Int(fps) * seconds
        for frame in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            guard let pool = adaptor.pixelBufferPool else { preconditionFailure("no pixel buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            guard let buffer else { preconditionFailure("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let total = bytesPerRow * CVPixelBufferGetHeight(buffer)
                if blue {
                    let pixels = base.assumingMemoryBound(to: UInt8.self)
                    for offset in stride(from: 0, to: total, by: 4) {
                        pixels[offset] = 255
                        pixels[offset + 1] = 0
                        pixels[offset + 2] = 0
                        pixels[offset + 3] = 255
                    }
                } else {
                    memset(base, Int32(UInt8(truncatingIfNeeded: frame * 7)), total)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            precondition(adaptor.append(buffer, withPresentationTime: time), "test video append failed")
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        precondition(writer.status == .completed, "test video writer failed: \(String(describing: writer.error))")
    }

    static func makeAudio(at url: URL) throws {
        let sampleRate = 44_100.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2
        ])
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(sampleRate)
        for second in 0..<seconds {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            for channel in 0..<Int(format.channelCount) {
                guard let data = buffer.floatChannelData?[channel] else { continue }
                for frame in 0..<Int(frames) {
                    let t = Double(second) + Double(frame) / sampleRate
                    data[frame] = Float(sin(2 * .pi * 440 * t) * 0.2)
                }
            }
            try file.write(from: buffer)
        }
    }

    static func run() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-export-check-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let videoURL = dir.appendingPathComponent("source.mp4")
        let cameraURL = dir.appendingPathComponent("source.camera.mp4")
        let audioURL = dir.appendingPathComponent("source.m4a")
        let outputURL = dir.appendingPathComponent("out.mp4")
        try makeVideo(at: videoURL)
        try makeVideo(at: cameraURL, width: 640, height: 480, blue: true)
        try makeAudio(at: audioURL)

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)

        let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)

        let cameraAsset = AVURLAsset(url: cameraURL)
        let cameraTrack = try await cameraAsset.loadTracks(withMediaType: .video)[0]
        let compCamera = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try compCamera.insertTimeRange(range, of: cameraTrack, at: .zero)

        let canvasSize = CGSize(width: CGFloat(sourceWidth) + pad * 2, height: CGFloat(sourceHeight) + pad * 2)
        let clickPoint = CGPoint(x: pad + 900, y: pad + 160)
        let clickRadius: CGFloat = 60
        let clickTime: TimeInterval = 2
        let cameraRect = CGRect(x: pad + 120, y: pad + 100, width: 200, height: 200)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvasSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(CGAffineTransform(translationX: pad, y: pad), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let configuration = VideoFrameExporter.Configuration(
            composition: composition,
            videoComposition: videoComposition,
            canvasSize: canvasSize,
            cardRect: CGRect(x: pad, y: pad, width: CGFloat(sourceWidth), height: CGFloat(sourceHeight)),
            cornerRadius: 24,
            backgroundStyle: .gradient(GradientPreset.presets[0]),
            shadowStrength: 0.6,
            outputURL: outputURL,
            camera: VideoFrameExporter.Configuration.Camera(trackID: compCamera.trackID, rect: cameraRect),
            clicks: [ClickHighlight(time: clickTime, point: clickPoint)],
            clickRadius: clickRadius
        )

        let result = try await VideoFrameExporter().export(configuration) { _ in }

        let exported = AVURLAsset(url: result)
        let exportedVideo = try await exported.loadTracks(withMediaType: .video)
        let exportedAudio = try await exported.loadTracks(withMediaType: .audio)
        precondition(exportedVideo.count == 1, "expected 1 video track, got \(exportedVideo.count)")
        precondition(exportedAudio.count == 1, "expected 1 audio track, got \(exportedAudio.count)")

        let exportedDuration = try await exported.load(.duration).seconds
        precondition(abs(exportedDuration - Double(seconds)) < 0.5, "expected ~\(seconds)s, got \(exportedDuration)")

        let audioDuration = try await exportedAudio[0].load(.timeRange).duration.seconds
        precondition(audioDuration > Double(seconds) - 0.5, "audio track truncated: \(audioDuration)s of \(seconds)s")

        let size = try await exportedVideo[0].load(.naturalSize)
        precondition(size == canvasSize, "expected canvas \(canvasSize), got \(size)")

        let bytes = (try FileManager.default.attributesOfItem(atPath: result.path)[.size] as? Int) ?? 0
        precondition(bytes > 50_000, "exported file suspiciously small: \(bytes) bytes")

        let generator = AVAssetImageGenerator(asset: exported)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image
        // The sampling context is y-up like the bubble rect, so both read in the same coordinate space.
        let inside = try sample(frame, at: CGPoint(x: cameraRect.midX, y: cameraRect.midY), canvasSize: canvasSize)
        let outside = try sample(frame, at: CGPoint(x: cameraRect.midX, y: cameraRect.midY + cameraRect.height), canvasSize: canvasSize)
        precondition(inside.blue > 180 && inside.red < 80, "the face cam must be composited into its circle, sampled \(inside)")
        precondition(!(outside.blue > 180 && outside.red < 80), "the face cam must stay inside its circle, sampled \(outside)")

        // The click ring is the only bright thing on a flat gray frame, so its own mirror image is the control sample.
        let ringTime = clickTime + ClickHighlight.duration * 0.48
        guard let ringPhase = ClickHighlight(time: clickTime, point: clickPoint).phase(at: ringTime) else {
            preconditionFailure("expected the ring to still be alive at \(ringTime)")
        }
        let strokeOffset = (clickRadius - max(2, clickRadius * 0.16) / 2) * ringPhase.scale
        let ringFrame = try await generator.image(at: CMTime(seconds: ringTime, preferredTimescale: 600)).image
        let onRing = try sample(ringFrame, at: CGPoint(x: clickPoint.x + strokeOffset, y: clickPoint.y), canvasSize: canvasSize)
        let mirrored = try sample(
            ringFrame,
            at: CGPoint(x: clickPoint.x + strokeOffset, y: canvasSize.height - clickPoint.y),
            canvasSize: canvasSize
        )
        precondition(
            onRing.red > mirrored.red + 15,
            "the click ring must land at its own y, not mirrored: on-ring \(onRing) vs mirrored \(mirrored)"
        )

        let afterRing = try await generator.image(at: CMTime(seconds: clickTime + ClickHighlight.duration + 0.2, preferredTimescale: 600)).image
        let faded = try sample(afterRing, at: CGPoint(x: clickPoint.x + strokeOffset, y: clickPoint.y), canvasSize: canvasSize)
        let fadedControl = try sample(afterRing, at: CGPoint(x: clickPoint.x + strokeOffset, y: canvasSize.height - clickPoint.y), canvasSize: canvasSize)
        precondition(
            abs(faded.red - fadedControl.red) < 12,
            "the ring must be gone once its window closes: \(faded) vs \(fadedControl)"
        )

        print("VideoFrameExportCheck: exported \(Int(size.width))x\(Int(size.height)) \(String(format: "%.1f", exportedDuration))s with audio (\(bytes / 1024) KB)")
    }

    static func sample(_ image: CGImage, at point: CGPoint, canvasSize: CGSize) throws -> (red: Int, green: Int, blue: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let scaleX = CGFloat(image.width) / canvasSize.width
        let scaleY = CGFloat(image.height) / canvasSize.height
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { preconditionFailure("no sampling context") }
        context.translateBy(x: -point.x * scaleX, y: -point.y * scaleY)
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    static func main() async throws {
        let watchdog = Thread {
            Thread.sleep(forTimeInterval: 120)
            FileHandle.standardError.write(Data("VideoFrameExportCheck: TIMED OUT after 120s (reader/writer stall)\n".utf8))
            exit(1)
        }
        watchdog.start()
        try await run()
    }
}
