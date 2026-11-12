import AppKit
import AVFoundation
import CoreImage
import Foundation

@testable import BetterShot

@MainActor
func checkRecordingNestedImports(movieURL: URL) async throws {
    precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
    let library = RecordingSessionStore.recordingsDirectory
    precondition(library.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: library) }
    func fixture(_ name: String, color: AnnotationBackgroundColor, cameraAndAudio: Bool = false) throws -> RecordingSession {
        let session = RecordingSession(directoryURL: library.appendingPathComponent(name + ".bettershotrec"))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        var style = RecordingStudioStyle()
        style.background = .solid(color)
        style.padding = 0.08
        style.shadow = 0
        style.camera.isVisible = cameraAndAudio
        var document = RecordingEditDocument(style: style, zoomEnabled: false, zoomCues: [],
            clipTimeline: RecordingClipTimeline(segments: cameraAndAudio ? [
                RecordingClipSegment(sourceStart: 0.3, sourceEnd: 1.3, speed: 2),
                RecordingClipSegment(sourceStart: 1.8, sourceEnd: 2.8, speed: 0.5)
            ] : [RecordingClipSegment(sourceStart: 0.2, sourceEnd: 1.2)]))
        document.exportAspect = ExportAspectPreset.wide16x9.rawValue
        if cameraAndAudio {
            try FileManager.default.copyItem(at: movieURL, to: session.cameraURL)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
            tone.frameLength = 96_000
            for sample in 0..<96_000 {
                tone.floatChannelData![0][sample] = Float(sin(Double(sample) * 2 * .pi * 220 / 48_000) * 0.3)
            }
            let soundtrack = session.directoryURL.appendingPathComponent("replacement.caf")
            try AVAudioFile(forWriting: soundtrack, settings: format.settings).write(from: tone)
            document.replacementAudioFileName = soundtrack.lastPathComponent
        }
        try session.writeEditDocument(document)
        return session
    }
    func append(_ source: RecordingSession, document: RecordingEditDocument?, to model: RecordingStudioModel) async throws {
        let prepared = try await model.prepareAppendRecording(from: source.directoryURL, document: document)
        defer { prepared.discard() }
        precondition(model.commitAppendRecording(prepared, expectedRevision: prepared.revision) == .changed)
    }
    let a = try fixture("Nested A", color: .blue)
    let b = try fixture("Nested B", color: .orange)
    let c = try fixture("Nested C", color: .red, cameraAndAudio: true)
    let d = try fixture("Nested D", color: .green)
    let models = [a, b, c].map { RecordingStudioModel(url: $0.directoryURL) }
    let am = models[0], bm = models[1], cm = models[2]
    for model in models { await model.load(); precondition(model.isLoaded) }
    defer { for model in models { model.teardown() } }
    try await append(d, document: nil, to: cm)
    precondition(cm.setClipSpeed(2, forClipID: cm.clipTimeline.segments[0].id) == .changed)
    precondition(cm.reorderClips(ids: cm.clipTimeline.segments.reversed().map(\.id)) == .changed)
    cm.exportAspect = .square
    guard case .saved = cm.saveProject() else { preconditionFailure("Save combined C") }
    try await append(c, document: cm.currentEditDocument, to: bm)
    bm.exportAspect = .vertical9x16
    bm.exportSettings.removeAudio = true
    guard case .saved = bm.saveProject() else { preconditionFailure("Save combined B") }
    let bDocument = bm.currentEditDocument
    let bConfiguration = bm.makeExportConfiguration()
    let bAspect = Double(bConfiguration.canvasSize.width / bConfiguration.canvasSize.height)
    am.exportAspect = .wide16x9
    am.exportSettings.frameRate = .fps30
    let initial = am.currentEditDocument
    let originals = try [a.screenURL, b.screenURL, c.screenURL, d.screenURL, c.cameraURL,
        c.directoryURL.appendingPathComponent("replacement.caf"), b.editDocumentURL, c.editDocumentURL,
        d.editDocumentURL].map { ($0, try Data(contentsOf: $0)) }

    let operations = RecordingAgentOperations.shared
    let bID = operations.listProjects().first { $0.name == b.displayName }!.id
    let handle = StudioProjectRegistry.shared.snapshot(for: a.directoryURL)!.handle
    let revision = am.editRevision, request = UUID()
    let appended = try await operations.appendRecording(handle: handle, expectedRevision: revision,
        projectID: bID, requestID: request, lease: RecordingAgentRequestLease())
    let retried = try await operations.appendRecording(handle: handle, expectedRevision: revision,
        projectID: bID, requestID: request, lease: RecordingAgentRequestLease())
    precondition(retried == appended && am.projectSources?.count == 4)
    let imported = am.currentEditDocument
    let importedClips = Array(am.clipTimeline.segments.dropFirst())
    let priorClips = bm.clipTimeline.segments
    precondition(importedClips.count == priorClips.count && Set(importedClips.map(\.id)).isDisjoint(with: priorClips.map(\.id)))
    for (actual, old) in zip(importedClips, priorClips) {
        precondition(actual.sourceStart == old.sourceStart && actual.sourceEnd == old.sourceEnd && actual.speed == old.speed)
    }
    precondition(importedClips[importedClips.count - 2].sourceID == importedClips.last!.sourceID,
        "Repeated imported clips must share one new editable source")
    precondition(Set(am.projectSources!.map(\.id)).isDisjoint(with: bm.projectSources!.map(\.id)))
    precondition(am.sourceDocuments!.values.allSatisfy { $0.sources == nil && $0.sourceDocuments == nil })
    let cSource = am.projectSources!.first { $0.displayName == c.displayName }!
    precondition(cSource.presentationAspectRatios == [1, bAspect])
    let copiedC = am.sourceConfigurations.first { $0.id == cSource.id }!
    precondition(copiedC.configuration.cameraURL != nil && copiedC.configuration.audioReplacementURL != nil)
    precondition(am.hasAudio && !am.exportSettings.removeAudio,
        "Destination encoding policy must not inherit the imported root's audio-removal setting")
    precondition(abs(am.duration - 5.25) < 0.001)
    am.undo()
    precondition(am.currentEditDocument == initial)
    am.redo()
    precondition(am.currentEditDocument == imported)

    let size = CGSize(width: 320, height: 180)
    let rootConfiguration = am.makeExportConfiguration()
    let renderer = try await RecordingStudioMultiSourceRenderer(configuration: rootConfiguration, canvasSize: size)
    let wideLeaf = bConfiguration.sources[0].configuration
    let constrained = RecordingStudioSourceConfiguration(id: UUID(), configuration: wideLeaf,
        presentationAspectRatios: [0.5, 1])
    let constrainedRect = constrained.fittedCanvasRect(in: size)
    let constrainedHeight = 90 * wideLeaf.canvasSize.height / wideLeaf.canvasSize.width
    precondition(wideLeaf.canvasSize.width > wideLeaf.canvasSize.height)
    precondition(abs(constrainedRect.width - 90) < 1e-9 && abs(constrainedRect.height - constrainedHeight) < 1e-9
        && abs(constrainedRect.minX - 115) < 1e-9 && abs(constrainedRect.midY - 90) < 1e-9,
        "The inner portrait container must narrow the outer square's 180-pixel viewport to 90 pixels")
    // Independent reference: render B as a whole into its portrait viewport, then center it in A.
    let bSize = CGSize(width: 180 * bAspect, height: 180)
    let bRenderer = try await RecordingStudioMultiSourceRenderer(configuration: bConfiguration, canvasSize: bSize)
    let context = CIContext(options: [.cacheIntermediates: false])
    let bounds = CGRect(origin: .zero, size: size)
    func pixels(_ image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 320 * 180 * 4)
        context.render(image, toBitmap: &bytes, rowBytes: 320 * 4, bounds: bounds,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return bytes
    }
    // 4.1s straddles the 0.7s raw-frame boundary after nested floating-point clock arithmetic.
    for time in [0.25, 1.25, 2.25, 4.1, 0.25] {
        let reference = try bRenderer.composedImage(at: time)
            .transformed(by: CGAffineTransform(translationX: (size.width - bSize.width) / 2, y: 0))
            .composited(over: CIImage(color: .black).cropped(to: bounds)).cropped(to: bounds)
        let actualImage = try renderer.composedImage(at: time + 1)
        let actual = pixels(actualImage), expected = pixels(reference)
        let aLocation = RecordingStudioSourceResolver.location(at: time + 1, timeline: rootConfiguration.clipTimeline, sources: rootConfiguration.sources)!
        let bLocation = RecordingStudioSourceResolver.location(at: time, timeline: bConfiguration.clipTimeline, sources: bConfiguration.sources)!
        let aSource = rootConfiguration.sources.first { $0.id == aLocation.sourceID }!
        let bSource = bConfiguration.sources.first { $0.id == bLocation.sourceID }!
        let aRect = aSource.fittedCanvasRect(in: size)
        let referenceRect = bSource.fittedCanvasRect(in: bSize)
            .offsetBy(dx: (size.width - bSize.width) / 2, dy: 0)
        precondition(abs(aRect.minX - referenceRect.minX) < 1e-9 && abs(aRect.minY - referenceRect.minY) < 1e-9
            && abs(aRect.width - referenceRect.width) < 1e-9 && abs(aRect.height - referenceRect.height) < 1e-9)
        precondition(abs(aLocation.sourceEditorTime - bLocation.sourceEditorTime) < 1e-9
            && abs(aLocation.rawSourceTime - bLocation.rawSourceTime) < 1e-9)
        let errors = zip(actual, expected).map { abs(Int($0) - Int($1)) }
        let viewportLeft = (size.width - bSize.width) / 2, viewportRight = (size.width + bSize.width) / 2
        // A second crop/composite samples fractional viewport edges twice; every other pixel stays exact.
        let differsAwayFromEdge = actual.indices.contains { index in
            guard actual[index] != expected[index] else { return false }
            let centerX = CGFloat((index / 4) % 320) + 0.5
            return abs(centerX - viewportLeft) > 0.5 && abs(centerX - viewportRight) > 0.5
        }
        let meanError = Double(errors.reduce(0, +)) / Double(errors.count * 255)
        if differsAwayFromEdge || meanError >= 0.0005 {
            print("NESTED pixel mismatch time=\(time), components=\(errors.filter { $0 != 0 }.count), max=\(errors.max()!), normalizedMean=\(meanError), nonEdge=\(differsAwayFromEdge)")
            print(String(format: "NESTED raw clocks A=%.18g B=%.18g", aLocation.rawSourceTime, bLocation.rawSourceTime))
            print("NESTED fitted rectangles A=\(aRect) reference=\(referenceRect)")
            let snapshots = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/editor-snapshots")
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            for (name, image) in [("actual", actualImage), ("reference", reference)] {
                let raster = context.createCGImage(image, from: bounds)!
                let png = NSBitmapImageRep(cgImage: raster).representation(using: .png, properties: [:])!
                try png.write(to: snapshots.appendingPathComponent("nested-import-\(name).png"))
            }
        }
        precondition(!differsAwayFromEdge && meanError < 0.0005,
            "C→B→A must retain exact interior geometry/pixels; fractional viewport-edge resampling stays bounded")
    }
    let configuration = RecordingStudioExporter.Configuration(screenURL: rootConfiguration.screenURL,
        cameraURL: nil, cameraOffset: 0, style: rootConfiguration.style, viewportTimeline: .identity,
        pointerTimeline: nil, showsPressEffects: false, keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
        subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(), canvasSize: size,
        clipTimeline: rootConfiguration.clipTimeline, exportSettings: am.exportSettings, sources: rootConfiguration.sources)
    let output = try await RecordingStudioExporter().export(configuration) { _ in }
    defer { try? FileManager.default.removeItem(at: output) }
    let asset = AVURLAsset(url: output)
    let outputDuration = try await asset.load(.duration).seconds
    precondition(abs(outputDuration - am.duration) < 0.05)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    for time in [1.25, 2.25, 3.25, 5.1] {
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let difference = zip(pixels(CIImage(cgImage: image)), pixels(try renderer.composedImage(at: time)))
            .enumerated().filter { $0.offset % 4 != 3 }.reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) }
        precondition(difference / Double(320 * 180 * 3 * 255) < 0.08,
            "Encoded nested import must match the composed preview")
    }
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    precondition(!audioTracks.isEmpty)
    let reader = try AVAssetReader(asset: asset)
    let audio = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])
    reader.add(audio)
    precondition(reader.startReading())
    var tone = false, silence = false
    while let sample = audio.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: &bytes)
        let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        bytes.withUnsafeBytes { raw in
            for (index, value) in raw.bindMemory(to: Float.self).enumerated() {
                let time = start + Double(index) / 48_000
                if (3.1...3.5).contains(time), abs(value) > 0.1 { tone = true }
                if (4.65...4.85).contains(time) { precondition(abs(value) < 0.02); silence = true }
            }
        }
    }
    precondition(reader.status == .completed && tone && silence, "Imported replacement audio must retain its authored clock")

    var effects = try am.sourceDocumentForEditing(sourceID: cSource.id)
    var style = effects.style.value
    style.padding += 0.03
    effects.style = StoredRecordingStudioStyle(style)
    let applied = await am.applySourceDocument(effects, sourceID: cSource.id, expectedRevision: am.editRevision)
    precondition(applied == .changed)
    let edited = am.currentEditDocument
    am.undo()
    precondition(am.currentEditDocument == imported)
    am.redo()
    precondition(am.currentEditDocument == edited)
    guard case .saved = am.saveProject() else { preconditionFailure("Save nested import") }
    am.teardown()
    let reopened = RecordingStudioModel(url: a.directoryURL)
    await reopened.load()
    defer { reopened.teardown() }
    precondition(reopened.isLoaded && reopened.currentEditDocument == edited)
    let baseline = reopened.currentEditDocument
    let existing = Set(reopened.projectSources!.map(\.id))
    let pending = try await reopened.prepareAppendRecording(from: b.directoryURL, document: bDocument)
    let staged = pending.document.sources!.filter { !existing.contains($0.id) }.map { $0.sessionDirectory(in: a.directoryURL) }
    precondition(staged.count == 3)
    reopened.style.padding += 0.01
    guard case .failed = reopened.commitAppendRecording(pending, expectedRevision: pending.revision) else {
        preconditionFailure("Stale combined append must fail")
    }
    precondition(staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    reopened.style = baseline.style.value
    let cancelled = Task { @MainActor in try await reopened.prepareAppendRecording(from: b.directoryURL, document: bDocument) }
    cancelled.cancel()
    do { let result = try await cancelled.value; result.discard(); preconditionFailure("Cancelled import must fail") }
    catch is CancellationError {}
    precondition(reopened.currentEditDocument == baseline)
    var deep = bDocument
    for index in deep.sources!.indices { deep.sources![index].presentationAspectRatios = Array(repeating: 1, count: 16) }
    do {
        let result = try await reopened.prepareAppendRecording(from: b.directoryURL, document: deep)
        result.discard(); preconditionFailure("Imported layout ancestry must remain bounded")
    } catch RecordingProjectSourceError.invalidSource {}
    for invalid in [[0.0], [-1], [.infinity], [.nan], Array(repeating: 1.0, count: 17)] {
        do { try RecordingProjectSource.validatePresentationAspectRatios(invalid); preconditionFailure("Invalid layout chain") }
        catch RecordingProjectSourceError.invalidSource {}
    }
    for (url, bytes) in originals {
        let retained = try Data(contentsOf: url)
        precondition(retained == bytes, "Nested import must preserve every original")
    }
    print("PASS editable C→B→A imports, nested canvas/encoded/audio parity, UUID/range/speed preservation, undo/save/reopen and rejected-stage cleanup")
}
