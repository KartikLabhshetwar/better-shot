//
//  TeleprompterSpeechEngine.swift
//  BetterShot
//
//  Live narration tracking for the teleprompter: microphone sample buffers
//  are teed off the recording's SCStream (no second capture session), fed
//  into SpeechAnalyzer with volatile results enabled, and every recognizer
//  update is matched against the script. Progress only ever moves forward -
//  a volatile-result retraction must never scroll the prompter backwards
//  while someone is mid-sentence.
//
//  The engine is best-effort by design: if the model asset is missing, the
//  locale unsupported, or the analyzer dies, the teleprompter simply stops
//  auto-advancing. It never interferes with the recording itself.
//

@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import Speech

nonisolated final class TeleprompterSpeechEngine: @unchecked Sendable {
    private let matcher: TeleprompterScriptMatcher
    /// Called with the (monotonic) count of script display words spoken.
    private let onProgress: @Sendable (Int) -> Void

    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var isPaused = false
    private var isFinished = false
    private var analyzer: SpeechAnalyzer?
    private var analysisTask: Task<Void, Never>?

    init(matcher: TeleprompterScriptMatcher, onProgress: @escaping @Sendable (Int) -> Void) {
        self.matcher = matcher
        self.onProgress = onProgress
    }

    /// Resolves the locale + on-device model before a recording needs it, so
    /// enabling the teleprompter (not pressing Record) pays the download.
    static func preflightAssets() async {
        guard let locale = try? await RecordingTranscriptionService.resolveLocale() else { return }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let installation = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await installation.downloadAndInstall()
        }
    }

    func start() async throws {
        let locale = try await RecordingTranscriptionService.resolveLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CocoaError(.featureUnsupported)
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let alreadyFinished: Bool = lock.withLock {
            guard !isFinished else { return true }
            self.continuation = inputContinuation
            self.analyzerFormat = format
            self.analyzer = analyzer
            return false
        }
        if alreadyFinished {
            // The recording ended while the model was still downloading.
            inputContinuation.finish()
            return
        }

        analysisTask = Task { [matcher, onProgress] in
            // Finalized segments accumulate; the volatile tail is replaced on
            // every update. Matching reruns over the whole history so revised
            // guesses converge instead of compounding.
            var finalizedWords: [String] = []
            var reported = 0

            func report(_ spoken: [String]) {
                let count = matcher.spokenDisplayWordCount(spoken: spoken)
                guard count > reported else { return }
                reported = count
                onProgress(count)
            }

            do {
                for try await result in transcriber.results {
                    let words = TeleprompterScriptText.normalizedWords(
                        String(result.text.characters)
                    )
                    if result.isFinal {
                        finalizedWords.append(contentsOf: words)
                        report(finalizedWords)
                    } else {
                        report(finalizedWords + words)
                    }
                }
            } catch {
                // Recognition died; the prompter stays put and the recording
                // is unaffected.
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Called on the recording's audio sample queue for every microphone
    /// buffer. Must stay cheap: convert, yield, return.
    func ingest(_ sampleBuffer: CMSampleBuffer) {
        let (continuation, format): (AsyncStream<AnalyzerInput>.Continuation?, AVAudioFormat?) = lock.withLock {
            guard !isPaused, !isFinished else { return (nil, nil) }
            return (self.continuation, self.analyzerFormat)
        }
        guard let continuation, let format else { return }
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        guard let converted = convert(buffer, to: format) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func setPaused(_ paused: Bool) {
        lock.withLock { isPaused = paused }
    }

    /// Tears the session down without waiting for trailing results - the
    /// overlay is collapsing anyway.
    func finish() {
        let (continuation, analyzer, task): (
            AsyncStream<AnalyzerInput>.Continuation?,
            SpeechAnalyzer?,
            Task<Void, Never>?
        ) = lock.withLock {
            let values = (self.continuation, self.analyzer, self.analysisTask)
            isFinished = true
            self.continuation = nil
            self.analyzer = nil
            self.analysisTask = nil
            return values
        }
        continuation?.finish()
        Task {
            await analyzer?.cancelAndFinishNow()
            task?.cancel()
        }
    }

    // MARK: - Audio plumbing

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio else {
            return nil
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format {
            return buffer
        }

        let converter: AVAudioConverter? = lock.withLock {
            if let existing = self.converter,
               existing.inputFormat == buffer.format,
               existing.outputFormat == format {
                return existing
            }
            let fresh = AVAudioConverter(from: buffer.format, to: format)
            self.converter = fresh
            return fresh
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        nonisolated(unsafe) let inputBuffer = buffer
        nonisolated(unsafe) var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
