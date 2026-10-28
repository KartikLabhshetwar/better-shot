import AVFoundation
import Foundation

@testable import BetterShot

@MainActor
func checkRecordingMultiSourceModel(movieURL: URL) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("multi-model-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func fixture(_ name: String, timeline: RecordingClipTimeline) throws -> RecordingSession {
        let session = RecordingSession(directoryURL: directory.appendingPathComponent(name + ".bettershotrec"))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        try session.writeEditDocument(RecordingEditDocument(style: RecordingStudioDefaults.style,
            zoomEnabled: false, zoomCues: [], clipTimeline: timeline))
        return session
    }
    let rootTimeline = RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceStart: 0.2, sourceEnd: 1.2, speed: 2),
        RecordingClipSegment(sourceStart: 1.5, sourceEnd: 2.5)
    ])
    let root = try fixture("Root", timeline: rootTimeline)
    let incoming = try fixture("Incoming", timeline: RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceStart: 0.5, sourceEnd: 2.5, speed: 0.5)
    ]))
    let incomingBytes = try Data(contentsOf: incoming.editDocumentURL)
    let movieBytes = try Data(contentsOf: root.screenURL)
    let model = RecordingStudioModel(url: root.directoryURL)
    await model.load()
    precondition(model.isLoaded)
    let baseline = model.currentEditDocument
    let corruptDocument = Data("{broken".utf8)
    for documentURL in [incoming.editDocumentURL, incoming.draftDocumentURL] {
        try corruptDocument.write(to: documentURL, options: .atomic)
        do {
            let corruptAppend = try await model.prepareAppendRecording(from: incoming.directoryURL)
            corruptAppend.discard()
            preconditionFailure("Existing corrupt authored edits must not become default edits")
        } catch RecordingStudioSourceResolver.ResolutionError.invalidDocument {}
        let retainedCorruption = try Data(contentsOf: documentURL)
        precondition(retainedCorruption == corruptDocument && model.currentEditDocument == baseline && !model.isMultiSource)
        if documentURL == incoming.editDocumentURL {
            try incomingBytes.write(to: documentURL, options: .atomic)
        } else {
            try FileManager.default.removeItem(at: documentURL)
        }
    }
    let pending = try await model.prepareAppendRecording(from: incoming.directoryURL)
    precondition(!model.isMultiSource && model.currentEditDocument == baseline,
                 "Async preparation must not change the root document")
    let rejectedDirectories = pending.document.sources!.map { $0.sessionDirectory(in: root.directoryURL) }
    model.style.padding += 0.01
    let rejection = model.commitAppendRecording(pending, expectedRevision: pending.revision)
    guard case .failed = rejection else { preconditionFailure("Stale append must fail") }
    precondition(rejectedDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    model.style = baseline.style.value

    let prepared = try await model.prepareAppendRecording(from: incoming.directoryURL)
    defer { prepared.discard() }
    precondition(model.commitAppendRecording(prepared, expectedRevision: prepared.revision) == .changed)
    let promoted = model.currentEditDocument
    precondition(model.isMultiSource && promoted.sources?.count == 2 && promoted.sourceDocuments?.count == 2)
    precondition(Array(model.clipTimeline.segments.prefix(2).map(\.id)) == rootTimeline.segments.map(\.id))
    precondition(model.clipTimeline.segments[0].sourceStart == 0 && model.clipTimeline.segments[0].sourceEnd == 0.5)
    precondition(model.clipTimeline.segments[1].sourceStart == 0.5 && model.clipTimeline.segments[1].sourceEnd == 1.5)
    precondition(model.clipTimeline.segments.allSatisfy { $0.speed == 1 }, "Authored speed must not be applied twice")
    precondition(abs(model.duration - 5.5) < 0.001 && model.makeExportConfiguration().sources.count == 2)
    let installed = promoted.sources!.map { $0.sessionDirectory(in: root.directoryURL) }
    model.undo()
    precondition(!model.isMultiSource && model.currentEditDocument == baseline, "Undo promotion restores the complete legacy document")
    precondition(installed.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Redo retains managed media")
    model.redo()
    precondition(model.currentEditDocument == promoted)
    guard case .saved = model.saveProject() else { preconditionFailure("Multi-source save must succeed") }
    model.teardown()

    let reopened = RecordingStudioModel(url: root.directoryURL)
    await reopened.load()
    precondition(reopened.isLoaded && reopened.currentEditDocument == promoted && !reopened.hasUnsavedChanges)
    let order = reopened.clipTimeline.segments.map(\.id)
    precondition(reopened.reorderClips(ids: Array(order.reversed())) == .changed)
    precondition(reopened.clipTimeline.segments.map(\.id) == Array(order.reversed()))
    let reorderedRevision = reopened.editRevision
    guard case .failed = reopened.reorderClips(ids: [order[0], order[0], order[1]]) else {
        preconditionFailure("Reorder must reject duplicate or missing clips")
    }
    precondition(reopened.editRevision == reorderedRevision)
    reopened.undo()
    precondition(reopened.clipTimeline.segments.map(\.id) == order)
    reopened.redo()
    let discarded = await reopened.discardChanges()
    precondition(discarded && reopened.currentEditDocument == promoted && !reopened.hasUnsavedChanges)
    reopened.teardown()

    let effects = RecordingStudioModel(url: root.directoryURL)
    await effects.load()
    defer { effects.teardown() }
    let source = effects.projectSources!.last!
    let leafSession = RecordingSession(directoryURL: source.sessionDirectory(in: root.directoryURL))
    let immutableLeaf = try Data(contentsOf: leafSession.editDocumentURL)
    var authored = effects.sourceDocuments![source.id]!
    var sourceStyle = authored.style.value
    sourceStyle.padding = 0.14
    authored.style = StoredRecordingStudioStyle(sourceStyle)
    authored.crop = [0.1, 0.1, 0.7, 0.6]
    let applied = await effects.applySourceDocument(authored, sourceID: source.id, expectedRevision: effects.editRevision)
    precondition(applied == .changed)
    precondition(effects.sourceConfigurations.last?.configuration.style.padding == 0.14)
    precondition(effects.sourceConfigurations.last?.configuration.crop == authored.cropValue)
    effects.undo()
    precondition(effects.currentEditDocument == promoted)
    effects.redo()
    precondition(effects.sourceDocuments?[source.id] == authored)
    var retimed = authored
    retimed.clips?[0].speed = 2
    let rejected = await effects.applySourceDocument(retimed, sourceID: source.id, expectedRevision: effects.editRevision)
    guard case .failed = rejected else { preconditionFailure("Leaf clock edits must use the outer timeline") }
    effects.flushDraft()
    precondition(root.loadDraftDocument()?.sourceDocuments?[source.id] == authored)
    guard case .saved = effects.saveProject() else { preconditionFailure("Source effects save must succeed") }
    precondition(root.loadEditDocument()?.sourceDocuments?[source.id] == authored)
    let unchangedLeaf = try Data(contentsOf: leafSession.editDocumentURL)
    let unchangedIncoming = try Data(contentsOf: incoming.editDocumentURL)
    let unchangedMovie = try Data(contentsOf: root.screenURL)
    precondition(unchangedLeaf == immutableLeaf && unchangedIncoming == incomingBytes && unchangedMovie == movieBytes)

    let child = RecordingStudioModel(url: leafSession.directoryURL, embeddedDocument: authored, isEmbeddedSource: true)
    await child.load()
    precondition(child.isLoaded && child.style.padding == 0.14 && child.cropRect == authored.cropValue)
    precondition(child.splitClip(at: 1) == .unchanged)
    child.style.padding = 0.16
    precondition(child.saveProject() == .unavailable)
    child.flushDraft()
    child.teardown()
    let childLeaf = try Data(contentsOf: leafSession.editDocumentURL)
    precondition(!leafSession.hasUnsavedDraft && childLeaf == immutableLeaf)

    let encoded = try JSONEncoder().encode(effects.currentEditDocument)
    let roundTrip = try JSONDecoder().decode(RecordingEditDocument.self, from: encoded)
    precondition(roundTrip == effects.currentEditDocument)
    let legacy = try JSONDecoder().decode(RecordingEditDocument.self, from: JSONEncoder().encode(baseline))
    precondition(legacy.sourceDocuments == nil && legacy.sources == nil)
    var nested = authored
    nested.sourceDocuments = [source.id: authored]
    var invalid = effects.currentEditDocument
    invalid.sourceDocuments?[source.id] = nested
    do {
        try invalid.validateSourceDocuments()
        preconditionFailure("Nested snapshots must be rejected")
    } catch {}
    invalid = effects.currentEditDocument
    invalid.sourceDocuments?[UUID()] = authored
    do {
        try invalid.validateSourceDocuments()
        preconditionFailure("Unknown source snapshot IDs must be rejected")
    } catch {}
    print("PASS native promotion/append/reorder/source effects, root undo/draft/save/reopen, and rejected-stage cleanup")
}
