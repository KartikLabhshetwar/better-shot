import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A fade-through-black handover dips the whole canvas, so the compositor darkens every layer at once instead of the screen track alone.
nonisolated struct TransitionDim: Equatable, Sendable {
    let start: TimeInterval
    let duration: TimeInterval

    func brightness(at time: TimeInterval) -> CGFloat {
        guard duration > 0, time >= start, time < start + duration else { return 1 }
        return abs((time - start) / duration * 2 - 1)
    }

    static func brightness(of windows: [TransitionDim], at time: TimeInterval) -> CGFloat {
        windows.reduce(1) { min($0, $1.brightness(at: time)) }
    }
}

/// The stretch of output time over which one scene mode holds, so a cut can swap layouts mid-export.
nonisolated struct SceneWindow: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let mode: SceneMode

    static func mode(of windows: [SceneWindow], at time: TimeInterval) -> SceneMode {
        windows.last { time >= $0.start && time < $0.end }?.mode ?? .screenAndCamera
    }
}

nonisolated final class VideoFrameExporter: @unchecked Sendable {
    struct Configuration: @unchecked Sendable {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let canvasSize: CGSize
        let cardRect: CGRect
        let cornerRadius: CGFloat
        let backgroundStyle: BackgroundStyle
        let shadowStrength: CGFloat
        let outputURL: URL
        var camera: Camera?
        var clicks: [ClickHighlight] = []
        var clickRadius: CGFloat = 0
        var audioMix: AVAudioMix?
        var screenGrade = ColorGrade.neutral
        var cameraGrade = ColorGrade.neutral
        var dimWindows: [TransitionDim] = []
        var scenes: [SceneWindow] = []
        var pose: Camera3D = .neutral
        var resolveMasks: (@Sendable (TimeInterval) -> [ResolvedMask])?
        var resolveTexts: (@Sendable (TimeInterval) -> [ResolvedText])?
        var cursorSprite: CursorSprite?
        var resolveCursor: (@Sendable (TimeInterval) -> ResolvedCursor?)?

        /// The face cam rides in the same composition as a second video track, so the compositor can draw it as a circle wherever the editor put it.
        struct Camera: Sendable {
            let trackID: CMPersistentTrackID
            /// Canvas coordinates with y pointing up, matching the CoreGraphics and CoreImage passes.
            let rect: CGRect
        }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flagged = false

        func cancel() { lock.withLock { flagged = true } }
        var isCancelled: Bool { lock.withLock { flagged } }
    }

    func export(
        _ configuration: Configuration,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let cancelFlag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await run(configuration, cancelFlag: cancelFlag, progress: progress)
        } onCancel: {
            cancelFlag.cancel()
        }
    }

    private func run(
        _ configuration: Configuration,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let composition = configuration.composition
        let cameraTrack = configuration.camera.flatMap { camera in
            composition.tracks(withMediaType: .video).first { $0.trackID == camera.trackID }
        }
        let videoTracks = composition.tracks(withMediaType: .video).filter { $0.trackID != cameraTrack?.trackID }
        guard !videoTracks.isEmpty else { throw VideoExportError.noVideoTrack }

        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = configuration.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        var cameraOutput: AVAssetReaderTrackOutput?
        if let cameraTrack {
            let output = AVAssetReaderTrackOutput(
                track: cameraTrack,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            reader.add(output)
            cameraOutput = output
        }

        var audioOutput: AVAssetReaderAudioMixOutput?
        let audioTracks = composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            output.audioMix = configuration.audioMix
            output.audioTimePitchAlgorithm = .spectral
            output.alwaysCopiesSampleData = false
            reader.add(output)
            audioOutput = output
        }

        let canvasWidth = max(2, Int(configuration.canvasSize.width.rounded()))
        let canvasHeight = max(2, Int(configuration.canvasSize.height.rounded()))

        try? FileManager.default.removeItem(at: configuration.outputURL)
        let writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: canvasWidth,
            AVVideoHeightKey: canvasHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.averageBitRate(width: canvasWidth, height: canvasHeight),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ] as [String: Any]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: canvasWidth,
                kCVPixelBufferHeightKey as String: canvasHeight
            ]
        )

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard reader.startReading() else {
            throw VideoExportError.exportFailed(reader.error)
        }
        guard writer.startWriting() else {
            throw VideoExportError.exportFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let compositor = FrameCompositor(
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
            cardRect: configuration.cardRect,
            cornerRadius: configuration.cornerRadius,
            backgroundStyle: configuration.backgroundStyle,
            shadowStrength: configuration.shadowStrength,
            cameraRect: configuration.camera?.rect,
            clicks: configuration.clicks,
            clickRadius: configuration.clickRadius,
            screenGrade: configuration.screenGrade,
            cameraGrade: configuration.cameraGrade,
            dimWindows: configuration.dimWindows,
            scenes: configuration.scenes,
            pose: configuration.pose,
            resolveMasks: configuration.resolveMasks,
            resolveTexts: configuration.resolveTexts,
            cursorSprite: configuration.cursorSprite,
            resolveCursor: configuration.resolveCursor
        )

        let frameCount = max(1, Int((composition.duration.seconds * 30).rounded()))

        do {
            try await pump(
                videoOutput: videoOutput,
                videoInput: videoInput,
                adaptor: adaptor,
                cameraOutput: cameraOutput,
                audioOutput: audioOutput,
                audioInput: audioInput,
                compositor: compositor,
                frameCount: frameCount,
                cancelFlag: cancelFlag,
                progress: progress
            )
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: configuration.outputURL)
            throw error
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: configuration.outputURL)
            throw VideoExportError.exportFailed(writer.error)
        }
        progress(1)
        return configuration.outputURL
    }

    private func pump(
        videoOutput: AVAssetReaderVideoCompositionOutput,
        videoInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        cameraOutput: AVAssetReaderTrackOutput?,
        audioOutput: AVAssetReaderAudioMixOutput?,
        audioInput: AVAssetWriterInput?,
        compositor: FrameCompositor,
        frameCount: Int,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var videoDone = false
        var audioDone = audioOutput == nil || audioInput == nil
        var frameIndex = 0
        var cameraExhausted = cameraOutput == nil
        var cameraLookahead: (buffer: CVPixelBuffer, time: CMTime)?
        var cameraFrame: CVPixelBuffer?

        while !videoDone || !audioDone {
            if cancelFlag.isCancelled { throw VideoExportError.exportCancelled }
            var madeProgress = false

            if !videoDone, videoInput.isReadyForMoreMediaData {
                if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    madeProgress = true
                    if let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        guard let pool = adaptor.pixelBufferPool else {
                            throw VideoExportError.exportFailed(nil)
                        }
                        var destinationBuffer: CVPixelBuffer?
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinationBuffer)
                        guard let destinationBuffer else {
                            throw VideoExportError.exportFailed(nil)
                        }
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        // The face cam decodes at its own rate, so hold the newest frame that is not ahead of the screen frame being written.
                        while !cameraExhausted {
                            if let ahead = cameraLookahead {
                                guard ahead.time <= presentationTime else { break }
                                cameraFrame = ahead.buffer
                                cameraLookahead = nil
                            }
                            guard let cameraSample = cameraOutput?.copyNextSampleBuffer() else {
                                cameraExhausted = true
                                break
                            }
                            guard let buffer = CMSampleBufferGetImageBuffer(cameraSample) else { continue }
                            cameraLookahead = (buffer, CMSampleBufferGetPresentationTimeStamp(cameraSample))
                        }
                        compositor.render(
                            videoFrame: sourceBuffer,
                            cameraFrame: cameraFrame,
                            at: presentationTime.seconds,
                            into: destinationBuffer
                        )
                        if !adaptor.append(destinationBuffer, withPresentationTime: presentationTime) {
                            throw VideoExportError.exportFailed(nil)
                        }
                        frameIndex += 1
                        if frameIndex % 10 == 0 {
                            progress(min(0.98, Double(frameIndex) / Double(frameCount)))
                        }
                    }
                } else {
                    videoInput.markAsFinished()
                    videoDone = true
                }
            }

            if !audioDone, let audioOutput, let audioInput, audioInput.isReadyForMoreMediaData {
                if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                    madeProgress = true
                    if !audioInput.append(sampleBuffer) {
                        throw VideoExportError.exportFailed(nil)
                    }
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
            }

            if !madeProgress {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    private static func averageBitRate(width: Int, height: Int) -> Int {
        max(4_000_000, Int(Double(width * height) * 6))
    }
}

private final class FrameCompositor: @unchecked Sendable {
    private let canvasSize: CGSize
    private let ciContext = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let backdrop: CIImage
    private let cardMask: CIImage
    private let cameraRect: CGRect?
    private let cameraMask: CIImage?
    private let cameraRing: CIImage?
    private let clicks: [ClickHighlight]
    private let clickRing: CIImage?
    private let clickRadius: CGFloat
    private let screenGrade: ColorGrade
    private let cameraGrade: ColorGrade
    private let cardRect: CGRect
    private let dimWindows: [TransitionDim]
    private let scenes: [SceneWindow]
    private let posedCorners: [CGPoint]?
    private let layouts: [SceneMode: SceneLayout]
    private let sceneMasks: [SceneMode: SceneMasks]
    private let resolveMasks: (@Sendable (TimeInterval) -> [ResolvedMask])?
    private let resolveTexts: (@Sendable (TimeInterval) -> [ResolvedText])?
    private let cursorImage: CIImage?
    private let cursorHotspot: CGPoint
    private let resolveCursor: (@Sendable (TimeInterval) -> ResolvedCursor?)?

    private struct SceneMasks {
        var screen: CIImage?
        var camera: CIImage?
    }

    init(
        canvasSize: CGSize,
        cardRect: CGRect,
        cornerRadius: CGFloat,
        backgroundStyle: BackgroundStyle,
        shadowStrength: CGFloat,
        cameraRect: CGRect?,
        clicks: [ClickHighlight] = [],
        clickRadius: CGFloat = 0,
        screenGrade: ColorGrade = .neutral,
        cameraGrade: ColorGrade = .neutral,
        dimWindows: [TransitionDim] = [],
        scenes: [SceneWindow] = [],
        pose: Camera3D = .neutral,
        resolveMasks: (@Sendable (TimeInterval) -> [ResolvedMask])? = nil,
        resolveTexts: (@Sendable (TimeInterval) -> [ResolvedText])? = nil,
        cursorSprite: CursorSprite? = nil,
        resolveCursor: (@Sendable (TimeInterval) -> ResolvedCursor?)? = nil
    ) {
        cursorImage = cursorSprite.map { CIImage(cgImage: $0.image) }
        cursorHotspot = cursorSprite?.hotspot ?? .zero
        self.resolveCursor = resolveCursor
        self.canvasSize = canvasSize
        self.cardRect = cardRect
        self.resolveMasks = resolveMasks
        self.resolveTexts = resolveTexts
        self.screenGrade = screenGrade
        self.cameraGrade = cameraGrade
        self.dimWindows = dimWindows
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        posedCorners = pose.isNeutral ? nil : pose.corners(in: cardRect, flipped: true)
        if let backdropImage = Self.renderBackdrop(canvasSize: canvasSize, cardRect: cardRect, cornerRadius: cornerRadius, backgroundStyle: backgroundStyle, shadowStrength: shadowStrength, posedCorners: posedCorners) {
            backdrop = CIImage(cgImage: backdropImage)
        } else {
            backdrop = CIImage(color: .black).cropped(to: canvasRect)
        }
        if let maskImage = Self.renderCardMask(canvasSize: canvasSize, cardRect: cardRect, cornerRadius: cornerRadius) {
            cardMask = CIImage(cgImage: maskImage)
        } else {
            cardMask = CIImage(color: .white).cropped(to: canvasRect)
        }
        self.cameraRect = cameraRect
        cameraMask = cameraRect
            .flatMap { Self.renderCircleMask(canvasSize: canvasSize, circle: $0) }
            .map { CIImage(cgImage: $0) }
        cameraRing = cameraRect
            .flatMap { Self.renderCircleRing(canvasSize: canvasSize, circle: $0) }
            .map { CIImage(cgImage: $0) }
        self.clicks = clicks
        self.clickRadius = clickRadius
        clickRing = clicks.isEmpty || clickRadius <= 0
            ? nil
            : Self.renderClickRing(radius: clickRadius).map { CIImage(cgImage: $0) }

        self.scenes = scenes
        let bubble = cameraRect ?? .zero
        let modes = Set(scenes.map(\.mode)).union([.screenAndCamera])
        var layouts: [SceneMode: SceneLayout] = [:]
        var masks: [SceneMode: SceneMasks] = [:]
        for mode in modes {
            let layout = mode.layout(card: cardRect, bubble: bubble, flipped: true)
            layouts[mode] = layout
            masks[mode] = SceneMasks(
                screen: Self.paneMask(layout.screen, isCircle: false, canvasSize: canvasSize, cardRect: cardRect, cardMask: cardMask, circleMask: cameraMask, cornerRadius: cornerRadius),
                camera: Self.paneMask(layout.camera, isCircle: layout.cameraIsCircle, canvasSize: canvasSize, cardRect: cardRect, cardMask: cardMask, circleMask: cameraMask, cornerRadius: cornerRadius)
            )
        }
        self.layouts = layouts
        sceneMasks = masks
    }

    func render(videoFrame: CVPixelBuffer, cameraFrame: CVPixelBuffer?, at frameTime: TimeInterval, into destination: CVPixelBuffer) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let mode = SceneWindow.mode(of: scenes, at: frameTime)
        let layout = layouts[mode] ?? SceneLayout(screen: cardRect, camera: cameraRect, cameraIsCircle: true)
        let masks = sceneMasks[mode] ?? SceneMasks(screen: cardMask, camera: cameraMask)
        var content = CIImage.clear.cropped(to: canvasRect)

        if let screenRect = layout.screen, let screenMask = masks.screen {
            let source = CIImage(cvPixelBuffer: videoFrame)
            let fit = Self.aspectFillTransform(from: cardRect, into: screenRect)
            let placed = screenRect == cardRect ? source : source.cropped(to: cardRect).transformed(by: fit)
            let graded = screenGrade.applied(to: placed, extent: screenRect, frameTime: frameTime)
            let filter = CIFilter.blendWithMask()
            filter.inputImage = ResolvedMask.applied(resolveMasks?(frameTime) ?? [], to: graded, extent: screenRect)
            filter.backgroundImage = content
            filter.maskImage = screenMask
            content = (filter.outputImage ?? content).cropped(to: canvasRect)

            if let clickRing {
                for (highlight, phase) in ClickHighlight.active(in: clicks, at: frameTime) {
                    let scaled = clickRing.transformed(by: CGAffineTransform(scaleX: phase.scale * fit.a, y: phase.scale * fit.d))
                    let center = highlight.point.applying(fit)
                    let placedRing = scaled.transformed(by: CGAffineTransform(
                        translationX: center.x - scaled.extent.midX,
                        y: center.y - scaled.extent.midY
                    ))
                    let fade = CIFilter.colorMatrix()
                    fade.inputImage = placedRing
                    fade.aVector = CIVector(x: 0, y: 0, z: 0, w: phase.opacity)
                    guard let faded = fade.outputImage else { continue }
                    content = faded.composited(over: content).cropped(to: canvasRect)
                }
            }

            if let cursorImage, let cursor = resolveCursor?(frameTime), cursor.scale > 0 {
                let scale = cursor.scale * fit.a
                let sprite = cursorImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let tip = cursor.point.applying(fit)
                let placed = sprite.transformed(by: CGAffineTransform(
                    translationX: tip.x - cursorHotspot.x * sprite.extent.width - sprite.extent.minX,
                    y: tip.y + cursorHotspot.y * sprite.extent.height - sprite.extent.height - sprite.extent.minY
                ))
                content = placed.composited(over: content).cropped(to: canvasRect)
            }
        }

        if let cameraFrame, let rect = layout.camera, let cameraMask = masks.camera {
            let bubble = CIFilter.blendWithMask()
            bubble.inputImage = cameraGrade.applied(
                to: Self.aspectFilled(CIImage(cvPixelBuffer: cameraFrame), into: rect),
                extent: rect,
                frameTime: frameTime
            )
            bubble.backgroundImage = content
            bubble.maskImage = cameraMask
            content = (bubble.outputImage ?? content).cropped(to: canvasRect)
            if layout.cameraIsCircle, let cameraRing {
                content = cameraRing.composited(over: content).cropped(to: canvasRect)
            }
        }

        var output = posed(content).composited(over: backdrop).cropped(to: canvasRect)

        if let resolveTexts {
            output = ResolvedText.composited(resolveTexts(frameTime), over: output, canvasSize: canvasSize)
        }

        let brightness = TransitionDim.brightness(of: dimWindows, at: frameTime)
        if brightness < 1 {
            let dim = CIFilter.colorMatrix()
            dim.inputImage = output
            dim.rVector = CIVector(x: brightness, y: 0, z: 0, w: 0)
            dim.gVector = CIVector(x: 0, y: brightness, z: 0, w: 0)
            dim.bVector = CIVector(x: 0, y: 0, z: brightness, w: 0)
            output = (dim.outputImage ?? output).cropped(to: canvasRect)
        }

        ciContext.render(output, to: destination, bounds: canvasRect, colorSpace: colorSpace)
    }

    private func posed(_ content: CIImage) -> CIImage {
        guard let posedCorners else { return content }
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = content.cropped(to: cardRect)
        filter.bottomLeft = posedCorners[0]
        filter.bottomRight = posedCorners[1]
        filter.topRight = posedCorners[2]
        filter.topLeft = posedCorners[3]
        return filter.outputImage ?? content
    }

    private static func paneMask(
        _ rect: CGRect?,
        isCircle: Bool,
        canvasSize: CGSize,
        cardRect: CGRect,
        cardMask: CIImage,
        circleMask: CIImage?,
        cornerRadius: CGFloat
    ) -> CIImage? {
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        if isCircle { return circleMask }
        if rect == cardRect { return cardMask }
        return renderCardMask(canvasSize: canvasSize, cardRect: rect, cornerRadius: cornerRadius)
            .map { CIImage(cgImage: $0) }
    }

    private static func aspectFillTransform(from extent: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard extent.width > 0, extent.height > 0 else { return .identity }
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -extent.midX, y: -extent.midY)
    }

    private static func aspectFilled(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY
        ))
    }

    private static func renderClickRing(radius: CGFloat) -> CGImage? {
        let side = Int((radius * 2).rounded(.up)) + 4
        guard side > 4, let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let center = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let lineWidth = max(2, radius * 0.16)
        let circle = CGRect(
            x: center.x - radius + lineWidth / 2,
            y: center.y - radius + lineWidth / 2,
            width: (radius - lineWidth / 2) * 2,
            height: (radius - lineWidth / 2) * 2
        )
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: circle)
        return context.makeImage()
    }

    private static func renderCircleMask(canvasSize: CGSize, circle: CGRect) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvasSize))
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: circle)
        return context.makeImage()
    }

    private static func renderCircleRing(canvasSize: CGSize, circle: CGRect) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(max(2, min(circle.width, circle.height) * 0.022))
        context.strokeEllipse(in: circle)
        return context.makeImage()
    }

    private static func quadPath(_ corners: [CGPoint], canvasHeight: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let flipped = corners.map { CGPoint(x: $0.x, y: canvasHeight - $0.y) }
        path.addLines(between: flipped)
        path.closeSubpath()
        return path
    }

    private static func flipped(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let fillSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let fillRect = CGRect(
            x: rect.minX + (rect.width - fillSize.width) / 2,
            y: rect.minY + (rect.height - fillSize.height) / 2,
            width: fillSize.width,
            height: fillSize.height
        )
        context.draw(image, in: fillRect)
    }

    private static func renderBackdrop(
        canvasSize: CGSize,
        cardRect: CGRect,
        cornerRadius: CGFloat,
        backgroundStyle: BackgroundStyle,
        shadowStrength: CGFloat,
        posedCorners: [CGPoint]?
    ) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        switch backgroundStyle {
        case .none:
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(canvasRect)
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(canvasRect)
        case .gradient(let preset):
            if let gradient = preset.cgGradient(in: colorSpace) {
                let start = CGPoint(x: preset.startPoint.x * canvasSize.width, y: canvasSize.height - preset.startPoint.y * canvasSize.height)
                let end = CGPoint(x: preset.endPoint.x * canvasSize.width, y: canvasSize.height - preset.endPoint.y * canvasSize.height)
                context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case .wallpaper(let source):
            if let image = NSImage(contentsOfFile: source.path),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                drawAspectFill(cgImage, in: canvasRect, context: context)
            }
        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image,
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                drawAspectFill(cgImage, in: canvasRect, context: context)
            }
        }

        if shadowStrength > 0.01, backgroundStyle != .none {
            let minDimension = min(canvasSize.width, canvasSize.height)
            let blur = minDimension * 0.045 * shadowStrength
            let flippedCard = flipped(cardRect, canvasHeight: canvasSize.height)
            let radius = min(cornerRadius, min(flippedCard.width, flippedCard.height) / 2)
            let path = posedCorners.map { quadPath($0, canvasHeight: canvasSize.height) }
                ?? (radius > 0.5
                    ? CGPath(roundedRect: flippedCard, cornerWidth: radius, cornerHeight: radius, transform: nil)
                    : CGPath(rect: flippedCard, transform: nil))

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -blur * 0.35),
                blur: blur,
                color: CGColor(gray: 0, alpha: 0.55 * shadowStrength)
            )
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }

        return context.makeImage()
    }

    private static func renderCardMask(canvasSize: CGSize, cardRect: CGRect, cornerRadius: CGFloat) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvasSize))

        let flippedCard = flipped(cardRect, canvasHeight: canvasSize.height)
        let radius = min(cornerRadius, min(flippedCard.width, flippedCard.height) / 2)
        let path = radius > 0.5
            ? CGPath(roundedRect: flippedCard, cornerWidth: radius, cornerHeight: radius, transform: nil)
            : CGPath(rect: flippedCard, transform: nil)

        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path)
        context.fillPath()

        return context.makeImage()
    }
}
