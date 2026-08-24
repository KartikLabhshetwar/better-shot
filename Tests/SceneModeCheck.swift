import AVFoundation
import AppKit
import CoreVideo

@main
enum SceneModeCheck {
    static let fps: Int32 = 30
    static let seconds = 4
    static let width = 160
    static let height = 120

    static func makeVideo(at url: URL, red: UInt8, green: UInt8, blue: UInt8) throws {
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
        for frame in 0..<(Int(fps) * seconds) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { preconditionFailure("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for row in 0..<CVPixelBufferGetHeight(buffer) {
                    for column in 0..<CVPixelBufferGetWidth(buffer) {
                        let pixel = base + row * stride + column * 4
                        pixel[0] = blue
                        pixel[1] = green
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

    static func sample(_ url: URL, at seconds: TimeInterval, unit: CGPoint) async throws -> (red: Int, green: Int, blue: Int) {
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
        context.draw(image, in: CGRect(
            x: -unit.x * CGFloat(image.width),
            y: -(1 - unit.y) * CGFloat(image.height),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))
        return (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
    }

    static func checkLayout() {
        let card = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bubble = CGRect(x: 10, y: 60, width: 30, height: 30)

        precondition(SceneMode.screenOnly.layout(card: card, bubble: bubble).camera == nil, "screen-only draws no camera")
        precondition(SceneMode.cameraOnly.layout(card: card, bubble: bubble).screen == nil, "camera-only draws no screen")
        precondition(SceneMode.screenAndCamera.layout(card: card, bubble: bubble).camera == bubble, "the bubble keeps whatever the editor set")
        precondition(SceneMode.screenAndCamera.layout(card: card, bubble: bubble).cameraIsCircle, "the floating face cam is a circle")

        let wide = SceneMode.splitScreen.layout(card: card, bubble: bubble)
        precondition(wide.screen!.minX == card.minX && wide.camera!.maxX == card.maxX, "a wide card splits left and right, got \(wide)")
        precondition(wide.screen!.maxX < wide.camera!.minX, "the split panes must not touch")
        precondition(!wide.cameraIsCircle, "a split pane is a rounded card, not a bubble")

        let tall = CGRect(x: 0, y: 0, width: 100, height: 200)
        let down = SceneMode.splitScreen.layout(card: tall, bubble: bubble)
        let up = SceneMode.splitScreen.layout(card: tall, bubble: bubble, flipped: true)
        precondition(down.screen!.minY == tall.minY, "with y pointing down the screen takes the top pane")
        precondition(up.screen!.maxY == tall.maxY, "with y pointing up the screen still takes the top pane")

        let windows = [
            SceneWindow(start: 0, end: 2, mode: .screenOnly),
            SceneWindow(start: 2, end: 4, mode: .splitScreen)
        ]
        precondition(SceneWindow.mode(of: windows, at: 1) == .screenOnly, "the first window owns its range")
        precondition(SceneWindow.mode(of: windows, at: 3) == .splitScreen, "the second window owns its range")
        precondition(SceneWindow.mode(of: [], at: 1) == .screenAndCamera, "with no windows the default scene holds")
    }

    static func export(
        screen: AVAssetTrack,
        camera: CameraSource,
        clips: [Clip],
        to url: URL
    ) async throws {
        let built = try ClipCompositionBuilder.makeComposition(
            videoTrack: screen,
            audioTracks: [],
            camera: camera,
            clips: clips
        )
        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let card = CGRect(origin: .zero, size: canvas)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: built.composition.duration)
        let lane = built.composition.tracks(withMediaType: .video).first { $0.trackID == built.videoTrackIDs[0] }!
        instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: lane)]
        videoComposition.instructions = [instruction]

        let starts = ClipTimeline(clips: clips).outputStarts
        try await VideoFrameExporter().export(
            VideoFrameExporter.Configuration(
                composition: built.composition,
                videoComposition: videoComposition,
                canvasSize: canvas,
                cardRect: card,
                cornerRadius: 0,
                backgroundStyle: .none,
                shadowStrength: 0,
                outputURL: url,
                camera: built.cameraTrackID.map {
                    VideoFrameExporter.Configuration.Camera(trackID: $0, rect: CGRect(x: 8, y: 8, width: 40, height: 40))
                },
                scenes: clips.indices.map {
                    SceneWindow(start: starts[$0], end: starts[$0] + clips[$0].editorDuration, mode: clips[$0].scene)
                }
            ),
            progress: { _ in }
        )
    }

    static func run() async throws {
        checkLayout()

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-scene-check-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let screenURL = dir.appendingPathComponent("screen.mp4")
        let cameraURL = dir.appendingPathComponent("camera.mp4")
        let outputURL = dir.appendingPathComponent("out.mp4")
        try makeVideo(at: screenURL, red: 255, green: 0, blue: 0)
        try makeVideo(at: cameraURL, red: 0, green: 0, blue: 255)

        let screenAsset = AVURLAsset(url: screenURL)
        let cameraAsset = AVURLAsset(url: cameraURL)
        let screenTrack = try await screenAsset.loadTracks(withMediaType: .video)[0]
        let cameraTrack = try await cameraAsset.loadTracks(withMediaType: .video)[0]
        let camera = CameraSource(track: cameraTrack, duration: try await cameraAsset.load(.duration))

        let clips = [
            Clip(sourceStart: 0, sourceEnd: 1, scene: .screenOnly),
            Clip(sourceStart: 1, sourceEnd: 2, scene: .cameraOnly),
            Clip(sourceStart: 2, sourceEnd: 4, scene: .splitScreen)
        ]
        try await export(screen: screenTrack, camera: camera, clips: clips, to: outputURL)

        let center = CGPoint(x: 0.5, y: 0.5)
        let screenOnly = try await sample(outputURL, at: 0.5, unit: center)
        precondition(screenOnly.red > 150 && screenOnly.blue < 80, "screen-only should show the red screen, got \(screenOnly)")

        let cameraOnly = try await sample(outputURL, at: 1.5, unit: center)
        precondition(cameraOnly.blue > 150 && cameraOnly.red < 80, "camera-only should fill with the blue face cam, got \(cameraOnly)")

        let left = try await sample(outputURL, at: 3, unit: CGPoint(x: 0.2, y: 0.5))
        let right = try await sample(outputURL, at: 3, unit: CGPoint(x: 0.8, y: 0.5))
        precondition(left.red > 150 && left.blue < 80, "the split's left pane is the screen, got \(left)")
        precondition(right.blue > 150 && right.red < 80, "the split's right pane is the face cam, got \(right)")

        print("scene modes: screen-only red, camera-only blue, split red|blue, layouts and windows hold")
    }

    static func main() async throws {
        try await run()
    }
}
