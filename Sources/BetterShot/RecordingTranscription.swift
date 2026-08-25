//
//  RecordingTranscription.swift
//  BetterShot
//
//  Narration subtitles for the recording studio: SpeechAnalyzer (the
//  macOS 26 on-device transcription engine) turns the recorded microphone
//  track into timed subtitle cues on the source timeline. The timeline and
//  bar metrics are shared verbatim by the live preview and the offline
//  exporter, exactly like the keystroke caption.
//

import AVFoundation
import CoreGraphics
import Foundation
import Speech

/// One transcribed word on the source (unedited) timeline, in seconds.
/// `text` keeps the transcript's original trailing punctuation/spacing so
/// concatenating words reconstructs the transcript exactly.
nonisolated struct RecordingTranscriptWord: Codable, Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval

    /// Word as shown in the transcript editor, without the glued spacing.
    var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var midpoint: TimeInterval {
        (start + end) / 2
    }
}

/// A full transcription: the word-level timing (drives transcript-based
/// video editing) plus the readable cues derived from it (drive the
/// subtitle bar).
nonisolated struct RecordingTranscript: Sendable {
    var words: [RecordingTranscriptWord]
    var cues: [RecordingSubtitleCue]
}

/// One subtitle on the source (unedited) timeline, in seconds.
nonisolated struct RecordingSubtitleCue: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Cues saved before editing shipped carry no identity; mint one so
        // the editor's list rows stay stable for this session.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
    }
}

/// User-adjustable subtitle appearance. The bar is always center-locked
/// horizontally; only its height position and text size are editable.
nonisolated struct SubtitleBarStyle: Sendable, Equatable {
    static let verticalRange: ClosedRange<Double> = 0.1...0.95
    static let fontScaleRange: ClosedRange<Double> = 0.6...1.8

    /// Normalized (0...1, top-left origin) center of the bar along the
    /// card's height.
    var verticalPosition: Double = 0.92
    /// Multiplier on the default font size (which the paddings and corner
    /// radius derive from, so the whole bar scales together).
    var fontScale: Double = 1
    /// Karaoke mode: the word being spoken renders in the accent color.
    /// Needs word-level timings; the bar falls back to plain cues without.
    var highlightsSpokenWord: Bool = false

    var clampedVerticalPosition: Double {
        min(max(verticalPosition, Self.verticalRange.lowerBound), Self.verticalRange.upperBound)
    }

    var clampedFontScale: Double {
        min(max(fontScale, Self.fontScaleRange.lowerBound), Self.fontScaleRange.upperBound)
    }
}

// MARK: - Subtitle timeline

/// Deterministic subtitle playback: the cue covering a source time, if any.
nonisolated struct SubtitleTimeline: Sendable, Equatable {
    private let cues: [RecordingSubtitleCue]

    static let empty = SubtitleTimeline(cues: [])

    init(cues: [RecordingSubtitleCue]) {
        self.cues = cues
            .filter { $0.start.isFinite && $0.end > $0.start && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
    }

    var isEmpty: Bool {
        cues.isEmpty
    }

    var count: Int {
        cues.count
    }

    func text(at time: TimeInterval) -> String? {
        cue(at: time)?.text
    }

    func cue(at time: TimeInterval) -> RecordingSubtitleCue? {
        guard !cues.isEmpty, time.isFinite else { return nil }

        // Last cue that has already started.
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0 else { return nil }

        let cue = cues[index]
        return time < cue.end ? cue : nil
    }
}

// MARK: - Karaoke word timing

/// Word-level state of the subtitle bar at a moment in time: the active
/// cue's words plus which one is being spoken. Shared verbatim by the
/// SwiftUI preview and the CoreGraphics exporter so highlights match.
nonisolated struct KaraokeTimeline: Sendable {
    struct Line: Equatable {
        /// Display words of the active cue, original order, trimmed.
        var words: [String]
        /// Index into `words` currently being spoken; nil between words
        /// and after the cue's last word ends.
        var activeIndex: Int?
        /// How many words have started; spoken words render fully lit
        /// even once the active highlight has moved on.
        var spokenCount: Int
    }

    private struct CueLine {
        var start: TimeInterval
        var end: TimeInterval
        /// Display words from the cue's (possibly hand-edited) text.
        var words: [String]
        /// Per-display-word timing, index-mapped from the timed words so
        /// text edits keep working even when word counts drift.
        var timings: [(start: TimeInterval, end: TimeInterval)]
    }

    private let cues: [CueLine]

    static let empty = KaraokeTimeline(cues: [], words: [])

    /// Groups timed words into cues the same way the cues were chunked
    /// from them (a word belongs to the last cue starting at or before
    /// it), but displays the cue's *text* - the editable source of truth -
    /// with timings carried over from the recognizer's words.
    init(cues: [RecordingSubtitleCue], words: [RecordingTranscriptWord]) {
        let sortedCues = cues
            .filter { $0.start.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var timedByCue: [[RecordingTranscriptWord]] = sortedCues.map { _ in [] }
        var cueIndex = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            while cueIndex < sortedCues.count - 1,
                  word.start >= sortedCues[cueIndex + 1].start - 0.001 {
                cueIndex += 1
            }
            if !timedByCue.isEmpty {
                timedByCue[min(cueIndex, timedByCue.count - 1)].append(word)
            }
        }

        self.cues = zip(sortedCues, timedByCue).compactMap { cue, timed in
            guard !timed.isEmpty else { return nil }
            let displayWords = cue.text
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            guard !displayWords.isEmpty else { return nil }
            let timings = displayWords.indices.map { index in
                let timedIndex = min(
                    timed.count - 1,
                    index * timed.count / displayWords.count
                )
                return (start: timed[timedIndex].start, end: timed[timedIndex].end)
            }
            return CueLine(
                start: cue.start,
                end: cue.end,
                words: displayWords,
                timings: timings
            )
        }
    }

    var isEmpty: Bool {
        cues.isEmpty
    }

    /// The karaoke line covering a source time; nil when nobody is
    /// speaking or the cue carries no word timings.
    func line(at time: TimeInterval) -> Line? {
        guard !cues.isEmpty, time.isFinite else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0, time < cues[index].end else { return nil }

        let cue = cues[index]
        var activeIndex: Int?
        var spokenCount = 0
        if let lastStarted = cue.timings.lastIndex(where: { $0.start <= time }) {
            spokenCount = lastStarted + 1
            let timing = cue.timings[lastStarted]
            // The highlight rides each word until the next one starts; on
            // the cue's last word a small bridge past its end keeps it from
            // flickering off early, after which the line reads fully spoken.
            if lastStarted < cue.timings.count - 1 || time <= timing.end + 0.25 {
                activeIndex = lastStarted
            }
        }
        return Line(
            words: cue.words,
            activeIndex: activeIndex,
            spokenCount: spokenCount
        )
    }
}

// MARK: - Subtitle bar metrics

/// Geometry shared verbatim by the SwiftUI preview and the CoreGraphics
/// exporter: a rounded black bar with white text, center-locked
/// horizontally at the style's vertical position. Everything derives from
/// the full canvas height - the bar belongs to the composition, background
/// included, not just the recording card - so it is identical at any
/// render resolution and stays put in padded or portrait layouts.
nonisolated struct SubtitleBarMetrics: Sendable {
    let fontSize: CGFloat
    let paddingHorizontal: CGFloat
    let paddingVertical: CGFloat
    let cornerRadius: CGFloat

    static let backgroundAlpha: Double = 0.78

    /// Karaoke palette, shared by preview and export: the spoken word in
    /// warm yellow, words not yet spoken slightly dimmed.
    static let karaokeAccent = CGColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    static let karaokeUpcomingAlpha: Double = 0.55

    /// Widest the bar may grow, as a fraction of the canvas width; text
    /// that would exceed it wraps into centered lines.
    static let maximumWidthFraction: CGFloat = 0.92
    /// Wrapped lines allowed before the font starts scaling down.
    static let maximumLineCount = 3
    /// Baseline-to-baseline advance as a multiple of ascent + descent,
    /// shared by the preview's lineSpacing and the exporter's layout.
    static let lineSpacingFactor: CGFloat = 1.12

    /// Sized off the canvas's smaller dimension: identical to the old
    /// height-based sizing in landscape, and keeps the bar inside narrow
    /// portrait/square canvases.
    init(canvasSize: CGSize, style: SubtitleBarStyle = SubtitleBarStyle()) {
        let reference = min(canvasSize.width, canvasSize.height)
        fontSize = max(11, reference * 0.032 * style.clampedFontScale)
        paddingHorizontal = fontSize * 0.85
        paddingVertical = fontSize * 0.5
        cornerRadius = fontSize * 0.6
    }

    /// Room available for the text line itself on this canvas.
    func maximumTextWidth(canvasWidth: CGFloat) -> CGFloat {
        max(24, canvasWidth * Self.maximumWidthFraction - paddingHorizontal * 2)
    }
}

// MARK: - Transcription service

nonisolated enum RecordingTranscriptionService {
    enum TranscriptionError: LocalizedError {
        case noNarrationTrack
        case unsupportedLocale
        case narrationUnreadable
        case noSpeechDetected

        var errorDescription: String? {
            switch self {
            case .noNarrationTrack:
                "This recording has no microphone audio to transcribe."
            case .unsupportedLocale:
                "On-device transcription isn't available for your language yet."
            case .narrationUnreadable:
                "The narration audio could not be read."
            case .noSpeechDetected:
                "No speech was detected in the narration."
            }
        }
    }

    /// A subtitle should stay readable at a glance, so speech is chunked
    /// into short cues at natural pauses rather than whole sentences.
    private static let maximumCueCharacters = 42
    private static let maximumCueDuration: TimeInterval = 4
    private static let cueGapThreshold: TimeInterval = 0.9
    private static let minimumCueDuration: TimeInterval = 0.8

    static func transcribe(screenMovieURL: URL) async throws -> RecordingTranscript {
        let narrationURL = try await extractNarrationAudio(from: screenMovieURL)
        defer { try? FileManager.default.removeItem(at: narrationURL) }

        let locale = try await resolveLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: narrationURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Result collection must be consuming before audio is fed in, or the
        // analyzer's early results are dropped on the floor.
        async let collectedWords = collectWords(from: transcriber)
        if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let words = try await collectedWords
        let cues = makeCues(from: words)
        guard !cues.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return RecordingTranscript(words: words, cues: cues)
    }

    /// Best transcription locale for the user's language; on-device models
    /// are per-locale, so an unsupported language has to fail loudly rather
    /// than produce gibberish English cues. Also used by the live
    /// teleprompter, which tracks the same narration as it is spoken.
    static func resolveLocale() async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if let exact = supported.first(where: {
            $0.identifier(.bcp47) == current.identifier(.bcp47)
        }) {
            return exact
        }
        if let sameLanguage = supported.first(where: {
            $0.language.languageCode == current.language.languageCode
        }) {
            return sameLanguage
        }
        if let english = supported.first(where: { $0.language.languageCode?.identifier == "en" }) {
            return english
        }
        throw TranscriptionError.unsupportedLocale
    }

    /// Pulls the narration out of the screen movie into a standalone audio
    /// file. The recorder writes system audio as stereo and the microphone
    /// as mono, so the mono track is the narration whenever both exist.
    /// Track timing is preserved so cue timestamps stay on the movie's
    /// timeline.
    private static func extractNarrationAudio(from movieURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: movieURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard var narrationTrack = audioTracks.last else {
            throw TranscriptionError.noNarrationTrack
        }
        if audioTracks.count > 1 {
            for track in audioTracks {
                let descriptions = try await track.load(.formatDescriptions)
                let channels = descriptions
                    .compactMap { $0.audioStreamBasicDescription?.mChannelsPerFrame }
                    .max() ?? 0
                if channels == 1 {
                    narrationTrack = track
                    break
                }
            }
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TranscriptionError.narrationUnreadable
        }
        let timeRange = try await narrationTrack.load(.timeRange)
        try compositionTrack.insertTimeRange(timeRange, of: narrationTrack, at: timeRange.start)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.narrationUnreadable
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettershot-narration-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try await exportSession.export(to: outputURL, as: .m4a)
        return outputURL
    }

    private static func collectWords(from transcriber: SpeechTranscriber) async throws -> [RecordingTranscriptWord] {
        var words: [RecordingTranscriptWord] = []
        for try await result in transcriber.results where result.isFinal {
            for run in result.text.runs {
                let runText = String(result.text[run.range].characters)
                guard let timeRange = run.audioTimeRange else {
                    // Punctuation and whitespace runs carry no audio range;
                    // glue them onto the previous word so cues keep them.
                    if !words.isEmpty {
                        words[words.count - 1].text += runText
                    }
                    continue
                }
                let start = timeRange.start.seconds
                let end = timeRange.end.seconds
                guard start.isFinite, end.isFinite else { continue }
                words.append(RecordingTranscriptWord(text: runText, start: start, end: max(start, end)))
            }
        }
        return words
    }

    static func makeCues(from words: [RecordingTranscriptWord]) -> [RecordingSubtitleCue] {
        var cues: [RecordingSubtitleCue] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard !trimmed.isEmpty else { return }
            cues.append(RecordingSubtitleCue(
                start: start,
                end: max(end, start + minimumCueDuration),
                text: trimmed
            ))
        }

        for word in words {
            let wordLength = word.text.trimmingCharacters(in: .whitespaces).count
            if !text.isEmpty {
                let breaksOnLength = text.count + wordLength > maximumCueCharacters
                let breaksOnSilence = word.start - end > cueGapThreshold
                let breaksOnDuration = word.end - start > maximumCueDuration
                if breaksOnLength || breaksOnSilence || breaksOnDuration {
                    flush()
                }
            }
            if text.isEmpty {
                start = word.start
                end = word.end
            }
            // Runs keep the transcript's original spacing, so plain
            // concatenation reconstructs the text exactly.
            text += word.text
            end = max(end, word.end)
        }
        flush()
        return cues
    }
}
