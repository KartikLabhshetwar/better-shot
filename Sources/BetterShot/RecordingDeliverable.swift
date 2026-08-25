//
//  RecordingDeliverable.swift
//  BetterShot
//
//  Screen captures are recorded without the OS cursor (see
//  ScreenRecordingManager.buildConfiguration) and keep the camera as a
//  separate movie, so a session's raw screen master is never what the user
//  saw. Anything that hands a recording to the user - Save, Copy, upload -
//  has to go through here first, or it ships a video with no pointer, no
//  camera bubble, and none of the project's edits.
//

import Foundation

@MainActor
enum RecordingDeliverable {
    /// The session a recording media URL belongs to, if any. Bare movies
    /// opened from disk have none and are already their own deliverable.
    static func session(for mediaURL: URL) -> RecordingSession? {
        let sessionDirectory = mediaURL.deletingLastPathComponent()
        guard RecordingSession.isSessionDirectory(sessionDirectory) else { return nil }
        return RecordingSession(directoryURL: sessionDirectory)
    }

    /// True when resolving will have to encode, so callers can show progress
    /// instead of appearing to hang.
    static func needsRender(for mediaURL: URL) -> Bool {
        guard let session = session(for: mediaURL) else { return false }
        return session.freshFinalURL(matching: session.effectiveEditDocument()) == nil
    }

    /// The file to actually give the user. Renders the flattened deliverable
    /// when one is needed and caches it in the session, so a second Save or a
    /// later upload is a plain copy.
    static func resolve(for mediaURL: URL) async throws -> URL {
        guard let session = session(for: mediaURL) else { return mediaURL }
        guard needsRender(for: mediaURL) else {
            return try await RecordingSessionRenderer.ensureDeliverable(for: session)
        }

        let dockProgressID = DockExportProgressCoordinator.shared.start()
        defer { DockExportProgressCoordinator.shared.finish(dockProgressID) }
        return try await RecordingSessionRenderer.ensureDeliverable(for: session) { progress in
            Task { @MainActor in
                DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
            }
        }
    }
}
