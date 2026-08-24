import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

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
        let videoTracks = composition.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw VideoExportError.noVideoTrack }

        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = configuration.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        let audioTracks = composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
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
        )

        let frameCount = max(1, Int((composition.duration.seconds * 30).rounded()))

        do {
            try await pump(
                videoOutput: videoOutput,
                videoInput: videoInput,
                adaptor: adaptor,
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
                        compositor.render(videoFrame: sourceBuffer, into: destinationBuffer)
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
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

    init(canvasSize: CGSize, cardRect: CGRect, cornerRadius: CGFloat, backgroundStyle: BackgroundStyle, shadowStrength: CGFloat) {
        self.canvasSize = canvasSize
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        if let backdropImage = Self.renderBackdrop(canvasSize: canvasSize, cardRect: cardRect, cornerRadius: cornerRadius, backgroundStyle: backgroundStyle, shadowStrength: shadowStrength) {
            backdrop = CIImage(cgImage: backdropImage)
        } else {
            backdrop = CIImage(color: .black).cropped(to: canvasRect)
        }
        if let maskImage = Self.renderCardMask(canvasSize: canvasSize, cardRect: cardRect, cornerRadius: cornerRadius) {
            cardMask = CIImage(cgImage: maskImage)
        } else {
            cardMask = CIImage(color: .white).cropped(to: canvasRect)
        }
    }

    func render(videoFrame: CVPixelBuffer, into destination: CVPixelBuffer) {
        let videoImage = CIImage(cvPixelBuffer: videoFrame)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = videoImage
        filter.backgroundImage = backdrop
        filter.maskImage = cardMask
        let output = (filter.outputImage ?? backdrop).cropped(to: CGRect(origin: .zero, size: canvasSize))
        ciContext.render(output, to: destination, bounds: CGRect(origin: .zero, size: canvasSize), colorSpace: colorSpace)
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
        shadowStrength: CGFloat
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
            let path = radius > 0.5
                ? CGPath(roundedRect: flippedCard, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: flippedCard, transform: nil)

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
