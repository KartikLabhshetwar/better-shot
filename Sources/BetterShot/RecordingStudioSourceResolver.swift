import CoreGraphics
import Foundation

nonisolated struct RecordingStudioSourceConfiguration: Sendable {
    let id: UUID
    let configuration: RecordingStudioExporter.Configuration
    let presentationAspectRatios: [Double]

    init(id: UUID, configuration: RecordingStudioExporter.Configuration,
         presentationAspectRatios: [Double] = []) {
        self.id = id
        self.configuration = configuration
        self.presentationAspectRatios = presentationAspectRatios
    }

    func fittedCanvasRect(in canvasSize: CGSize) -> CGRect {
        var available = CGRect(origin: .zero, size: canvasSize)
        for aspect in presentationAspectRatios.reversed() {
            let height = min(available.height, available.width / aspect)
            let size = CGSize(width: height * aspect, height: height)
            available = CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                               width: size.width, height: size.height)
        }
        let leaf = configuration.canvasSize
        let scale = min(available.width / leaf.width, available.height / leaf.height)
        let size = CGSize(width: leaf.width * scale, height: leaf.height * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
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

    static func validatedTimeline(_ configuration: RecordingStudioExporter.Configuration) throws -> RecordingClipTimeline {
        let sources = configuration.sources
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count,
              sources.allSatisfy({ $0.configuration.sources.isEmpty &&
                  $0.configuration.clipTimeline.segments.allSatisfy({ $0.sourceID == nil }) }) else {
            throw ResolutionError.invalidSources
        }
        for source in sources {
            try RecordingProjectSource.validatePresentationAspectRatios(source.presentationAspectRatios)
        }
        return try configuration.clipTimeline.validated(sourceDurations: Dictionary(uniqueKeysWithValues:
            sources.map { ($0.id, $0.configuration.clipTimeline.duration) }))
    }

    @MainActor
    static func configurations(
        for sources: [RecordingProjectSource],
        in project: RecordingSession,
        documents: [UUID: RecordingEditDocument]? = nil
    ) async throws -> [RecordingStudioSourceConfiguration] {
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count else {
            throw ResolutionError.invalidSources
        }
        guard documents?.keys.allSatisfy({ id in sources.contains(where: { $0.id == id }) }) != false else {
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
            if let snapshot = documents?[source.id] {
                document = snapshot
            } else if FileManager.default.fileExists(atPath: session.editDocumentURL.path) {
                do {
                    document = try JSONDecoder().decode(RecordingEditDocument.self,
                                                       from: Data(contentsOf: session.editDocumentURL))
                } catch { throw ResolutionError.invalidDocument }
            } else {
                document = nil
            }
            guard document?.sources == nil, document?.sourceDocuments == nil,
                  document?.clips?.contains(where: { $0.sourceID != nil }) != true else {
                throw ResolutionError.nestedProject
            }
            let configuration = try await RecordingSessionRenderer.configuration(for: session, document: document)
            guard source.duration.isFinite, source.duration > 0,
                  abs(configuration.clipTimeline.duration - source.duration) < 0.001 else {
                throw ResolutionError.durationChanged
            }
            result.append(RecordingStudioSourceConfiguration(id: source.id, configuration: configuration,
                presentationAspectRatios: source.presentationAspectRatios ?? []))
        }
        return result
    }
}
