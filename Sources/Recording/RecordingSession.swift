import AVFoundation
import CoreMedia

final class RecordingSession: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let micInput: AVAssetWriterInput?

    private let lock = NSLock()
    private var _isCapturing = false
    private var _isPaused = false
    private var _sessionStarted = false
    private var _sessionStartTime: CMTime?
    private var _pauseStartTime: CMTime?
    private var _totalPauseDuration: CMTime = .zero
    private var _needsPauseDurationUpdate = false
    private var _latestAdjustedTime: CMTime = .zero
    private var _failed = false

    let outputURL: URL

    var isCapturing: Bool {
        get { lock.withLock { _isCapturing } }
        set { lock.withLock { _isCapturing = newValue } }
    }

    var duration: TimeInterval { lock.withLock { _latestAdjustedTime.seconds } }

    static func averageBitRate(width: Int, height: Int) -> Int {
        min(40_000_000, max(4_000_000, width * height * 4))
    }

    init(outputURL: URL, width: Int, height: Int, fps: Int, includeAudio: Bool, includeMicrophone: Bool = false) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let bitRate = Self.averageBitRate(width: width, height: height)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ] as [String: Any],
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        writer.add(videoInput)

        if includeAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 2))
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        if includeMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 1))
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            micInput = input
        } else {
            micInput = nil
        }
    }

    private static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 192_000 : 96_000,
        ]
    }

    func startWriting() -> Bool {
        writer.startWriting()
        return writer.status == .writing
    }

    func pause() {
        lock.withLock {
            guard !_isPaused else { return }
            _isPaused = true
            _pauseStartTime = nil
        }
    }

    func resume() {
        lock.withLock {
            guard _isPaused else { return }
            _isPaused = false
            _needsPauseDurationUpdate = true
        }
    }

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            var shouldStartSession = false
            var adjusted = CMTime.invalid

            lock.lock()
            guard _isCapturing, !_failed else { lock.unlock(); return }
            if !_sessionStarted {
                _sessionStartTime = timestamp
                _sessionStarted = true
                shouldStartSession = true
            }
            guard resolvePauseStateLocked(sampleTime: timestamp) else { lock.unlock(); return }
            adjusted = adjustedTimeLocked(timestamp)
            lock.unlock()

            if shouldStartSession {
                writer.startSession(atSourceTime: .zero)
            }

            guard adjusted >= .zero, isHealthy(), videoInput.isReadyForMoreMediaData else { return }

            if adaptor.append(pixelBuffer, withPresentationTime: adjusted) {
                lock.withLock { _latestAdjustedTime = adjusted }
            } else {
                _ = isHealthy()
            }
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer, isMicrophone: Bool = false) {
        autoreleasepool {
            let input = isMicrophone ? micInput : audioInput
            guard let input else { return }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            lock.lock()
            guard _isCapturing, _sessionStarted, !_isPaused, !_failed else { lock.unlock(); return }
            let adjusted = adjustedTimeLocked(timestamp)
            lock.unlock()

            guard adjusted >= .zero,
                  isHealthy(),
                  input.isReadyForMoreMediaData,
                  let retimed = Self.retime(sampleBuffer, to: adjusted) else { return }

            if !input.append(retimed) {
                _ = isHealthy()
            }
        }
    }

    private func adjustedTimeLocked(_ time: CMTime) -> CMTime {
        var adjusted = time
        if let start = _sessionStartTime { adjusted = CMTimeSubtract(adjusted, start) }
        if _totalPauseDuration > .zero { adjusted = CMTimeSubtract(adjusted, _totalPauseDuration) }
        return adjusted
    }

    private func resolvePauseStateLocked(sampleTime: CMTime) -> Bool {
        if _isPaused {
            if _pauseStartTime == nil { _pauseStartTime = sampleTime }
            return false
        }
        if _needsPauseDurationUpdate {
            if let pauseStart = _pauseStartTime {
                _totalPauseDuration = CMTimeAdd(_totalPauseDuration, CMTimeSubtract(sampleTime, pauseStart))
                _pauseStartTime = nil
            }
            _needsPauseDurationUpdate = false
        }
        return true
    }

    private func isHealthy() -> Bool {
        guard writer.status == .failed else { return true }
        lock.withLock { _failed = true }
        return false
    }

    private static func retime(_ sampleBuffer: CMSampleBuffer, to newPTS: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        return status == noErr ? newBuffer : nil
    }

    func finishInputs() {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
    }

    func finishWriting() async -> Bool {
        guard writer.status == .writing else { return hasUsableFootage }
        await writer.finishWriting()
        return writer.status == .completed && hasUsableFootage
    }

    private var hasUsableFootage: Bool {
        lock.withLock { _sessionStarted && _latestAdjustedTime.seconds > 0.1 }
    }

    func cancelWriting() {
        guard writer.status == .writing else { return }
        writer.cancelWriting()
    }
}
