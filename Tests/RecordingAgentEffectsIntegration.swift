import AVFoundation
import CoreGraphics
import Foundation
import MCP

@testable import BetterShot

@MainActor
func checkRecordingAgentEffectsParsing() throws {
    func capabilities(cursor: Bool = true, camera: Bool = true, overlays: Bool = true) throws -> RecordingAgentEffects.Capabilities {
        let fields: Value = .object([
            "rawDuration": .double(12), "editorDuration": .double(4), "videoWidth": .double(1920), "videoHeight": .double(1080),
            "canRestyleCursor": .bool(cursor), "hasCamera": .bool(camera), "canShowClickEffects": .bool(overlays),
            "hasKeystrokes": .bool(overlays), "hasSubtitles": .bool(overlays)
        ])
        return try JSONDecoder().decode(RecordingAgentEffects.Capabilities.self, from: JSONEncoder().encode(fields))
    }
    let available = try capabilities()
    var base = RecordingEditDocument(style: RecordingStudioStyle(), zoomEnabled: false, zoomCues: [],
        clipTimeline: RecordingClipTimeline(segments: [RecordingClipSegment(sourceStart: 2, sourceEnd: 10, speed: 2)]))
    let privatePath = "/private/test-only-secret-wallpaper.png"
    base.style.background = .customWallpaper(path: privatePath)
    base.replacementAudioFileName = "private-authored-audio.caf"
    let original = base
    func apply(_ fields: [String: Value], capabilities: RecordingAgentEffects.Capabilities? = nil) throws -> RecordingEditDocument {
        try RecordingAgentEffects.applying(.object(fields), to: base, capabilities: capabilities ?? available)
    }
    func rejected(_ patch: Value, capabilities: RecordingAgentEffects.Capabilities? = nil) throws {
        do {
            _ = try RecordingAgentEffects.applying(patch, to: base, capabilities: capabilities ?? available)
            preconditionFailure("Invalid effects patches must be rejected")
        } catch let error as RecordingAgentOperationError {
            precondition(error.code == "invalid_argument")
            precondition(!error.localizedDescription.contains(privatePath))
        }
        precondition(base == original, "Validation must not mutate the document being edited")
    }
    let rect: Value = .object(["x": .double(0.1), "y": .double(0.1), "width": .double(0.5), "height": .double(0.6)])
    let zoomID = UUID(), partialMaskID = UUID(), fullMaskID = UUID(), shotID = UUID()
    let cue: Value = .object(["id": .string(zoomID.uuidString), "start": .double(6), "end": .double(8), "zoom": .double(2),
        "anchorMode": .string("pinnedAnchor"), "pinnedX": .double(0.2), "pinnedY": .double(0.7), "boundsBias": .double(0.4), "skipEasing": .bool(true)])
    let partial: Value = .object(["id": .string(partialMaskID.uuidString), "scope": .string("cropOnly"), "rect": rect,
        "effect": .string("blur"), "amount": .double(20), "start": .double(1), "end": .double(3)])
    let full: Value = .object(["id": .string(fullMaskID.uuidString), "scope": .string("fullFrame"), "effect": .string("pixelate"), "amount": .double(30)])
    let shot: Value = .object(["id": .string(shotID.uuidString), "start": .double(0), "end": .double(1),
        "preset": .string(Recording3DPreset.spotlight.rawValue), "enabled": .bool(true)])
    let patched = try apply([
        "background": .object(["kind": .string("solid"), "color": .object(["red": .double(0.2), "green": .double(0.3), "blue": .double(0.4), "alpha": .double(0.8)])]),
        "framing": .object(["padding": .double(0.1), "cornerRadius": .double(0.04), "shadow": .double(0.7), "aspect": .string("square"), "contentMode": .string("fit")]),
        "cursor": .object(["visible": .bool(false), "appearance": .string("dot"), "scale": .double(2), "smoothMotion": .bool(false), "pressEffect": .bool(false), "rippleEffect": .bool(false), "hideWhenIdle": .bool(true)]),
        "camera": .object(["visible": .bool(true), "layout": .string("sideBySide"), "onLeft": .bool(true), "centerX": .double(0.4), "centerY": .double(0.5), "size": .double(0.3), "roundness": .double(0.4), "aspect": .string("16:9")]),
        "zooms": .object(["enabled": .bool(true), "cues": .array([cue])]), "crop": rect,
        "masks": .array([partial, full]), "shots3D": .array([shot]),
        "overlays": .object(["clicksVisible": .bool(false), "keystrokesVisible": .bool(false), "keystrokePlacement": .string("topRight"), "subtitlesVisible": .bool(false), "subtitleVerticalPosition": .double(0.4), "subtitleFontScale": .double(1.5), "subtitleWordHighlight": .bool(true)])
    ])
    precondition(patched.clips == base.clips && patched.sources == base.sources && patched.replacementAudioFileName == base.replacementAudioFileName)
    precondition(patched.style.padding == 0.1 && patched.style.cornerRadius == 0.04 && patched.style.shadow == 0.7)
    precondition(patched.exportAspectPreset == .square && patched.exportAspectContentMode == .fit)
    precondition(patched.style.cursor?.appearance == .dot && patched.style.cursor?.isVisible == false && patched.style.cursorScale == 2)
    precondition(patched.style.value.layoutPreset == .sideBySide && patched.style.cameraOnLeft == true && patched.style.value.camera.aspectRatio == .wide)
    precondition(patched.zoomCues[0].start == 6 && patched.zoomCues[0].end == 8 && patched.zoomCues[0].id == zoomID,
        "Zooms use raw time even beyond the source's authored editor duration")
    precondition(patched.masks?.first?.start == 1 && patched.masks?.first?.end == 3)
    precondition(patched.masks?.last?.rect == RecordingVideoCrop.unit && patched.masks?.first?.rect != RecordingVideoCrop.unit)
    var partialUntimed = partial.objectValue!
    partialUntimed.removeValue(forKey: "start"); partialUntimed.removeValue(forKey: "end")
    var fullTimed = full.objectValue!
    fullTimed["start"] = .int(0); fullTimed["end"] = .int(2)
    fullTimed["rect"] = .object(["x": .int(0), "y": .int(0), "width": .int(1), "height": .int(1)])
    let alternateMasks = try apply(["masks": .array([.object(partialUntimed), .object(fullTimed)])])
    precondition(alternateMasks.masks?.first?.start == nil && alternateMasks.masks?.last?.end == 2)
    precondition(patched.shots3D?.first?.id == shotID && patched.shots3D?.first?.startPose == Recording3DPreset.spotlight.poses.0)
    precondition(patched.showsSubtitles == false && patched.subtitleStyle.fontScale == 1.5 && patched.keystrokePlacement == .topRight)
    let emptyPatch = try apply([:]), emptyCursorPatch = try apply(["cursor": .object([:])])
    precondition(emptyPatch == base && emptyCursorPatch == base)
    let resetCrop = try apply(["crop": .null]), resetMasks = try apply(["masks": .array([])]), resetShots = try apply(["shots3D": .array([])])
    precondition(resetCrop.crop == nil && resetMasks.masks == nil && resetShots.shots3D == nil)
    let noBackground = try apply(["background": .object(["kind": .string("none")])])
    precondition(noBackground.style.background == .none)
    let gradient = AnnotationBackgroundGradient.presets[0]
    let gradientDocument = try apply(["background": .object(["kind": .string("gradient"), "gradientId": .string(gradient.id)])])
    precondition(gradientDocument.style.background == .gradient(StoredGradient(gradient)))

    for patch: Value in [
        .array([]), .object(["path": .string(privatePath)]),
        .object(["background": .object(["kind": .string("wallpaper"), "path": .string(privatePath)])]),
        .object(["background": .object(["kind": .string("gradient"), "gradientId": .string("unknown")])]),
        .object(["framing": .object(["padding": .double(.nan)])]), .object(["framing": .object(["shadow": .double(.infinity)])]),
        .object(["framing": .object(["cornerRadius": .double(0.5)])]), .object(["framing": .object(["aspect": .string("unknown")])]),
        .object(["cursor": .object(["visible": .int(1)])]), .object(["cursor": .object(["appearance": .string("hand")])]),
        .object(["cursor": .object(["appearance": .string("dot"), "assetPath": .string(privatePath)])]),
        .object(["camera": .object(["size": .double(0.9)])]), .object(["camera": .object(["layout": .string("unknown")])]),
        .object(["crop": .object(["x": .double(0.8), "y": .int(0), "width": .double(0.5), "height": .double(0.5)])]),
        .object(["crop": .object(["x": .int(0), "y": .int(0), "width": .double(0.01), "height": .double(0.5)])]),
        .object(["zooms": .object(["cues": .array([cue, cue])])]),
        .object(["zooms": .object(["cues": .array(Array(repeating: cue, count: 65))])]),
        .object(["zooms": .object(["cues": .array([.object(["id": .string("invalid"), "start": .int(0), "end": .int(2), "zoom": .int(2)])])])]),
        .object(["masks": .array([partial, partial])]),
        .object(["masks": .array([.object(["id": .string(UUID().uuidString), "scope": .string("cropOnly"), "effect": .string("blur"), "amount": .int(16)])])]),
        .object(["masks": .array([.object(["id": .string(UUID().uuidString), "scope": .string("fullFrame"), "rect": rect, "effect": .string("blur"), "amount": .int(16)])])]),
        .object(["shots3D": .array([shot, shot])]),
        .object(["shots3D": .array([.object(["id": .string(UUID().uuidString), "start": .int(0), "end": .int(6), "preset": .string("Spotlight")])])]),
        .object(["masks": .array([.object(["id": .string(UUID().uuidString), "scope": .string("fullFrame"), "effect": .string("blur"), "amount": .int(16), "start": .int(0), "end": .int(6)])])]),
        .object(["zooms": .object(["cues": .array([.object(["id": .string(UUID().uuidString), "start": .int(11), "end": .int(13), "zoom": .int(2)])])])]),
        .object(["overlays": .object(["subtitleFontScale": .int(8)])])
    ] { try rejected(patch) }
    var oneSidedMask = partial.objectValue!
    oneSidedMask.removeValue(forKey: "end")
    try rejected(.object(["masks": .array([.object(oneSidedMask)])]))
    oneSidedMask["end"] = .int(3); oneSidedMask.removeValue(forKey: "start")
    try rejected(.object(["masks": .array([.object(oneSidedMask)])]))
    try rejected(.object(["cursor": .object(["visible": .bool(false)])]), capabilities: capabilities(cursor: false))
    try rejected(.object(["camera": .object(["visible": .bool(true)])]), capabilities: capabilities(camera: false))
    try rejected(.object(["overlays": .object(["subtitlesVisible": .bool(true)])]), capabilities: capabilities(overlays: false))
    try rejected(.object(["overlays": .object(["clicksVisible": .bool(true)])]), capabilities: capabilities(overlays: false))
    try rejected(.object(["overlays": .object(["keystrokesVisible": .bool(true)])]), capabilities: capabilities(overlays: false))

    var longDocument = patched
    longDocument.zoomCues = (0..<70).map { ZoomCue(start: Double($0), end: Double($0) + 1) }
    let page = try RecordingAgentEffects.inspect(document: longDocument, capabilities: available, offset: 65, limit: 3)
    precondition(page.zoomCues.total == 70 && page.zoomCues.items.count == 3 && page.zoomCues.offset == 65)
    precondition(page.masks.total == 2 && page.masks.items.isEmpty && page.shots3D.total == 1)
    let empty = try RecordingAgentEffects.inspect(document: longDocument, capabilities: available, offset: Int.max, limit: 64)
    precondition(empty.zoomCues.items.isEmpty)
    for (offset, limit) in [(-1, 1), (0, 0), (0, 65)] {
        do { _ = try RecordingAgentEffects.inspect(document: base, capabilities: available, offset: offset, limit: limit); preconditionFailure("Invalid pagination must fail") }
        catch let error as RecordingAgentOperationError { precondition(error.code == "invalid_argument") }
    }
    let inspection = try RecordingAgentEffects.inspect(document: base, capabilities: available)
    let serialized = String(decoding: try JSONEncoder().encode(inspection), as: UTF8.self)
    precondition(!serialized.contains(privatePath) && !serialized.contains("private-authored-audio"))
    precondition(inspection.settings["background"] == .object(["kind": .string("existingWallpaper")]))
    precondition(inspection.zoomClock == "rawSourceTime" && inspection.maskAnd3DClock == "sourceEditorTime")
    var customGradient = StoredGradient(gradient)
    customGradient.colors[0].red += 0.01
    var customDocument = base
    customDocument.style.background = .gradient(customGradient)
    var customShot = patched.shots3D![0]
    customShot.easing = .easeOut
    customDocument.shots3D = [customShot]
    let customInspection = try RecordingAgentEffects.inspect(document: customDocument, capabilities: available)
    precondition(customInspection.settings["background"] == .object(["kind": .string("existingGradient")]),
        "A reused built-in ID must not disguise an authored custom gradient")
    precondition(customInspection.shots3D.items[0].objectValue?["preset"] == .string("existingCustom"),
        "Customized preset timing must remain identified as custom")
    let knownInspection = try RecordingAgentEffects.inspect(document: patched, capabilities: available)
    precondition(knownInspection.shots3D.items[0].objectValue?["preset"] == .string(Recording3DPreset.spotlight.rawValue))
    var rootDocument = base
    rootDocument.sources = [RecordingProjectSource(displayName: "Leaf", duration: 4)]
    do { _ = try RecordingAgentEffects.applying(.object([:]), to: rootDocument, capabilities: available); preconditionFailure("Effects helpers must reject multi-source roots") }
    catch let error as RecordingAgentOperationError { precondition(error.code == "invalid_argument") }
    do { _ = try RecordingAgentEffects.inspect(document: rootDocument, capabilities: available); preconditionFailure("Effects inspection requires a selected leaf") }
    catch let error as RecordingAgentOperationError { precondition(error.code == "invalid_argument") }
    guard case .object(let schema) = RecordingAgentEffects.patchSchema,
          case .object(let properties)? = schema["properties"] else { preconditionFailure("Effects patch schema must be an object") }
    precondition(schema["additionalProperties"] == .bool(false) && properties.count == 9)
    guard let maskVariants = properties["masks"]?.objectValue?["items"]?.objectValue?["oneOf"]?.arrayValue else {
        preconditionFailure("Mask schema must distinguish scope and timed/untimed records")
    }
    precondition(maskVariants.count == 4)
    for variant in maskVariants {
        let fields = variant.objectValue!, values = fields["properties"]!.objectValue!
        let required = Set(fields["required"]!.arrayValue!.compactMap(\.stringValue))
        let scope = values["scope"]!.objectValue!["enum"]!.arrayValue!.first!.stringValue!
        precondition(fields["additionalProperties"] == .bool(false))
        precondition((scope == "cropOnly") == required.contains("rect"))
        precondition((values["start"] != nil) == (values["end"] != nil))
        precondition(required.contains("start") == required.contains("end"))
        precondition((values["start"] != nil) == required.contains("start"))
        if scope == "fullFrame" {
            let rectangle = values["rect"]!.objectValue!["properties"]!.objectValue!
            precondition(rectangle["x"]!.objectValue!["maximum"] == .double(0))
            precondition(rectangle["width"]!.objectValue!["minimum"] == .double(1))
        }
    }
    let encodedSchema = try JSONEncoder().encode(RecordingAgentEffects.patchSchema)
    precondition(!encodedSchema.isEmpty)
    precondition(base == original)
    print("PASS strict visual-effects parsing, capability and clock bounds, array limits, paginated inspection and path redaction")
}

@MainActor
func checkRecordingAgentEffects(movieURL: URL) async throws {
    precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
    let library = RecordingSessionStore.recordingsDirectory
    precondition(library.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    func fixture() throws -> RecordingSession {
        let session = try RecordingSessionStore.createSession()
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        try FileManager.default.copyItem(at: movieURL, to: session.cameraURL)
        var manifest = CaptureManifest()
        manifest.duration = 2
        manifest.pointerSynthesized = true
        manifest.pressEffectsBaked = false
        manifest.cameraLeadIn = 0
        try session.writeCaptureManifest(manifest)
        var input = PointerCaptureFile()
        input.travel = [.init(time: 0, x: 0.2, y: 0.3), .init(time: 1.8, x: 0.8, y: 0.7)]
        input.presses = [.init(time: 0.5, x: 0.4, y: 0.4, button: 0, phase: .down), .init(time: 0.6, x: 0.4, y: 0.4, button: 0, phase: .up)]
        input.keystrokes = [.init(time: 0.7, modifiers: ["⌘"], key: "C")]
        try session.writePointerCapture(input)
        var style = RecordingStudioStyle()
        style.background = .none
        let document = RecordingEditDocument(style: style, zoomEnabled: false, zoomCues: [],
            clipTimeline: RecordingClipTimeline(segments: [RecordingClipSegment(sourceStart: 0, sourceEnd: 2)]),
            subtitleCues: [.init(start: 0, end: 1.5, text: "Isolated fixture")])
        try session.writeEditDocument(document)
        return session
    }
    let root = try fixture(), incoming = try fixture()
    defer {
        try? FileManager.default.removeItem(at: root.directoryURL)
        try? FileManager.default.removeItem(at: incoming.directoryURL)
    }
    let originalScreen = try Data(contentsOf: root.screenURL)
    let originalCamera = try Data(contentsOf: root.cameraURL)
    let incomingScreen = try Data(contentsOf: incoming.screenURL)
    let incomingDocumentBytes = try Data(contentsOf: incoming.editDocumentURL)
    let model = RecordingStudioModel(url: root.directoryURL)
    await model.load()
    defer { model.teardown() }
    precondition(model.isLoaded && model.pointerIsSynthesized && model.hasCameraVideo)
    let agent = RecordingAgentOperations.shared
    #if DEBUG
    defer { agent.effectsPreparedForTesting = nil }
    #endif
    let handle = StudioProjectRegistry.shared.snapshot(for: root.directoryURL)!.handle
    let first = try await agent.inspectEffects(handle: handle, lease: RecordingAgentRequestLease())
    precondition(first.handle == handle && first.sourceId == nil && first.revision == model.editRevision)
    precondition(first.effects.capabilities.canRestyleCursor && first.effects.capabilities.hasCamera)
    precondition(first.effects.capabilities.hasKeystrokes && first.effects.capabilities.hasSubtitles)
    let legacyBaseline = model.currentEditDocument
    let previewBefore = try await agent.preview(handle: handle, expectedRevision: first.revision, at: 0.8)
    let zoomID = UUID(), maskID = UUID(), shotID = UUID()
    let legacyPatch: Value = .object([
        "background": .object(["kind": .string("gradient"), "gradientId": .string(AnnotationBackgroundGradient.presets[0].id)]),
        "framing": .object(["padding": .double(0.1), "shadow": .double(0.2), "cornerRadius": .double(0.03), "aspect": .string("square"), "contentMode": .string("fit")]),
        "cursor": .object(["appearance": .string("dot"), "scale": .double(2), "smoothMotion": .bool(false)]),
        "camera": .object(["layout": .string("sideBySide"), "onLeft": .bool(true), "aspect": .string("4:3")]),
        "zooms": .object(["enabled": .bool(true), "cues": .array([.object(["id": .string(zoomID.uuidString), "start": .double(0.2), "end": .double(1.2), "zoom": .double(1.5)])])]),
        "crop": .object(["x": .double(0.1), "y": .double(0.1), "width": .double(0.8), "height": .double(0.8)]),
        "masks": .array([.object(["id": .string(maskID.uuidString), "scope": .string("cropOnly"),
            "rect": .object(["x": .double(0.2), "y": .double(0.2), "width": .double(0.3), "height": .double(0.3)]),
            "effect": .string("blur"), "amount": .int(16), "start": .double(0.2), "end": .double(1.4)])]),
        "shots3D": .array([.object(["id": .string(shotID.uuidString), "start": .double(0), "end": .double(1.6), "preset": .string(Recording3DPreset.spotlight.rawValue)])]),
        "overlays": .object(["clicksVisible": .bool(false), "keystrokesVisible": .bool(false), "subtitlesVisible": .bool(true), "subtitleFontScale": .double(1.2)])
    ])
    let legacyResult = try await agent.setEffects(handle: handle, expectedRevision: first.revision, patch: legacyPatch, lease: RecordingAgentRequestLease())
    precondition(legacyResult.revision == first.revision + 1, "An effects patch must commit exactly one revision")
    let legacyPatched = model.currentEditDocument
    precondition(legacyPatched.clips == legacyBaseline.clips && legacyPatched.style.cursor?.appearance == .dot)
    precondition(legacyPatched.zoomCues.first?.id == zoomID && legacyPatched.masks?.first?.id == maskID && legacyPatched.shots3D?.first?.id == shotID)
    let previewAfter = try await agent.preview(handle: handle, expectedRevision: model.editRevision, at: 0.8)
    precondition(previewAfter.png != previewBefore.png, "Agent effects must reach the production composed preview")
    let undo = try agent.undo(handle: handle, expectedRevision: model.editRevision)
    precondition(model.currentEditDocument == legacyBaseline, "One undo must remove the entire effects patch")
    _ = try agent.redo(handle: handle, expectedRevision: undo.revision)
    precondition(model.currentEditDocument == legacyPatched)
    let noOpRevision = model.editRevision
    let noOp = try await agent.setEffects(handle: handle, expectedRevision: noOpRevision, patch: .object([:]), lease: RecordingAgentRequestLease())
    precondition(noOp.revision == noOpRevision && model.currentEditDocument == legacyPatched)
    do {
        _ = try await agent.setEffects(handle: handle, expectedRevision: first.revision, patch: legacyPatch, lease: RecordingAgentRequestLease())
        preconditionFailure("Old revisions must reject effect patches")
    } catch RecordingAgentOperationError.staleRevision {}
    do {
        _ = try await agent.inspectEffects(handle: handle, sourceID: UUID(), lease: RecordingAgentRequestLease())
        preconditionFailure("Legacy projects must reject a supplied source ID")
    } catch RecordingAgentOperationError.invalidArgument {}
    let known = agent.listProjects()
    let incomingID = known.first { $0.name == incoming.displayName }!.id
    let appended = try await agent.appendRecording(handle: handle, expectedRevision: model.editRevision,
        projectID: incomingID, requestID: UUID(), lease: RecordingAgentRequestLease())
    let sourceID = appended.sources.last!.id
    let sourceBaseline = try model.sourceDocumentForEditing(sourceID: sourceID)
    let outerBaseline = model.clipTimeline
    let sourcePatch: Value = .object([
        "background": .object(["kind": .string("solid"), "color": .object(["red": .double(0.1), "green": .double(0.8), "blue": .double(0.2)])]),
        "framing": .object(["padding": .double(0.14)]),
        "cursor": .object(["appearance": .string("dark")]),
        "camera": .object(["layout": .string("bubble"), "size": .double(0.2)]),
        "masks": .array([.object(["id": .string(UUID().uuidString), "scope": .string("fullFrame"), "effect": .string("pixelate"), "amount": .int(8)])])
    ])
    let sourceResult = try await agent.setEffects(handle: handle, expectedRevision: model.editRevision, sourceID: sourceID, patch: sourcePatch, lease: RecordingAgentRequestLease())
    precondition(sourceResult.revision == appended.revision + 1 && sourceResult.sourceId == sourceID)
    precondition(model.clipTimeline == outerBaseline && model.currentEditDocument.sourceDocuments?[sourceID] != sourceBaseline)
    let sourcePatchedRoot = model.currentEditDocument
    _ = try agent.undo(handle: handle, expectedRevision: model.editRevision)
    let undoneSource = try model.sourceDocumentForEditing(sourceID: sourceID)
    precondition(undoneSource == sourceBaseline)
    _ = try agent.redo(handle: handle, expectedRevision: model.editRevision)
    precondition(model.currentEditDocument == sourcePatchedRoot)
    do {
        _ = try await agent.inspectEffects(handle: handle, lease: RecordingAgentRequestLease())
        preconditionFailure("Combined projects must require an explicit source ID")
    } catch RecordingAgentOperationError.invalidArgument {}
    do {
        _ = try await agent.setEffects(handle: handle, expectedRevision: model.editRevision, sourceID: UUID(), patch: sourcePatch, lease: RecordingAgentRequestLease())
        preconditionFailure("Unknown source IDs must reject effects")
    } catch RecordingAgentOperationError.invalidArgument {}
    let lastTime = model.clipTimeline.editorRange(for: model.clipTimeline.segments.last!.id)!.lowerBound + 0.8
    let multiPreview = try await agent.preview(handle: handle, expectedRevision: model.editRevision, at: lastTime)
    precondition(!multiPreview.png.isEmpty)
    let output = try await RecordingStudioExporter().export(model.makeExportConfiguration()) { _ in }
    defer { try? FileManager.default.removeItem(at: output) }
    let exportedDuration = try await AVURLAsset(url: output).load(.duration).seconds
    precondition(abs(exportedDuration - model.duration) < 0.05)
    let saved = try agent.save(handle: handle, expectedRevision: model.editRevision)
    precondition(saved.saved)
    let reopened = RecordingStudioModel(url: root.directoryURL)
    await reopened.load()
    precondition(reopened.isLoaded && reopened.currentEditDocument == model.currentEditDocument)
    reopened.teardown()

    #if DEBUG
    for failure in ["lease", "busy", "stale", "duplicate", "cancel"] {
        let before = model.currentEditDocument, revision = model.editRevision
        let lease = RecordingAgentRequestLease()
        var duplicate: RecordingStudioModel?
        agent.effectsPreparedForTesting = {
            switch failure {
            case "lease": lease.invalidate()
            case "busy": model.isEditingSource = true
            case "stale": precondition(model.splitClip(at: 0.5) == .changed)
            case "duplicate":
                duplicate = RecordingStudioModel(url: root.directoryURL)
                await duplicate!.load()
            default: withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let attempt = Task { @MainActor in
            try await agent.setEffects(handle: handle, expectedRevision: revision, sourceID: sourceID,
                patch: .object(["framing": .object(["padding": .double(0.05)])]), lease: lease)
        }
        do { _ = try await attempt.value; preconditionFailure("A prepared effect must reject a changed request context") }
        catch is CancellationError { precondition(failure == "lease" || failure == "cancel") }
        catch let error as RecordingAgentOperationError {
            precondition(error.code == (failure == "stale" ? "stale_revision" : failure == "duplicate" ? "ambiguous_project" : "operation_unavailable"))
        }
        agent.effectsPreparedForTesting = nil
        model.isEditingSource = false
        duplicate?.teardown()
        if failure == "stale" { model.undo() }
        precondition(model.currentEditDocument == before, "Rejected effects must not mutate the target")
    }
    #endif
    let beforeCallback = model.currentEditDocument, callbackRevision = model.editRevision
    var callbackDocument = try model.sourceDocumentForEditing(sourceID: sourceID)
    callbackDocument.style.padding = 0.06
    let callbackLease = RecordingAgentRequestLease()
    var validatedCommit = false
    do {
        _ = try await model.applyEffectsDocument(callbackDocument, sourceID: sourceID, expectedRevision: callbackRevision) {
            validatedCommit = true
            callbackLease.invalidate()
            guard callbackLease.isValid else { throw CancellationError() }
        }
        preconditionFailure("The final prepared-source validation must prevent a revoked commit")
    } catch is CancellationError {}
    precondition(validatedCommit && model.currentEditDocument == beforeCallback && model.editRevision == callbackRevision)

    let access = RecordingAgentAccessController.shared
    await access.setEnabled(true)
    precondition(access.status == .ready)
    let configuration = try JSONSerialization.jsonObject(with: Data(access.clientConfiguration().utf8)) as! [String: Any]
    let servers = configuration["mcpServers"] as! [String: Any]
    let server = servers["bettershot"] as! [String: Any]
    let headers = server["headers"] as! [String: String]
    let authorization = headers["Authorization"]!
    let transport = HTTPClientTransport(endpoint: access.endpoint, configuration: .ephemeral, streaming: false, requestModifier: { request in
        var request = request
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    })
    let client = Client(name: "visual-effects-test", version: "1")
    _ = try await client.connect(transport: transport)
    func call(_ name: String, _ arguments: [String: Value]) async throws -> CallTool.Result {
        let request: RequestContext<CallTool.Result> = try await client.callTool(name: name, arguments: arguments)
        return try await request.value
    }
    func errorCode(_ result: CallTool.Result) -> String? {
        result.structuredContent?.objectValue?["error"]?.objectValue?["code"]?.stringValue
    }
    let tools = try await client.listTools().tools
    precondition(tools.contains { $0.name == "inspect_effects" } && tools.contains { $0.name == "set_effects" })
    let effectsTool = tools.first { $0.name == "set_effects" }!
    precondition(effectsTool.inputSchema.objectValue?["additionalProperties"] == .bool(false))
    let inspected = try await call("inspect_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString), "offset": .int(0), "limit": .int(1)])
    precondition(inspected.isError != true && inspected.structuredContent?.objectValue?["sourceId"] == .string(sourceID.uuidString))
    for (name, arguments) in [
        ("inspect_effects", ["handle": Value.string(handle.uuidString), "sourceId": .null]),
        ("inspect_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString), "offset": .double(0.5)]),
        ("inspect_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString), "limit": .int(0)]),
        ("inspect_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString), "path": .string("/private/test-only-path")]),
        ("set_effects", ["handle": .string(handle.uuidString), "expectedRevision": .int(Int(model.editRevision)), "patch": .object([:])]),
        ("set_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString), "expectedRevision": .int(Int(model.editRevision)), "patch": .object([:]), "requestId": .string(UUID().uuidString)])
    ] {
        let result = try await call(name, arguments)
        precondition(errorCode(result) == "invalid_argument")
        let serialized = String(decoding: try JSONEncoder().encode(result.structuredContent), as: UTF8.self)
        precondition(!serialized.contains("/private/test-only-path"))
    }
    let sdkResult = try await call("set_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString),
        "expectedRevision": .int(Int(model.editRevision)), "patch": .object(["framing": .object(["padding": .double(0.12)])])])
    precondition(sdkResult.isError != true && model.currentEditDocument.sourceDocuments?[sourceID]?.style.padding == 0.12)
    #if DEBUG
    let beforeDisable = model.currentEditDocument, disableRevision = model.editRevision
    let (preparedStream, preparedSignal) = AsyncStream<Void>.makeStream()
    var releasePrepared: CheckedContinuation<Void, Never>?
    agent.effectsPreparedForTesting = {
        await withCheckedContinuation { continuation in
            releasePrepared = continuation
            preparedSignal.yield(())
        }
    }
    let pending = Task { @MainActor in
        try await call("set_effects", ["handle": .string(handle.uuidString), "sourceId": .string(sourceID.uuidString),
            "expectedRevision": .int(Int(disableRevision)), "patch": .object(["framing": .object(["padding": .double(0.07)])])])
    }
    var preparedIterator = preparedStream.makeAsyncIterator()
    _ = await preparedIterator.next()
    await access.setEnabled(false)
    releasePrepared?.resume()
    _ = try? await pending.value
    agent.effectsPreparedForTesting = nil
    preparedSignal.finish()
    precondition(model.currentEditDocument == beforeDisable && model.editRevision == disableRevision)
    #else
    await access.setEnabled(false)
    #endif
    await client.disconnect()
    let finalScreen = try Data(contentsOf: root.screenURL), finalCamera = try Data(contentsOf: root.cameraURL)
    let finalIncoming = try Data(contentsOf: incoming.screenURL), finalIncomingDocument = try Data(contentsOf: incoming.editDocumentURL)
    precondition(finalScreen == originalScreen && finalCamera == originalCamera && finalIncoming == incomingScreen && finalIncomingDocument == incomingDocumentBytes)
    print("PASS atomic legacy/source visual effects, one-step undo/revision, preview/export/save/reopen, stale/busy/lease rejection, SDK envelopes/disable and original captures")
}
