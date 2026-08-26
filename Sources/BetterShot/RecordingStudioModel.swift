//
//  RecordingStudioModel.swift
//  BetterShot
//
//  View-model for the recording studio: loads a recording session (screen
//  movie + optional camera movie + pointer-capture sidecar), owns the style
//  settings and zoom cues, and keeps the screen and camera players in
//  sync. Layout math lives in RecordingStudioLayout so the live preview and
//  the exporter compose frames identically.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation

enum RecordingTranscriptionState: Equatable {
    case idle
    case transcribing
    case failed(String)

    var isTranscribing: Bool {
        self == .transcribing
    }
}

enum RecordingStudioExportState: Equatable {
    case idle
    case exporting(progress: Double)
    case finished(URL)
    case failed(String)

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
    }
}

/// Share-to-cloud pipeline: render the current edits, upload, copy link.
enum RecordingStudioShareState: Equatable {
    case idle
    case rendering(progress: Double)
    case uploading
    case finished(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .rendering, .uploading: true
        default: false
        }
    }
}

@MainActor
@Observable
final class RecordingStudioModel {
    let sessionURL: URL
    private(set) var session: RecordingSession?
    private(set) var manifest: CaptureManifest?
    private(set) var pointerCapture = PointerCaptureFile()
    private(set) var recordedPressTimes: [TimeInterval] = []
    private(set) var sourceDuration: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var videoSize = CGSize(width: 1920, height: 1080)
    private(set) var hasCameraVideo = false
    private(set) var hasRecordedAudio = false
    private(set) var cameraOffset: TimeInterval = 0
    private(set) var isLoaded = false
    private(set) var loadError: String?

    let screenPlayer = AVPlayer()
    let cameraPlayer = AVPlayer()

    var style = RecordingStudioStyle(background: RecordingStudioDefaults.background) {
        didSet {
            if isLoaded, oldValue.background != style.background {
                RecordingStudioDefaults.background = style.background
            }
            scheduleProjectSave()
        }
    }
    /// The style preset currently applied, so the Studio's preset bar can
    /// show its name and detect whether the user has since edited away from
    /// it. Not persisted in the project file: reapplied by content match.
    var appliedStylePresetID: RecordingStudioStylePreset.ID?
    var zoomEnabled = true {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    var exportSettings = VideoCompressionSettings() {
        didSet { scheduleProjectSave() }
    }
    /// Studio-side input feedback: both are reconstructed from the sidecar,
    /// so they can be toggled after the fact without touching the footage.
    var showsClickEffects = true {
        didSet { scheduleProjectSave() }
    }
    var showsKeystrokes = true {
        didSet { scheduleProjectSave() }
    }
    var keystrokePlacement: RecordingKeystrokePlacement = .bottomCenter {
        didSet { scheduleProjectSave() }
    }
    var showsSubtitles = true {
        didSet { scheduleProjectSave() }
    }
    var subtitleStyle = SubtitleBarStyle() {
        didSet { scheduleProjectSave() }
    }
    /// Output aspect for Export/Share. Anything but `.original` crops the
    /// render with a virtual camera that follows the pointer and zooms;
    /// the Studio preview shows the same crop live.
    var exportAspect: ExportAspectPreset = .original {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    /// Fill crops with the follow camera; Fit shows the whole recording
    /// framed on the background.
    var exportAspectMode: ExportAspectContentMode = .fill {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    private(set) var cropRect = RecordingVideoCrop.unit
    private(set) var isCroppingVideo = false
    var cropDraft = RecordingVideoCrop.unit
    var cropAspect: CropAspectRatio = .freeform
    private(set) var maskSegments: [RecordingMaskSegment] = []
    private(set) var isEditingMasks = false
    var selectedMaskID: UUID?
    private var maskEditSnapshot: [RecordingMaskSegment]?
    private var maskRangeEditSnapshot: [RecordingMaskSegment]?
    private let previewMaskState = RecordingMaskPreviewState()
    private var previewMaskTask: Task<Void, Never>?
    /// The preview's copy of the reframe camera, kept current with every
    /// edit that would change the exported crop.
    private(set) var previewReframe: ReframeTrack?
    private var reframeFocusTimeline: PointerTimeline?
    private var reframeFocusResolved = false
    private(set) var subtitleCues: [RecordingSubtitleCue] = []
    private(set) var subtitleTimeline = SubtitleTimeline.empty
    /// Word-level timing behind the cues; empty for projects transcribed
    /// before transcript editing shipped (cues only).
    private(set) var transcriptWords: [RecordingTranscriptWord] = []
    /// Word-timing lookup for karaoke captions; rebuilt with the cues.
    private(set) var karaokeTimeline = KaraokeTimeline.empty
    /// Word under the playhead, updated only on word boundaries so the
    /// transcript view isn't invalidated on every 20 ms playback tick.
    private(set) var activeTranscriptWordIndex: Int?
    var transcriptionState = RecordingTranscriptionState.idle
    private(set) var zoomCues: [ZoomCue] = []
    private(set) var viewportTimeline = ViewportTimeline.identity
    private(set) var pointerTimeline = PointerTimeline.empty
    private(set) var keystrokeTimeline = KeystrokeCaptionTimeline.empty
    var selectedCueID: UUID?
    private(set) var clipTimeline = RecordingClipTimeline(segments: [])
    var selectedClipID: UUID?
    var timelineHoverTime: TimeInterval?
    /// Storyboard tiles for the clip lane, sampled on demand at whatever
    /// density the lane's current zoom needs.
    let timelineThumbnails = RecordingTimelineThumbnailStore()

    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    /// Live scrub-preview time while the pointer hovers the trim strip
    /// without committing to a new playhead position, matching Final
    /// Cut/iMovie skimming. `nil` shows the real playhead again.
    var hoverPreviewTime: TimeInterval? {
        didSet {
            guard isLoaded, duration > 0, !isPlaying else { return }
            movePlayers(to: hoverPreviewTime ?? currentTime)
        }
    }
    var exportState: RecordingStudioExportState = .idle
    var audioExportState: RecordingStudioExportState = .idle
    var shareState: RecordingStudioShareState = .idle
    /// Upload identity while sharing, so the UI can read the uploader's
    /// live progress and the history card mirrors the state.
    private(set) var shareItemID: UUID?
    private var lastShareOptions: CloudUploadOptions?

    /// Format the audio-only export writes. Persisted so the round trip
    /// through an external tool keeps whatever that tool accepts.
    var audioExportFormat: RecordingAudioFormat = .m4a {
        didSet { scheduleProjectSave() }
    }
    /// The soundtrack standing in for the recording's own audio, resolved
    /// so both playback and export can use it without reloading tracks.
    private(set) var replacementAudio: RecordingReplacementAudio?
    /// Why the last import was rejected, shown next to the Replace control.
    private(set) var replacementAudioError: String?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var exportTask: Task<Void, Never>?
    private var audioExportTask: Task<Void, Never>?
    private var replacementAudioTask: Task<Void, Never>?
    /// The screen movie's video track, kept from load so the player item
    /// can be rebuilt synchronously when an imported soundtrack means the
    /// composition has to be assembled track by track.
    private var screenVideoTrack: AVAssetTrack?
    private var shareTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var projectSaveTask: Task<Void, Never>?
    private var screenAsset: AVURLAsset?
    private let editUndoManager = UndoManager()
    private(set) var undoRevision = 0
    private var zoomEditSnapshot: [ZoomCue]?
    /// The document as of the last explicit save. Everything the user does
    /// after that lives in memory and in the autosaved draft until they save
    /// again, which is what makes the close prompt meaningful.
    private var lastSavedDocument: RecordingEditDocument?
    /// Set while a stored document is being applied to the model, so the
    /// resulting property writes don't register as user edits.
    private var isApplyingDocument = false
    /// Whether the editor holds edits that have not been committed with an
    /// explicit save. Stored rather than derived: the title bar and the Save
    /// button read it on every body evaluation, and rebuilding the whole
    /// document to compare it there would cost real time while dragging.
    private(set) var hasUnsavedChanges = false
    private(set) var saveFlash = false

    /// Accepts either a recording session folder or a bare video file (so
    /// history items and old recordings still open, just without events).
    init(url: URL) {
        sessionURL = url
        if RecordingSession.isSessionDirectory(url) {
            session = RecordingSession(directoryURL: url)
        } else {
            session = nil
        }
    }

    var screenURL: URL {
        session?.screenURL ?? sessionURL
    }

    /// False for a bare movie opened from disk: there is no project package
    /// behind it, so there is nothing to save into.
    var isProject: Bool { session != nil }

    /// What the window title, share sheet, and Projects browser call this
    /// project. A bare movie falls back to its file name.
    var projectDisplayName: String {
        session?.displayName ?? sessionURL.deletingPathExtension().lastPathComponent
    }

    func load() async {
        guard !isLoaded else { return }

        if let session {
            manifest = session.loadCaptureManifest()
        }

        let asset = AVURLAsset(url: screenURL)
        screenAsset = asset
        do {
            let (durationTime, tracks) = try await asset.load(.duration, .tracks)
            sourceDuration = durationTime.seconds
            duration = sourceDuration
            if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                screenVideoTrack = videoTrack
                let naturalSize = try await videoTrack.load(.naturalSize)
                if naturalSize.width > 0, naturalSize.height > 0 {
                    videoSize = naturalSize
                }
            }
            hasRecordedAudio = tracks.contains { $0.mediaType == .audio }
        } catch {
            loadError = "Could not open the recording: \(error.localizedDescription)"
            return
        }

        if let session {
            let pointScale = max(manifest?.pixelScale ?? 1, 1)
            let recordingSize = CGSize(
                width: videoSize.width / CGFloat(pointScale),
                height: videoSize.height / CGFloat(pointScale)
            )
            // The recorder writes one sample per 60 Hz tick with no thinning, so the
            // sidecar of a long recording is megabytes of JSON and the thinning pass
            // walks every sample. Both are pure work over Sendable values, so they
            // run off the main actor rather than in front of the opening window.
            pointerCapture = await Task.detached(priority: .userInitiated) {
                PointerStreamSanitizer.sanitize(
                    session.loadPointerCapture() ?? PointerCaptureFile(),
                    options: PointerSanitizeOptions(recordingSizeInPoints: recordingSize)
                ).sanitizedCapture
            }.value
            recordedPressTimes = pointerCapture.presses
                .filter { $0.phase == .down }
                .map(\.time)
            keystrokeTimeline = KeystrokeCaptionTimeline(events: pointerCapture.keystrokes)
        }

        if let session, session.hasCamera {
            hasCameraVideo = true
            cameraOffset = manifest?.cameraLeadIn ?? 0
            cameraPlayer.replaceCurrentItem(with: AVPlayerItem(url: session.cameraURL))
            cameraPlayer.actionAtItemEnd = .pause
            cameraPlayer.isMuted = true
        } else {
            style.camera.isVisible = false
        }

        lastSavedDocument = session?.loadEditDocument()
        // A draft that outlived its editor means the last session ended
        // without a save - a crash, a force quit, or a Studio window that is
        // still open elsewhere. Reopen on the draft so nothing is lost; the
        // project simply opens dirty.
        let document = session?.effectiveEditDocument()
        // Sessions recorded before the toggle moved into Studio stored the
        // choice in the manifest; honor it as the default.
        showsClickEffects = manifest?.pressEffectsEnabled ?? true
        // A brand new recording has no project yet, so it also starts from
        // the remembered export choice.
        exportSettings = RecordingExportPreferences.lastSettings
        if let document {
            applyDocumentSettings(document)
        } else if session == nil {
            // Legacy bare movies use the same editor, but open visually
            // unchanged until the user explicitly adds styling.
            style = RecordingStudioStyle(
                background: .none,
                padding: 0,
                cornerRadius: 0,
                shadow: 0,
                camera: RecordingCameraBubbleSettings(isVisible: false)
            )
            zoomEnabled = false
        } else {
            zoomCues = ZoomCueSynthesizer.cues(from: pointerCapture, duration: sourceDuration)
            if let defaultPreset = RecordingStudioStylePresetStore.shared.activePreset {
                style = defaultPreset.value
                appliedStylePresetID = defaultPreset.id
            } else {
                let defaultLook = AppPreferences.defaultBeautifierConfig
                if defaultLook != .default {
                    style.background = defaultLook.annotationStyle
                    style.padding = defaultLook.padding
                    style.cornerRadius = defaultLook.cornerRadius
                    style.shadow = defaultLook.shadowStrength
                }
            }
        }

        if let storedClips = document?.clips, !storedClips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: storedClips)
                .normalized(to: sourceDuration)
        } else {
            clipTimeline = .legacyTrim(
                start: document?.trimStart,
                end: document?.trimEnd,
                sourceDuration: sourceDuration
            )
        }
        duration = clipTimeline.duration
        selectedClipID = clipTimeline.segments.first?.id

        // Resolve the imported soundtrack before the first player item is
        // built, so the editor opens already playing what it will export.
        if let session, let fileName = document?.replacementAudioFileName {
            let url = session.directoryURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                replacementAudio = await RecordingReplacementAudio.load(
                    url: url,
                    displayName: document?.replacementAudioDisplayName ?? fileName
                )
            }
        }

        do {
            try rebuildScreenPlayerItem(preserving: 0)
        } catch {
            loadError = "Could not prepare the recording timeline: \(error.localizedDescription)"
            return
        }
        rebuildPointerTimeline()
        rebuildViewportTimeline()
        installObservers()
        isLoaded = true
        rebuildPreviewReframe()
        loadTimelineThumbnails()

        if let session {
            if session.hasUnsavedDraft {
                // Reopened on a draft that outlived its editor.
                hasUnsavedChanges = true
            } else if lastSavedDocument == nil {
                // A recording that has never been saved is unsaved work by
                // definition, which is what makes the close prompt offer to
                // throw the whole thing away.
                hasUnsavedChanges = true
            } else {
                hasUnsavedChanges = false
                // Adopt the loaded document in its normalized in-memory form
                // as the baseline. Defaults filled in during load (an export
                // preset an older project never stored, clips normalized to
                // the real duration) would otherwise read as edits.
                lastSavedDocument = currentDocument()
            }
            session.updateProjectMetadata { $0.lastOpenedAt = Date() }
        }
        StudioProjectRegistry.shared.register(self)
    }

    /// Copies a stored project onto the model. Shared by the initial load and
    /// by discarding changes, so both routes can never drift apart.
    private func applyDocumentSettings(_ document: RecordingEditDocument) {
        isApplyingDocument = true
        defer { isApplyingDocument = false }

        style = document.style.value
        zoomEnabled = document.zoomEnabled
        zoomCues = document.zoomCues
        // A project that never chose its own settings inherits whatever
        // was picked last, so "export as MP4" sticks across recordings.
        exportSettings = document.exportSettings ?? RecordingExportPreferences.lastSettings
        showsClickEffects = document.showsClickEffects ?? showsClickEffects
        showsKeystrokes = document.showsKeystrokes ?? true
        keystrokePlacement = document.keystrokePlacement ?? .bottomCenter
        showsSubtitles = document.showsSubtitles ?? true
        subtitleCues = document.subtitleCues ?? []
        subtitleTimeline = SubtitleTimeline(cues: subtitleCues)
        transcriptWords = document.subtitleWords ?? []
        karaokeTimeline = KaraokeTimeline(cues: subtitleCues, words: transcriptWords)
        subtitleStyle = document.subtitleStyle
        exportAspect = document.exportAspectPreset
        exportAspectMode = document.exportAspectContentMode
        audioExportFormat = document.audioExportFormatValue
        cropRect = document.cropValue
        maskSegments = document.masks ?? []
        updatePreviewMaskComposition()
    }

    func teardown() {
        StudioProjectRegistry.shared.unregister(self)
        exportTask?.cancel()
        audioExportTask?.cancel()
        replacementAudioTask?.cancel()
        shareTask?.cancel()
        transcriptionTask?.cancel()
        projectSaveTask?.cancel()
        previewMaskTask?.cancel()
        timelineThumbnails.cancel()
        writeDraftNow()
        pause()
        if let timeObserver {
            screenPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        screenPlayer.replaceCurrentItem(with: nil)
        cameraPlayer.replaceCurrentItem(with: nil)
    }

    // MARK: - Style presets

    func applyStylePreset(_ preset: RecordingStudioStylePreset) {
        style = preset.value
        appliedStylePresetID = preset.id
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying else { return }
        if hoverPreviewTime != nil {
            hoverPreviewTime = nil
        }
        guard duration >= RecordingClipSegment.minimumDuration else { return }
        if currentTime < 0 || currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        isPlaying = true
        screenPlayer.play()
        syncCameraPlayback()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        screenPlayer.pause()
        cameraPlayer.pause()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(duration, 0))
        currentTime = clamped
        updateActiveTranscriptWord()
        movePlayers(to: clamped)
        if isPlaying {
            syncCameraPlayback()
        }
    }

    /// Moves both players to a source time without touching `currentTime`,
    /// so hover skimming can preview a frame and cleanly hand back to the
    /// real playhead position afterward.
    private func movePlayers(to time: TimeInterval) {
        let editorTime = min(max(time, 0), max(duration, 0))
        let sourceTime = clipTimeline.sourceTime(at: editorTime)
        let target = CMTime(seconds: editorTime, preferredTimescale: 600)
        screenPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if hasCameraVideo {
            if sourceTime >= cameraOffset {
                let cameraTime = CMTime(seconds: max(0, sourceTime - cameraOffset), preferredTimescale: 600)
                cameraPlayer.seek(to: cameraTime, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                cameraPlayer.pause()
                cameraPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    /// Time the preview canvas should render right now.
    var displayTime: TimeInterval {
        if isPlaying {
            let time = screenPlayer.currentTime().seconds
            return time.isFinite ? time : currentTime
        }
        return hoverPreviewTime ?? currentTime
    }

    private func installObservers() {
        timeObserver = screenPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.02, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPlaying {
                    let seconds = time.seconds
                    if seconds >= self.duration - 0.001 {
                        self.pause()
                        self.currentTime = self.duration
                        self.screenPlayer.seek(
                            to: CMTime(seconds: self.duration, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        return
                    }
                    self.currentTime = seconds
                    self.updateActiveTranscriptWord()
                    self.correctCameraDriftIfNeeded()
                }
            }
        }

        installEndObserver()
    }

    private func installEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: screenPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.cameraPlayer.pause()
                self.currentTime = self.duration
            }
        }
    }

    // MARK: - Clips

    var canUndo: Bool {
        _ = undoRevision
        return !isCroppingVideo && !isEditingMasks && editUndoManager.canUndo
    }

    var canRedo: Bool {
        _ = undoRevision
        return !isCroppingVideo && !isEditingMasks && editUndoManager.canRedo
    }

    var selectedClip: RecordingClipSegment? {
        guard let selectedClipID else { return nil }
        return clipTimeline.segments.first { $0.id == selectedClipID }
    }

    var hasClipEdits: Bool {
        !clipTimeline.isUnedited(sourceDuration: sourceDuration)
    }

    var canDeleteSelectedClip: Bool {
        selectedClipID != nil && clipTimeline.segments.count > 1
    }

    func selectClip(id: UUID) {
        guard clipTimeline.segments.contains(where: { $0.id == id }) else { return }
        selectedClipID = id
        selectedCueID = nil
    }

    func selectZoomCue(id: UUID) {
        guard zoomCues.contains(where: { $0.id == id }) else { return }
        selectedCueID = id
        selectedClipID = nil
    }

    func undo() {
        guard !isCroppingVideo, !isEditingMasks, editUndoManager.canUndo else { return }
        pause()
        editUndoManager.undo()
        undoRevision &+= 1
    }

    func redo() {
        guard !isCroppingVideo, !isEditingMasks, editUndoManager.canRedo else { return }
        pause()
        editUndoManager.redo()
        undoRevision &+= 1
    }

    func splitClip(at editorTime: TimeInterval) {
        guard let result = clipTimeline.split(at: editorTime) else { return }
        applyClipTimeline(
            result.timeline,
            selectedID: result.selectedID,
            playheadTime: min(max(editorTime, 0), duration),
            actionName: "Split Clip"
        )
    }

    func splitClipAtHover() {
        guard let timelineHoverTime else { return }
        splitClip(at: timelineHoverTime)
    }

    func deleteSelectedClip() {
        guard let selectedClipID,
              let deletedRange = clipTimeline.editorRange(for: selectedClipID),
              let next = clipTimeline.deleting(segmentID: selectedClipID) else {
            return
        }
        let seekTime = min(deletedRange.lowerBound, next.duration)
        let nextSelection = next.location(at: seekTime)?.segmentID
            ?? next.segments.last?.id
        applyClipTimeline(
            next,
            selectedID: nextSelection,
            playheadTime: seekTime,
            actionName: "Delete Clip"
        )
    }

    func trimClip(_ replacement: RecordingClipSegment) {
        let next = clipTimeline.replacing(replacement)
        guard next != clipTimeline else { return }
        let editorTime = next.editorRange(for: replacement.id)?.lowerBound ?? currentTime
        applyClipTimeline(
            next,
            selectedID: replacement.id,
            playheadTime: min(currentTime, next.duration),
            actionName: "Trim Clip",
            hoverTime: editorTime
        )
    }

    func setClipSpeed(_ speed: Double, forClipID id: UUID) {
        guard let segment = clipTimeline.segments.first(where: { $0.id == id }) else { return }
        let clamped = min(max(speed, RecordingClipSegment.minimumSpeed), RecordingClipSegment.maximumSpeed)
        guard abs(segment.speed - clamped) > 0.000_001 else { return }
        var replacement = segment
        replacement.speed = clamped
        let next = clipTimeline.replacing(replacement)
        applyClipTimeline(
            next,
            selectedID: id,
            playheadTime: min(currentTime, next.duration),
            actionName: "Change Clip Speed"
        )
    }

    func resetClips() {
        let full = RecordingClipTimeline.full(sourceDuration: sourceDuration)
        guard full != clipTimeline else { return }
        applyClipTimeline(
            full,
            selectedID: full.segments.first?.id,
            playheadTime: 0,
            actionName: "Reset Clips"
        )
    }

    private func applyClipTimeline(
        _ requestedTimeline: RecordingClipTimeline,
        selectedID: UUID?,
        playheadTime: TimeInterval,
        actionName: String,
        hoverTime: TimeInterval? = nil
    ) {
        let next = requestedTimeline.normalized(to: sourceDuration)
        guard !next.segments.isEmpty, next != clipTimeline else { return }

        let previousTimeline = clipTimeline
        let previousSelection = selectedClipID
        let previousTime = currentTime
        registerUndo(actionName) { target in
            target.applyClipTimeline(
                previousTimeline,
                selectedID: previousSelection,
                playheadTime: previousTime,
                actionName: actionName
            )
        }

        pause()
        hoverPreviewTime = nil
        timelineHoverTime = nil
        clipTimeline = next
        duration = next.duration
        selectedClipID = selectedID.flatMap { id in
            next.segments.contains(where: { $0.id == id }) ? id : nil
        } ?? next.segments.first?.id
        // Both motion timelines integrate along editor time, so a cut, trim,
        // or speed change invalidates them even when their source data did not
        // change.
        rebuildPointerTimeline()
        rebuildViewportTimeline()

        do {
            try rebuildScreenPlayerItem(preserving: min(max(playheadTime, 0), duration))
            if let hoverTime {
                hoverPreviewTime = min(max(hoverTime, 0), duration)
            }
        } catch {
            loadError = "Could not update the recording timeline: \(error.localizedDescription)"
        }
        updateActiveTranscriptWord()
        scheduleProjectSave()
    }

    private func rebuildScreenPlayerItem(preserving editorTime: TimeInterval) throws {
        guard let screenAsset else { return }
        let playbackAsset: AVAsset
        if let replacementAudio, let screenVideoTrack {
            playbackAsset = try RecordingCompositionBuilder.makeAsset(
                videoTrack: screenVideoTrack,
                timeline: clipTimeline,
                sourceDuration: sourceDuration,
                replacementAudio: replacementAudio
            )
        } else {
            playbackAsset = try RecordingCompositionBuilder.makeAsset(
                from: screenAsset,
                timeline: clipTimeline,
                sourceDuration: sourceDuration
            )
        }

        screenPlayer.replaceCurrentItem(with: AVPlayerItem(asset: playbackAsset))
        screenPlayer.actionAtItemEnd = .pause
        currentTime = min(max(editorTime, 0), duration)
        movePlayers(to: currentTime)
        if timeObserver != nil {
            installEndObserver()
        }
        updatePreviewMaskComposition()
    }

    private func registerUndo(
        _ actionName: String,
        operation: @escaping @MainActor (RecordingStudioModel) -> Void
    ) {
        editUndoManager.registerUndo(withTarget: self) { target in
            operation(target)
        }
        editUndoManager.setActionName(actionName)
        undoRevision &+= 1
    }

    private func loadTimelineThumbnails() {
        timelineThumbnails.prepare(url: screenURL, duration: sourceDuration)
    }

    /// Speed of whichever clip covers this editor time; 1 when nothing
    /// covers it (e.g. past the end of the timeline).
    private func speed(atEditorTime time: TimeInterval) -> Double {
        guard let location = clipTimeline.location(at: time) else { return 1 }
        return clipTimeline.segments[location.segmentIndex].speed
    }

    private func syncCameraPlayback() {
        guard hasCameraVideo else { return }
        let sourceTime = clipTimeline.sourceTime(at: currentTime)
        guard sourceTime >= cameraOffset else {
            cameraPlayer.pause()
            cameraPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        // The camera master is a separate, unedited recording - it has no
        // composition to bake speed into, so a sped-up clip must also play
        // the camera bubble at that rate or the two drift apart immediately.
        let rate = Float(speed(atEditorTime: currentTime))
        let cameraTime = CMTime(seconds: max(0, sourceTime - cameraOffset), preferredTimescale: 600)
        cameraPlayer.seek(to: cameraTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.cameraPlayer.rate = rate
            }
        }
    }

    private func correctCameraDriftIfNeeded() {
        guard hasCameraVideo, isPlaying else { return }
        let sourceTime = clipTimeline.sourceTime(at: currentTime)
        guard sourceTime >= cameraOffset else {
            cameraPlayer.pause()
            return
        }
        if cameraPlayer.rate == 0 {
            syncCameraPlayback()
            return
        }
        let targetRate = Float(speed(atEditorTime: currentTime))
        if abs(cameraPlayer.rate - targetRate) > 0.01 {
            cameraPlayer.rate = targetRate
        }
        let expected = sourceTime - cameraOffset
        let actual = cameraPlayer.currentTime().seconds
        guard expected.isFinite, actual.isFinite else { return }
        if abs(expected - actual) > 0.12 {
            cameraPlayer.seek(
                to: CMTime(seconds: max(0, expected), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    // MARK: - Zoom cues

    private func replaceZoomCues(_ cues: [ZoomCue]) {
        zoomCues = cues.sorted { $0.start < $1.start }
        rebuildViewportTimeline()
        scheduleProjectSave()
    }

    private func applyZoomCues(_ cues: [ZoomCue], actionName: String) {
        let sorted = cues.sorted { $0.start < $1.start }
        guard sorted != zoomCues else { return }
        let previous = zoomCues
        registerUndo(actionName) { target in
            target.applyZoomCues(previous, actionName: actionName)
        }
        replaceZoomCues(sorted)
    }

    func beginZoomCueEdit() {
        if zoomEditSnapshot == nil {
            zoomEditSnapshot = zoomCues
        }
    }

    func endZoomCueEdit(actionName: String = "Edit Zoom") {
        guard let previous = zoomEditSnapshot else { return }
        zoomEditSnapshot = nil
        guard previous != zoomCues else { return }
        registerUndo(actionName) { target in
            target.applyZoomCues(previous, actionName: actionName)
        }
    }

    func resynthesizeZoomCues() {
        applyZoomCues(
            ZoomCueSynthesizer.cues(from: pointerCapture, duration: sourceDuration),
            actionName: "Reset Zooms"
        )
    }

    func addZoomCue(at time: TimeInterval) {
        let sourceTime = clipTimeline.sourceTime(at: time)
        let start = min(max(0, sourceTime), max(0, sourceDuration - 1))
        insertZoomCue(start: start, end: min(sourceDuration, start + 3))
    }

    /// Room a cue has to grow or slide into before it would run into a
    /// neighbor. Cues are kept sorted and non-overlapping, so the only cues
    /// that can be in the way are the ones on either side.
    private func neighborBounds(
        forCueAt index: Int,
        in cues: [ZoomCue]
    ) -> (lower: TimeInterval, upper: TimeInterval) {
        (
            lower: index > 0 ? max(0, cues[index - 1].end) : 0,
            upper: index + 1 < cues.count
                ? min(cues[index + 1].start, sourceDuration)
                : sourceDuration
        )
    }

    /// Where a new cue can actually go. A request landing inside an existing
    /// zoom is pushed past it rather than dropped, and the span is trimmed to
    /// the next cue; nil when no gap from here on is long enough to use.
    private func freeSpan(
        from start: TimeInterval,
        preferredEnd: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard sourceDuration > 0 else { return nil }
        let length = max(preferredEnd - start, ZoomCue.minimumDuration)
        var lower = min(max(start, 0), sourceDuration)
        // Walks chains of touching cues, so "add at playhead" inside a run of
        // zooms lands in the first real gap after them.
        while let covering = zoomCues.first(where: { $0.start <= lower && $0.end > lower }) {
            lower = covering.end
        }
        let upper = zoomCues
            .filter { $0.start > lower }
            .map(\.start)
            .min() ?? sourceDuration
        guard upper - lower >= ZoomCue.minimumDuration else { return nil }
        return lower...min(lower + length, upper)
    }

    /// Creates a zoom cue spanning a dragged range in the zoom lane. Times
    /// are editor time and need not be ordered.
    func addZoomCue(fromEditorTime editorStart: TimeInterval, toEditorTime editorEnd: TimeInterval) {
        let lowSource = clipTimeline.sourceTime(at: min(editorStart, editorEnd))
        let highSource = clipTimeline.sourceTime(at: max(editorStart, editorEnd))
        let start = min(max(0, lowSource), max(0, sourceDuration - 0.5))
        let end = max(start + 0.5, min(sourceDuration, highSource))
        insertZoomCue(start: start, end: end)
    }

    private func insertZoomCue(start: TimeInterval, end: TimeInterval) {
        guard let span = freeSpan(from: start, preferredEnd: end) else { return }
        let hasPointerTrack = !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty
        let editorTime = clipTimeline.editorTime(forSourceTime: span.lowerBound) ?? currentTime
        let target = pointerTimeline.location(at: editorTime) ?? CGPoint(x: 0.5, y: 0.5)
        let cue = ZoomCue(
            start: span.lowerBound,
            end: span.upperBound,
            zoom: 1.5,
            anchorMode: hasPointerTrack ? .pointerAnchor : .pinnedAnchor,
            pinnedPoint: target,
            boundsBias: hasPointerTrack ? 0.25 : 0
        )
        var cues = zoomCues
        cues.append(cue)
        applyZoomCues(cues, actionName: "Add Zoom")
        selectedCueID = cue.id
        selectedClipID = nil
    }

    func removeZoomCue(id: UUID) {
        applyZoomCues(zoomCues.filter { $0.id != id }, actionName: "Remove Zoom")
        if selectedCueID == id {
            selectedCueID = nil
        }
    }

    /// Applies an edited cue, stopping either edge at the neighboring cues so
    /// blocks can be resized right up to each other but never through.
    func updateZoomCue(_ cue: ZoomCue) {
        var cues = zoomCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = neighborBounds(forCueAt: index, in: cues)
        var updated = sanitized(cue)
        updated.start = min(
            max(updated.start, bounds.lower),
            max(bounds.lower, bounds.upper - ZoomCue.minimumDuration)
        )
        updated.end = min(
            max(updated.end, updated.start + ZoomCue.minimumDuration),
            bounds.upper
        )
        cues[index] = updated
        replaceZoomCues(cues)
    }

    /// Slides a cue without changing its length. Unlike a resize, running into
    /// a neighbor parks the block against it rather than squashing it.
    func moveZoomCue(_ cue: ZoomCue) {
        var cues = zoomCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = neighborBounds(forCueAt: index, in: cues)
        let room = max(bounds.upper - bounds.lower, ZoomCue.minimumDuration)
        let length = min(max(cue.duration, ZoomCue.minimumDuration), room)
        var moved = sanitized(cue)
        moved.start = min(max(cue.start, bounds.lower), max(bounds.lower, bounds.upper - length))
        moved.end = min(moved.start + length, bounds.upper)
        cues[index] = moved
        replaceZoomCues(cues)
    }

    /// Everything about a cue except its placement, which the caller clamps
    /// against its neighbors.
    private func sanitized(_ cue: ZoomCue) -> ZoomCue {
        var cue = cue
        cue.start = min(max(0, cue.start), sourceDuration)
        cue.end = min(max(cue.start, cue.end), sourceDuration)
        cue.zoom = min(max(cue.zoom, 1), 4)
        cue.boundsBias = min(max(cue.boundsBias, 0), 1)
        cue.pinnedPoint = CGPoint(
            x: min(max(cue.pinnedPoint.x, 0), 1),
            y: min(max(cue.pinnedPoint.y, 0), 1)
        )
        return cue
    }

    var selectedCue: ZoomCue? {
        zoomCues.first { $0.id == selectedCueID }
    }

    var visibleRecordedPressTimes: [TimeInterval] {
        recordedPressTimes.compactMap { clipTimeline.editorTime(forSourceTime: $0) }
    }

    /// One visual block per cue on the edited timeline. A cue's per-segment
    /// slices are always contiguous in editor time (a cut removes the editor
    /// time between them), so they merge into a single block - cutting a clip
    /// inside a zoom never splits the zoom's lane representation.
    var zoomTimelineBlocks: [RecordingZoomTimelineBlock] {
        zoomCues
            .filter { !$0.isImplicit }
            .compactMap { cue in
                let slices = clipTimeline.slices(overlapping: cue.start, sourceEnd: cue.end)
                guard let first = slices.first, let last = slices.last else { return nil }
                return RecordingZoomTimelineBlock(
                    cue: cue,
                    editorStart: first.editorStart,
                    editorEnd: last.editorEnd
                )
            }
    }

    func sourceTime(atEditorTime time: TimeInterval) -> TimeInterval {
        clipTimeline.sourceTime(at: time)
    }

    func editorTime(forSourceTime time: TimeInterval) -> TimeInterval? {
        clipTimeline.editorTime(forSourceTime: time)
    }

    private func rebuildPointerTimeline() {
        reframeFocusTimeline = nil
        reframeFocusResolved = false
        guard pointerIsSynthesized, sourceDuration > 0 else {
            pointerTimeline = .empty
            return
        }
        pointerTimeline = PointerTimeline.build(
            capture: pointerCapture,
            duration: sourceDuration,
            recordingSizeInPoints: recordingPointSize,
            fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
            clipTimeline: clipTimeline
        )
    }

    private func rebuildViewportTimeline() {
        guard sourceDuration > 0 else {
            viewportTimeline = .identity
            return
        }
        viewportTimeline = ViewportTimeline.build(
            cues: zoomCues,
            capture: pointerCapture,
            clipTimeline: clipTimeline
        )
        // The reframe camera derives from the viewport, so it follows
        // every rebuild (zoom edits, cuts, speed changes).
        rebuildPreviewReframe()
    }

    private func scheduleProjectSave() {
        guard isLoaded, !isApplyingDocument, session != nil else { return }
        hasUnsavedChanges = true
        projectSaveTask?.cancel()
        projectSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.writeDraftNow()
        }
    }

    /// Every edit in the editor, as a storable document.
    private func currentDocument() -> RecordingEditDocument {
        RecordingEditDocument(
            style: style,
            zoomEnabled: zoomEnabled,
            zoomCues: zoomCues.filter { !$0.isImplicit },
            clipTimeline: clipTimeline,
            exportSettings: exportSettings,
            showsClickEffects: showsClickEffects,
            showsKeystrokes: showsKeystrokes,
            keystrokePlacement: keystrokePlacement,
            showsSubtitles: showsSubtitles,
            subtitleCues: subtitleCues.isEmpty ? nil : subtitleCues,
            subtitleWords: transcriptWords.isEmpty ? nil : transcriptWords,
            subtitleStyle: subtitleStyle,
            exportAspect: exportAspect,
            exportAspectMode: exportAspectMode,
            replacementAudioFileName: replacementAudio?.url.lastPathComponent,
            replacementAudioDisplayName: replacementAudio?.displayName,
            audioExportFormat: audioExportFormat,
            crop: RecordingVideoCrop.isUnit(cropRect) ? nil : cropRect,
            masks: maskSegments.isEmpty ? nil : maskSegments
        )
    }

    /// True until the project has been saved at least once. Only these get
    /// offered "Delete and close" - throwing away a project the user already
    /// committed to would be unrecoverable.
    var hasNeverBeenSaved: Bool {
        guard let session else { return false }
        return !session.hasSavedProject
    }

    /// Persists the working copy. Cheap, debounced, and never touches the
    /// committed `edit.json`, so a crash costs nothing and Save still means
    /// something.
    private func writeDraftNow() {
        guard isLoaded, let session else { return }
        let document = currentDocument()
        if document == lastSavedDocument {
            // Edited back to the saved state (undo, or a discard landing):
            // the draft is now noise and would reopen the project dirty.
            session.removeDraftDocument()
            hasUnsavedChanges = false
        } else {
            try? session.writeDraftDocument(document)
            hasUnsavedChanges = true
        }
        dropStaleRender(for: document, in: session)
    }

    /// A cached flatten that no longer matches the edits is worse than no
    /// cache: History previews it and Share would upload it.
    private func dropStaleRender(for document: RecordingEditDocument, in session: RecordingSession) {
        guard session.existingFinalURL != nil else { return }
        guard session.freshFinalURL(matching: document) == nil else { return }
        session.removeFinalVideos()
    }

    /// Writes the working copy immediately, bypassing the debounce. Used on
    /// teardown and on quit so no edit is left only in memory.
    func flushDraft() {
        projectSaveTask?.cancel()
        writeDraftNow()
    }

    /// ⌘S. Commits the working copy to `edit.json` and clears the draft.
    func saveProject() {
        guard isLoaded, let session else { return }
        projectSaveTask?.cancel()
        let document = currentDocument()
        do {
            try session.writeEditDocument(document)
            session.removeDraftDocument()
            lastSavedDocument = document
            hasUnsavedChanges = false
            session.updateProjectMetadata { $0.savedAt = Date() }
            dropStaleRender(for: document, in: session)
            RecordingProjectStore.shared.reload()
            flashSaveConfirmation()
        } catch {
            print("Failed to save recording project: \(error)")
        }
    }

    /// Throws away everything since the last save and returns the editor to
    /// that state. Only offered for projects that have actually been saved.
    func discardChanges() async {
        guard isLoaded, let session else { return }
        projectSaveTask?.cancel()
        session.removeDraftDocument()
        guard let document = lastSavedDocument else { return }
        applyDocumentSettings(document)
        await applyDocumentTimeline(document)
        // Rebuilding the timeline touches published state; let the normal
        // draft path settle the dirty flag rather than assuming it landed.
        flushDraft()
    }

    /// Deletes the whole recording package - footage included - and its
    /// History entry. Reserved for a project that was never saved.
    func deleteProject() {
        guard let session else { return }
        teardown()
        RecordingProjectStore.shared.delete(session)
    }

    private func flashSaveConfirmation() {
        saveFlash = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            self?.saveFlash = false
        }
    }

    /// The parts of a stored project that need the timeline rebuilt around
    /// them: cuts, the imported soundtrack, and everything derived from both.
    private func applyDocumentTimeline(_ document: RecordingEditDocument) async {
        guard let session else { return }
        isApplyingDocument = true

        if let storedClips = document.clips, !storedClips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: storedClips)
                .normalized(to: sourceDuration)
        } else {
            clipTimeline = .legacyTrim(
                start: document.trimStart,
                end: document.trimEnd,
                sourceDuration: sourceDuration
            )
        }
        duration = clipTimeline.duration
        selectedClipID = clipTimeline.segments.first?.id

        if let fileName = document.replacementAudioFileName {
            let url = session.directoryURL.appendingPathComponent(fileName)
            if url != replacementAudio?.url, FileManager.default.fileExists(atPath: url.path) {
                replacementAudio = await RecordingReplacementAudio.load(
                    url: url,
                    displayName: document.replacementAudioDisplayName ?? fileName
                )
            }
        } else {
            replacementAudio = nil
        }

        isApplyingDocument = false

        try? rebuildScreenPlayerItem(preserving: currentTime)
        rebuildPointerTimeline()
        rebuildViewportTimeline()
        rebuildPreviewReframe()
        editUndoManager.removeAllActions()
        undoRevision += 1
    }

    /// Viewport frame to render at a given time, honoring the zoom toggle.
    func viewportFrame(at time: TimeInterval) -> ViewportFrame {
        guard zoomEnabled else { return .identity }
        return viewportTimeline.frame(at: time)
    }

    /// True when this session was captured without the OS cursor, so the
    /// preview and export draw the synthetic pointer.
    var pointerIsSynthesized: Bool {
        manifest?.pointerSynthesized == true
    }

    /// Smoothed normalized pointer location for the preview overlay; nil when
    /// the recording carries its cursor in the pixels.
    func pointerLocation(at time: TimeInterval) -> CGPoint? {
        guard pointerIsSynthesized else { return nil }
        return pointerTimeline.location(at: time)
    }

    func pointerFrame(at time: TimeInterval) -> PointerFrame? {
        guard pointerIsSynthesized else { return nil }
        return pointerTimeline.frame(at: time)
    }

    func artwork(id: String?) -> PointerArtwork? {
        pointerTimeline.artwork(id: id)
    }

    /// Legacy sessions may already contain baked-in press feedback; only
    /// sidecar-reconstructed sessions can re-render it on demand.
    var canShowPressEffects: Bool {
        pointerIsSynthesized && manifest?.pressEffectsBaked == false
    }

    var showsPressEffects: Bool {
        canShowPressEffects && showsClickEffects
    }

    var hasKeystrokes: Bool {
        !keystrokeTimeline.isEmpty
    }

    // MARK: - Transcription

    /// Only narrated sessions can be transcribed; the mic requirement means
    /// legacy bare movies and silent captures never show the section.
    var canTranscribe: Bool {
        manifest?.includesMicrophone == true
    }

    var hasSubtitles: Bool {
        !subtitleTimeline.isEmpty
    }

    /// Subtitle text to draw over the card right now; nil when hidden or
    /// nobody is speaking.
    func subtitleText(at time: TimeInterval) -> String? {
        guard showsSubtitles, hasSubtitles else { return nil }
        return subtitleTimeline.text(at: clipTimeline.sourceTime(at: time))
    }

    /// Karaoke word state for the bar at this editor time; nil when the
    /// style doesn't highlight words or no timings exist, in which case
    /// the bar renders `subtitleText` plainly.
    func subtitleKaraokeLine(at time: TimeInterval) -> KaraokeTimeline.Line? {
        guard showsSubtitles, subtitleStyle.highlightsSpokenWord,
              !karaokeTimeline.isEmpty else {
            return nil
        }
        return karaokeTimeline.line(at: clipTimeline.sourceTime(at: time))
    }

    func transcribe() {
        guard !transcriptionState.isTranscribing, isLoaded else { return }
        transcriptionState = .transcribing
        let movieURL = screenURL
        transcriptionTask = Task { [weak self] in
            do {
                let transcript = try await RecordingTranscriptionService.transcribe(screenMovieURL: movieURL)
                guard !Task.isCancelled else { return }
                self?.applyTranscription(transcript)
            } catch {
                guard !Task.isCancelled else { return }
                self?.transcriptionState = .failed(error.localizedDescription)
            }
        }
    }

    private func applyTranscription(_ transcript: RecordingTranscript) {
        subtitleCues = transcript.cues
        subtitleTimeline = SubtitleTimeline(cues: transcript.cues)
        transcriptWords = transcript.words
        karaokeTimeline = KaraokeTimeline(cues: transcript.cues, words: transcript.words)
        showsSubtitles = true
        transcriptionState = .idle
        updateActiveTranscriptWord()
        scheduleProjectSave()
    }

    func removeTranscription() {
        subtitleCues = []
        subtitleTimeline = .empty
        transcriptWords = []
        karaokeTimeline = .empty
        activeTranscriptWordIndex = nil
        transcriptionState = .idle
        scheduleProjectSave()
    }

    func updateSubtitleText(id: UUID, text: String) {
        guard let index = subtitleCues.firstIndex(where: { $0.id == id }),
              subtitleCues[index].text != text else {
            return
        }
        subtitleCues[index].text = text
        subtitleTimeline = SubtitleTimeline(cues: subtitleCues)
        karaokeTimeline = KaraokeTimeline(cues: subtitleCues, words: transcriptWords)
        scheduleProjectSave()
    }

    /// Moves the paused playhead to a cue's first surviving frame; a cue
    /// whose audio was cut out entirely has no home on the edited timeline.
    func seekToSubtitle(_ cue: RecordingSubtitleCue) {
        let target = clipTimeline.editorTime(forSourceTime: cue.start)
            ?? clipTimeline.editorTime(forSourceTime: (cue.start + cue.end) / 2)
        guard let target else { return }
        pause()
        seek(to: target)
    }

    /// Cue under the playhead right now, for highlighting the list row.
    var activeSubtitleCue: RecordingSubtitleCue? {
        guard hasSubtitles else { return nil }
        return subtitleTimeline.cue(at: clipTimeline.sourceTime(at: currentTime))
    }

    // MARK: - Transcript editing

    /// Cues-only projects (transcribed before words were stored) can still
    /// show captions but need a fresh transcription to edit by text.
    var hasTranscriptWords: Bool {
        !transcriptWords.isEmpty
    }

    /// Whether this word's audio still exists on the edited timeline.
    func transcriptWordSurvives(_ index: Int) -> Bool {
        guard transcriptWords.indices.contains(index) else { return false }
        return clipTimeline.editorTime(forSourceTime: transcriptWords[index].midpoint) != nil
    }

    func isFillerWord(_ index: Int) -> Bool {
        guard transcriptWords.indices.contains(index) else { return false }
        return TranscriptEditPlanner.isFiller(transcriptWords[index])
    }

    /// Fillers that would actually be cut - ones already removed don't count.
    var removableFillerWordCount: Int {
        TranscriptEditPlanner.fillerIndices(in: transcriptWords)
            .count { transcriptWordSurvives($0) }
    }

    /// Narration pauses long enough to trim that still exist in the edit.
    var trimmableSilenceCount: Int {
        TranscriptEditPlanner.silenceCutRanges(in: transcriptWords, sourceDuration: sourceDuration)
            .count { !clipTimeline.slices(overlapping: $0.lowerBound, sourceEnd: $0.upperBound).isEmpty }
    }

    /// Moves the paused playhead to a word's first surviving frame.
    func seekToTranscriptWord(at index: Int) {
        guard transcriptWords.indices.contains(index) else { return }
        let word = transcriptWords[index]
        let target = clipTimeline.editorTime(forSourceTime: word.start)
            ?? clipTimeline.editorTime(forSourceTime: word.midpoint)
        guard let target else { return }
        pause()
        seek(to: target)
    }

    /// Cuts the selected words' footage out of the video.
    func cutTranscriptWords(in range: ClosedRange<Int>) {
        guard let cut = TranscriptEditPlanner.cutRange(
            forWordsAt: range,
            in: transcriptWords,
            sourceDuration: sourceDuration
        ) else { return }
        cutSourceRanges([cut], actionName: range.count == 1 ? "Cut Word" : "Cut Words")
    }

    func removeFillerWords() {
        cutSourceRanges(
            TranscriptEditPlanner.fillerCutRanges(in: transcriptWords, sourceDuration: sourceDuration),
            actionName: "Remove Filler Words"
        )
    }

    func trimNarrationSilences() {
        cutSourceRanges(
            TranscriptEditPlanner.silenceCutRanges(in: transcriptWords, sourceDuration: sourceDuration),
            actionName: "Trim Silences"
        )
    }

    /// The shared transcript-cut path: removes source ranges from the clip
    /// timeline and drops the cut words from any overlapping captions. Both
    /// registrations land in one undo group, so a single ⌘Z restores the
    /// footage and the caption text together.
    private func cutSourceRanges(_ ranges: [ClosedRange<TimeInterval>], actionName: String) {
        let merged = RecordingClipTimeline.mergedRanges(ranges)
        guard !merged.isEmpty,
              let next = clipTimeline.removingSourceRanges(merged)?.normalized(to: sourceDuration),
              next != clipTimeline else {
            return
        }

        let updatedCues = Self.rebuildingCueTexts(
            subtitleCues,
            words: transcriptWords,
            cutRanges: merged,
            surviving: next
        )
        if updatedCues != subtitleCues {
            applySubtitleCues(updatedCues, actionName: actionName)
        }

        // Park the playhead on the first splice so the result is audible
        // right where the cut happened.
        let playhead = next.editorTime(forSourceTime: merged[0].upperBound)
            ?? min(currentTime, next.duration)
        applyClipTimeline(
            next,
            selectedID: selectedClipID,
            playheadTime: playhead,
            actionName: actionName
        )
    }

    private func applySubtitleCues(_ cues: [RecordingSubtitleCue], actionName: String) {
        guard cues != subtitleCues else { return }
        let previous = subtitleCues
        registerUndo(actionName) { target in
            target.applySubtitleCues(previous, actionName: actionName)
        }
        subtitleCues = cues
        subtitleTimeline = SubtitleTimeline(cues: cues)
        karaokeTimeline = KaraokeTimeline(cues: cues, words: transcriptWords)
        scheduleProjectSave()
    }

    /// Rewrites the text of cues touched by a cut so captions stop showing
    /// words whose audio is gone. Only touched cues are rebuilt, so manual
    /// caption edits elsewhere survive. A word belongs to the last cue that
    /// starts at or before it.
    private static func rebuildingCueTexts(
        _ cues: [RecordingSubtitleCue],
        words: [RecordingTranscriptWord],
        cutRanges: [ClosedRange<TimeInterval>],
        surviving timeline: RecordingClipTimeline
    ) -> [RecordingSubtitleCue] {
        guard !words.isEmpty, !cues.isEmpty else { return cues }
        var result = cues
        let byStart = result.indices.sorted { result[$0].start < result[$1].start }

        for (position, index) in byStart.enumerated() {
            let cue = result[index]
            let overlapsCut = cutRanges.contains {
                $0.lowerBound < cue.end && $0.upperBound > cue.start
            }
            guard overlapsCut else { continue }

            let nextCueStart = position < byStart.count - 1
                ? result[byStart[position + 1]].start
                : .infinity
            result[index].text = words
                .filter { word in
                    word.start >= cue.start - 0.001
                        && word.start < nextCueStart - 0.001
                        && timeline.editorTime(forSourceTime: word.midpoint) != nil
                }
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Recomputes which word the playhead is on; assigns only on change so
    /// observation-driven views wake on word boundaries, not every tick.
    private func updateActiveTranscriptWord() {
        guard !transcriptWords.isEmpty else {
            if activeTranscriptWordIndex != nil {
                activeTranscriptWordIndex = nil
            }
            return
        }
        let index = Self.transcriptWordIndex(
            at: clipTimeline.sourceTime(at: currentTime),
            in: transcriptWords
        )
        if activeTranscriptWordIndex != index {
            activeTranscriptWordIndex = index
        }
    }

    /// Last word started at or before this source time, if the time is
    /// still within it (with a small bridge across inter-word gaps so the
    /// highlight doesn't flicker between words).
    private static func transcriptWordIndex(
        at sourceTime: TimeInterval,
        in words: [RecordingTranscriptWord]
    ) -> Int? {
        guard sourceTime.isFinite, !words.isEmpty else { return nil }
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= sourceTime {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0 else { return nil }
        return sourceTime <= words[index].end + 0.25 ? index : nil
    }

    /// Caption to draw over the card right now; nil when hidden or silent.
    func keystrokeCaption(at time: TimeInterval) -> KeystrokeCaptionFrame? {
        guard showsKeystrokes, hasKeystrokes else { return nil }
        return keystrokeTimeline.frame(at: clipTimeline.sourceTime(at: time))
    }

    private var recordingPointSize: CGSize {
        let scale = max(CGFloat(manifest?.pixelScale ?? 1), 1)
        return CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
    }

    func isCameraVisible(at time: TimeInterval) -> Bool {
        // No time gate: before cameraOffset the player is parked on the
        // camera's first frame, which beats the bubble popping in late.
        hasCameraVideo && style.camera.isVisible
    }

    // MARK: - Export

    private func makeExportConfiguration() -> RecordingStudioExporter.Configuration {
        let reframe = makeReframeTrack(crop: cropRect)
        let exportVideoSize = croppedVideoSize
        let fitContentAspect: CGFloat? =
            exportAspect != .original && exportAspectMode == .fit && exportVideoSize.height > 0
                ? exportVideoSize.width / exportVideoSize.height
                : nil
        return RecordingStudioExporter.Configuration(
            screenURL: screenURL,
            cameraURL: hasCameraVideo && style.camera.isVisible ? session?.cameraURL : nil,
            cameraOffset: cameraOffset,
            style: style,
            viewportTimeline: (zoomEnabled ? viewportTimeline : .identity).cropped(to: cropRect),
            pointerTimeline: pointerIsSynthesized ? pointerTimeline : nil,
            showsPressEffects: showsPressEffects,
            keystrokeTimeline: showsKeystrokes && hasKeystrokes ? keystrokeTimeline : nil,
            keystrokePlacement: keystrokePlacement,
            subtitleTimeline: showsSubtitles && hasSubtitles ? subtitleTimeline : nil,
            subtitleStyle: subtitleStyle,
            karaokeTimeline: showsSubtitles && hasSubtitles && !karaokeTimeline.isEmpty
                ? karaokeTimeline
                : nil,
            canvasSize: exportAspect == .original
                ? exportVideoSize
                : exportAspect.canvasSize(for: exportVideoSize),
            clipTimeline: clipTimeline,
            exportSettings: exportSettings,
            audioReplacementURL: replacementAudio?.url,
            reframe: reframe,
            fitContentAspect: fitContentAspect,
            crop: cropRect,
            masks: maskSegments
        )
    }

    /// The crop-and-follow camera for non-original aspect exports. Focus
    /// comes from the recorded pointer whenever the session captured one,
    /// whether or not the cursor is drawn synthetically.
    private func makeReframeTrack(crop: CGRect) -> ReframeTrack? {
        guard exportAspect != .original, exportAspectMode == .fill else { return nil }
        let focusTimeline = reframeFocusPointer()
        let effectiveViewport = (zoomEnabled ? viewportTimeline : .identity).cropped(to: crop)
        return ReframeTrack.build(
            preset: exportAspect,
            sourceSize: RecordingVideoCrop.croppedSize(videoSize, crop: crop),
            viewportTimeline: effectiveViewport,
            duration: duration
        ) { editorTime in
            guard let location = focusTimeline?.location(at: editorTime) else { return nil }
            let remapped = RecordingVideoCrop.point(location, in: crop)
            return CGPoint(
                x: min(max(remapped.x, 0), 1),
                y: min(max(remapped.y, 0), 1)
            )
        }
    }

    /// The focus source is immutable per session, so it resolves once.
    private func reframeFocusPointer() -> PointerTimeline? {
        if reframeFocusResolved { return reframeFocusTimeline }
        reframeFocusResolved = true
        if pointerIsSynthesized {
            reframeFocusTimeline = pointerTimeline
        } else if !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty {
            reframeFocusTimeline = PointerTimeline.build(
                capture: pointerCapture,
                duration: sourceDuration,
                recordingSizeInPoints: recordingPointSize,
                fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
                clipTimeline: clipTimeline
            )
        }
        return reframeFocusTimeline
    }

    private func rebuildPreviewReframe() {
        guard isLoaded else { return }
        previewReframe = makeReframeTrack(crop: effectivePreviewCrop)
    }

    // MARK: - Video crop

    var hasVideoCrop: Bool {
        !RecordingVideoCrop.isUnit(cropRect)
    }

    var effectivePreviewCrop: CGRect {
        isCroppingVideo || isEditingMasks ? RecordingVideoCrop.unit : cropRect
    }

    var croppedVideoSize: CGSize {
        RecordingVideoCrop.croppedSize(videoSize, crop: cropRect)
    }

    private var previewVideoSize: CGSize {
        RecordingVideoCrop.croppedSize(videoSize, crop: effectivePreviewCrop)
    }

    func beginVideoCrop() {
        guard isLoaded, !isCroppingVideo, !isEditingMasks else { return }
        pause()
        cropDraft = cropRect
        cropAspect = .freeform
        isCroppingVideo = true
        rebuildPreviewReframe()
    }

    func cancelVideoCrop() {
        guard isCroppingVideo else { return }
        isCroppingVideo = false
        rebuildPreviewReframe()
    }

    func applyVideoCrop() {
        guard isCroppingVideo else { return }
        isCroppingVideo = false
        setVideoCrop(cropDraft, actionName: "Crop Video")
        rebuildPreviewReframe()
    }

    func resetVideoCropDraft() {
        guard isCroppingVideo else { return }
        cropDraft = RecordingVideoCrop.unit
        if let ratio = cropAspect.normalizedRatio(imageSize: videoSize) {
            cropDraft = CropRectEditor.applyAspect(to: cropDraft, aspect: ratio)
        }
    }

    func setVideoCropAspect(_ aspect: CropAspectRatio) {
        guard isCroppingVideo else { return }
        cropAspect = aspect
        if let ratio = aspect.normalizedRatio(imageSize: videoSize) {
            cropDraft = CropRectEditor.applyAspect(to: cropDraft, aspect: ratio)
        }
    }

    func updateVideoCropDraft(handle: CropHandle, toNormalized point: CGPoint) {
        guard isCroppingVideo else { return }
        let aspect = handle.isCorner ? cropAspect.normalizedRatio(imageSize: videoSize) : nil
        cropDraft = CropRectEditor.resize(
            cropDraft,
            handle: handle,
            to: point,
            aspect: aspect,
            minWidth: minimumVideoCropWidth,
            minHeight: minimumVideoCropHeight,
            fromCenter: isCropCenterResizeModifierPressed
        )
    }

    func moveVideoCropDraft(from start: CGRect, byNormalized delta: CGSize) {
        guard isCroppingVideo else { return }
        cropDraft = CropRectEditor.move(start, by: delta)
    }

    private var isCropCenterResizeModifierPressed: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.option) || (flags.contains(.command) && flags.contains(.shift))
    }

    private var minimumVideoCropWidth: CGFloat {
        guard videoSize.width > 0 else { return 0.05 }
        return min(0.5, max(RecordingVideoCrop.minimumSpan, 24 / videoSize.width))
    }

    private var minimumVideoCropHeight: CGFloat {
        guard videoSize.height > 0 else { return 0.05 }
        return min(0.5, max(RecordingVideoCrop.minimumSpan, 24 / videoSize.height))
    }

    private func setVideoCrop(_ rect: CGRect, actionName: String) {
        let next = RecordingVideoCrop.sanitized(rect)
        guard next != cropRect else { return }
        let previous = cropRect
        registerUndo(actionName) { target in
            target.setVideoCrop(previous, actionName: actionName)
        }
        cropRect = next
        rebuildPreviewReframe()
        scheduleProjectSave()
    }

    // MARK: - Video masks

    var selectedMask: RecordingMaskSegment? {
        guard let selectedMaskID else { return nil }
        return maskSegments.first { $0.id == selectedMaskID }
    }

    private var selectedMaskIndex: Int? {
        guard let selectedMaskID else { return nil }
        return maskSegments.firstIndex { $0.id == selectedMaskID }
    }

    func beginMaskEditing() {
        guard isLoaded, !isEditingMasks, !isCroppingVideo else { return }
        pause()
        maskEditSnapshot = maskSegments
        isEditingMasks = true
        if maskSegments.isEmpty {
            addMask()
        } else {
            selectedMaskID = maskSegments.last?.id
        }
        rebuildPreviewReframe()
    }

    func endMaskEditing() {
        guard isEditingMasks else { return }
        isEditingMasks = false
        selectedMaskID = nil
        if let snapshot = maskEditSnapshot, snapshot != maskSegments {
            let edited = maskSegments
            maskSegments = snapshot
            setMaskSegments(edited, actionName: "Edit Masks")
        }
        maskEditSnapshot = nil
        rebuildPreviewReframe()
    }

    var showsMaskLane: Bool {
        isEditingMasks || !maskSegments.isEmpty
    }

    func addMask() {
        guard isEditingMasks else { return }
        let segment = RecordingMaskSegment()
        maskSegments.append(segment)
        selectedMaskID = segment.id
        updatePreviewMaskComposition()
    }

    func addMask(at time: TimeInterval) {
        guard isEditingMasks else { return }
        var segment = RecordingMaskSegment()
        if duration > RecordingMaskSegment.minimumDuration {
            let length = min(3, duration)
            let start = min(max(time - length / 2, 0), duration - length)
            segment.start = start
            segment.end = start + length
        }
        maskSegments.append(segment)
        selectedMaskID = segment.id
        seek(to: min(max(time, 0), max(duration, 0)))
        updatePreviewMaskComposition()
    }

    func deleteSelectedMask() {
        guard isEditingMasks, let selectedMaskID else { return }
        maskSegments.removeAll { $0.id == selectedMaskID }
        self.selectedMaskID = maskSegments.last?.id
        updatePreviewMaskComposition()
    }

    func removeMask(id: UUID) {
        if isEditingMasks {
            maskSegments.removeAll { $0.id == id }
            if selectedMaskID == id { selectedMaskID = maskSegments.last?.id }
            updatePreviewMaskComposition()
        } else {
            var edited = maskSegments
            edited.removeAll { $0.id == id }
            setMaskSegments(edited, actionName: "Remove Mask")
        }
    }

    func selectMask(id: UUID) {
        guard isEditingMasks,
              let segment = maskSegments.first(where: { $0.id == id }) else { return }
        selectedMaskID = id
        if !segment.isActive(at: currentTime) {
            pause()
            seek(to: segment.editorRange(duration: duration).lowerBound)
        }
    }

    func beginMaskRangeEdit() {
        guard maskRangeEditSnapshot == nil else { return }
        pause()
        maskRangeEditSnapshot = maskSegments
    }

    func endMaskRangeEdit(actionName: String) {
        guard let snapshot = maskRangeEditSnapshot else { return }
        maskRangeEditSnapshot = nil
        guard !isEditingMasks, snapshot != maskSegments else { return }
        let edited = maskSegments
        maskSegments = snapshot
        setMaskSegments(edited, actionName: actionName)
    }

    func updateMaskRange(id: UUID, start: Double, end: Double) {
        guard let index = maskSegments.firstIndex(where: { $0.id == id }) else { return }
        let clampedStart = min(
            max(0, start),
            max(0, duration - RecordingMaskSegment.minimumDuration)
        )
        maskSegments[index].start = clampedStart
        maskSegments[index].end = min(
            max(clampedStart + RecordingMaskSegment.minimumDuration, end),
            max(duration, clampedStart + RecordingMaskSegment.minimumDuration)
        )
        updatePreviewMaskComposition()
    }

    func updateSelectedMask(handle: CropHandle, toNormalized point: CGPoint) {
        guard let index = selectedMaskIndex else { return }
        maskSegments[index].rect = CropRectEditor.resize(
            maskSegments[index].rect,
            handle: handle,
            to: point,
            aspect: nil,
            minWidth: minimumVideoCropWidth,
            minHeight: minimumVideoCropHeight,
            fromCenter: isCropCenterResizeModifierPressed
        )
        updatePreviewMaskComposition()
    }

    func moveSelectedMask(from start: CGRect, byNormalized delta: CGSize) {
        guard let index = selectedMaskIndex else { return }
        maskSegments[index].rect = CropRectEditor.move(start, by: delta)
        updatePreviewMaskComposition()
    }

    func setSelectedMaskEffect(_ effect: RecordingMaskSegment.Effect) {
        guard let index = selectedMaskIndex, maskSegments[index].effect != effect else { return }
        maskSegments[index].effect = effect
        updatePreviewMaskComposition()
    }

    func setSelectedMaskAmount(_ amount: Double) {
        guard let index = selectedMaskIndex else { return }
        maskSegments[index].amount = min(
            max(amount, RecordingMaskSegment.minimumAmount),
            RecordingMaskSegment.maximumAmount
        )
        updatePreviewMaskComposition()
    }

    private func setMaskSegments(_ segments: [RecordingMaskSegment], actionName: String) {
        guard segments != maskSegments else { return }
        let previous = maskSegments
        registerUndo(actionName) { target in
            target.setMaskSegments(previous, actionName: actionName)
        }
        maskSegments = segments
        updatePreviewMaskComposition()
        scheduleProjectSave()
    }

    private func updatePreviewMaskComposition() {
        previewMaskState.update(maskSegments)
        previewMaskTask?.cancel()
        previewMaskTask = nil
        guard let item = screenPlayer.currentItem else { return }
        if maskSegments.isEmpty {
            item.videoComposition = nil
            refreshPausedPreviewFrame()
            return
        }
        if item.videoComposition != nil {
            refreshPausedPreviewFrame()
            return
        }
        let state = previewMaskState
        let asset = item.asset
        previewMaskTask = Task { [weak self, weak item] in
            let composition = try? await AVMutableVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    request.finish(
                        with: RecordingMaskRenderer.masked(
                            request.sourceImage,
                            segments: state.current(),
                            at: request.compositionTime.seconds
                        ),
                        context: nil
                    )
                }
            )
            guard !Task.isCancelled,
                  let self,
                  let item,
                  let composition,
                  self.screenPlayer.currentItem === item,
                  !self.maskSegments.isEmpty else { return }
            item.videoComposition = composition
            self.refreshPausedPreviewFrame()
        }
    }

    private func refreshPausedPreviewFrame() {
        guard isLoaded, !isPlaying else { return }
        if let item = screenPlayer.currentItem,
           let composition = item.videoComposition?.mutableCopy() as? AVMutableVideoComposition {
            item.videoComposition = composition
        }
        movePlayers(to: hoverPreviewTime ?? currentTime)
    }

    // MARK: - Preview canvas

    /// What the Studio canvas shows: the target-aspect canvas when a
    /// non-original aspect is selected, the source canvas otherwise.
    var previewCanvasSize: CGSize {
        exportAspect == .original ? previewVideoSize : exportAspect.canvasSize(for: previewVideoSize)
    }

    /// Source aspect for laying out the card on a target-aspect canvas;
    /// nil in the original-aspect layout where card and content agree.
    var previewContentAspect: CGFloat? {
        guard exportAspect != .original, previewVideoSize.height > 0 else { return nil }
        return previewVideoSize.width / previewVideoSize.height
    }

    /// How the content occupies the card on a target-aspect canvas.
    var previewContentMode: RecordingStudioLayout.ContentMode {
        exportAspect != .original && exportAspectMode == .fit ? .fit : .fill
    }

    /// Virtual camera for the preview: the reframe crop when active, the
    /// zoom viewport otherwise (including Fit mode, where zooms play
    /// inside the fitted card).
    func previewViewportFrame(at time: TimeInterval) -> ViewportFrame {
        guard !isCroppingVideo, !isEditingMasks else { return .identity }
        return previewReframe?.frame(at: time) ?? viewportFrame(at: time).cropped(to: cropRect)
    }

    func previewPointerFrame(at time: TimeInterval) -> PointerFrame? {
        guard var frame = pointerFrame(at: time) else { return nil }
        let crop = effectivePreviewCrop
        guard !RecordingVideoCrop.isUnit(crop) else { return frame }
        frame.location = RecordingVideoCrop.point(frame.location, in: crop)
        if var press = frame.press {
            press.location = RecordingVideoCrop.point(press.location, in: crop)
            frame.press = press
        }
        return frame
    }

    /// The flattened deliverable when it provably matches the current
    /// in-memory edits - the render is stamped with the document that
    /// produced it. Both Export and Share can then skip the render entirely.
    private var freshDeliverableURL: URL? {
        guard let session else { return nil }
        return session.freshFinalURL(matching: currentDocument())
    }

    private var exportSuggestedFileName: String {
        let container = exportSettings.effectiveContainer
        return session.map {
            $0.directoryURL
                .deletingPathExtension()
                .lastPathComponent
                .appending(".\(container.fileExtension)")
        } ?? VideoFileActions.exportFileName(for: screenURL, container: container)
    }

    /// Entry point for the export options popover. Assigning settings marks
    /// the project dirty and drops the cached render, so an unchanged
    /// confirmation must not touch them.
    func export(settings: VideoCompressionSettings) {
        if settings != exportSettings {
            exportSettings = settings
        }
        export()
    }

    func export() {
        // One render at a time: the share pipeline uses the same exporter,
        // so a second encode would just fight it for the media engine.
        guard !exportState.isExporting, !shareState.isBusy, isLoaded else { return }
        pause()

        // A fresh deliverable (e.g. right after a share) is byte-identical
        // to what this render would produce - same configuration builds
        // both - so exporting becomes a plain copy into the save folder.
        if let cached = freshDeliverableURL {
            let suggestedFileName = exportSuggestedFileName
            exportTask = Task { [weak self] in
                do {
                    let savedURL = try await VideoFileActions.saveToDefaultLocation(
                        from: cached,
                        suggestedFileName: suggestedFileName
                    )
                    RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                    RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                    self?.exportState = .finished(savedURL)
                } catch {
                    self?.exportState = .failed(error.localizedDescription)
                }
            }
            return
        }

        exportState = .exporting(progress: 0)

        let configuration = makeExportConfiguration()
        let suggestedFileName = exportSuggestedFileName

        let dockProgressID = DockExportProgressCoordinator.shared.start()

        exportTask = Task { [weak self] in
            do {
                let exporter = RecordingStudioExporter()
                let temporaryURL = try await exporter.export(configuration) { progress in
                    Task { @MainActor [weak self] in
                        DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                        if self?.exportState.isExporting == true {
                            self?.exportState = .exporting(progress: progress)
                        }
                    }
                }
                let savedURL = try await VideoFileActions.saveToDefaultLocation(
                    from: temporaryURL,
                    suggestedFileName: suggestedFileName
                )
                try? FileManager.default.removeItem(at: temporaryURL)
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                self?.exportState = .finished(savedURL)
            } catch is CancellationError {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .idle
            } catch RecordingStudioExporter.ExportError.cancelled {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .idle
            } catch {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        if exportState.isExporting {
            exportState = .idle
        }
    }

    // MARK: - Audio only

    /// True once there is a soundtrack to export or swap - the recording's
    /// own audio, or one already imported over it.
    var hasAudio: Bool {
        hasRecordedAudio || replacementAudio != nil
    }

    /// How far the imported soundtrack falls short of (or overruns) the
    /// edited timeline. Nil when there is nothing imported or the two
    /// agree closely enough to be the same take.
    var replacementAudioDrift: TimeInterval? {
        guard let replacementAudio else { return nil }
        let drift = replacementAudio.duration - duration
        return abs(drift) > 0.25 ? drift : nil
    }

    private var audioExportSuggestedFileName: String {
        let base = session.map {
            $0.directoryURL.deletingPathExtension().lastPathComponent
        } ?? screenURL.deletingPathExtension().lastPathComponent
        return "\(base).\(audioExportFormat.fileExtension)"
    }

    /// Writes the edited soundtrack on its own, for cleanup in a tool that
    /// has no API - the outbound half of the replace-audio round trip.
    func exportAudio() {
        guard !audioExportState.isExporting, isLoaded, hasAudio else { return }
        pause()

        audioExportState = .exporting(progress: 0)

        let configuration = RecordingAudioExporter.Configuration(
            screenURL: screenURL,
            clipTimeline: clipTimeline,
            replacementURL: replacementAudio?.url,
            format: audioExportFormat
        )
        let suggestedFileName = audioExportSuggestedFileName
        let dockProgressID = DockExportProgressCoordinator.shared.start()

        audioExportTask = Task { [weak self] in
            do {
                let temporaryURL = try await RecordingAudioExporter().export(configuration) { progress in
                    Task { @MainActor [weak self] in
                        DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                        if self?.audioExportState.isExporting == true {
                            self?.audioExportState = .exporting(progress: progress)
                        }
                    }
                }
                let savedURL = try await VideoFileActions.saveToDefaultLocation(
                    from: temporaryURL,
                    suggestedFileName: suggestedFileName
                )
                try? FileManager.default.removeItem(at: temporaryURL)
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                self?.audioExportState = .finished(savedURL)
            } catch is CancellationError {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.audioExportState = .idle
            } catch {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.audioExportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelAudioExport() {
        audioExportTask?.cancel()
        audioExportTask = nil
        if audioExportState.isExporting {
            audioExportState = .idle
        }
    }

    /// The inbound half: adopts a cleaned-up soundtrack as the project's
    /// audio. The file is copied into the session so the project keeps
    /// playing after the original is moved, and playback switches to it
    /// immediately rather than only revealing itself at export.
    func replaceAudio(with pickedURL: URL) {
        guard isLoaded else { return }
        pause()
        replacementAudioTask?.cancel()

        replacementAudioError = nil
        let displayName = pickedURL.lastPathComponent
        let storedURL: URL
        if let session {
            let destination = session.directoryURL
                .appendingPathComponent(RecordingSession.replacementAudioBaseName)
                .appendingPathExtension(pickedURL.pathExtension.isEmpty ? "m4a" : pickedURL.pathExtension)
            do {
                // Clear every previous import, whatever extension it had,
                // so the session never accumulates orphaned soundtracks.
                removeStoredReplacementAudio(in: session)
                try FileManager.default.copyItem(at: pickedURL, to: destination)
            } catch {
                replacementAudioError = "Could not import that file: \(error.localizedDescription)"
                clearReplacementAudio()
                return
            }
            storedURL = destination
        } else {
            // Bare movies have no project folder to copy into; they
            // reference the picked file where it sits.
            storedURL = pickedURL
        }

        replacementAudioTask = Task { [weak self] in
            let resolved = await RecordingReplacementAudio.load(
                url: storedURL,
                displayName: displayName
            )
            guard let self, !Task.isCancelled else { return }
            guard let resolved else {
                if let session = self.session {
                    self.removeStoredReplacementAudio(in: session)
                }
                self.replacementAudioError = "That file has no audio track."
                self.clearReplacementAudio()
                return
            }
            self.replacementAudio = resolved
            self.applyReplacementAudioToPlayback()
        }
    }

    func removeReplacementAudio() {
        guard replacementAudio != nil else { return }
        replacementAudioTask?.cancel()
        replacementAudioTask = nil
        pause()
        if let session {
            removeStoredReplacementAudio(in: session)
        }
        replacementAudioError = nil
        clearReplacementAudio()
    }

    /// Drops back to the recorded audio, whether that follows a removal or
    /// a failed import that already deleted the copy.
    private func clearReplacementAudio() {
        guard replacementAudio != nil else { return }
        replacementAudio = nil
        applyReplacementAudioToPlayback()
    }

    private func applyReplacementAudioToPlayback() {
        do {
            try rebuildScreenPlayerItem(preserving: currentTime)
        } catch {
            loadError = "Could not update the recording timeline: \(error.localizedDescription)"
        }
        scheduleProjectSave()
    }

    private func removeStoredReplacementAudio(in session: RecordingSession) {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: session.directoryURL.path
        )) ?? []
        for name in names
        where name.hasPrefix("\(RecordingSession.replacementAudioBaseName).") {
            try? FileManager.default.removeItem(
                at: session.directoryURL.appendingPathComponent(name)
            )
        }
    }

    // MARK: - Share to cloud

    var canShareToCloud: Bool {
        CloudUploader.shared.isConfigured
    }

    /// The Loom loop: render the current edits, cache the result as the
    /// session's flattened deliverable, upload it, and copy the share
    /// link - without leaving the Studio or touching a save panel.
    func shareToCloud(options: CloudUploadOptions) {
        guard !shareState.isBusy, !exportState.isExporting, isLoaded,
              canShareToCloud else {
            return
        }
        pause()
        lastShareOptions = options
        // Flush the draft first so the deliverable-invalidation in the
        // debounced autosave can't race the file this render produces.
        projectSaveTask?.cancel()
        writeDraftNow()

        // A fresh deliverable (e.g. sharing again without edits) skips
        // the render and goes straight to upload.
        let cachedDeliverable = freshDeliverableURL
        let configuration = cachedDeliverable == nil ? makeExportConfiguration() : nil
        let session = session
        let renderedDocument = session == nil ? nil : currentDocument()
        shareState = cachedDeliverable == nil ? .rendering(progress: 0) : .uploading

        shareTask = Task { [weak self] in
            // Bare (session-less) videos upload straight from the render's
            // temp file; whatever happens, it must not outlive the share.
            var temporaryUploadURL: URL?
            defer {
                if let temporaryUploadURL {
                    try? FileManager.default.removeItem(at: temporaryUploadURL)
                }
            }
            do {
                let uploadURL: URL
                if let cachedDeliverable {
                    uploadURL = cachedDeliverable
                } else if let configuration {
                    let dockProgressID = DockExportProgressCoordinator.shared.start()
                    let temporaryURL: URL
                    do {
                        temporaryURL = try await RecordingStudioExporter().export(configuration) { progress in
                            Task { @MainActor [weak self] in
                                DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                                if case .rendering = self?.shareState {
                                    self?.shareState = .rendering(progress: progress)
                                }
                            }
                        }
                        DockExportProgressCoordinator.shared.finish(dockProgressID)
                    } catch {
                        DockExportProgressCoordinator.shared.finish(dockProgressID)
                        throw error
                    }
                    // From here the deferred cleanup owns the temp render;
                    // once it moves into the session the delete is a
                    // harmless no-op.
                    temporaryUploadURL = temporaryURL

                    // Session recordings keep the render as the flattened
                    // deliverable, so history, preview, and sidecar mapping
                    // all agree on what was shared.
                    if let session {
                        uploadURL = try session.installFinalVideo(
                            movingFrom: temporaryURL,
                            renderedFrom: renderedDocument
                        )
                    } else {
                        uploadURL = temporaryURL
                    }
                } else {
                    return
                }

                guard let self, !Task.isCancelled else { return }
                self.shareState = .uploading
                let itemID = self.historyItemID(for: session) ?? UUID()
                self.shareItemID = itemID
                let result = try await CloudUploader.shared.upload(
                    itemID: itemID,
                    fileURL: uploadURL,
                    title: options.trimmedTitleOrNil
                )

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url, forType: .string)
                if session != nil {
                    ScreenshotHistoryStore.shared.setCloudURL(for: uploadURL, cloudURL: result.url)
                }
                self.shareState = .finished(result.url)
            } catch is CancellationError {
                self?.shareState = .idle
            } catch RecordingStudioExporter.ExportError.cancelled {
                self?.shareState = .idle
            } catch {
                self?.shareState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelShare() {
        shareTask?.cancel()
        shareTask = nil
        if let shareItemID {
            CloudUploader.shared.cancelUpload(for: shareItemID)
        }
        if shareState.isBusy {
            shareState = .idle
        }
    }

    var canRetryShare: Bool {
        lastShareOptions != nil
    }

    func retryShare() {
        guard case .failed = shareState, let lastShareOptions else { return }
        shareState = .idle
        shareToCloud(options: lastShareOptions)
    }

    func acknowledgeShareResult() {
        switch shareState {
        case .finished, .failed:
            shareState = .idle
        default:
            break
        }
    }

    func acknowledgeExportResult() {
        switch exportState {
        case .finished, .failed:
            exportState = .idle
        default:
            break
        }
    }

    /// History item for this session, so the share upload's progress and
    /// resulting link also appear on the preview card.
    private func historyItemID(for session: RecordingSession?) -> UUID? {
        guard let session else { return nil }
        let standardizedPath = session.directoryURL.standardizedFileURL.path
        return ScreenshotHistoryStore.shared.items
            .first { $0.recordingSessionPath == standardizedPath }?
            .id
    }
}

/// A zoom cue's single merged footprint on the edited timeline.
struct RecordingZoomTimelineBlock: Identifiable, Equatable, Sendable {
    let cue: ZoomCue
    let editorStart: TimeInterval
    let editorEnd: TimeInterval

    var id: UUID {
        cue.id
    }
}
