//
//  RecordingSession.swift
//  BetterShot
//
//  A recording is a folder ("session") rather than a bare .mov so the studio
//  editor can keep the screen video, the separately captured camera video,
//  and the timestamped pointer-capture sidecar together. Sessions live in
//  Application Support (not the temp dir) so a crash mid-recording never
//  hands the footage to the OS temp purger.
//

import CoreGraphics
import Foundation

nonisolated struct RecordingSession: Sendable, Equatable {
    static let directoryExtension = "bettershotrec"
    static let screenFileName = "screen.mov"
    static let cameraFileName = "camera.mov"
    static let pointerCaptureFileName = "input.json"
    static let captureManifestFileName = "capture.json"
    static let editDocumentFileName = "edit.json"
    /// The working copy the editor autosaves while you type. `edit.json` is
    /// only rewritten by an explicit save, so a crash mid-edit costs nothing
    /// and closing a window still has something meaningful to prompt about.
    static let draftDocumentFileName = "edit.draft.json"
    static let projectMetadataFileName = "project.json"
    /// The document that produced the current flattened deliverable, so a
    /// cached render can be proven fresh instead of assumed fresh.
    static let renderStampFileName = "render.json"
    static let posterFileName = "poster.jpg"
    /// Base name for an imported soundtrack. The picked file is copied in
    /// beside the footage (keeping its own extension) so the project keeps
    /// playing after the original is moved or deleted.
    static let replacementAudioBaseName = "audio-replacement"

    let directoryURL: URL

    var screenURL: URL { directoryURL.appendingPathComponent(Self.screenFileName) }
    var cameraURL: URL { directoryURL.appendingPathComponent(Self.cameraFileName) }
    /// The default flattened deliverable. The source screen/camera movies stay
    /// untouched so Studio can always re-render the project non-destructively.
    var finalURL: URL {
        finalURL(for: .default)
    }

    func finalURL(for container: VideoExportContainer) -> URL {
        let fileName = directoryURL
            .deletingPathExtension()
            .lastPathComponent
            .appending(".\(container.fileExtension)")
        return directoryURL.appendingPathComponent(fileName)
    }
    var pointerCaptureURL: URL { directoryURL.appendingPathComponent(Self.pointerCaptureFileName) }
    var captureManifestURL: URL { directoryURL.appendingPathComponent(Self.captureManifestFileName) }
    var editDocumentURL: URL { directoryURL.appendingPathComponent(Self.editDocumentFileName) }
    var draftDocumentURL: URL { directoryURL.appendingPathComponent(Self.draftDocumentFileName) }
    var projectMetadataURL: URL { directoryURL.appendingPathComponent(Self.projectMetadataFileName) }
    var renderStampURL: URL { directoryURL.appendingPathComponent(Self.renderStampFileName) }
    var posterURL: URL { directoryURL.appendingPathComponent(Self.posterFileName) }

    /// True once the project has been committed with an explicit save. Every
    /// package written by older builds has an `edit.json` from the previous
    /// silent autosave, so those open as already-saved - no migration.
    var hasSavedProject: Bool {
        FileManager.default.fileExists(atPath: editDocumentURL.path)
    }

    /// The name shown wherever the project is listed.
    var displayName: String {
        let stored = loadProjectMetadata()?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return directoryURL.deletingPathExtension().lastPathComponent
    }

    var hasCamera: Bool {
        FileManager.default.fileExists(atPath: cameraURL.path)
    }

    /// The flattened cache on disk, whichever container it was rendered into.
    /// Nil when the project has never been rendered. Probing every container
    /// keeps an existing render valid after the export format is changed -
    /// switching the picker converts on save rather than forcing a re-render.
    var existingFinalURL: URL? {
        for container in VideoExportContainer.allCases {
            let candidate = finalURL(for: container)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    var hasFinalVideo: Bool {
        existingFinalURL != nil
    }

    /// Uses an existing flattened cache when one is available; otherwise
    /// history previews the screen master so the project can appear without
    /// turning Stop into an implicit export.
    var deliverableURL: URL {
        existingFinalURL ?? screenURL
    }

    /// Drops every cached deliverable, whichever container it was rendered
    /// into. Targeting a single container would leave a render in the other
    /// one behind, and `existingFinalURL` would then hand out stale footage.
    func removeFinalVideos() {
        for container in VideoExportContainer.allCases {
            try? FileManager.default.removeItem(at: finalURL(for: container))
        }
        try? FileManager.default.removeItem(at: renderStampURL)
    }

    /// Adopts a freshly rendered file as this session's deliverable, taking the
    /// container from the render itself. Deliverables in other containers are
    /// cleared so a stale render can never win the `existingFinalURL` lookup.
    @discardableResult
    func installFinalVideo(
        movingFrom temporaryURL: URL,
        renderedFrom document: RecordingEditDocument? = nil
    ) throws -> URL {
        let container = VideoExportContainer(fileExtension: temporaryURL.pathExtension) ?? .default
        let destinationURL = finalURL(for: container)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }

        for stale in VideoExportContainer.allCases where stale != container {
            try? FileManager.default.removeItem(at: finalURL(for: stale))
        }
        writeRenderStamp(document)
        return destinationURL
    }

    /// True when two documents would render identical media and differ only in
    /// the container they get wrapped in.
    static func differsOnlyByExportContainer(
        _ document: RecordingEditDocument,
        _ other: RecordingEditDocument?
    ) -> Bool {
        guard let other else { return false }
        var normalized = document
        normalized.exportSettings?.container = other.exportSettings?.container
        return normalized == other
    }

    static func isSessionDirectory(_ url: URL) -> Bool {
        url.pathExtension == directoryExtension
            && FileManager.default.fileExists(atPath: url.appendingPathComponent(screenFileName).path)
    }

    /// The project package a media URL belongs to: the package itself, or the package around its screen master.
    static func sessionDirectory(containing url: URL) -> URL? {
        if isSessionDirectory(url) { return url }
        let parent = url.deletingLastPathComponent()
        return url.lastPathComponent == screenFileName && isSessionDirectory(parent) ? parent : nil
    }

    func loadCaptureManifest() -> CaptureManifest? {
        guard let data = try? Data(contentsOf: captureManifestURL) else { return nil }
        return try? CaptureManifest.decoder.decode(CaptureManifest.self, from: data)
    }

    func loadPointerCapture() -> PointerCaptureFile? {
        guard let data = try? Data(contentsOf: pointerCaptureURL) else { return nil }
        return try? CaptureManifest.decoder.decode(PointerCaptureFile.self, from: data)
    }

    func writeCaptureManifest(_ manifest: CaptureManifest) throws {
        let data = try CaptureManifest.encoder.encode(manifest)
        try data.write(to: captureManifestURL, options: .atomic)
    }

    func writePointerCapture(_ capture: PointerCaptureFile) throws {
        let data = try CaptureManifest.encoder.encode(capture)
        do {
            try data.write(to: pointerCaptureURL, options: .atomic)
        } catch {
            // Atomic replacement needs a sibling temporary file. If that
            // narrow operation fails, make one direct attempt before treating
            // the pointer sidecar as lost and surfacing the failure to users.
            try data.write(to: pointerCaptureURL)
        }
    }

    func loadEditDocument() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: editDocumentURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeEditDocument(_ document: RecordingEditDocument) throws {
        let data = try CaptureManifest.encoder.encode(document)
        try data.write(to: editDocumentURL, options: .atomic)
    }

    // MARK: - Working draft

    func loadDraftDocument() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: draftDocumentURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeDraftDocument(_ document: RecordingEditDocument) throws {
        let data = try CaptureManifest.encoder.encode(document)
        try data.write(to: draftDocumentURL, options: .atomic)
    }

    func removeDraftDocument() {
        try? FileManager.default.removeItem(at: draftDocumentURL)
    }

    /// What the editor should actually open: the autosaved draft when one
    /// survived, otherwise the last explicit save. Every consumer outside the
    /// editor (flattening, uploads) uses this too, so a deliverable always
    /// reflects the edits the user can see.
    func effectiveEditDocument() -> RecordingEditDocument? {
        loadDraftDocument() ?? loadEditDocument()
    }

    /// True when unsaved edits are sitting in the draft. A draft identical to
    /// the saved document is just a leftover and doesn't count.
    var hasUnsavedDraft: Bool {
        guard let draft = loadDraftDocument() else { return false }
        return draft != loadEditDocument()
    }

    // MARK: - Project metadata

    func loadProjectMetadata() -> RecordingProjectMetadata? {
        guard let data = try? Data(contentsOf: projectMetadataURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingProjectMetadata.self, from: data)
    }

    func writeProjectMetadata(_ metadata: RecordingProjectMetadata) {
        guard let data = try? CaptureManifest.encoder.encode(metadata) else { return }
        try? data.write(to: projectMetadataURL, options: .atomic)
    }

    /// Read-modify-write so touching one field never drops the others.
    func updateProjectMetadata(_ mutate: (inout RecordingProjectMetadata) -> Void) {
        var metadata = loadProjectMetadata() ?? RecordingProjectMetadata()
        metadata.version = RecordingProjectMetadata.currentVersion
        mutate(&metadata)
        writeProjectMetadata(metadata)
    }

    // MARK: - Render stamp

    func loadRenderStamp() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: renderStampURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeRenderStamp(_ document: RecordingEditDocument?) {
        guard let document else {
            try? FileManager.default.removeItem(at: renderStampURL)
            return
        }
        guard let data = try? CaptureManifest.encoder.encode(document) else { return }
        try? data.write(to: renderStampURL, options: .atomic)
    }

    /// The flattened deliverable only when it provably matches `document`.
    /// Export and Share can then skip the render instead of trusting that
    /// nothing has changed since it was made.
    func freshFinalURL(matching document: RecordingEditDocument?) -> URL? {
        guard let existing = existingFinalURL else { return nil }
        let stamp = loadRenderStamp()
        if stamp == document { return existing }
        // Swapping only the container leaves every encoded sample intact, so
        // the render survives and export converts it on the way out.
        if let document, Self.differsOnlyByExportContainer(document, stamp) { return existing }
        return nil
    }
}

nonisolated struct CaptureManifest: Codable, Sendable, Equatable {
    var version = 1
    var createdAt = Date()
    /// Duration of the finished screen movie, in seconds.
    var duration: TimeInterval = 0
    var pixelWidth = 0
    var pixelHeight = 0
    /// Points→pixels scale of the captured source (Retina factor).
    var pixelScale: Double = 1
    var sourceDisplayID: UInt32?
    var includesSystemAudio = false
    var includesMicrophone = false
    /// Where the camera movie's t=0 falls on the screen movie's timeline.
    /// Positive means the camera started after the screen recording.
    var cameraLeadIn: TimeInterval?
    var cameraWidth: Int?
    var cameraHeight: Int?
    /// True when the capture excluded the OS cursor, so playback and export
    /// must draw the synthetic pointer from the capture sidecar. Optional so
    /// manifests written before this field decode as nil (cursor in pixels).
    var pointerSynthesized: Bool?
    /// New sessions keep press feedback out of the lossless screen master and
    /// reconstruct it from the pointer capture. Nil means a legacy session
    /// whose pixels may already contain the configured mouse indicators.
    var pressEffectsBaked: Bool?
    var pressEffectsEnabled: Bool?

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Sidecar of everything the user did during the recording, on the screen
/// movie's timeline. Coordinates are normalized (0...1) with a top-left
/// origin so they stay valid at any render resolution.
nonisolated struct PointerCaptureFile: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var travel: [PointerTravelSample] = []
    var presses: [PointerPressEvent] = []
    var keystrokes: [RecordingKeystrokeEvent] = []
    var artwork: [PointerArtwork] = []
    /// Prevents deterministic cleanup from being applied repeatedly when the
    /// same sidecar passes through Studio, flattening, and export builders.
    var isSanitized = false
}

/// A completed keyboard chord captured during recording: a special key press
/// (Tab, Esc, arrows, …) or a modifier shortcut (⌘C). Plain typing is never
/// recorded. Labels are display-ready strings so Studio and export render
/// exactly what was captured without re-deriving key names.
nonisolated struct RecordingKeystrokeEvent: Codable, Sendable, Equatable {
    /// Seconds on the screen movie timeline.
    var time: TimeInterval
    /// Held modifier symbols in keyboard order, e.g. ["⌃", "⌘"].
    var modifiers: [String] = []
    /// The trigger key's label, e.g. "K", "⇥", "esc".
    var key: String
}

nonisolated struct PointerTravelSample: Codable, Sendable, Equatable {
    enum PointerTravelKind: String, Codable, Sendable {
        case move
        case drag
    }

    /// Seconds on the screen movie timeline.
    var time: TimeInterval
    var x: Double
    var y: Double
    var kind: PointerTravelKind = .move
    /// References an entry in `PointerCaptureFile.artwork`. A nil ID means
    /// the renderer should use an AppKit-provided system arrow.
    var artworkID: String? = nil
}

nonisolated struct PointerPressEvent: Codable, Sendable, Equatable {
    enum PressPhase: String, Codable, Sendable {
        case down
        case up
    }

    var time: TimeInterval
    var x: Double
    var y: Double
    var button: Int
    var phase: PressPhase
    /// Pointer appearance active when the button event was captured.
    var artworkID: String? = nil
}

/// A captured pointer image embedded in input.json. `Data` is encoded as a
/// base-64 JSON string by Foundation's Codable implementation.
nonisolated struct PointerArtwork: Codable, Sendable, Equatable {
    nonisolated struct Point: Codable, Sendable, Equatable {
        var x: Double
        var y: Double
    }

    nonisolated struct Size: Codable, Sendable, Equatable {
        var width: Double
        var height: Double
    }

    var artworkID: String
    var imageData: Data
    /// Anchor point in the captured artwork's reference-size coordinate space.
    var anchorPoint: Point
    var referenceSize: Size
}

extension PointerCaptureFile {
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case travel
        case presses
        case keystrokes
        case artwork
        case isSanitized
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        travel = try container.decodeIfPresent([PointerTravelSample].self, forKey: .travel) ?? []
        presses = try container.decodeIfPresent([PointerPressEvent].self, forKey: .presses) ?? []
        keystrokes = try container.decodeIfPresent(
            [RecordingKeystrokeEvent].self,
            forKey: .keystrokes
        ) ?? []
        artwork = try container.decodeIfPresent(
            [PointerArtwork].self,
            forKey: .artwork
        ) ?? []
        isSanitized = try container.decodeIfPresent(Bool.self, forKey: .isSanitized) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(travel, forKey: .travel)
        try container.encode(presses, forKey: .presses)
        try container.encode(keystrokes, forKey: .keystrokes)
        try container.encode(artwork, forKey: .artwork)
        try container.encode(isSanitized, forKey: .isSanitized)
    }
}

extension PointerTravelSample {
    private enum CodingKeys: String, CodingKey {
        case time
        case x
        case y
        case kind
        case artworkID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(TimeInterval.self, forKey: .time)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        kind = try container.decodeIfPresent(
            PointerTravelKind.self,
            forKey: .kind
        ) ?? .move
        artworkID = try container.decodeIfPresent(String.self, forKey: .artworkID)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(artworkID, forKey: .artworkID)
    }
}

nonisolated enum RecordingSessionStore {
    static var recordingsDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("BetterShot", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static func createSession() throws -> RecordingSession {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = "BetterShot_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6))"
        let directory = recordingsDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(RecordingSession.directoryExtension)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return RecordingSession(directoryURL: directory)
    }

    static func allSessions() -> [RecordingSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { RecordingSession.isSessionDirectory($0) }
            .map { RecordingSession(directoryURL: $0) }
    }

    static func deleteSession(_ session: RecordingSession) {
        try? FileManager.default.removeItem(at: session.directoryURL)
    }
}
