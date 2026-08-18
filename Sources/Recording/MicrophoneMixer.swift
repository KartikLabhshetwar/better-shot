import AVFoundation
import CoreMedia

/// Sums microphone frames onto the system-audio timeline so both sources land on a
/// single audio track. Two tracks in one MP4 was the rejected alternative: QuickTime
/// mixes them but ffmpeg, browsers and most players take the first track only, which
/// would drop the voice-over for whoever the recording is sent to.
///
/// System audio is the clock master. The FIFO absorbs mic jitter, and an underrun is
/// zero-filled rather than shifting the track, so the voice never slides out of sync
/// with the picture.
final class MicrophoneMixer: @unchecked Sendable {
    private static let sampleRate: Double = 48_000
    private static let channelCount: AVAudioChannelCount = 2

    private let canonicalFormat: AVAudioFormat
    private let maxPendingSamples: Int

    private let lock = NSLock()
    private var pending: [Float] = []

    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init?() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: true
        ) else { return nil }
        canonicalFormat = format
        maxPendingSamples = Int(Self.sampleRate * 2) * Int(Self.channelCount)
    }

    // MARK: - Intake

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard let converted = canonicalBuffer(from: sampleBuffer),
              let channelData = converted.floatChannelData else { return }

        let sampleCount = Int(converted.frameLength) * Int(Self.channelCount)
        let samples = UnsafeBufferPointer(start: channelData[0], count: sampleCount)

        lock.lock()
        pending.append(contentsOf: samples)
        if pending.count > maxPendingSamples {
            pending.removeFirst(pending.count - maxPendingSamples)
        }
        lock.unlock()
    }

    // MARK: - Output

    /// Returns `nil` when no microphone frames are waiting, letting the caller append
    /// the untouched system buffer instead of paying for a rebuild.
    func mix(into sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        let micSamples = dequeue(frameCount: frameCount)
        guard !micSamples.isEmpty else { return nil }

        guard let system = pcmBuffer(from: sampleBuffer),
              let channelData = system.floatChannelData else { return nil }

        let frames = Int(system.frameLength)
        let channels = Int(system.format.channelCount)

        if system.format.isInterleaved {
            let output = channelData[0]
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    output[index] = clamp(output[index] + micSample(micSamples, frame: frame, channel: channel))
                }
            }
        } else {
            for channel in 0..<channels {
                let output = channelData[channel]
                for frame in 0..<frames {
                    output[frame] = clamp(output[frame] + micSample(micSamples, frame: frame, channel: channel))
                }
            }
        }

        return makeSampleBuffer(from: system, timedLike: sampleBuffer)
    }

    /// Microphone-only recordings have no system stream to ride, so the mic becomes the
    /// timeline itself.
    func standaloneSample(from sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let converted = canonicalBuffer(from: sampleBuffer) else { return nil }
        return makeSampleBuffer(from: converted, timedLike: sampleBuffer)
    }

    // MARK: - FIFO

    private func dequeue(frameCount: Int) -> [Float] {
        let needed = frameCount * Int(Self.channelCount)

        lock.lock()
        defer { lock.unlock() }

        guard !pending.isEmpty else { return [] }

        let available = min(needed, pending.count)
        var samples = Array(pending[0..<available])
        pending.removeFirst(available)

        if samples.count < needed {
            samples.append(contentsOf: repeatElement(0, count: needed - samples.count))
        }
        return samples
    }

    private func micSample(_ samples: [Float], frame: Int, channel: Int) -> Float {
        let index = frame * Int(Self.channelCount) + min(channel, Int(Self.channelCount) - 1)
        return index < samples.count ? samples[index] : 0
    }

    private func clamp(_ value: Float) -> Float {
        min(1, max(-1, value))
    }

    // MARK: - Format conversion

    private func canonicalBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let source = pcmBuffer(from: sampleBuffer) else { return nil }

        if converter == nil || converterInputFormat != source.format {
            converter = AVAudioConverter(from: source.format, to: canonicalFormat)
            converterInputFormat = source.format
        }
        guard let converter else { return nil }

        let ratio = canonicalFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: capacity) else { return nil }

        let feed = ConverterFeed(source)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard let next = feed.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// `AVAudioConverterInputBlock` is `@Sendable`, but it runs synchronously on the
    /// calling thread for the duration of `convert(to:error:withInputFrom:)`. Boxing the
    /// one-shot buffer satisfies Swift 6 concurrency checking without claiming a
    /// non-Sendable `AVAudioPCMBuffer` crosses threads, which it does not.
    private final class ConverterFeed: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }

        var asbd = streamDescription.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }

    private func makeSampleBuffer(from buffer: AVAudioPCMBuffer, timedLike source: CMSampleBuffer) -> CMSampleBuffer? {
        var asbd = buffer.format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(source),
            decodeTimeStamp: .invalid
        )

        var created: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &created
        ) == noErr, let created else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            created,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: buffer.audioBufferList
        ) == noErr else { return nil }

        return created
    }
}
