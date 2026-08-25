//
//  RecordingTranscriptEditing.swift
//  BetterShot
//
//  Planning for transcript-driven video edits: turns word selections,
//  filler words, and narration silences into source-time cut ranges for
//  RecordingClipTimeline.removingSourceRanges. Pure functions over the
//  word list so the studio model stays the single place that mutates the
//  timeline.
//

import Foundation

nonisolated enum TranscriptEditPlanner {
    /// Hesitation sounds safe to cut without changing meaning. Deliberately
    /// conservative: discourse words like "like" or "so" stay.
    private static let fillerSpellings: Set<String> = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "uhmm",
        "er", "erm", "hmm", "hm", "hmmm", "mhm", "mmm",
    ]

    /// A word cut bites up to this far into the silence around it, so the
    /// splice lands in the pause instead of clipping a neighboring word.
    private static let maximumWordPadding: TimeInterval = 0.12

    /// Narration pauses longer than this are considered dead air.
    static let silenceThreshold: TimeInterval = 1.1
    /// Breathing room kept on each side of a silence cut.
    private static let silencePadding: TimeInterval = 0.35
    /// Silence cuts shorter than this aren't worth a splice.
    private static let minimumSilenceCut: TimeInterval = 0.3

    static func isFiller(_ word: RecordingTranscriptWord) -> Bool {
        let normalized = word.displayText
            .lowercased()
            .filter(\.isLetter)
        return fillerSpellings.contains(normalized)
    }

    static func fillerIndices(in words: [RecordingTranscriptWord]) -> [Int] {
        words.indices.filter { isFiller(words[$0]) }
    }

    /// Source range that removes the words at `range`, biting into the
    /// surrounding silence but never into a neighboring word.
    static func cutRange(
        forWordsAt range: ClosedRange<Int>,
        in words: [RecordingTranscriptWord],
        sourceDuration: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard range.lowerBound >= 0, range.upperBound < words.count else { return nil }
        let first = words[range.lowerBound]
        let last = words[range.upperBound]

        let previousEnd = range.lowerBound > 0 ? words[range.lowerBound - 1].end : 0
        let nextStart = range.upperBound < words.count - 1
            ? words[range.upperBound + 1].start
            : sourceDuration

        let gapBefore = max(0, first.start - previousEnd)
        let gapAfter = max(0, nextStart - last.end)
        let start = max(0, first.start - min(maximumWordPadding, gapBefore / 2))
        let end = min(sourceDuration, last.end + min(maximumWordPadding, gapAfter / 2))
        guard end > start else { return nil }
        return start...end
    }

    /// One cut range per filler word; overlaps collapse when merged.
    static func fillerCutRanges(
        in words: [RecordingTranscriptWord],
        sourceDuration: TimeInterval
    ) -> [ClosedRange<TimeInterval>] {
        fillerIndices(in: words).compactMap {
            cutRange(forWordsAt: $0...$0, in: words, sourceDuration: sourceDuration)
        }
    }

    /// Cuts for every narration pause longer than the threshold, including
    /// dead air before the first word and after the last. Each cut keeps a
    /// natural beat of silence on both sides of the splice.
    static func silenceCutRanges(
        in words: [RecordingTranscriptWord],
        sourceDuration: TimeInterval
    ) -> [ClosedRange<TimeInterval>] {
        guard !words.isEmpty, sourceDuration > 0 else { return [] }

        var gaps: [(start: TimeInterval, end: TimeInterval)] = []
        var spokenEnd: TimeInterval = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            if word.start > spokenEnd {
                gaps.append((spokenEnd, word.start))
            }
            spokenEnd = max(spokenEnd, word.end)
        }
        if sourceDuration > spokenEnd {
            gaps.append((spokenEnd, sourceDuration))
        }

        return gaps.compactMap { gap in
            guard gap.end - gap.start > silenceThreshold else { return nil }
            let start = gap.start + silencePadding
            let end = gap.end - silencePadding
            guard end - start >= minimumSilenceCut else { return nil }
            return start...end
        }
    }
}
