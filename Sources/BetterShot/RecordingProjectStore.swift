//
//  RecordingProjectStore.swift
//  BetterShot
//
//  The Projects browser's model. Recording packages on disk are the source
//  of truth - not history.json - so a project whose History row was deleted
//  is still reachable, and a package deleted in Finder disappears here.
//

import AppKit
import AVFoundation
import Observation

struct RecordingProjectSummary: Identifiable, Equatable {
    let session: RecordingSession
    var displayName: String
    var createdAt: Date
    var duration: TimeInterval
    var pixelSize: CGSize
    /// Committed with an explicit save at least once.
    var isSaved: Bool
    /// Autosaved edits sitting on top of the saved state.
    var hasUnsavedDraft: Bool
    var sizeOnDisk: Int64
    var lastOpenedAt: Date?

    var id: URL { session.directoryURL }

    /// Orders both the Recordings menu and the browser's default sort:
    /// what you touched last, falling back to when it was recorded.
    var lastActivityAt: Date { lastOpenedAt ?? createdAt }

    var hasCamera: Bool { session.hasCamera }
}

@MainActor
@Observable
final class RecordingProjectStore {
    static let shared = RecordingProjectStore()

    private(set) var projects: [RecordingProjectSummary] = []

    /// Deliberately empty until something asks. Summarizing every package
    /// walks the Recordings folder, which is not worth doing at launch when
    /// most sessions never open the Recordings menu.
    private init() {}

    var totalSizeOnDisk: Int64 {
        projects.reduce(0) { $0 + $1.sizeOnDisk }
    }

    /// The Recordings menu shows only a handful; the rest live in the window.
    var recentProjects: [RecordingProjectSummary] {
        Array(projects.prefix(8))
    }

    func reload() {
        projects = RecordingSessionStore.allSessions()
            .map(Self.summarize)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func rename(_ project: RecordingProjectSummary, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.session.updateProjectMetadata {
            // An emptied field falls back to the folder name rather than
            // leaving the project nameless.
            $0.displayName = trimmed.isEmpty ? nil : trimmed
        }
        reload()
    }

    /// Removes the package, the History row, and any preview card together, so
    /// no surface can disagree about whether a recording exists. The card goes
    /// first, while its files are still on disk.
    func delete(_ session: RecordingSession) {
        ScreenshotPreviewStack.shared.dismissRecordingSession(session.directoryURL)
        ScreenshotHistoryStore.shared.deleteRecordingSession(session)
        RecordingSessionStore.deleteSession(session)
        reload()
    }

    func delete(_ project: RecordingProjectSummary) {
        delete(project.session)
    }

    func reveal(_ project: RecordingProjectSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([project.session.directoryURL])
    }

    // MARK: - Posters

    /// A cached first frame, written into the package so the browser doesn't
    /// decode video every time it opens.
    static func poster(for session: RecordingSession) async -> NSImage? {
        if let cached = NSImage(contentsOf: session.posterURL) {
            return cached
        }
        // Prefer the flattened deliverable when there is one: it shows the
        // background and camera, which is what the project actually looks like.
        let source = session.existingFinalURL ?? session.screenURL
        guard let image = await VideoPreviewImageLoader.thumbnail(at: source, maxPixelSize: 640) else {
            return nil
        }
        writePoster(image, to: session.posterURL)
        return image
    }

    private static func writePoster(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
        else {
            return
        }
        try? jpeg.write(to: url, options: .atomic)
    }

    // MARK: - Summaries

    private static func summarize(_ session: RecordingSession) -> RecordingProjectSummary {
        let manifest = session.loadCaptureManifest()
        let metadata = session.loadProjectMetadata()
        let folderCreatedAt = try? session.directoryURL
            .resourceValues(forKeys: [.creationDateKey])
            .creationDate
        let createdAt = manifest?.createdAt ?? folderCreatedAt ?? Date.distantPast

        return RecordingProjectSummary(
            session: session,
            displayName: session.displayName,
            createdAt: createdAt,
            duration: manifest?.duration ?? 0,
            pixelSize: CGSize(
                width: manifest?.pixelWidth ?? 0,
                height: manifest?.pixelHeight ?? 0
            ),
            isSaved: session.hasSavedProject,
            hasUnsavedDraft: session.hasUnsavedDraft,
            sizeOnDisk: sizeOnDisk(of: session.directoryURL),
            lastOpenedAt: metadata?.lastOpenedAt
        )
    }

    private static func sizeOnDisk(of directoryURL: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

/// Opening a project has to reach the `VIDEO_EDITOR` scene from AppKit-hosted
/// surfaces (the menu bar extra, the Projects window), which have no scene
/// environment of their own. `BetterShotApp` installs the opener, mirroring
/// what `PreviewPanelPresenter.onEditVideo` already does.
@MainActor
final class RecordingProjectOpener {
    static let shared = RecordingProjectOpener()

    var openHandler: ((URL) -> Void)?

    private init() {}

    func open(_ session: RecordingSession) {
        RecordingProjectStore.shared.reload()
        openHandler?(session.directoryURL)
    }
}

/// Knows which Studio windows are currently holding uncommitted edits, so
/// quitting can say so.
@MainActor
final class StudioProjectRegistry {
    static let shared = StudioProjectRegistry()

    private var models: [ObjectIdentifier: WeakModel] = [:]

    private struct WeakModel {
        weak var model: RecordingStudioModel?
    }

    private init() {}

    func register(_ model: RecordingStudioModel) {
        models[ObjectIdentifier(model)] = WeakModel(model: model)
    }

    func unregister(_ model: RecordingStudioModel) {
        models.removeValue(forKey: ObjectIdentifier(model))
    }

    var unsavedProjectCount: Int {
        models.values.compactMap(\.model).filter(\.hasUnsavedChanges).count
    }

    /// Called before the app goes away. The autosave is debounced, so without
    /// this a quit can drop the last fraction of a second of edits.
    func flushDrafts() {
        for model in models.values.compactMap(\.model) {
            model.flushDraft()
        }
    }
}
