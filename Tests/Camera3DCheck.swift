import AVFoundation
import AppKit
import CoreVideo

@main
enum Camera3DCheck {
    static let fps: Int32 = 30
    static let seconds = 2
    static let width = 200
    static let height = 160
    static let card = CGRect(x: 20, y: 20, width: 160, height: 120)

    static func makeVideo(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(card.width),
            AVVideoHeightKey: Int(card.height)
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(card.width),
                kCVPixelBufferHeightKey as String: Int(card.height)
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
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 255, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
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

    static func sample(_ url: URL, unit: CGPoint) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
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
        return Int(pixels[0])
    }

    static func checkProjection() {
        let rect = CGRect(x: 20, y: 20, width: 160, height: 120)
        let level = Camera3D.neutral.corners(in: rect)
        precondition(Camera3D.neutral.isNeutral, "a fresh pose is level")
        precondition(
            abs(level[0].x - rect.minX) < 0.001 && abs(level[2].y - rect.maxY) < 0.001,
            "a level pose leaves the card where it was, got \(level)"
        )

        let turned = Camera3D(tiltY: 40, perspective: 1).corners(in: rect)
        precondition(turned[1].x < rect.maxX, "turning right pushes the far edge away, got \(turned[1])")
        precondition(turned[0].x < rect.minX, "turning right swings the near edge wider, got \(turned[0])")
        let far = abs(turned[2].y - turned[1].y)
        let near = abs(turned[3].y - turned[0].y)
        precondition(far < near, "the far edge must be shorter than the near one, got \(far) against \(near)")

        let down = Camera3D(tiltX: 30, perspective: 1).corners(in: rect)
        let up = Camera3D(tiltX: 30, perspective: 1).corners(in: rect, flipped: true)
        precondition(
            abs(down[0].y + up[3].y - 2 * rect.midY) < 0.001,
            "flipping the axis mirrors the tilt, got \(down[0]) and \(up[3])"
        )
        precondition(abs(down[0].x - up[3].x) < 0.001, "flipping the axis leaves the horizontal alone")

        let rolled = Camera3D(roll: 90, perspective: 0).corners(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        precondition(
            abs(rolled[0].x - 100) < 0.5 && abs(rolled[0].y) < 0.5,
            "a quarter roll sends the bottom-left corner to the bottom-right, got \(rolled[0])"
        )
    }

    static func export(track: AVAssetTrack, pose: Camera3D, to url: URL) async throws {
        let composition = AVMutableComposition()
        let lane = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try lane.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: Double(seconds), preferredTimescale: 600)),
            of: track,
            at: .zero
        )
        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: lane)
        layer.setTransform(CGAffineTransform(translationX: card.minX, y: card.minY), at: .zero)
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        try await VideoFrameExporter().export(
            VideoFrameExporter.Configuration(
                composition: composition,
                videoComposition: videoComposition,
                canvasSize: canvas,
                cardRect: card,
                cornerRadius: 0,
                backgroundStyle: .none,
                shadowStrength: 0,
                outputURL: url,
                pose: pose
            ),
            progress: { _ in }
        )
    }

    static func run() async throws {
        checkProjection()

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-camera3d-check-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.mp4")
        let levelURL = dir.appendingPathComponent("level.mp4")
        let turnedURL = dir.appendingPathComponent("turned.mp4")
        try makeVideo(at: sourceURL)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let track = try await sourceAsset.loadTracks(withMediaType: .video)[0]

        try await export(track: track, pose: .neutral, to: levelURL)
        try await export(track: track, pose: Camera3D(tiltY: 40, perspective: 1), to: turnedURL)

        let middle = CGPoint(x: 0.5, y: 0.5)
        let insideRight = CGPoint(x: 0.88, y: 0.5)
        let outsideLeft = CGPoint(x: 0.05, y: 0.5)

        let levelMiddle = try await sample(levelURL, unit: middle)
        let levelRight = try await sample(levelURL, unit: insideRight)
        let levelLeft = try await sample(levelURL, unit: outsideLeft)
        precondition(levelMiddle > 200, "a level card fills the middle, got \(levelMiddle)")
        precondition(levelRight > 200, "a level card reaches its own right edge, got \(levelRight)")
        precondition(levelLeft < 80, "the backdrop shows outside a level card, got \(levelLeft)")

        let turnedMiddle = try await sample(turnedURL, unit: middle)
        let turnedRight = try await sample(turnedURL, unit: insideRight)
        let turnedLeft = try await sample(turnedURL, unit: outsideLeft)
        precondition(turnedMiddle > 200, "the turned card still holds the middle, got \(turnedMiddle)")
        precondition(turnedRight < 80, "the far edge pulled in past \(insideRight.x), got \(turnedRight)")
        precondition(turnedLeft > 200, "the near edge swung out past \(outsideLeft.x), got \(turnedLeft)")

        print("3D camera: level card square, 40° turn pulls the far edge in and throws the near edge wide")
    }

    static func main() async throws {
        try await run()
    }
}
