import AVFoundation
import CoreMedia
import Foundation

/// Finds the stretches of a recording where nobody is talking, as source-time ranges ready for `ClipTimeline.removingSourceRanges`. Loudness is measured against the recording's own speech level rather than a fixed floor, so a quiet microphone is judged on its own scale.
nonisolated enum SilenceDetector {
    static let windowDuration: TimeInterval = 0.05
    static let minimumSilenceDuration: TimeInterval = 0.8
    static let speechPadding: TimeInterval = 0.15

    /// How far below the speech level a window must fall to read as silence, in decibels.
    static let silenceMarginDb: Float = 25
    /// A recording whose loudest windows sit below this never had speech, so nothing is cut.
    static let minimumSpeechLevelDb: Float = -45

    private static let sampleRate = 16_000

    static func silentRanges(at url: URL) async -> [ClosedRange<TimeInterval>] {
        let levels = await windowLevels(at: url)
        return silentRanges(levels: levels, windowDuration: windowDuration)
    }

    static func silentRanges(
        levels: [Float],
        windowDuration: TimeInterval,
        minimumSilenceDuration: TimeInterval = SilenceDetector.minimumSilenceDuration,
        speechPadding: TimeInterval = SilenceDetector.speechPadding
    ) -> [ClosedRange<TimeInterval>] {
        guard levels.count > 1, windowDuration > 0 else { return [] }

        let sorted = levels.sorted()
        let speechLevel = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        guard speechLevel > minimumSpeechLevelDb else { return [] }
        let threshold = speechLevel - silenceMarginDb

        var ranges: [ClosedRange<TimeInterval>] = []
        var runStart: Int?
        for index in 0...levels.count {
            if index < levels.count, levels[index] < threshold {
                if runStart == nil { runStart = index }
                continue
            }
            guard let start = runStart else { continue }
            runStart = nil
            let lower = Double(start) * windowDuration + speechPadding
            let upper = Double(index) * windowDuration - speechPadding
            if upper - lower >= minimumSilenceDuration {
                ranges.append(lower...upper)
            }
        }
        return ranges
    }

    /// One decibel reading per window, from all audio tracks mixed down to mono. Runs on the concurrent executor because the reader loop blocks while it decodes.
    private static func windowLevels(at url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let reader = try? AVAssetReader(asset: asset) else { return [] }

        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let samplesPerWindow = max(1, Int(Double(sampleRate) * windowDuration))
        var levels: [Float] = []
        var sumOfSquares = 0.0
        var count = 0

        func flushWindow() {
            let rms = (sumOfSquares / Double(count)).squareRoot()
            levels.append(Float(20 * log10(max(rms, 1e-5))))
            sumOfSquares = 0
            count = 0
        }

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= MemoryLayout<Float>.size else { continue }
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let copied = floats.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            guard copied == noErr else { continue }
            for value in floats {
                sumOfSquares += Double(value) * Double(value)
                count += 1
                if count == samplesPerWindow { flushWindow() }
            }
        }
        if count > 0 { flushWindow() }
        return levels
    }
}
