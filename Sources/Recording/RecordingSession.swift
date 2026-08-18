import AVFoundation
import CoreMedia

final class RecordingSession: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let micMixer: MicrophoneMixer?
    private let systemAudioIsTimeline: Bool

    private let lock = NSLock()
    private var _isCapturing = false
    private var _firstTimestamp: CMTime?
    private var _sessionStarted = false

    var isCapturing: Bool {
        get { lock.withLock { _isCapturing } }
        set { lock.withLock { _isCapturing = newValue } }
    }

    init(outputURL: URL, width: Int, height: Int, fps: Int, includeAudio: Bool, includeMicrophone: Bool) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * fps * 4,
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

        if includeAudio || includeMicrophone {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        micMixer = includeMicrophone ? MicrophoneMixer() : nil
        systemAudioIsTimeline = includeAudio
    }

    func startWriting() -> Bool {
        writer.startWriting()
        return writer.status == .writing
    }

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let shouldStartSession: Bool

        lock.lock()
        guard _isCapturing else { lock.unlock(); return }
        if !_sessionStarted {
            _firstTimestamp = timestamp
            _sessionStarted = true
            shouldStartSession = true
        } else {
            shouldStartSession = false
        }
        lock.unlock()

        if shouldStartSession {
            writer.startSession(atSourceTime: timestamp)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              videoInput.isReadyForMoreMediaData else { return }

        adaptor.append(pixelBuffer, withPresentationTime: timestamp)
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isWithinSession(sampleBuffer) else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }

        if let micMixer, let mixed = micMixer.mix(into: sampleBuffer) {
            audioInput.append(mixed)
        } else {
            audioInput.append(sampleBuffer)
        }
    }

    /// With system audio on, the mic queues behind it and is summed in on the system
    /// clock. With system audio off there is no timeline to ride, so the mic is written
    /// straight to the track.
    func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        guard let micMixer, isCapturing else { return }

        if systemAudioIsTimeline {
            micMixer.enqueue(sampleBuffer)
            return
        }

        guard isWithinSession(sampleBuffer) else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard let sample = micMixer.standaloneSample(from: sampleBuffer) else { return }
        audioInput.append(sample)
    }

    private func isWithinSession(_ sampleBuffer: CMSampleBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard _isCapturing, _sessionStarted else { return false }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let first = _firstTimestamp, timestamp >= first else { return false }
        return true
    }

    func finishInputs() {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
    }

    func finishWriting() async {
        await writer.finishWriting()
    }

    func cancelWriting() {
        writer.cancelWriting()
    }
}
