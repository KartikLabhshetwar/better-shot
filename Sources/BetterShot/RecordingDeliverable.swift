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
    private static var saveTasks: [URL: Task<URL, Error>] = [:]

    static func saveToDefaultLocation(for mediaURL: URL) async throws -> URL {
        let key = (session(for: mediaURL)?.directoryURL ?? mediaURL).standardizedFileURL
        if let task = saveTasks[key] { return try await task.value }
        let task = Task {
            let deliverable = try await resolve(for: mediaURL)
            let session = session(for: mediaURL)
            let suggestedFileName = session.map { fileName(for: $0, extension: deliverable.pathExtension) }
                ?? ScreenshotFileNaming.currentFileName(extension: deliverable.pathExtension, kind: .recording)
            return try await save(deliverable, named: suggestedFileName, for: session, replacingExport: true)
        }
        saveTasks[key] = task
        defer { saveTasks.removeValue(forKey: key) }
        return try await task.value
    }

    /// Writes over the recording's saved file, in that file's format, when `replacingExport` finds one.
    /// Otherwise writes a new file to the save folder, which later saves replace.
    static func save(_ deliverable: URL, named fileName: String, for session: RecordingSession?, replacingExport: Bool) async throws -> URL {
        if replacingExport, let session, let existing = exportURL(for: session) {
            try await VideoFileActions.save(from: deliverable, to: existing)
            return existing
        }
        let savedURL = try await VideoFileActions.saveToDefaultLocation(from: deliverable, suggestedFileName: fileName)
        session?.updateProjectMetadata { $0.exportPath = savedURL.path }
        return savedURL
    }

    /// The file the recording was last saved or exported to, while it is still there.
    static func exportURL(for session: RecordingSession) -> URL? {
        guard let path = session.loadProjectMetadata()?.exportPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The recording's name, carrying `pathExtension`. It is rendered from the
    /// template once, when the recording is made, and kept in the package, so
    /// every Save and Export reuses it. Packages from older builds are named on
    /// their first save and keep that name. The package folder is not renamed.
    static func fileName(for session: RecordingSession, extension pathExtension: String) -> String {
        let name: String
        if let stored = session.loadProjectMetadata()?.fileName {
            name = stored
        } else {
            name = ScreenshotFileNaming.currentFileName(extension: pathExtension, kind: .recording)
            session.updateProjectMetadata { $0.fileName = name }
        }
        return ScreenshotFileNaming.fileName(of: URL(fileURLWithPath: name), extension: pathExtension)
    }

    /// The recording's name without an extension, for Share, drag-out, and
    /// tooltips. Only the stored name's own extension is dropped.
    static func name(for session: RecordingSession) -> String {
        // Any extension works here: it is appended, then dropped again.
        URL(fileURLWithPath: fileName(for: session, extension: "mp4")).deletingPathExtension().lastPathComponent
    }

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
