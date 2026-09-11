//
//  RecordingStudioExporter.swift
//  BetterShot
//
//  Offline compositor for studio exports: decodes the screen (and camera)
//  recordings frame by frame, draws each frame through the same
//  RecordingStudioLayout / ViewportTimeline math the live preview
//  uses, and writes a new H.264 or HEVC movie. Audio tracks (system + microphone)
//  are mixed and passed through on the unchanged timeline, unless the
//  project imported a soundtrack to replace them.
//
//  Static backgrounds, clipping masks, and camera decoration are cached.
//  Core Image composites media directly into the encoder buffer; Quartz
//  supplies only cursor and text artwork.
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import SwiftUI
import VideoToolbox

nonisolated final class RecordingStudioExporter: @unchecked Sendable {
    struct Configuration: Sendable {
        let screenURL: URL
        let cameraURL: URL?
        let cameraOffset: TimeInterval
        let style: RecordingStudioStyle
        let viewportTimeline: ViewportTimeline
        /// Non-nil when the capture hid the OS cursor and the export must
        /// draw the synthetic pointer along this smoothed timeline.
        let pointerTimeline: PointerTimeline?
        let showsPressEffects: Bool
        /// Non-nil when recorded keystroke chords should be captioned.
        let keystrokeTimeline: KeystrokeCaptionTimeline?
        let keystrokePlacement: RecordingKeystrokePlacement
        /// Non-nil when transcribed narration should be subtitled.
        let subtitleTimeline: SubtitleTimeline?
        let subtitleStyle: SubtitleBarStyle
        /// Word timings behind the subtitles, for karaoke highlighting.
        let karaokeTimeline: KaraokeTimeline?
        let canvasSize: CGSize
        let clipTimeline: RecordingClipTimeline
        let exportSettings: VideoCompressionSettings
        /// Non-nil when an imported soundtrack stands in for the recorded
        /// audio. It is already the finished cut's audio, so it plays flat
        /// from zero instead of being re-cut through the clip timeline.
        let audioReplacementURL: URL?
        /// Non-nil when exporting into a different aspect ratio; drives the
        /// crop-and-follow virtual camera in place of the zoom viewport.
        let reframe: ReframeTrack?
        /// Non-nil when exporting into a different aspect ratio in Fit
        /// mode: the whole recording shows in a content-aspect card and
        /// the background fills the rest. Mutually exclusive with
        /// `reframe`.
        let fitContentAspect: CGFloat?
        let crop: CGRect
        let masks: [RecordingMaskSegment]

        init(
            screenURL: URL,
            cameraURL: URL?,
            cameraOffset: TimeInterval,
            style: RecordingStudioStyle,
            viewportTimeline: ViewportTimeline,
            pointerTimeline: PointerTimeline?,
            showsPressEffects: Bool,
            keystrokeTimeline: KeystrokeCaptionTimeline?,
            keystrokePlacement: RecordingKeystrokePlacement,
            subtitleTimeline: SubtitleTimeline?,
            subtitleStyle: SubtitleBarStyle,
            karaokeTimeline: KaraokeTimeline? = nil,
            canvasSize: CGSize,
            clipTimeline: RecordingClipTimeline,
            exportSettings: VideoCompressionSettings,
            audioReplacementURL: URL? = nil,
            reframe: ReframeTrack? = nil,
            fitContentAspect: CGFloat? = nil,
            crop: CGRect = RecordingVideoCrop.unit,
            masks: [RecordingMaskSegment] = []
        ) {
            self.screenURL = screenURL
            self.cameraURL = cameraURL
            self.cameraOffset = cameraOffset
            self.style = style
            self.viewportTimeline = viewportTimeline
            self.pointerTimeline = pointerTimeline
            self.showsPressEffects = showsPressEffects
            self.keystrokeTimeline = keystrokeTimeline
            self.keystrokePlacement = keystrokePlacement
            self.subtitleTimeline = subtitleTimeline
            self.subtitleStyle = subtitleStyle
            self.karaokeTimeline = karaokeTimeline
            self.canvasSize = canvasSize
            self.clipTimeline = clipTimeline
            self.exportSettings = exportSettings
            self.audioReplacementURL = audioReplacementURL
            self.reframe = reframe
            self.fitContentAspect = fitContentAspect
            self.crop = crop
            self.masks = masks
        }
    }

    enum ExportError: LocalizedError {
        case noVideoTrack
        case writerFailed(Error?)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "The recording has no video track."
            case .writerFailed(let error):
                error?.localizedDescription ?? "Writing the exported video failed."
            case .cancelled:
                "Export cancelled."
            }
        }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.withLock { cancelled = true }
        }

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }
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

    @concurrent
    private func run(
        _ configuration: Configuration,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let sourceAsset = AVURLAsset(url: configuration.screenURL)
        let sourceDuration = try await sourceAsset.load(.duration).seconds
        let clipTimeline = configuration.clipTimeline.normalized(to: sourceDuration)
        guard clipTimeline.duration >= RecordingClipSegment.minimumDuration else {
            throw VideoTrimExportError.invalidRange
        }
        let screenAsset = try RecordingCompositionBuilder.makeAsset(
            from: sourceAsset,
            timeline: clipTimeline,
            sourceDuration: sourceDuration
        )
        guard let videoTrack = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let audioTracks = try await screenAsset.loadTracks(withMediaType: .audio)
        let exportStartTime = CMTime.zero
        let exportTimeRange = CMTimeRange(
            start: exportStartTime,
            duration: CMTime(seconds: clipTimeline.duration, preferredTimescale: 600)
        )

        let outputSize = Self.outputSize(
            source: configuration.canvasSize,
            resolution: configuration.exportSettings.resolution
        )
        let canvasWidth = max(2, Int(outputSize.width.rounded()) & ~1)
        let canvasHeight = max(2, Int(outputSize.height.rounded()) & ~1)
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        // Readers
        let screenReader = try AVAssetReader(asset: screenAsset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        screenReader.add(videoOutput)
        screenReader.timeRange = exportTimeRange

        // An imported soundtrack replaces the recorded one wholesale, and it
        // needs its own reader: it is a different file, already carrying the
        // finished cut's timing, so it plays straight through from zero
        // while the screen reader stays on the composed video.
        var audioOutput: AVAssetReaderAudioMixOutput?
        var replacementReader: AVAssetReader?
        if !configuration.exportSettings.removeAudio {
            if let replacementURL = configuration.audioReplacementURL {
                let replacementAsset = AVURLAsset(url: replacementURL)
                let replacementTracks = try await replacementAsset.loadTracks(withMediaType: .audio)
                if !replacementTracks.isEmpty {
                    let reader = try AVAssetReader(asset: replacementAsset)
                    // Clamps a soundtrack that overruns the cut; a shorter
                    // one simply leaves the tail silent.
                    reader.timeRange = exportTimeRange
                    let output = AVAssetReaderAudioMixOutput(
                        audioTracks: replacementTracks,
                        audioSettings: nil
                    )
                    output.alwaysCopiesSampleData = false
                    reader.add(output)
                    replacementReader = reader
                    audioOutput = output
                }
            } else if !audioTracks.isEmpty {
                let output = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: nil
                )
                output.alwaysCopiesSampleData = false
                screenReader.add(output)
                audioOutput = output
            }
        }

        let cameraFeed = try await CameraFrameFeed(
            url: configuration.cameraURL,
            offset: configuration.cameraOffset
        )

        // Writer
        let container = configuration.exportSettings.effectiveContainer
        let outputURL = Self.temporaryOutputURL(container: container)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: container.fileType)
        // Faststart puts the index ahead of the media so a shared link plays
        // before it finishes downloading. The writer pays for that with an
        // extra pass at the end, so only MP4 - the container people actually
        // stream - opts in.
        writer.shouldOptimizeForNetworkUse = container.supportsFastStart

        let codec: AVVideoCodecType = configuration.exportSettings.codec == .hevc ? .hevc : .h264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
            ],
            AVVideoWidthKey: canvasWidth,
            AVVideoHeightKey: canvasHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.averageBitRate(
                    width: canvasWidth,
                    height: canvasHeight,
                    quality: configuration.exportSettings.quality
                ),
                AVVideoExpectedSourceFrameRateKey: configuration.exportSettings.effectiveFrameRate.framesPerSecond
            ] as [String: Any]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: canvasWidth,
                kCVPixelBufferHeightKey as String: canvasHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard screenReader.startReading() else {
            throw screenReader.error ?? ExportError.writerFailed(nil)
        }
        if let replacementReader, !replacementReader.startReading() {
            screenReader.cancelReading()
            throw replacementReader.error ?? ExportError.writerFailed(nil)
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error)
        }
        writer.startSession(atSourceTime: exportStartTime)

        let compositor = StudioFrameCompositor(
            canvasSize: canvasSize,
            style: configuration.style,
            viewportTimeline: configuration.viewportTimeline,
            pointerTimeline: configuration.pointerTimeline,
            showsPressEffects: configuration.showsPressEffects,
            keystrokeTimeline: configuration.keystrokeTimeline,
            keystrokePlacement: configuration.keystrokePlacement,
            subtitleTimeline: configuration.subtitleTimeline,
            subtitleStyle: configuration.subtitleStyle,
            karaokeTimeline: configuration.karaokeTimeline,
            includeBubble: cameraFeed != nil,
            outputFrameInterval: 1 / Double(configuration.exportSettings.effectiveFrameRate.framesPerSecond),
            reframe: configuration.reframe,
            fitContentAspect: configuration.fitContentAspect,
            crop: configuration.crop,
            masks: configuration.masks,
            maximumBlurSamples: configuration.exportSettings.speed.motionBlurSamples
        )

        let screenAudioOutput = audioOutput
        let writerAudioInput = audioInput

        do {
            async let videoDone: Void = pumpVideo(
                output: videoOutput,
                input: videoInput,
                adaptor: adaptor,
                compositor: compositor,
                cameraFeed: cameraFeed,
                clipTimeline: clipTimeline,
                frameRate: Double(configuration.exportSettings.effectiveFrameRate.framesPerSecond),
                writer: writer,
                cancelFlag: cancelFlag,
                progress: progress
            )
            async let audioDone: Void = pumpAudio(
                output: screenAudioOutput,
                input: writerAudioInput,
                writer: writer,
                cancelFlag: cancelFlag
            )
            _ = try await (videoDone, audioDone)
        } catch {
            screenReader.cancelReading()
            replacementReader?.cancelReading()
            cameraFeed?.cancel()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        cameraFeed?.cancel()
        if screenReader.status == .failed || replacementReader?.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw screenReader.error ?? replacementReader?.error ?? ExportError.writerFailed(nil)
        }
        if cancelFlag.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.cancelled
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.writerFailed(writer.error)
        }
        progress(1)
        return outputURL
    }

    private func pumpVideo(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        compositor: StudioFrameCompositor,
        cameraFeed: CameraFrameFeed?,
        clipTimeline: RecordingClipTimeline,
        frameRate: Double,
        writer: AVAssetWriter,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Render on a fixed output clock, not per source frame. Screen
        // captures only contain frames where pixels changed, so a static
        // screen has second-long gaps - but the virtual camera animates
        // through them (most zoom-outs happen exactly there, seconds after
        // the last click). Each tick re-renders the newest source frame at
        // or before it; only writing on source arrivals would hold the last
        // zoomed frame through the move and then visibly jump.
        let duration = clipTimeline.duration
        let frameCount = max(1, Int((duration * frameRate).rounded()))

        func nextSourceFrame() -> (buffer: CVPixelBuffer, time: TimeInterval)? {
            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                return (buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
            }
            return nil
        }

        var currentBuffer: CVPixelBuffer?
        var pending = nextSourceFrame()
        var previousClipID: UUID?

        // Three retained frames overlap decode, GPU work, and hardware encoding
        // without allowing a long export to accumulate full-resolution buffers.
        var pendingFrames: [(task: CIRenderTask, image: CIImage, buffer: CVPixelBuffer, time: CMTime)] = []
        defer {
            for frame in pendingFrames {
                withExtendedLifetime(frame.image) { _ = try? frame.task.waitUntilCompleted() }
            }
        }
        func appendFirstFrame() async throws {
            while !input.isReadyForMoreMediaData {
                if cancelFlag.isCancelled { throw ExportError.cancelled }
                try Task.checkCancellation()
                guard writer.status == .writing else { throw ExportError.writerFailed(writer.error) }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let frame = pendingFrames.removeFirst()
            try withExtendedLifetime(frame.image) { try frame.task.waitUntilCompleted() }
            if !adaptor.append(frame.buffer, withPresentationTime: frame.time) {
                throw ExportError.writerFailed(writer.error)
            }
        }

        for frame in 0..<frameCount {
            if cancelFlag.isCancelled { throw ExportError.cancelled }
            try Task.checkCancellation()
            let editorTime = Double(frame) / frameRate
            guard let location = clipTimeline.location(at: editorTime) else { break }
            let sourceTime = location.sourceTime

            if previousClipID != location.segmentID {
                // Never carry a sparse screen-capture frame across a hard
                // edit boundary - the reader may not have caught up yet to
                // the new clip's starting source position.
                if previousClipID != nil {
                    currentBuffer = nil
                }
                previousClipID = location.segmentID
            }

            while let sample = pending, sample.time <= editorTime {
                currentBuffer = sample.buffer
                pending = nextSourceFrame()
            }
            // Ticks before the first source frame show it early rather than
            // emitting black; a capture with no frames at all has nothing to
            // render.
            guard let sourceBuffer = currentBuffer ?? pending?.buffer else { break }

            guard let pool = adaptor.pixelBufferPool else {
                throw ExportError.writerFailed(nil)
            }
            var destinationBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinationBuffer)
            guard let destinationBuffer else {
                throw ExportError.writerFailed(nil)
            }

            CVBufferSetAttachments(destinationBuffer, [
                kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
                kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_sRGB,
                kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2
            ] as CFDictionary, .shouldPropagate)
            try autoreleasepool {
                let cameraBuffer = cameraFeed?.latestFrame(at: sourceTime)
                let render = try compositor.startRender(
                    screenFrame: sourceBuffer,
                    cameraFrame: cameraBuffer,
                    editorTime: editorTime,
                    sourceTime: sourceTime,
                    into: destinationBuffer
                )

                let pts = CMTime(seconds: editorTime, preferredTimescale: 600)
                pendingFrames.append((render.task, render.image, destinationBuffer, pts))
            }
            if pendingFrames.count == 3 { try await appendFirstFrame() }
            if frame % 10 == 0 {
                progress(min(0.98, Double(frame) / Double(frameCount)))
            }
        }
        while !pendingFrames.isEmpty {
            if cancelFlag.isCancelled { throw ExportError.cancelled }
            try Task.checkCancellation()
            try await appendFirstFrame()
        }
        input.markAsFinished()
    }

    private func pumpAudio(
        output: AVAssetReaderAudioMixOutput?,
        input: AVAssetWriterInput?,
        writer: AVAssetWriter,
        cancelFlag: CancelFlag
    ) async throws {
        guard let output, let input else { return }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if cancelFlag.isCancelled { throw ExportError.cancelled }
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                if cancelFlag.isCancelled { throw ExportError.cancelled }
                try Task.checkCancellation()
                guard writer.status == .writing else { throw ExportError.writerFailed(writer.error) }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            if !input.append(sampleBuffer) {
                throw ExportError.writerFailed(nil)
            }
        }
        input.markAsFinished()
    }

    private static func temporaryOutputURL(container: VideoExportContainer) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BetterShot", isDirectory: true)
            .appendingPathComponent("StudioExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).\(container.fileExtension)")
    }

    private static func outputSize(
        source: CGSize,
        resolution: VideoCompressionResolution
    ) -> CGSize {
        guard source.width > 0, source.height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }
        let requestedHeight: CGFloat?
        switch resolution {
        case .original: requestedHeight = nil
        case .p1080: requestedHeight = 1080
        case .p720: requestedHeight = 720
        case .p480: requestedHeight = 480
        }
        guard let requestedHeight, source.height > requestedHeight else { return source }
        return CGSize(
            width: source.width * requestedHeight / source.height,
            height: requestedHeight
        )
    }

    private static func averageBitRate(
        width: Int,
        height: Int,
        quality: VideoCompressionQuality
    ) -> Int {
        let factor: Double
        switch quality {
        case .high: factor = 3.2
        case .medium: factor = 2.1
        case .low: factor = 1.25
        }
        return max(2_500_000, Int(Double(width * height) * factor))
    }
}

// MARK: - Camera frame feed

/// Sequential decoder for the camera movie that answers "latest camera frame
/// at screen-time t". Screen frames arrive in order, so a one-frame
/// look-ahead over the camera reader is all that's needed.
nonisolated private final class CameraFrameFeed: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let offset: TimeInterval
    private var currentFrame: CVPixelBuffer?
    private var pendingFrame: (buffer: CVPixelBuffer, time: TimeInterval)?
    private var isFinished = false

    init?(url: URL?, offset: TimeInterval) async throws {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? RecordingStudioExporter.ExportError.noVideoTrack
        }

        self.reader = reader
        self.output = output
        self.offset = offset
    }

    func latestFrame(at screenTime: TimeInterval) -> CVPixelBuffer? {
        while !isFinished {
            if let pending = pendingFrame {
                // Promote the very first frame unconditionally: the camera
                // starts a beat after the screen (capture warmup), and holding
                // its first frame from t=0 beats the bubble popping in late.
                guard pending.time <= screenTime || currentFrame == nil else { break }
                currentFrame = pending.buffer
                pendingFrame = nil
            }
            guard let sample = output.copyNextSampleBuffer() else {
                isFinished = true
                break
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds + offset
            pendingFrame = (buffer: buffer, time: time)
        }
        return currentFrame
    }

    func cancel() {
        reader.cancelReading()
    }
}

// MARK: - Frame compositor

/// Draws one output frame: cached backdrop, then the zoom-transformed screen
/// frame clipped to the rounded card, then the camera bubble.
nonisolated final class StudioFrameCompositor: @unchecked Sendable {
    private let canvasSize: CGSize
    private let layout: RecordingStudioLayout
    private let viewportTimeline: ViewportTimeline
    private let pointerTimeline: PointerTimeline?
    private let showsPressEffects: Bool
    private let keystrokeTimeline: KeystrokeCaptionTimeline?
    private let keystrokePlacement: RecordingKeystrokePlacement
    private let subtitleTimeline: SubtitleTimeline?
    private let subtitleStyle: SubtitleBarStyle
    private let karaokeTimeline: KaraokeTimeline?
    private let reframe: ReframeTrack?
    private let crop: CGRect
    private let masks: [RecordingMaskSegment]
    private let renderContext = CIContext(options: [.cacheIntermediates: false])
    private var artworkImageCache: [String: CGImage] = [:]
    // Retain the buffer: decoder pools may recycle its address after release.
    // Only source-dependent work is reused; overlays and mask timing run at the output cadence.
    private var cachedSource: CVPixelBuffer?
    private var cachedScreen: CIImage?
    private var cachedSampleRects: [CGRect] = []
    private var cachedMasks: [Int: CIImage] = [:]
    private var cachedMaskBytes = 0
    private lazy var overlayPool: CVPixelBufferPool? = {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(canvasSize.width),
            kCVPixelBufferHeightKey as String: Int(canvasSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as CFDictionary, &pool)
        return pool
    }()
    private lazy var backgroundImage = backdrop.map { CIImage(cgImage: $0) }
        ?? CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvasSize))
    private lazy var cardMask = try? raster { context in
        context.addPath(roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
    }
    private lazy var cameraMask = try? raster { context in
        context.addPath(roundedPath(for: layout.bubbleRect, radius: layout.bubbleCornerRadius))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
    }
    private lazy var cameraShadow = try? raster { drawCameraShadow(in: $0) }
    private lazy var cameraBorder = try? raster { context in
        context.addPath(roundedPath(for: layout.bubbleRect.insetBy(dx: 0.5, dy: 0.5),
                                    radius: layout.bubbleCornerRadius))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        context.setLineWidth(max(1, min(canvasSize.width, canvasSize.height) * 0.0018))
        context.strokePath()
    }
    private let pointerScale: CGFloat
    private let colorSpace: CGColorSpace
    private let backdrop: CGImage?
    /// Fixed output cadence, matching `pumpVideo`'s frame clock. Since the
    /// output timeline is gapless by construction, the shutter window for
    /// motion-blur supersampling is always exactly one output frame - no
    /// need to measure elapsed time between calls.
    private let outputFrameInterval: TimeInterval
    private let maximumBlurSamples: Int

    init(
        canvasSize: CGSize,
        style: RecordingStudioStyle,
        viewportTimeline: ViewportTimeline,
        pointerTimeline: PointerTimeline?,
        showsPressEffects: Bool,
        keystrokeTimeline: KeystrokeCaptionTimeline?,
        keystrokePlacement: RecordingKeystrokePlacement,
        subtitleTimeline: SubtitleTimeline?,
        subtitleStyle: SubtitleBarStyle = SubtitleBarStyle(),
        karaokeTimeline: KaraokeTimeline? = nil,
        includeBubble: Bool,
        outputFrameInterval: TimeInterval = 1.0 / 60.0,
        reframe: ReframeTrack? = nil,
        fitContentAspect: CGFloat? = nil,
        crop: CGRect = RecordingVideoCrop.unit,
        masks: [RecordingMaskSegment] = [],
        maximumBlurSamples: Int = 4
    ) {
        self.maximumBlurSamples = max(1, maximumBlurSamples)
        self.canvasSize = canvasSize
        self.layout = RecordingStudioLayout.make(
            canvasSize: canvasSize,
            style: style,
            includeBubble: includeBubble,
            contentAspect: reframe?.sourceAspect ?? fitContentAspect,
            contentMode: fitContentAspect != nil && reframe == nil ? .fit : .fill
        )
        self.viewportTimeline = viewportTimeline
        self.pointerTimeline = pointerTimeline
        self.showsPressEffects = showsPressEffects
        self.keystrokeTimeline = keystrokeTimeline
        self.keystrokePlacement = keystrokePlacement
        self.subtitleTimeline = subtitleTimeline
        self.subtitleStyle = subtitleStyle
        self.karaokeTimeline = karaokeTimeline
        self.reframe = reframe
        self.crop = crop
        self.masks = masks
        self.outputFrameInterval = outputFrameInterval
        self.pointerScale = style.cursorScale
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.backdrop = Self.renderBackdrop(
            canvasSize: canvasSize,
            layout: layout,
            style: style,
            colorSpace: colorSpace
        )
    }

    /// The virtual camera for a frame: the reframe crop-and-follow track
    /// when exporting into a different aspect, the zoom viewport otherwise.
    private func viewportFrame(at editorTime: TimeInterval) -> ViewportFrame {
        reframe?.frame(at: editorTime) ?? viewportTimeline.frame(at: editorTime)
    }

    private func contentRect(at editorTime: TimeInterval) -> CGRect {
        RecordingVideoCrop.expandedRect(
            layout.frameRect(for: viewportFrame(at: editorTime)),
            crop: crop
        )
    }

    func render(
        screenFrame: CVPixelBuffer,
        cameraFrame: CVPixelBuffer?,
        editorTime: TimeInterval,
        sourceTime: TimeInterval,
        into destination: CVPixelBuffer
    ) throws {
        let render = try startRender(screenFrame: screenFrame, cameraFrame: cameraFrame,
                                     editorTime: editorTime, sourceTime: sourceTime, into: destination)
        try withExtendedLifetime(render.image) { try render.task.waitUntilCompleted() }
    }

    func startRender(
        screenFrame: CVPixelBuffer,
        cameraFrame: CVPixelBuffer?,
        editorTime: TimeInterval,
        sourceTime: TimeInterval,
        into destination: CVPixelBuffer
    ) throws -> (task: CIRenderTask, image: CIImage) {
        if cachedSource !== screenFrame {
            cachedSource = screenFrame
            cachedScreen = nil
            cachedMasks.removeAll(keepingCapacity: true)
            cachedMaskBytes = 0
        }
        var result = backgroundImage
        if layout.showsScreen {
            let sourceImage = CIImage(cvPixelBuffer: screenFrame)
            let shutter = outputFrameInterval
            let sampleCount = blurSampleCount(at: editorTime, shutter: shutter)
            let sampleRects = (0..<sampleCount).map { sample in
                let sampleTime = editorTime - shutter / 2
                    + shutter * (Double(sample) + 0.5) / Double(sampleCount)
                return flipped(contentRect(at: sampleTime))
            }
            let cardRect = flipped(layout.cardRect).integral
            if cachedScreen == nil || cachedSampleRects != sampleRects {
                var averaged: CIImage?
                for (sample, rect) in sampleRects.enumerated() {
                    let transformed = sourceImage.transformed(by: CGAffineTransform(
                        a: rect.width / sourceImage.extent.width, b: 0,
                        c: 0, d: rect.height / sourceImage.extent.height,
                        tx: rect.minX, ty: rect.minY
                    ))
                    if let previous = averaged {
                        let opacity = CIFilter.colorMatrix()
                        opacity.inputImage = transformed
                        opacity.aVector = CIVector(x: 0, y: 0, z: 0, w: 1 / CGFloat(sample + 1))
                        guard let sampleImage = opacity.outputImage else {
                            throw RecordingStudioExporter.ExportError.writerFailed(nil)
                        }
                        averaged = sampleImage.composited(over: previous)
                    } else {
                        averaged = transformed
                    }
                }
                guard let averaged else {
                    throw RecordingStudioExporter.ExportError.writerFailed(nil)
                }
                cachedScreen = averaged.cropped(to: cardRect).insertingIntermediate(cache: true)
                cachedSampleRects = sampleRects
            }
            guard var screenImage = cachedScreen, let cardMask else {
                throw RecordingStudioExporter.ExportError.writerFailed(nil)
            }
            let content = flipped(contentRect(at: editorTime))
            let transform = CGAffineTransform(
                a: content.width / sourceImage.extent.width, b: 0,
                c: 0, d: content.height / sourceImage.extent.height,
                tx: content.minX, ty: content.minY
            )
            for (index, segment) in masks.enumerated() where segment.isActive(at: editorTime) {
                let region: CIImage
                if let cached = cachedMasks[index] {
                    region = cached
                } else {
                    guard let filtered = RecordingMaskRenderer.filteredRegion(source: sourceImage, segment: segment) else {
                        throw RecordingStudioExporter.ExportError.writerFailed(nil)
                    }
                    let bytes = Int(filtered.extent.width.rounded(.up) * filtered.extent.height.rounded(.up)) * 8
                    // Bound retained half-float GPU mask rasters to 32 MiB per source frame.
                    if cachedMaskBytes + bytes <= 32 * 1024 * 1024 {
                        region = filtered.insertingIntermediate(cache: true)
                        cachedMasks[index] = region
                        cachedMaskBytes += bytes
                    } else {
                        region = filtered
                    }
                }
                screenImage = region.transformed(by: transform).composited(over: screenImage)
            }
            result = screenImage.applyingFilter("CISourceInCompositing", parameters: [
                kCIInputBackgroundImageKey: cardMask
            ]).composited(over: backgroundImage)

            // Pointer motion is resolved independently from viewport shutter
            // blur. Its interaction magnification and tilt stay anchored at the
            // recorded artwork anchor point, while the final point still passes
            // through the same viewport transform and rounded-card clip as the
            // source pixels.
            if pointerTimeline != nil || keystrokeTimeline != nil {
                result = try raster { context in
                    drawPointer(editorTime: editorTime, in: context)
                    drawKeystrokeCaption(at: sourceTime, in: context)
                }.composited(over: result)
            }
        }

        if let cameraFrame, layout.bubbleRect.width > 0 {
            guard let cameraMask, let cameraShadow, let cameraBorder else {
                throw RecordingStudioExporter.ExportError.writerFailed(nil)
            }
            let camera = CIImage(cvPixelBuffer: cameraFrame)
            let bubble = flipped(layout.bubbleRect)
            let scale = max(bubble.width / camera.extent.width, bubble.height / camera.extent.height)
            let transformed = camera.transformed(by: CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: bubble.midX - camera.extent.width * scale / 2,
                ty: bubble.midY - camera.extent.height * scale / 2
            ))
            if layout.decoratesCamera { result = cameraShadow.composited(over: result) }
            result = transformed.applyingFilter("CISourceInCompositing", parameters: [
                kCIInputBackgroundImageKey: cameraMask
            ]).composited(over: result)
            if layout.decoratesCamera { result = cameraBorder.composited(over: result) }
        }

        if subtitleTimeline != nil {
            result = try raster { drawSubtitleBar(at: sourceTime, in: $0) }.composited(over: result)
        }
        // Keep media on the GPU through the encoder's IOSurface-backed buffer.
        // Only cursor/text artwork is rasterized with Quartz; no video readback.
        let destination = CIRenderDestination(pixelBuffer: destination)
        destination.colorSpace = colorSpace
        // Retain the graph (including pooled source/overlay buffers) until GPU completion.
        return (try renderContext.startTask(toRender: result, to: destination), result)
    }

    private func raster(_ draw: (CGContext) -> Void) throws -> CIImage {
        guard let pool = overlayPool else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), let context = CGContext(
            data: base,
            width: Int(canvasSize.width), height: Int(canvasSize.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        context.clear(CGRect(origin: .zero, size: canvasSize))
        context.interpolationQuality = .high
        draw(context)
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: colorSpace])
    }

    private func drawCameraShadow(in context: CGContext) {
        let minDimension = min(canvasSize.width, canvasSize.height)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -minDimension * 0.009),
            blur: minDimension * 0.022,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        context.addPath(roundedPath(for: layout.bubbleRect, radius: layout.bubbleCornerRadius))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    /// How many shutter sub-samples this frame needs: one when the camera is
    /// still, up to twenty-four when it sweeps, spaced so consecutive samples
    /// land roughly two output pixels apart.
    private func blurSampleCount(at editorTime: TimeInterval, shutter: TimeInterval) -> Int {
        guard maximumBlurSamples > 1 else { return 1 }
        let a = contentRect(at: editorTime - shutter / 2)
        let b = contentRect(at: editorTime + shutter / 2)
        let displacement = max(
            max(abs(a.minX - b.minX), abs(a.minY - b.minY)),
            max(abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
        )
        guard displacement > 1.5 else { return 1 }
        return min(maximumBlurSamples, max(2, Int((displacement / 2).rounded(.up))))
    }

    private func drawPointer(editorTime: TimeInterval, in context: CGContext) {
        guard let pointerTimeline,
              let pointer = pointerTimeline.frame(at: editorTime) else {
            return
        }

        let drawRect = contentRect(at: editorTime)
        let tip = CGPoint(
            x: drawRect.minX + pointer.location.x * drawRect.width,
            y: canvasSize.height - (drawRect.minY + pointer.location.y * drawRect.height)
        )

        context.saveGState()
        context.addPath(roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius))
        context.clip()
        if showsPressEffects, let press = pointer.press {
            let pressTip = CGPoint(
                x: drawRect.minX + press.location.x * drawRect.width,
                y: canvasSize.height - (drawRect.minY + press.location.y * drawRect.height)
            )
            let effect = PointerPressEffectStyle.geometry(
                progress: press.progress,
                referenceHeight: layout.contentFillSize.height,
                cursorScale: pointerScale
            )
            let accent = PointerPressEffectStyle.color
            context.saveGState()
            context.setFillColor(CGColor(
                red: accent.red,
                green: accent.green,
                blue: accent.blue,
                alpha: press.impactEnabled ? effect.impactOpacity : 0
            ))
            context.fillEllipse(in: CGRect(
                x: pressTip.x - effect.impactRadius,
                y: pressTip.y - effect.impactRadius,
                width: effect.impactRadius * 2,
                height: effect.impactRadius * 2
            ))
            context.setStrokeColor(CGColor(
                red: accent.red,
                green: accent.green,
                blue: accent.blue,
                alpha: press.rippleEnabled ? effect.rippleOpacity : 0
            ))
            context.setLineWidth(effect.rippleLineWidth)
            context.strokeEllipse(in: CGRect(
                x: pressTip.x - effect.rippleRadius,
                y: pressTip.y - effect.rippleRadius,
                width: effect.rippleRadius * 2,
                height: effect.rippleRadius * 2
            ))
            context.restoreGState()
        }

        if let resolved = artwork(for: pointer, in: pointerTimeline) {
            let height = layout.contentFillSize.height
                * PointerArtworkMetrics.heightRatio
                * pointerScale
                * resolved.intrinsicScale
            let size = CGSize(width: height * resolved.aspectRatio, height: height)
            context.setAlpha(CGFloat(min(max(pointer.opacity, 0), 1)))
            context.translateBy(x: tip.x, y: tip.y)
            context.rotate(by: -CGFloat(pointer.tiltDegrees * .pi / 180))
            let interactionScale = CGFloat(max(pointer.magnification, 0.1))
            context.scaleBy(x: interactionScale, y: interactionScale)
            context.draw(
                resolved.image,
                in: CGRect(
                    x: -resolved.anchor.x * size.width,
                    y: -(1 - resolved.anchor.y) * size.height,
                    width: size.width,
                    height: size.height
                )
            )
        }
        context.restoreGState()
    }

    private func drawKeystrokeCaption(at time: TimeInterval, in context: CGContext) {
        guard let keystrokeTimeline,
              let caption = keystrokeTimeline.frame(at: time) else {
            return
        }

        let metrics = KeystrokeCaptionMetrics(cardHeight: layout.cardRect.height)
        let font = Self.captionFont(size: metrics.fontSize)
        let (modifierText, keyText) = KeystrokeCaptionMetrics.text(for: caption)

        let text = NSMutableAttributedString()
        if !modifierText.isEmpty {
            text.append(NSAttributedString(string: modifierText, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 1, alpha: KeystrokeCaptionMetrics.modifierAlpha)
            ]))
        }
        text.append(NSAttributedString(string: keyText, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 1, alpha: 1)
        ]))

        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        guard textWidth > 0 else { return }

        let pillSize = CGSize(
            width: textWidth + metrics.paddingHorizontal * 2,
            height: ascent + descent + metrics.paddingVertical * 2
        )
        let origin = metrics.pillOrigin(
            pillSize: pillSize,
            cardRect: layout.cardRect,
            placement: keystrokePlacement
        )
        let pillRect = flipped(CGRect(origin: origin, size: pillSize))

        context.saveGState()
        context.setAlpha(CGFloat(caption.opacity))
        context.translateBy(x: pillRect.midX, y: pillRect.midY)
        context.scaleBy(x: CGFloat(caption.scale), y: CGFloat(caption.scale))
        context.translateBy(x: -pillRect.midX, y: -pillRect.midY)

        let radius = min(metrics.cornerRadius, pillRect.height / 2)
        context.addPath(CGPath(
            roundedRect: pillRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0, alpha: KeystrokeCaptionMetrics.backgroundAlpha))
        context.fillPath()

        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: pillRect.minX + metrics.paddingHorizontal,
            y: pillRect.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawSubtitleBar(at time: TimeInterval, in context: CGContext) {
        guard let subtitleTimeline,
              let text = subtitleTimeline.text(at: time) else {
            return
        }

        let metrics = SubtitleBarMetrics(canvasSize: canvasSize, style: subtitleStyle)
        let maximumTextWidth = metrics.maximumTextWidth(canvasWidth: canvasSize.width)

        // On narrow canvases the text wraps into centered lines rather
        // than shrinking into a full-width sliver; the font only scales
        // down when even the maximum line count can't hold it.
        var fontSize = metrics.fontSize
        var wrappedLines: [CTLine] = []
        for _ in 0..<3 {
            let font = Self.captionFont(size: fontSize)
            let attributed = subtitleAttributedText(plainText: text, at: time, font: font)
            wrappedLines = Self.wrapLines(attributed, width: maximumTextWidth)
            if wrappedLines.count <= SubtitleBarMetrics.maximumLineCount || fontSize <= 11 {
                break
            }
            fontSize *= CGFloat(SubtitleBarMetrics.maximumLineCount) / CGFloat(wrappedLines.count)
        }
        guard !wrappedLines.isEmpty else { return }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidths = wrappedLines.map {
            CGFloat(CTLineGetTypographicBounds($0, &ascent, &descent, &leading))
        }
        guard let widestLine = lineWidths.max(), widestLine > 0 else { return }
        let lineAdvance = (ascent + descent) * SubtitleBarMetrics.lineSpacingFactor
        let textHeight = ascent + descent + lineAdvance * CGFloat(wrappedLines.count - 1)

        let barSize = CGSize(
            width: widestLine + metrics.paddingHorizontal * 2,
            height: textHeight + metrics.paddingVertical * 2
        )
        let barCenterY = canvasSize.height * CGFloat(subtitleStyle.clampedVerticalPosition)
        let origin = CGPoint(
            x: canvasSize.width / 2 - barSize.width / 2,
            y: barCenterY - barSize.height / 2
        )
        let barRect = flipped(CGRect(origin: origin, size: barSize))

        context.saveGState()
        let radius = min(metrics.cornerRadius, barRect.height / 2)
        context.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0, alpha: SubtitleBarMetrics.backgroundAlpha))
        context.fillPath()

        context.textMatrix = .identity
        // The CG context is bottom-up, so the first wrapped line sits at
        // the top of the bar and subsequent lines step downward.
        let firstBaseline = barRect.maxY - metrics.paddingVertical - ascent
        for (index, wrappedLine) in wrappedLines.enumerated() {
            context.textPosition = CGPoint(
                x: barRect.midX - lineWidths[index] / 2,
                y: firstBaseline - lineAdvance * CGFloat(index)
            )
            CTLineDraw(wrappedLine, context)
        }
        context.restoreGState()
    }

    /// Word-wraps an attributed string into CTLines within a width.
    private static func wrapLines(
        _ attributed: NSAttributedString,
        width: CGFloat
    ) -> [CTLine] {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: max(24, width), height: 100_000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        return (CTFrameGetLines(frame) as? [CTLine]) ?? []
    }

    /// The bar's text: karaoke-colored words when word timings exist and
    /// the style asks for them, the plain cue text otherwise. Colors match
    /// StudioSubtitleBarView exactly.
    private func subtitleAttributedText(
        plainText: String,
        at time: TimeInterval,
        font: CTFont
    ) -> NSAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        guard subtitleStyle.highlightsSpokenWord,
              let karaokeTimeline,
              let karaokeLine = karaokeTimeline.line(at: time),
              !karaokeLine.words.isEmpty else {
            return NSAttributedString(string: plainText, attributes: [
                fontKey: font,
                colorKey: CGColor(gray: 1, alpha: 1)
            ])
        }

        let text = NSMutableAttributedString()
        for (index, word) in karaokeLine.words.enumerated() {
            let color: CGColor
            if index == karaokeLine.activeIndex {
                color = SubtitleBarMetrics.karaokeAccent
            } else if index < karaokeLine.spokenCount {
                color = CGColor(gray: 1, alpha: 1)
            } else {
                color = CGColor(gray: 1, alpha: SubtitleBarMetrics.karaokeUpcomingAlpha)
            }
            text.append(NSAttributedString(
                string: index > 0 ? " \(word)" : word,
                attributes: [fontKey: font, colorKey: color]
            ))
        }
        return text
    }

    private static func captionFont(size: CGFloat) -> CTFont {
        let descriptor = NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor
        let rounded = descriptor.withDesign(.rounded) ?? descriptor
        return CTFontCreateWithFontDescriptor(rounded as CTFontDescriptor, size, nil)
    }

    private func artwork(
        for pointer: PointerFrame,
        in timeline: PointerTimeline
    ) -> (image: CGImage, anchor: CGPoint, aspectRatio: CGFloat, intrinsicScale: CGFloat)? {
        if let resolved = timeline.artwork(id: pointer.artworkID),
           let image = artworkImage(for: resolved) {
            return (
                image,
                resolved.normalizedAnchor,
                resolved.aspectRatio,
                resolved.intrinsicScale
            )
        }
        return nil
    }

    private func artworkImage(for artwork: PointerArtwork) -> CGImage? {
        if let cached = artworkImageCache[artwork.artworkID] {
            return cached
        }
        guard let source = CGImageSourceCreateWithData(artwork.imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        artworkImageCache[artwork.artworkID] = image
        return image
    }

    /// Layout rects use a top-left origin; CoreGraphics draws bottom-up.
    private func flipped(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func roundedPath(for rect: CGRect, radius: CGFloat) -> CGPath {
        let flippedRect = flipped(rect)
        let boundedRadius = min(radius, min(flippedRect.width, flippedRect.height) / 2)
        guard boundedRadius > 0.5 else { return CGPath(rect: flippedRect, transform: nil) }
        return CGPath(
            roundedRect: flippedRect,
            cornerWidth: boundedRadius,
            cornerHeight: boundedRadius,
            transform: nil
        )
    }

    private static func renderBackdrop(
        canvasSize: CGSize,
        layout: RecordingStudioLayout,
        style: RecordingStudioStyle,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        switch style.background {
        case .none:
            context.setFillColor(CGColor(gray: 0.04, alpha: 1))
            context.fill(canvasRect)
        case .solid(let color):
            context.setFillColor(CGColor(
                colorSpace: colorSpace,
                components: [color.red, color.green, color.blue, color.alpha]
            ) ?? CGColor(gray: 0, alpha: 1))
            context.fill(canvasRect)
        case .gradient(let gradient):
            if let preset = gradient.preset {
                preset.draw(in: context, rect: canvasRect)
            } else {
            let cgColors = gradient.colors.map { color in
                CGColor(
                    colorSpace: colorSpace,
                    components: [color.red, color.green, color.blue, color.alpha]
                ) ?? CGColor(gray: 0, alpha: 1)
            }
            if let cgGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: cgColors as CFArray,
                locations: nil
            ) {
                // UnitPoint has a top-left origin; the context is bottom-up.
                let start = CGPoint(
                    x: gradient.startPoint.x * canvasSize.width,
                    y: canvasSize.height - gradient.startPoint.y * canvasSize.height
                )
                let end = CGPoint(
                    x: gradient.endPoint.x * canvasSize.width,
                    y: canvasSize.height - gradient.endPoint.y * canvasSize.height
                )
                context.drawLinearGradient(cgGradient, start: start, end: end, options: [
                    .drawsBeforeStartLocation,
                    .drawsAfterEndLocation
                ])
            }
            }
        case .customWallpaper(let wallpaper):
            if let source = CGImageSourceCreateWithURL(wallpaper.url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, [
                   kCGImageSourceShouldCache: false
               ] as CFDictionary) {
                let imageSize = CGSize(width: image.width, height: image.height)
                let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
                let fillSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let fillRect = CGRect(
                    x: (canvasSize.width - fillSize.width) / 2,
                    y: (canvasSize.height - fillSize.height) / 2,
                    width: fillSize.width,
                    height: fillSize.height
                )
                context.draw(image, in: fillRect)
            } else {
                context.setFillColor(CGColor(gray: 0.04, alpha: 1))
                context.fill(canvasRect)
            }
        }

        // Card shadow: static, so it lives in the backdrop. The filled shape
        // is fully covered by video pixels every frame.
        if layout.showsScreen, style.shadow > 0.01, style.background != .none {
            let minDimension = min(canvasSize.width, canvasSize.height)
            let blur = minDimension * 0.045 * style.shadow
            let cardRect = CGRect(
                x: layout.cardRect.minX,
                y: canvasSize.height - layout.cardRect.maxY,
                width: layout.cardRect.width,
                height: layout.cardRect.height
            )
            let radius = min(layout.cardCornerRadius, min(cardRect.width, cardRect.height) / 2)
            let path = radius > 0.5
                ? CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: cardRect, transform: nil)

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -blur * 0.35),
                blur: blur,
                color: CGColor(gray: 0, alpha: 0.55 * style.shadow)
            )
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }

        return context.makeImage()
    }
}
