import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo

// MARK: - Thread-safe writer using pixel buffer adaptor

final class RecordingWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let writingQueue = DispatchQueue(label: "com.bettershot.recording-writer")

    private var sessionStartTime: CMTime?
    private var totalPauseDuration: CMTime = .zero
    private var isPaused = false
    private var pauseStartTime: CMTime?
    private var needsPauseDurationUpdate = false
    private var latestSampleTime: CMTime = .zero

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let bitRate = max(20_000_000, width * height * 4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ] as [String: Any]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttrs
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        writer.startWriting()
    }

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writingQueue.sync {
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Handle pause state
            if isPaused {
                if pauseStartTime == nil { pauseStartTime = time }
                return
            }
            if needsPauseDurationUpdate, let pauseStart = pauseStartTime {
                totalPauseDuration = CMTimeAdd(totalPauseDuration, CMTimeSubtract(time, pauseStart))
                self.pauseStartTime = nil
                needsPauseDurationUpdate = false
            }
            latestSampleTime = time

            // First frame: start session at .zero
            if sessionStartTime == nil {
                sessionStartTime = time
                writer.startSession(atSourceTime: .zero)
            }

            // Remap PTS to 0-based, minus pauses
            guard let startTime = sessionStartTime else { return }
            var adjustedPTS = CMTimeSubtract(time, startTime)
            if totalPauseDuration > .zero {
                adjustedPTS = CMTimeSubtract(adjustedPTS, totalPauseDuration)
            }
            guard adjustedPTS >= .zero else { return }

            guard videoInput.isReadyForMoreMediaData else { return }
            adaptor.append(pixelBuffer, withPresentationTime: adjustedPTS)
        }
    }

    func pause() {
        writingQueue.sync {
            guard !isPaused else { return }
            isPaused = true
            pauseStartTime = latestSampleTime
        }
    }

    func resume() {
        writingQueue.sync {
            guard isPaused else { return }
            isPaused = false
            needsPauseDurationUpdate = true
        }
    }

    func finish() async {
        videoInput.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }
}

// MARK: - Main actor recorder that owns state and UI

@MainActor
@Observable
final class ScreenRecorder {
    static let shared = ScreenRecorder()

    enum State: Equatable {
        case idle, starting, recording, paused, finishing
    }

    private(set) var state: State = .idle
    private(set) var elapsedSeconds: TimeInterval = 0

    var isRecording: Bool { state == .recording || state == .paused }

    private var stream: SCStream?
    private var recordingWriter: RecordingWriter?
    private var timerTask: Task<Void, Never>?
    private var recordingStartDate: Date?
    private var pausedDuration: TimeInterval = 0
    private var lastPauseDate: Date?
    private var outputURL: URL?

    var onFinished: ((URL) -> Void)?

    private init() {}

    // MARK: - Start

    func startFullscreen() async {
        guard state == .idle else { return }
        state = .starting

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                state = .idle
                return
            }

            let ownBundleID = Bundle.main.bundleIdentifier ?? ""
            let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            let scaleFactor = max(1, Int(display.width) > 2000 ? 1 : 2)
            await startRecording(filter: filter, width: display.width * scaleFactor, height: display.height * scaleFactor)
        } catch {
            print("Failed to get screen content: \(error)")
            state = .idle
        }
    }

    func startWindow() async {
        guard state == .idle else { return }
        state = .starting

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier ?? ""
            let windows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier != ownBundleID
                && $0.isOnScreen
                && $0.frame.width >= 100
                && $0.frame.height >= 100
            }
            guard let frontWindow = windows.first else {
                state = .idle
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: frontWindow)
            let w = Int(frontWindow.frame.width) * 2
            let h = Int(frontWindow.frame.height) * 2
            await startRecording(filter: filter, width: w, height: h)
        } catch {
            print("Failed to start window recording: \(error)")
            state = .idle
        }
    }

    // MARK: - Controls

    func stop() {
        guard isRecording else { return }
        state = .finishing
        finishRecording()
    }

    func pause() {
        guard state == .recording else { return }
        recordingWriter?.pause()
        lastPauseDate = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        recordingWriter?.resume()
        if let lastPause = lastPauseDate {
            pausedDuration += Date().timeIntervalSince(lastPause)
        }
        lastPauseDate = nil
        state = .recording
    }

    func discard() {
        guard isRecording else { return }
        let url = outputURL
        timerTask?.cancel()
        timerTask = nil
        state = .idle
        cleanup()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Private

    private func startRecording(filter: SCContentFilter, width: Int, height: Int) async {
        // Ensure even dimensions (required by HEVC encoder)
        let pixelWidth = width % 2 == 0 ? width : width + 1
        let pixelHeight = height % 2 == 0 ? height : height + 1

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = true

        let url = makeOutputURL()
        outputURL = url

        do {
            let writerObj = try RecordingWriter(url: url, width: pixelWidth, height: pixelHeight)
            recordingWriter = writerObj

            let delegate = StreamDelegate(writer: writerObj, onError: { [weak self] in
                Task { @MainActor in self?.stop() }
            })

            let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
            try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.bettershot.screen-capture", qos: .userInitiated))
            try await stream.startCapture()

            self.stream = stream
            state = .recording
            recordingStartDate = Date()
            pausedDuration = 0
            lastPauseDate = nil
            elapsedSeconds = 0
            startTimer()
        } catch {
            print("Failed to start recording: \(error)")
            state = .idle
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func finishRecording() {
        timerTask?.cancel()
        timerTask = nil

        let capturedStream = stream
        let capturedWriter = recordingWriter
        let capturedURL = outputURL
        cleanup()

        Task {
            try? await capturedStream?.stopCapture()
            await capturedWriter?.finish()

            self.state = .idle
            self.elapsedSeconds = 0
            if let capturedURL, FileManager.default.fileExists(atPath: capturedURL.path) {
                self.onFinished?(capturedURL)
            }
        }
    }

    private func cleanup() {
        stream = nil
        recordingWriter = nil
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let start = self.recordingStartDate else { continue }
                var elapsed = Date().timeIntervalSince(start) - self.pausedDuration
                if self.state == .paused, let lastPause = self.lastPauseDate {
                    elapsed -= Date().timeIntervalSince(lastPause)
                }
                self.elapsedSeconds = max(0, elapsed)
            }
        }
    }

    private func makeOutputURL() -> URL {
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return URL(fileURLWithPath: "\(dir)BetterShot_Recording_\(stamp).mov")
    }

    var formattedTime: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - SCStream Delegate

private final class StreamDelegate: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let writer: RecordingWriter
    private let onError: @Sendable () -> Void

    init(writer: RecordingWriter, onError: @escaping @Sendable () -> Void) {
        self.writer = writer
        self.onError = onError
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Filter out blank/invalid frames
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == 0 // SCFrameStatus.complete
        else { return }

        autoreleasepool {
            writer.processSampleBuffer(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("Stream stopped with error: \(error)")
        onError()
    }
}
