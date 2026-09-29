import Foundation

struct RecordingAgentProject: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let duration: TimeInterval
    let width: Double
    let height: Double
    let isOpen: Bool
}

struct RecordingAgentClip: Codable, Equatable, Identifiable {
    let id: UUID
    let sourceStart: TimeInterval
    let sourceEnd: TimeInterval
    let speed: Double
    let editorStart: TimeInterval
    let editorEnd: TimeInterval
}

struct RecordingAgentTimeline: Codable, Equatable {
    let handle: UUID
    let revision: UInt64
    let projectName: String
    let sourceDuration: TimeInterval
    let duration: TimeInterval
    let clips: [RecordingAgentClip]
}

struct RecordingAgentPreview: Codable, Equatable {
    let handle: UUID
    let revision: UInt64
    let editorTime: TimeInterval
    let width: Int
    let height: Int
}

struct RecordingAgentSaveResult: Codable, Equatable {
    let revision: UInt64
    let saved: Bool
}

struct RecordingAgentExportJob: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        case running
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    let handle: UUID
    let revision: UInt64
    let state: State
    let progress: Double
    let fileName: String?
    let error: String?
    let isCurrentRevision: Bool
}

enum RecordingAgentOperationError: Error, LocalizedError {
    case unknownProject
    case projectNotOpen
    case ambiguousProject
    case openTimedOut
    case staleRevision(expected: UInt64, current: UInt64)
    case invalidArgument(String)
    case clipNotFound
    case cannotDeleteLastClip
    case unavailable(String)
    case unknownExportJob

    var code: String {
        switch self {
        case .unknownProject: "unknown_project"
        case .projectNotOpen: "project_not_open"
        case .ambiguousProject: "ambiguous_project"
        case .openTimedOut: "open_timed_out"
        case .staleRevision: "stale_revision"
        case .invalidArgument: "invalid_argument"
        case .clipNotFound: "clip_not_found"
        case .cannotDeleteLastClip: "cannot_delete_last_clip"
        case .unavailable: "operation_unavailable"
        case .unknownExportJob: "unknown_export_job"
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownProject: "The project is not in BetterShot’s recording library."
        case .projectNotOpen: "Open the project in BetterShot before editing it."
        case .ambiguousProject: "More than one editor window has this project open. Close the duplicate window and retry."
        case .openTimedOut: "BetterShot did not finish opening the project in time."
        case let .staleRevision(expected, current):
            "The project changed. Expected revision \(expected), current revision is \(current). Inspect it again before editing."
        case let .invalidArgument(message), let .unavailable(message): message
        case .clipNotFound: "The clip no longer exists. Inspect the timeline again."
        case .cannotDeleteLastClip: "A project must retain at least one playable clip."
        case .unknownExportJob: "The export job is no longer available."
        }
    }
}

/// Narrow, revision-checked operations over the existing Studio model. Project
/// IDs are minted from the recording library and never accept caller paths.
@MainActor
final class RecordingAgentOperations {
    static let shared = RecordingAgentOperations()

    private struct ExportJobRecord {
        let handle: UUID
        let revision: UInt64
        let runID: UUID
    }

    private struct ExportRequestRecord: Equatable {
        let handle: UUID
        let revision: UInt64
        let jobID: UUID
    }

    private var knownProjects: [UUID: URL] = [:]
    private var projectIDsByURL: [URL: UUID] = [:]
    private var exportJobs: [UUID: ExportJobRecord] = [:]
    private var exportJobOrder: [UUID] = []
    private var exportRequests: [UUID: ExportRequestRecord] = [:]

    private init() {}

    func listProjects() -> [RecordingAgentProject] {
        let sessions = RecordingSessionStore.allSessions()
        let liveURLs = Set(sessions.map { $0.directoryURL.standardizedFileURL })
        for (id, url) in knownProjects where !liveURLs.contains(url) {
            knownProjects.removeValue(forKey: id)
            projectIDsByURL.removeValue(forKey: url)
        }

        return sessions.map { session in
            let url = session.directoryURL.standardizedFileURL
            let id = projectIDsByURL[url] ?? UUID()
            projectIDsByURL[url] = id
            knownProjects[id] = url
            let manifest = session.loadCaptureManifest()
            return RecordingAgentProject(
                id: id,
                name: session.displayName,
                duration: manifest?.duration ?? 0,
                width: Double(manifest?.pixelWidth ?? 0),
                height: Double(manifest?.pixelHeight ?? 0),
                isOpen: StudioProjectRegistry.shared.hasOpenProject(for: url)
            )
        }
    }

    func openProject(id: UUID) async throws -> RecordingAgentTimeline {
        guard let url = knownProjects[id], RecordingSession.isSessionDirectory(url),
              RecordingSessionStore.allSessions().contains(where: {
                  $0.directoryURL.standardizedFileURL == url
              }) else {
            throw RecordingAgentOperationError.unknownProject
        }

        let registry = StudioProjectRegistry.shared
        if registry.hasOpenProject(for: url) {
            let snapshots = registry.snapshots(for: url)
            guard snapshots.count == 1, let snapshot = snapshots.first else {
                throw RecordingAgentOperationError.ambiguousProject
            }
            return try inspect(handle: snapshot.handle)
        }

        RecordingProjectOpener.shared.open(RecordingSession(directoryURL: url))
        for _ in 0..<100 {
            try Task.checkCancellation()
            if registry.hasOpenProject(for: url) {
                let snapshots = registry.snapshots(for: url)
                guard snapshots.count == 1, let snapshot = snapshots.first else {
                    throw RecordingAgentOperationError.ambiguousProject
                }
                return try inspect(handle: snapshot.handle)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RecordingAgentOperationError.openTimedOut
    }

    func inspect(handle: UUID) throws -> RecordingAgentTimeline {
        guard let snapshot = StudioProjectRegistry.shared.snapshot(for: handle),
              let model = StudioProjectRegistry.shared.model(for: handle) else {
            throw RecordingAgentOperationError.projectNotOpen
        }
        try requireUniqueEditor(for: model, handle: handle)
        let clips = model.clipTimeline.segments.compactMap { segment -> RecordingAgentClip? in
            guard let range = model.clipTimeline.editorRange(for: segment.id) else { return nil }
            return RecordingAgentClip(
                id: segment.id,
                sourceStart: segment.sourceStart,
                sourceEnd: segment.sourceEnd,
                speed: segment.speed,
                editorStart: range.lowerBound,
                editorEnd: range.upperBound
            )
        }
        return RecordingAgentTimeline(
            handle: snapshot.handle,
            revision: snapshot.revision,
            projectName: model.projectDisplayName,
            sourceDuration: model.sourceDuration,
            duration: model.clipTimeline.duration,
            clips: clips
        )
    }

    func preview(handle: UUID, expectedRevision: UInt64, at editorTime: TimeInterval) async throws -> (metadata: RecordingAgentPreview, png: Data) {
        guard editorTime.isFinite, editorTime >= 0 else {
            throw RecordingAgentOperationError.invalidArgument("Preview time must be a nonnegative timeline time.")
        }
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard editorTime <= model.clipTimeline.duration else {
            throw RecordingAgentOperationError.invalidArgument("Preview time is past the end of the timeline.")
        }
        let captured = StudioProjectRegistry.shared.snapshot(for: handle)
        guard let captured, captured.revision == expectedRevision else {
            throw RecordingAgentOperationError.staleRevision(expected: expectedRevision, current: model.editRevision)
        }
        let configuration = model.makeExportConfiguration()
        let rendered: (data: Data, size: CGSize)
        do {
            rendered = try await RecordingStudioExporter.previewPNG(
                configuration: configuration,
                editorTime: editorTime
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RecordingAgentOperationError.unavailable("BetterShot could not render this preview. Check the Studio window and retry.")
        }
        try Task.checkCancellation()
        let latestEditors = StudioProjectRegistry.shared.snapshots(for: model.sessionURL)
        guard latestEditors.count == 1,
              let latest = latestEditors.first,
              latest.handle == captured.handle,
              latest.revision == captured.revision else {
            throw RecordingAgentOperationError.staleRevision(
                expected: expectedRevision,
                current: StudioProjectRegistry.shared.snapshot(for: handle)?.revision ?? model.editRevision
            )
        }
        return (
            RecordingAgentPreview(
                handle: handle,
                revision: captured.revision,
                editorTime: editorTime,
                width: Int(rendered.size.width),
                height: Int(rendered.size.height)
            ),
            rendered.data
        )
    }

    @discardableResult
    func split(handle: UUID, expectedRevision: UInt64, at editorTime: TimeInterval) throws -> RecordingAgentTimeline {
        guard editorTime.isFinite, editorTime >= 0 else {
            throw RecordingAgentOperationError.invalidArgument("The split time must be a nonnegative timeline time.")
        }
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard model.clipTimeline.split(at: editorTime) != nil else {
            throw RecordingAgentOperationError.invalidArgument("The split must leave at least 0.12 seconds on both sides of the cut.")
        }
        try requireChanged(model.splitClip(at: editorTime))
        return try inspect(handle: handle)
    }

    @discardableResult
    func trim(
        handle: UUID,
        expectedRevision: UInt64,
        clipID: UUID,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval
    ) throws -> RecordingAgentTimeline {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard let index = model.clipTimeline.segments.firstIndex(where: { $0.id == clipID }) else {
            throw RecordingAgentOperationError.clipNotFound
        }
        guard sourceStart.isFinite, sourceEnd.isFinite,
              sourceEnd - sourceStart >= RecordingClipSegment.minimumDuration,
              sourceStart >= 0, sourceEnd <= model.sourceDuration else {
            throw RecordingAgentOperationError.invalidArgument("The trim must be a valid source range at least 0.12 seconds long.")
        }
        let segments = model.clipTimeline.segments
        let lowerLimit = index == segments.startIndex ? 0 : segments[segments.index(before: index)].sourceEnd
        let upperLimit = index == segments.index(before: segments.endIndex)
            ? model.sourceDuration : segments[segments.index(after: index)].sourceStart
        guard sourceStart >= lowerLimit, sourceEnd <= upperLimit else {
            throw RecordingAgentOperationError.invalidArgument("The trim cannot overlap a neighboring clip.")
        }
        var replacement = segments[index]
        replacement.sourceStart = sourceStart
        replacement.sourceEnd = sourceEnd
        try requireChanged(model.trimClip(replacement))
        return try inspect(handle: handle)
    }

    @discardableResult
    func deleteClip(handle: UUID, expectedRevision: UInt64, clipID: UUID) throws -> RecordingAgentTimeline {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard model.clipTimeline.segments.contains(where: { $0.id == clipID }) else {
            throw RecordingAgentOperationError.clipNotFound
        }
        guard model.clipTimeline.segments.count > 1 else {
            throw RecordingAgentOperationError.cannotDeleteLastClip
        }
        model.selectClip(id: clipID)
        try requireChanged(model.deleteSelectedClip())
        return try inspect(handle: handle)
    }

    @discardableResult
    func setSpeed(
        handle: UUID,
        expectedRevision: UInt64,
        clipID: UUID,
        speed: Double
    ) throws -> RecordingAgentTimeline {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard model.clipTimeline.segments.contains(where: { $0.id == clipID }) else {
            throw RecordingAgentOperationError.clipNotFound
        }
        guard speed.isFinite,
              (RecordingClipSegment.minimumSpeed...RecordingClipSegment.maximumSpeed).contains(speed) else {
            throw RecordingAgentOperationError.invalidArgument("Clip speed must be between 0.25× and 8×.")
        }
        guard !model.clipSpeedDraft.hasActiveEdit else {
            throw RecordingAgentOperationError.unavailable("Finish the current clip speed adjustment before using timeline operations.")
        }
        try requireChanged(model.setClipSpeed(speed, forClipID: clipID))
        return try inspect(handle: handle)
    }

    @discardableResult
    func undo(handle: UUID, expectedRevision: UInt64) throws -> RecordingAgentTimeline {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard model.canUndo else { throw RecordingAgentOperationError.unavailable("There is no edit to undo.") }
        let revision = model.editRevision
        model.undo()
        guard model.editRevision != revision else {
            throw RecordingAgentOperationError.unavailable("Undo could not be applied to the current timeline.")
        }
        return try inspect(handle: handle)
    }

    @discardableResult
    func redo(handle: UUID, expectedRevision: UInt64) throws -> RecordingAgentTimeline {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard model.canRedo else { throw RecordingAgentOperationError.unavailable("There is no edit to redo.") }
        let revision = model.editRevision
        model.redo()
        guard model.editRevision != revision else {
            throw RecordingAgentOperationError.unavailable("Redo could not be applied to the current timeline.")
        }
        return try inspect(handle: handle)
    }

    func save(handle: UUID, expectedRevision: UInt64) throws -> RecordingAgentSaveResult {
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        switch model.saveProject() {
        case let .saved(revision): return RecordingAgentSaveResult(revision: revision, saved: true)
        case .unavailable: throw RecordingAgentOperationError.projectNotOpen
        case .failed:
            throw RecordingAgentOperationError.unavailable("Could not save the project. Check the Save status in BetterShot and retry.")
        }
    }

    func startExport(handle: UUID, expectedRevision: UInt64, requestID: UUID) throws -> RecordingAgentExportJob {
        if let prior = exportRequests[requestID] {
            guard prior.handle == handle, prior.revision == expectedRevision else {
                throw RecordingAgentOperationError.invalidArgument("This request ID was already used for a different export request.")
            }
            return try exportJob(id: prior.jobID)
        }
        let model = try checkedModel(handle: handle, revision: expectedRevision)
        guard !model.exportState.isExporting, !model.shareState.isBusy else {
            throw RecordingAgentOperationError.unavailable("An export is already running for this project.")
        }
        guard let runID = model.export() else {
            throw RecordingAgentOperationError.unavailable("BetterShot could not start the export.")
        }
        let id = UUID()
        exportJobs[id] = ExportJobRecord(handle: handle, revision: expectedRevision, runID: runID)
        exportRequests[requestID] = ExportRequestRecord(handle: handle, revision: expectedRevision, jobID: id)
        exportJobOrder.append(id)
        while exportJobOrder.count > 16 {
            let removedID = exportJobOrder.removeFirst()
            exportJobs.removeValue(forKey: removedID)
            exportRequests = exportRequests.filter { $0.value.jobID != removedID }
        }
        return try exportJob(id: id)
    }

    func exportJob(id: UUID) throws -> RecordingAgentExportJob {
        guard let record = exportJobs[id],
              let model = StudioProjectRegistry.shared.model(for: record.handle) else {
            throw RecordingAgentOperationError.unknownExportJob
        }
        guard let exportState = model.exportState(for: record.runID) else {
            throw RecordingAgentOperationError.unknownExportJob
        }
        let state: RecordingAgentExportJob.State
        let progress: Double
        var fileName: String?
        var error: String?
        switch exportState {
        case .idle:
            state = .cancelled
            progress = 0
        case let .exporting(value):
            state = .running
            progress = min(max(value, 0), 1)
        case let .finished(url):
            state = .completed
            progress = 1
            fileName = url.lastPathComponent
        case .failed:
            state = .failed
            progress = 0
            // The local error can include an absolute path. Keep it in the
            // Studio UI, but return only safe retry guidance to the agent.
            error = "Export failed in BetterShot. Check the Studio window and retry."
        }
        return RecordingAgentExportJob(
            id: id,
            handle: record.handle,
            revision: record.revision,
            state: state,
            progress: progress,
            fileName: fileName,
            error: error,
            isCurrentRevision: model.editRevision == record.revision
        )
    }

    func cancelExportJob(id: UUID) throws -> RecordingAgentExportJob {
        guard let record = exportJobs[id],
              let model = StudioProjectRegistry.shared.model(for: record.handle) else {
            throw RecordingAgentOperationError.unknownExportJob
        }
        if model.currentExportRunID == record.runID, model.exportState.isExporting {
            model.cancelExport()
        }
        return try exportJob(id: id)
    }

    private func checkedModel(handle: UUID, revision: UInt64) throws -> RecordingStudioModel {
        guard let snapshot = StudioProjectRegistry.shared.snapshot(for: handle),
              let model = StudioProjectRegistry.shared.model(for: handle) else {
            throw RecordingAgentOperationError.projectNotOpen
        }
        try requireUniqueEditor(for: model, handle: handle)
        guard snapshot.revision == revision else {
            throw RecordingAgentOperationError.staleRevision(expected: revision, current: snapshot.revision)
        }
        guard !model.isCroppingVideo, !model.isEditingMasks else {
            throw RecordingAgentOperationError.unavailable("Finish or cancel the current crop or mask edit before using timeline operations.")
        }
        return model
    }

    private func requireUniqueEditor(for model: RecordingStudioModel, handle: UUID) throws {
        guard StudioProjectRegistry.shared.snapshots(for: model.sessionURL).count == 1,
              StudioProjectRegistry.shared.snapshot(for: model.sessionURL)?.handle == handle else {
            throw RecordingAgentOperationError.ambiguousProject
        }
    }

    private func requireChanged(_ outcome: RecordingClipEditOutcome) throws {
        switch outcome {
        case .changed: return
        case .unchanged:
            throw RecordingAgentOperationError.unavailable("The requested edit did not change the timeline.")
        case .failed:
            throw RecordingAgentOperationError.unavailable("The timeline could not be rebuilt. Check the Studio window and retry.")
        }
    }
}
