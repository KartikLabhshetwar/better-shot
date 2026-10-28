import AVFoundation
import Foundation

@testable import BetterShot

@MainActor
func checkRecordingSourceConfigurations(movieURL: URL) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bettershotrec")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = RecordingSession(directoryURL: directory)
    let first = RecordingProjectSource(displayName: "First", duration: 1)
    let second = RecordingProjectSource(displayName: "Second", duration: 4)
    for source in [first, second] {
        let session = RecordingSession(directoryURL: source.sessionDirectory(in: directory))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        var style = RecordingStudioDefaults.style
        style.padding = source.id == first.id ? 0.1 : 0.2
        let timeline = RecordingClipTimeline(segments: [RecordingClipSegment(
            sourceStart: source.id == first.id ? 1 : 0,
            sourceEnd: source.id == first.id ? 3 : 2,
            speed: source.id == first.id ? 2 : 0.5)])
        try session.writeEditDocument(RecordingEditDocument(
            style: style, zoomEnabled: false, zoomCues: [], clipTimeline: timeline))
    }
    let configurations = try await RecordingStudioSourceResolver.configurations(for: [first, second], in: project)
    precondition(configurations.map(\.id) == [first.id, second.id])
    precondition(configurations[0].configuration.style.padding == 0.1
                 && configurations[1].configuration.style.padding == 0.2)
    let timeline = try RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceID: second.id, sourceStart: 1, sourceEnd: 3, speed: 2),
        RecordingClipSegment(sourceID: first.id, sourceStart: 0, sourceEnd: 1)
    ]).validated(sourceDurations: [first.id: first.duration, second.id: second.duration])
    let beforeCut = RecordingStudioSourceResolver.location(at: 0.5, timeline: timeline, sources: configurations)!
    precondition(beforeCut.sourceID == second.id && beforeCut.sourceEditorTime == 2 && beforeCut.rawSourceTime == 1)
    let afterCut = RecordingStudioSourceResolver.location(at: 1.5, timeline: timeline, sources: configurations)!
    precondition(afterCut.sourceID == first.id && afterCut.sourceEditorTime == 0.5 && afterCut.rawSourceTime == 2)
    let atCut = RecordingStudioSourceResolver.location(at: 1, timeline: timeline, sources: configurations)!
    precondition(atCut.sourceID == first.id && atCut.rawSourceTime == 1,
                 "An exact cut uses the incoming source's clock")
    precondition(RecordingStudioSourceResolver.location(at: .nan, timeline: timeline, sources: configurations) == nil)

    let firstSession = RecordingSession(directoryURL: first.sessionDirectory(in: directory))
    var authoredDocument = firstSession.loadEditDocument()!
    let audioURL = firstSession.directoryURL.appendingPathComponent("audio-replacement.caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
    audio.frameLength = 96_000
    audio.floatChannelData![0].initialize(repeating: 0, count: 96_000)
    do {
        try AVAudioFile(forWriting: audioURL, settings: format.settings).write(from: audio)
    }
    let replacement = await RecordingReplacementAudio.load(url: audioURL, displayName: "Fixture")
    precondition(replacement?.track.asset != nil, "Imported audio must retain its asset for later playback rebuilds")
    authoredDocument.crop = [0.1, 0.1, 0.6, 0.7]
    authoredDocument.replacementAudioFileName = audioURL.lastPathComponent
    let aspects: [(ExportAspectPreset, ExportAspectContentMode)] = [(.original, .fill), (.square, .fill), (.square, .fit)]
    for (aspect, mode) in aspects {
        authoredDocument.exportAspect = aspect.rawValue
        authoredDocument.exportAspectMode = mode.rawValue
        if FileManager.default.fileExists(atPath: firstSession.draftDocumentURL.path) {
            try FileManager.default.removeItem(at: firstSession.draftDocumentURL)
        }
        try firstSession.writeEditDocument(authoredDocument)
        let shared = try await RecordingSessionRenderer.configuration(for: firstSession, document: authoredDocument)
        let model = RecordingStudioModel(url: firstSession.directoryURL)
        await model.load()
        let native = model.makeExportConfiguration()
        precondition(model.isLoaded && shared.crop == native.crop && shared.canvasSize == native.canvasSize,
                     "Source parity \(aspect)/\(mode): loaded=\(model.isLoaded), error=\(String(describing: model.loadError)), " +
                     "crop=\(shared.crop)/\(native.crop), canvas=\(shared.canvasSize)/\(native.canvasSize)")
        precondition(shared.viewportTimeline.frame(at: 0.5) == native.viewportTimeline.frame(at: 0.5))
        precondition(shared.fitContentAspect == native.fitContentAspect)
        precondition(shared.reframe?.sourceAspect == native.reframe?.sourceAspect)
        precondition(shared.audioReplacementURL == audioURL && shared.audioReplacementURL == native.audioReplacementURL)
        model.teardown()
    }
    for name in ["../outside.caf", "missing.caf", "linked.caf"] {
        if name == "linked.caf" {
            try FileManager.default.createSymbolicLink(
                at: firstSession.directoryURL.appendingPathComponent(name), withDestinationURL: audioURL)
        }
        var invalidAudio = authoredDocument
        invalidAudio.replacementAudioFileName = name
        do {
            _ = try await RecordingSessionRenderer.configuration(for: firstSession, document: invalidAudio)
            preconditionFailure("Unsafe or missing replacement audio must not fall back to recorded audio")
        } catch {}
    }
    try FileManager.default.removeItem(at: firstSession.directoryURL.appendingPathComponent("linked.caf"))
    print("PASS shared crop and replacement-audio configuration matches Studio; unsafe/missing audio rejected")
    var rootDocument = authoredDocument
    rootDocument.sources = [first, second]
    rootDocument.clips = timeline.segments
    do {
        _ = try await RecordingSessionRenderer.configuration(for: firstSession, document: rootDocument)
        preconditionFailure("Unimplemented multi-source rendering must not silently export the primary recording")
    } catch {}
    rootDocument.sources = nil
    do {
        _ = try await RecordingSessionRenderer.configuration(for: firstSession, document: rootDocument)
        preconditionFailure("Tagged clips without their source table must not fall through legacy rendering")
    } catch {}
    try Data("invalid".utf8).write(to: firstSession.editDocumentURL, options: .atomic)
    do {
        _ = try await RecordingStudioSourceResolver.configurations(for: [first], in: project)
        preconditionFailure("Corrupt authored edits must never render as an untouched source")
    } catch {}
    authoredDocument.sources = [first]
    try firstSession.writeEditDocument(authoredDocument)
    do {
        _ = try await RecordingStudioSourceResolver.configurations(for: [first], in: project)
        preconditionFailure("Nested source projects must be rejected")
    } catch {}
    authoredDocument.sources = nil
    try firstSession.writeEditDocument(authoredDocument)
    try FileManager.default.removeItem(at: firstSession.screenURL)
    try FileManager.default.createSymbolicLink(at: firstSession.screenURL, withDestinationURL: movieURL)
    do {
        _ = try await RecordingStudioSourceResolver.configurations(for: [first], in: project)
        preconditionFailure("Symlinked source media must never escape the managed package")
    } catch RecordingProjectSourceError.unsafePackage {}
    print("PASS authored source configuration, nested speed clocks, reordered boundaries, and unsafe/corrupt source rejection")
}
