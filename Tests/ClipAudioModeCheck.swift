import AVFoundation
import AppKit
import CoreVideo

@main
enum ClipAudioModeCheck {
    static let fps: Int32 = 30
    static let seconds = 6
    static let width = 320
    static let height = 240
    static let tone = 440.0
    static let sampleRate = 44_100.0

    static func makeVideo(at url: URL) throws {
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
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
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

    static func makeAudio(at url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ])
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(sampleRate)
        for second in 0..<seconds {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            guard let data = buffer.floatChannelData?[0] else { continue }
            for frame in 0..<Int(frames) {
                let t = Double(second) + Double(frame) / sampleRate
                data[frame] = Float(sin(2 * .pi * tone * t) * 0.4)
            }
            try file.write(from: buffer)
        }
    }

    static func decode(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ])
        reader.add(output)
        precondition(reader.startReading(), "audio reader failed: \(String(describing: reader.error))")

        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: length / 4))
            }
        }
        return samples
    }

    static func slice(_ samples: [Float], from start: Double, to end: Double) -> ArraySlice<Float> {
        let lower = min(samples.count, Int(start * sampleRate))
        let upper = min(samples.count, Int(end * sampleRate))
        guard lower < upper else { return [] }
        return samples[lower..<upper]
    }

    static func rms(_ window: ArraySlice<Float>) -> Double {
        guard !window.isEmpty else { return 0 }
        return (window.reduce(0.0) { $0 + Double($1 * $1) } / Double(window.count)).squareRoot()
    }

    /// Hysteresis around zero so decoder noise cannot fake a crossing on a clean sine.
    static func frequency(_ window: ArraySlice<Float>) -> Double {
        guard window.count > 1 else { return 0 }
        let gate: Float = 0.08
        var crossings = 0
        var armed = false
        for value in window {
            if value < -gate { armed = true }
            if armed, value > gate {
                crossings += 1
                armed = false
            }
        }
        return Double(crossings) / (Double(window.count) / sampleRate)
    }

    static func run() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-audio-mode-check-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let videoURL = dir.appendingPathComponent("source.mp4")
        let audioURL = dir.appendingPathComponent("source.m4a")
        let outputURL = dir.appendingPathComponent("out.mp4")
        try makeVideo(at: videoURL)
        try makeAudio(at: audioURL)

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio)[0]

        let clips = [
            Clip(sourceStart: 0, sourceEnd: 2, speed: 1, audioMode: .mute),
            Clip(sourceStart: 2, sourceEnd: 4, speed: 2, audioMode: .maintainPitch),
            Clip(sourceStart: 4, sourceEnd: 6, speed: 2, audioMode: .matchSpeed)
        ]
        let built = try ClipCompositionBuilder.makeComposition(
            videoTrack: videoTrack,
            audioTracks: [audioTrack],
            camera: nil,
            clips: clips
        )

        precondition(built.audioMix != nil, "two pitch modes are in play, so the builder owes us an audio mix")
        precondition(
            built.composition.tracks(withMediaType: .audio).count == 2,
            "each pitch algorithm needs its own track, got \(built.composition.tracks(withMediaType: .audio).count)"
        )
        let timeline = ClipTimeline(clips: clips)
        precondition(abs(timeline.duration - 4) < 0.01, "expected a 4s timeline, got \(timeline.duration)")
        precondition(timeline.audioMode(atSourceTime: 3) == .maintainPitch, "clip lookup landed on the wrong clip")
        precondition(timeline.audioMode(atSourceTime: 5) == .matchSpeed, "clip lookup landed on the wrong clip")

        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: built.composition.duration)
        let compVideo = built.composition.tracks(withMediaType: .video)[0]
        instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)]
        videoComposition.instructions = [instruction]

        try await VideoFrameExporter().export(
            VideoFrameExporter.Configuration(
                composition: built.composition,
                videoComposition: videoComposition,
                canvasSize: canvas,
                cardRect: CGRect(origin: .zero, size: canvas),
                cornerRadius: 0,
                backgroundStyle: .none,
                shadowStrength: 0,
                outputURL: outputURL,
                audioMix: built.audioMix
            ),
            progress: { _ in }
        )

        let samples = try await decode(outputURL)
        precondition(samples.count > Int(3.5 * sampleRate), "exported audio is too short: \(samples.count) samples")

        let muted = rms(slice(samples, from: 0.3, to: 1.7))
        let kept = slice(samples, from: 2.2, to: 2.8)
        let matched = slice(samples, from: 3.2, to: 3.8)

        precondition(rms(kept) > 0.05, "the maintain-pitch clip should be audible, RMS \(rms(kept))")
        precondition(muted < rms(kept) * 0.1, "the muted clip leaked audio: RMS \(muted) against \(rms(kept))")

        let keptHz = frequency(kept)
        let matchedHz = frequency(matched)
        precondition(abs(keptHz - tone) < 60, "maintain-pitch must hold \(tone) Hz at 2x, measured \(keptHz)")
        precondition(abs(matchedHz - tone * 2) < 120, "match-speed must double to \(tone * 2) Hz at 2x, measured \(matchedHz)")

        print("clip audio: muted clip silent, keep-pitch \(Int(keptHz)) Hz, match-speed \(Int(matchedHz)) Hz")
    }

    static func main() async throws {
        try await run()
    }
}
