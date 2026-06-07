import AppIntents
import UniformTypeIdentifiers

/// Starts a fullscreen recording the same way the `⌘⇧2` shortcut does — including the
/// floating status bar and whatever audio settings are configured in Settings > Recording.
struct StartScreenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Screen Recording"
    static var description = IntentDescription(
        "Starts recording your screen with BetterShot's current recording settings."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !ScreenRecordingManager.shared.isRecording else {
            throw BetterShotIntentError.alreadyRecording
        }

        let started = (try? await ScreenRecordingManager.shared.startFullScreenRecording()) ?? false
        guard started else {
            throw BetterShotIntentError.recordingFailed
        }

        RecordingStatusBarController.shared.show()
        return .result()
    }
}

/// Stops the active recording and returns the resulting MP4 so it can be chained into
/// other Shortcuts steps (e.g. saved, shared, or sent for transcription).
struct StopScreenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Screen Recording"
    static var description = IntentDescription(
        "Stops the active BetterShot screen recording and returns the recorded video."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard ScreenRecordingManager.shared.isRecording else {
            throw BetterShotIntentError.notRecording
        }

        guard let url = await ScreenRecordingManager.shared.stopRecording() else {
            throw BetterShotIntentError.recordingFailed
        }

        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .mpeg4Movie
        let file = IntentFile(data: data, filename: url.lastPathComponent, type: type)
        return .result(value: file)
    }
}
