import Foundation

nonisolated struct RecordingStudioSourceConfiguration: Sendable {
    let id: UUID
    let configuration: RecordingStudioExporter.Configuration
}

/// Resolves project time through an authored source timeline, then into its raw movie.
nonisolated enum RecordingStudioSourceResolver {
    struct Location: Equatable, Sendable {
        let sourceID: UUID
        let clipID: UUID
        let sourceEditorTime: TimeInterval
        let rawSourceTime: TimeInterval
    }

    enum ResolutionError: LocalizedError {
        case invalidSources
        case missingSource
        case nestedProject
        case durationChanged
        case invalidDocument

        var errorDescription: String? {
            switch self {
            case .invalidSources: "The project's recording sources are invalid."
            case .missingSource: "A recording source is missing. Restore the project's source files and reopen it."
            case .nestedProject: "A recording source cannot itself contain multiple recordings."
            case .durationChanged: "A recording source's duration no longer matches this project."
            case .invalidDocument: "A recording source's saved edits could not be read. Restore its edit document and reopen the project."
            }
        }
    }

    static func location(
        at editorTime: TimeInterval,
        timeline: RecordingClipTimeline,
        sources: [RecordingStudioSourceConfiguration]
    ) -> Location? {
        guard editorTime.isFinite, editorTime >= 0, editorTime <= timeline.duration,
              let outer = timeline.location(at: editorTime),
              let clip = timeline.segments.first(where: { $0.id == outer.segmentID }),
              let sourceID = clip.sourceID,
              let source = sources.first(where: { $0.id == sourceID }),
              let inner = source.configuration.clipTimeline.location(at: outer.sourceTime) else {
            return nil
        }
        return Location(sourceID: sourceID, clipID: outer.segmentID,
                        sourceEditorTime: outer.sourceTime, rawSourceTime: inner.sourceTime)
    }

    @MainActor
    static func configurations(
        for sources: [RecordingProjectSource],
        in project: RecordingSession
    ) async throws -> [RecordingStudioSourceConfiguration] {
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count else {
            throw ResolutionError.invalidSources
        }
        var result: [RecordingStudioSourceConfiguration] = []
        for source in sources {
            try Task.checkCancellation()
            try source.validatePackage(in: project.directoryURL)
            let directory = source.sessionDirectory(in: project.directoryURL)
            guard RecordingSession.isSessionDirectory(directory) else {
                throw ResolutionError.missingSource
            }
            let session = RecordingSession(directoryURL: directory)
            let document: RecordingEditDocument?
            if FileManager.default.fileExists(atPath: session.editDocumentURL.path) {
                do {
                    document = try JSONDecoder().decode(RecordingEditDocument.self,
                                                       from: Data(contentsOf: session.editDocumentURL))
                } catch { throw ResolutionError.invalidDocument }
            } else {
                document = nil
            }
            guard document?.sources == nil else { throw ResolutionError.nestedProject }
            let configuration = try await RecordingSessionRenderer.configuration(for: session, document: document)
            guard source.duration.isFinite, source.duration > 0,
                  abs(configuration.clipTimeline.duration - source.duration) < 0.001 else {
                throw ResolutionError.durationChanged
            }
            result.append(RecordingStudioSourceConfiguration(id: source.id, configuration: configuration))
        }
        return result
    }
}
