//
//  TeleprompterController.swift
//  BetterShot
//
//  Glue between the recording lifecycle and the teleprompter: decides
//  whether a starting recording gets the overlay, owns the live speech
//  engine for the session, and tears both down on every finish path.
//  The engine is optional - no microphone means the script still shows,
//  it just doesn't auto-advance.
//

import CoreGraphics
import Foundation

@MainActor
final class TeleprompterController {
    static let shared = TeleprompterController()

    /// The session's live tracker. Read once when the recording wires its
    /// audio callback, so the sample-queue tee never touches the main actor.
    private(set) var activeEngine: TeleprompterSpeechEngine?
    private var hasPreflightedAssets = false

    private init() {}

    /// Kicks off the on-device model download when the user enables the
    /// teleprompter, so pressing Record never waits on an install.
    func preflightAssets() {
        guard !hasPreflightedAssets else { return }
        hasPreflightedAssets = true
        Task.detached {
            await TeleprompterSpeechEngine.preflightAssets()
        }
    }

    func beginRecordingSession(displayID: CGDirectDisplayID?, microphoneActive: Bool) {
        endRecordingSession()

        guard BetterShotPreferences.recordingTeleprompterEnabled else { return }
        let script = BetterShotPreferences.recordingTeleprompterScript
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        TeleprompterOverlayPresenter.shared.show(script: script, displayID: displayID)

        guard microphoneActive else { return }
        let matcher = TeleprompterScriptMatcher(script: script)
        guard !matcher.isEmpty else { return }

        let engine = TeleprompterSpeechEngine(matcher: matcher) { spokenWordCount in
            Task { @MainActor in
                TeleprompterOverlayPresenter.shared.updateProgress(spokenWordCount: spokenWordCount)
            }
        }
        activeEngine = engine
        Task.detached {
            // Best-effort: a failed engine start leaves a static prompter.
            try? await engine.start()
        }
    }

    func setPaused(_ paused: Bool) {
        activeEngine?.setPaused(paused)
    }

    func endRecordingSession() {
        activeEngine?.finish()
        activeEngine = nil
        TeleprompterOverlayPresenter.shared.hide()
    }
}
