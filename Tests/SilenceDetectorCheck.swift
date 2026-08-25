import Foundation

@main
enum SilenceDetectorCheck {
    static func main() {
        let window = 0.05
        let loud: Float = -15
        let quiet: Float = -60

        func levels(_ spans: [(level: Float, seconds: Double)]) -> [Float] {
            spans.flatMap { span in
                [Float](repeating: span.level, count: Int((span.seconds / window).rounded()))
            }
        }

        // MARK: - A long quiet stretch between speech is found, padded inward

        do {
            let ranges = SilenceDetector.silentRanges(
                levels: levels([(loud, 2), (quiet, 3), (loud, 2)]),
                windowDuration: window
            )
            assert(ranges.count == 1, "one silent stretch expected, got \(ranges)")
            let range = ranges[0]
            assert(abs(range.lowerBound - (2 + SilenceDetector.speechPadding)) < window, "silence must start padded after speech ends, got \(range.lowerBound)")
            assert(abs(range.upperBound - (5 - SilenceDetector.speechPadding)) < window, "silence must end padded before speech resumes, got \(range.upperBound)")
        }

        // MARK: - Short pauses between words survive

        do {
            let ranges = SilenceDetector.silentRanges(
                levels: levels([(loud, 2), (quiet, 0.4), (loud, 2)]),
                windowDuration: window
            )
            assert(ranges.isEmpty, "a breath between words must not be cut, got \(ranges)")
        }

        // MARK: - Leading and trailing silence are both found

        do {
            let ranges = SilenceDetector.silentRanges(
                levels: levels([(quiet, 2), (loud, 3), (quiet, 2)]),
                windowDuration: window
            )
            assert(ranges.count == 2, "silence at both ends must be found, got \(ranges)")
            assert(ranges[0].lowerBound < 1, "leading silence starts near zero")
            assert(ranges[1].upperBound > 6, "trailing silence runs to the end")
        }

        // MARK: - A recording with no speech is left alone

        do {
            let ranges = SilenceDetector.silentRanges(
                levels: levels([(quiet, 10)]),
                windowDuration: window
            )
            assert(ranges.isEmpty, "a recording that never had speech must not be shredded, got \(ranges)")
        }

        // MARK: - The threshold tracks the recording's own speech level

        do {
            let softSpeech: Float = -35
            let roomTone: Float = -70
            let ranges = SilenceDetector.silentRanges(
                levels: levels([(softSpeech, 2), (roomTone, 3), (softSpeech, 2)]),
                windowDuration: window
            )
            assert(ranges.count == 1, "a quiet microphone is judged on its own scale, got \(ranges)")
        }

        assert(SilenceDetector.silentRanges(levels: [], windowDuration: window).isEmpty, "no audio, no ranges")

        print("SilenceDetectorCheck: all assertions passed")
    }
}
