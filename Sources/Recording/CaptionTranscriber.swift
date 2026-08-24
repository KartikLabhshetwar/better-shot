import AVFoundation
import Foundation
import Speech

nonisolated enum CaptionTranscriptionError: LocalizedError {
    case notAuthorized
    case noAudio
    case unavailable
    case failed(Error?)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "BetterShot needs permission to use speech recognition. Turn it on in System Settings, Privacy & Security, Speech Recognition."
        case .noAudio:
            "This recording has no audio track to transcribe."
        case .unavailable:
            "Speech recognition is not available for your language right now."
        case let .failed(error):
            error?.localizedDescription ?? "The recording could not be transcribed."
        }
    }
}

/// Turns the recording's own audio into timed cues, on device where the Mac supports it so nothing leaves the machine.
nonisolated enum CaptionTranscriber {
    static func transcribe(_ videoURL: URL) async throws -> [CaptionCue] {
        guard await authorize() else { throw CaptionTranscriptionError.notAuthorized }

        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        return CaptionCue.grouped(try await recognize(audioURL))
    }

    private static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    private static func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else {
            throw CaptionTranscriptionError.noAudio
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptionTranscriptionError.failed(nil)
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bettershot-captions-\(UUID().uuidString).m4a")
        session.outputURL = outputURL
        session.outputFileType = .m4a
        await session.export()

        guard session.status == .completed else { throw CaptionTranscriptionError.failed(session.error) }
        return outputURL
    }

    private static func recognize(_ audioURL: URL) async throws -> [SpokenWord] {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw CaptionTranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            let box = ResumeOnce(continuation)
            box.hold(recognizer)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.fail(CaptionTranscriptionError.failed(error))
                } else if let result, result.isFinal {
                    box.finish(result.bestTranscription.segments.map {
                        SpokenWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                    })
                }
            }
            box.hold(task)
        }
    }
}

/// Speech can call back more than once, and a continuation may only be resumed once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[SpokenWord], Error>?
    private var held: [AnyObject] = []

    init(_ continuation: CheckedContinuation<[SpokenWord], Error>) {
        self.continuation = continuation
    }

    /// The recognizer and its task have to outlive this call or Speech tears the job down before it answers.
    func hold(_ object: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil else { return }
        held.append(object)
    }

    func finish(_ words: [SpokenWord]) {
        take()?.resume(returning: words)
    }

    func fail(_ error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<[SpokenWord], Error>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = continuation
        continuation = nil
        held = []
        return pending
    }
}
