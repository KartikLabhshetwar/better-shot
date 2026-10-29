import AppKit
import AVFoundation
import SwiftUI

@testable import BetterShot

@MainActor
func checkRecordingMultiSourceUI(movieURL: URL) async throws {
    let directory = RecordingSessionStore.recordingsDirectory
    precondition(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func fixture(_ name: String, withAudio: Bool = false) throws -> RecordingSession {
        let session = RecordingSession(directoryURL: directory.appendingPathComponent(name + ".bettershotrec"))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        var document = RecordingEditDocument(style: RecordingStudioDefaults.style,
            zoomEnabled: false, zoomCues: [], clipTimeline: RecordingClipTimeline(segments: [
                RecordingClipSegment(sourceStart: 0, sourceEnd: 2)
            ]))
        if withAudio {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
            tone.frameLength = 96_000
            for index in 0..<96_000 {
                tone.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 220 / 48_000) * 0.3)
            }
            let audioURL = session.directoryURL.appendingPathComponent("replacement.caf")
            try AVAudioFile(forWriting: audioURL, settings: format.settings).write(from: tone)
            document.replacementAudioFileName = audioURL.lastPathComponent
        }
        try session.writeEditDocument(document)
        return session
    }
    let root = try fixture("Project")
    let incoming = try fixture("Incoming recording with a longer library title", withAudio: true)
    let model = RecordingStudioModel(url: root.directoryURL)
    await model.load()
    defer { model.teardown() }
    let registry = StudioProjectRegistry.shared
    precondition(!registry.hasActiveSourceTransactions)
    model.isAddingRecording = true
    precondition(registry.hasActiveSourceTransactions, "Quit must wait for an open native Add transaction")
    model.isAddingRecording = false
    model.isEditingSource = true
    precondition(registry.hasActiveSourceTransactions, "Quit must preserve unapplied embedded source edits")
    model.isEditingSource = false
    precondition(!registry.hasActiveSourceTransactions)
    let beforeSpeedDraft = model.currentEditDocument
    model.beginClipSpeedEdit()
    _ = model.setClipSpeed(2, forClipID: model.clipTimeline.segments[0].id)
    precondition(model.currentEditDocument == beforeSpeedDraft, "Uncommitted speed must not leak into source snapshots")
    do {
        let blocked = try await model.prepareAppendRecording(from: incoming.directoryURL)
        blocked.discard()
        preconditionFailure("Append must reject an active uncommitted speed draft")
    } catch RecordingStudioSourceResolver.ResolutionError.invalidSources {}
    model.endClipSpeedEdit()
    model.undo()
    precondition(model.currentEditDocument == beforeSpeedDraft)
    let pendingWithDraft = try await model.prepareAppendRecording(from: incoming.directoryURL)
    model.beginClipSpeedEdit()
    let refusedDraftCommit = model.commitAppendRecording(pendingWithDraft, expectedRevision: pendingWithDraft.revision)
    guard case .failed = refusedDraftCommit else { preconditionFailure("A speed draft started during append must block commit") }
    model.endClipSpeedEdit()
    precondition(model.currentEditDocument == beforeSpeedDraft)
    let prepared = try await model.prepareAppendRecording(from: incoming.directoryURL)
    defer { prepared.discard() }
    precondition(model.commitAppendRecording(prepared, expectedRevision: prepared.revision) == .changed)
    let appended = model.currentEditDocument
    precondition(model.reorderClips(ids: model.clipTimeline.segments.reversed().map(\.id)) == .changed)
    let reordered = model.currentEditDocument
    model.undo()
    precondition(model.currentEditDocument == appended, "Reorder must undo without also undoing append in the same event")
    model.undo()
    precondition(!model.isMultiSource, "The preceding append must be its own undo step")
    model.redo()
    precondition(model.currentEditDocument == appended)
    model.redo()
    precondition(model.currentEditDocument == reordered, "Redo must preserve separate source transaction groups")
    model.undo()
    precondition(model.currentEditDocument == appended)
    let rootEffectsBaseline = model.currentEditDocument
    let rootEffectsRevision = model.editRevision
    model.addZoomCue(at: 0.5)
    model.addZoomCue(fromEditorTime: 0.2, toEditorTime: 1.2)
    model.add3DShot(at: 0.5)
    model.previewAuto3DScene(count: 2)
    model.applyAuto3DScene(count: 2)
    model.apply3DScene([.glide])
    model.beginMaskEditing()
    precondition(model.currentEditDocument == rootEffectsBaseline && model.editRevision == rootEffectsRevision,
        "Multi-recording roots must not persist effects ignored by source composition")
    precondition(!model.showsMaskLane && model.previewTimeline3D.shots.isEmpty && !model.isEditingMasks)
    precondition(StudioTimelineMetrics.scrollingLanesHeight(showsMaskLane: false, showsCutLane: false,
        shows3DLane: false, showsZoomLane: false) == StudioTimelineMetrics.clipLaneHeight
            + StudioTimelineMetrics.scrollerGutter + StudioTimelineMetrics.rowSpacing)
    let source = model.projectSources!.last!
    // Older valid catalogs can retain authored effects only in the leaf's edit.json.
    var legacyCatalog = model.currentEditDocument
    legacyCatalog.sourceDocuments = nil
    let legacySession = try fixture("Catalog without snapshots")
    try FileManager.default.copyItem(at: root.directoryURL.appendingPathComponent("sources"),
        to: legacySession.directoryURL.appendingPathComponent("sources"))
    try legacySession.writeEditDocument(legacyCatalog)
    let legacyModel = RecordingStudioModel(url: legacySession.directoryURL)
    await legacyModel.load()
    precondition(legacyModel.isLoaded)
    let fallback = try legacyModel.sourceDocumentForEditing(sourceID: source.id)
    precondition(fallback == model.sourceDocuments?[source.id])
    let leafDocumentURL = RecordingSession(directoryURL: source.sessionDirectory(in: legacySession.directoryURL)).editDocumentURL
    let leafDocument = try Data(contentsOf: leafDocumentURL)
    try Data("{broken".utf8).write(to: leafDocumentURL)
    do {
        _ = try legacyModel.sourceDocumentForEditing(sourceID: source.id)
        preconditionFailure("Corrupt fallback edits must never become default source effects")
    } catch RecordingStudioSourceResolver.ResolutionError.invalidDocument {}
    try leafDocument.write(to: leafDocumentURL)
    legacyModel.teardown()
    let child = RecordingStudioModel(url: source.sessionDirectory(in: root.directoryURL),
        embeddedDocument: model.sourceDocuments?[source.id], isEmbeddedSource: true)
    await child.load()
    defer { child.teardown() }
    let registrySnapshot = StudioProjectRegistry.shared.snapshots(for: child.sessionURL)
    precondition(registrySnapshot.isEmpty, "Source sheets must not register a second project editor")
    precondition(model.selectedClip != nil && child.isSourceEditor)
    precondition(model.hasAudio && child.replacementAudio != nil,
        "Root snapshots must exercise composed Export Audio using an authored leaf soundtrack")
    child.addZoomCue(fromEditorTime: 0.2, toEditorTime: 1.2)
    child.add3DShot(at: 0.5)
    precondition(!child.zoomCues.isEmpty && !child.shots3D.isEmpty,
        "Embedded leaf editors must retain their authored effect controls")
    child.undo()
    child.undo()
    precondition(child.currentEditDocument == model.sourceDocuments?[source.id])
    let snapshots = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        let suffix = scheme == .light ? "light" : "dark"
        try snapshot(StudioInspector(model: model), scheme: scheme, width: 360,
            to: snapshots.appendingPathComponent("multi-recording-inspector-\(suffix).png"), height: 760)
        try snapshot(StudioInspector(model: child, initialTab: .effects), scheme: scheme, width: 360,
            to: snapshots.appendingPathComponent("source-effects-inspector-\(suffix).png"), height: 640)
        try snapshot(StudioAddRecordingSheet(model: model), scheme: scheme, width: 540,
            to: snapshots.appendingPathComponent("add-recording-library-\(suffix).png"), height: 420)
        try snapshot(StudioEditRecordingSheet(root: model, source: source), scheme: scheme, width: 960,
            to: snapshots.appendingPathComponent("edit-recording-sheet-\(suffix).png"), height: 640)
    }
    // A source transaction preserves the outer timeline and creates one root undo action.
    let baseline = model.currentEditDocument
    let timeline = model.clipTimeline
    child.style.padding += 0.025
    await child.waitForSourceEdits()
    let outcome = await model.applySourceDocument(child.currentEditDocument,
        sourceID: source.id, expectedRevision: model.editRevision)
    precondition(outcome == .changed && model.clipTimeline == timeline)
    child.retainEmbeddedSourceFiles()
    model.undo()
    precondition(model.currentEditDocument == baseline)
    model.redo()
    precondition(model.sourceDocuments?[source.id]?.style.value.padding == child.style.padding)
    precondition(root.loadEditDocument()?.sources == nil && incoming.loadEditDocument()?.sources == nil,
        "Opening source controls must not save the root or original recording")
    let importedAudioURL = incoming.directoryURL.appendingPathComponent("replacement.caf")
    child.replaceAudio(with: importedAudioURL)
    precondition(child.sourceEditsInFlight && child.isReplacingAudio,
        "Import must block source snapshots before asynchronous audio validation")
    child.replaceAudio(with: importedAudioURL)
    precondition(child.isReplacingAudio, "A superseded import must not clear its successor's busy state")
    await child.waitForSourceEdits()
    precondition(!child.sourceEditsInFlight && !child.isReplacingAudio)
    precondition(child.replacementAudio != nil && child.replacementAudioError == nil,
        "Source audio cleanup must exercise a successfully decoded imported soundtrack")
    child.teardown()
    let leaf = RecordingSession(directoryURL: child.sessionURL)
    let files = try FileManager.default.contentsOfDirectory(at: leaf.directoryURL, includingPropertiesForKeys: nil)
    precondition(!files.contains { $0.lastPathComponent.hasPrefix(RecordingSession.replacementAudioBaseName + "-") },
        "Discarded source audio imports must be removed without touching saved media")
    let retainedAudio = try Data(contentsOf: leaf.directoryURL.appendingPathComponent("replacement.caf"))
    let originalAudio = try Data(contentsOf: importedAudioURL)
    precondition(retainedAudio == originalAudio, "Source teardown must retain the authored soundtrack")
    print("PASS compact light/dark recording source controls, library/sheet snapshots, source effect undo, and audio import cleanup")
}
