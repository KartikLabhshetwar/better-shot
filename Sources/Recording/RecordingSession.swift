import AVFoundation
import CoreMedia

final class RecordingSession: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?

    private let lock = NSLock()
    private var _isCapturing = false
    private var _firstTimestamp: CMTime?
    private var _sessionStarted = false

    var isCapturing: Bool {
        get { lock.withLock { _isCapturing } }
        set { lock.withLock { _isCapturing = newValue } }
    }

    init(outputURL: URL, width: Int, height: Int, fps: Int, includeAudio: Bool) throws {
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

        if includeAudio {
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
    }

    func startWriting() -> Bool {
        writer.startWriting()
        return writer.status == .writing
    }

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard _isCapturing else { lock.unlock(); return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !_sessionStarted {
            _firstTimestamp = timestamp
            _sessionStarted = true
            writer.startSession(atSourceTime: timestamp)
        }

        lock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              videoInput.isReadyForMoreMediaData else { return }

        adaptor.append(pixelBuffer, withPresentationTime: timestamp)
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard _isCapturing, _sessionStarted else { lock.unlock(); return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let first = _firstTimestamp, timestamp >= first else { lock.unlock(); return }

        lock.unlock()

        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
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
