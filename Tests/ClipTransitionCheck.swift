import AVFoundation
import AppKit
import CoreVideo

@main
enum ClipTransitionCheck {
    static let fps: Int32 = 30
    static let seconds = 6
    static let width = 160
    static let height = 120
    static let handover: TimeInterval = 1

    static func makeVideo(at url: URL) throws {
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
        precondition(writer.startWriting(), "video writer failed to start")
        writer.startSession(atSourceTime: .zero)
        let half = Int(fps) * seconds / 2
        for frame in 0..<(Int(fps) * seconds) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { preconditionFailure("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                let blue: UInt8 = frame < half ? 0 : 255
                let red: UInt8 = frame < half ? 255 : 0
                for row in 0..<CVPixelBufferGetHeight(buffer) {
                    for column in 0..<CVPixelBufferGetWidth(buffer) {
                        let pixel = base + row * stride + column * 4
                        pixel[0] = blue
                        pixel[1] = 0
                        pixel[2] = red
                        pixel[3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)), "video append failed")
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        precondition(writer.status == .completed, "video writer failed: \(String(describing: writer.error))")
    }

    static func centerPixel(of url: URL, at seconds: TimeInterval) async throws -> (red: Int, blue: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var pixels = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixels,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixels[0]), Int(pixels[2]))
    }

    static func checkTimelineMath() {
        let clips = [
            Clip(sourceStart: 0, sourceEnd: 3),
            Clip(sourceStart: 3, sourceEnd: 6, transitionIn: ClipTransition(kind: .crossFade, duration: handover))
        ]
        let timeline = ClipTimeline(clips: clips)
        precondition(abs(timeline.duration - 5) < 0.001, "a 1s handover should shorten 6s to 5s, got \(timeline.duration)")
        precondition(timeline.outputStarts.map { ($0 * 100).rounded() / 100 } == [0, 2], "second clip should start at 2s, got \(timeline.outputStarts)")
        precondition(abs(timeline.sourceTime(at: 2.5) - 3.5) < 0.001, "the incoming clip owns the overlap, got \(timeline.sourceTime(at: 2.5))")
        precondition(abs(timeline.sourceTime(at: 1.5) - 1.5) < 0.001, "before the overlap the outgoing clip still owns the axis")

        var greedy = clips
        greedy[1].transitionIn = ClipTransition(kind: .crossFade, duration: 5)
        let clamped = ClipTimeline(clips: greedy).effectiveTransition(at: 1)
        precondition(abs((clamped?.duration ?? 0) - 1.5) < 0.001, "a handover cannot exceed half the shorter clip, got \(String(describing: clamped?.duration))")

        var tiny = clips
        tiny[0] = Clip(sourceStart: 0, sourceEnd: 0.05)
        precondition(ClipTimeline(clips: tiny).effectiveTransition(at: 1) == nil, "a clip too short to overlap gets no handover")
        precondition(ClipTimeline(clips: clips).effectiveTransition(at: 0) == nil, "the first clip has nothing to blend into")

        let dim = TransitionDim(start: 2, duration: 1)
        precondition(dim.brightness(at: 2.5) < 0.001, "the black dip must bottom out at the midpoint, got \(dim.brightness(at: 2.5))")
        precondition(abs(dim.brightness(at: 2.25) - 0.5) < 0.001, "the dip should be linear, got \(dim.brightness(at: 2.25))")
        precondition(dim.brightness(at: 1.9) == 1, "outside the window the canvas stays lit")
        precondition(dim.brightness(at: 3.1) == 1, "outside the window the canvas stays lit")
    }

    static func run() async throws {
        checkTimelineMath()

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-transition-check-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.mp4")
        let outputURL = dir.appendingPathComponent("out.mp4")
        try makeVideo(at: sourceURL)

        let asset = AVURLAsset(url: sourceURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video)[0]
        let clips = [
            Clip(sourceStart: 0, sourceEnd: 3),
            Clip(sourceStart: 3, sourceEnd: 6, transitionIn: ClipTransition(kind: .crossFade, duration: handover))
        ]
        let built = try ClipCompositionBuilder.makeComposition(
            videoTrack: videoTrack,
            audioTracks: [],
            camera: nil,
            clips: clips
        )
        precondition(built.videoTrackIDs.count == 2, "a transition needs two lanes to blend across, got \(built.videoTrackIDs.count)")

        let lanes = built.videoTrackIDs.compactMap { id in
            built.composition.tracks(withMediaType: .video).first { $0.trackID == id }
        }
        precondition(lanes.count == 2, "the lane track IDs must resolve back to real tracks")

        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)

        func span(_ start: TimeInterval, _ end: TimeInterval) -> CMTimeRange {
            CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }

        func instruction(_ range: CMTimeRange, _ layers: [AVMutableVideoCompositionLayerInstruction]) -> AVMutableVideoCompositionInstruction {
            let step = AVMutableVideoCompositionInstruction()
            step.timeRange = range
            step.backgroundColor = CGColor.clear
            step.layerInstructions = layers
            return step
        }

        let blend = span(2, 3)
        let fadingOut = AVMutableVideoCompositionLayerInstruction(assetTrack: lanes[0])
        fadingOut.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: blend)
        videoComposition.instructions = [
            instruction(span(0, 2), [AVMutableVideoCompositionLayerInstruction(assetTrack: lanes[0])]),
            instruction(blend, [fadingOut, AVMutableVideoCompositionLayerInstruction(assetTrack: lanes[1])]),
            instruction(span(3, 5), [AVMutableVideoCompositionLayerInstruction(assetTrack: lanes[1])])
        ]

        try await VideoFrameExporter().export(
            VideoFrameExporter.Configuration(
                composition: built.composition,
                videoComposition: videoComposition,
                canvasSize: canvas,
                cardRect: CGRect(origin: .zero, size: canvas),
                cornerRadius: 0,
                backgroundStyle: .none,
                shadowStrength: 0,
                outputURL: outputURL
            ),
            progress: { _ in }
        )

        let before = try await centerPixel(of: outputURL, at: 1)
        let middle = try await centerPixel(of: outputURL, at: 2.5)
        let after = try await centerPixel(of: outputURL, at: 4)

        precondition(before.red > 180 && before.blue < 70, "before the handover the canvas should still be red, got \(before)")
        precondition(after.blue > 180 && after.red < 70, "after the handover the canvas should be blue, got \(after)")
        precondition(
            middle.red > 60 && middle.red < 200 && middle.blue > 60 && middle.blue < 200,
            "mid-crossfade both clips should be visible, got \(middle)"
        )

        print("clip transitions: 1s crossfade blends red \(middle.red) with blue \(middle.blue), fade-through-black dips to zero")
    }

    static func main() async throws {
        try await run()
    }
}
