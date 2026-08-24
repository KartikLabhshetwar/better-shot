import AVFoundation
import AppKit
import CoreImage
import SwiftUI


private struct ClipEditSnapshot {
    var clips: [Clip]
    var trimStart: Double
    var trimEnd: Double
    var selectedClipID: UUID?
}

@MainActor
@Observable
final class VideoEditorModel {
    var player: AVPlayer?
    var duration: Double = 0
    var currentTime: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var isPlaying = false
    var isExporting = false
    var exportProgress: Double = 0
    var toastMessage: String?
    var thumbnails: [NSImage] = []
    var config = BeautifierConfig()

    var videoWidth: Int = 0
    var videoHeight: Int = 0

    var sourceURL: URL?

    var cameraURL: URL?
    var cameraLayout = CameraOverlayLayout()
    var cameraPlayer: AVPlayer?

    var screenGrade = ColorGrade.neutral {
        didSet {
            guard screenGrade != oldValue else { return }
            filterBox.screenGrade = screenGrade
            syncPreviewFilters()
        }
    }
    var cameraGrade = ColorGrade.neutral {
        didSet {
            guard cameraGrade != oldValue else { return }
            filterBox.cameraGrade = cameraGrade
            syncPreviewFilters()
        }
    }
    @ObservationIgnored private let filterBox = PreviewFilterBox()

    var pose = Camera3D.neutral

    var isTrimming = false
    var isCropping = false
    var cropRect = CropGeometry.identity
    private var cropRectBeforeEditing = CropGeometry.identity

    var masks: [VideoMask] = [] {
        didSet {
            guard masks != oldValue else { return }
            filterBox.screenMasks = masks
            syncPreviewFilters()
        }
    }
    var selectedMaskID: UUID?

    var zoomCues: [ZoomCue] = []
    var selectedZoomCueID: UUID?
    private var pointerCapture: PointerCaptureFile?
    private var viewportTimeline: ViewportTimeline = .identity

    var clips: [Clip] = []
    var selectedClipID: UUID?
    var timelineSplitMode = false
    private var undoStack: [ClipEditSnapshot] = []
    private var redoStack: [ClipEditSnapshot] = []

    var zoomEnabled: Bool { !zoomCues.isEmpty }
    var clipTimeline: ClipTimeline { ClipTimeline(clips: clips) }

    /// What the timeline spans once the cuts are applied, which is shorter than the asset as soon as anything is removed.
    var timelineDuration: Double { clips.isEmpty ? duration : clipTimeline.duration }

    func editorTime(forSourceTime time: Double) -> Double {
        clips.isEmpty ? time : clipTimeline.clampedEditorTime(forSourceTime: time)
    }

    func sourceTime(atEditorTime time: Double) -> Double {
        clips.isEmpty ? time : clipTimeline.sourceTime(at: time)
    }

    var hasTrim: Bool { trimStart > 0.01 || (duration > 0 && trimEnd < duration - 0.01) }
    var hasCrop: Bool { cropRect != CropGeometry.identity }

    /// The frame the preview and the export both work in: the crop when there is one, the whole video otherwise.
    var croppedSize: CGSize {
        CGSize(
            width: (CGFloat(videoWidth) * cropRect.width).rounded(),
            height: (CGFloat(videoHeight) * cropRect.height).rounded()
        )
    }
    var isClipMode: Bool { !clips.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canDeleteSelectedClip: Bool { clips.count > 1 && selectedClipID != nil }
    var hasEdits: Bool {
        hasTrim || hasCrop || isClipMode
            || zoomEnabled || showsClickHighlights
            || config.padding > 0 || config.cornerRadius > 0 || config.shadowStrength > 0
            || config.style != .none || config.aspectRatio != .auto
            || !screenGrade.isNeutral || !cameraGrade.isNeutral || !pose.isNeutral || !masks.isEmpty
    }
    /// Escape backs out of whatever is in flight before it reaches the window, the way it does everywhere else on the Mac.
    @discardableResult
    func cancelCurrentOperation() -> Bool {
        if isCropping {
            cancelCrop()
            return true
        }
        if timelineSplitMode {
            timelineSplitMode = false
            return true
        }
        if selectedMaskID != nil {
            selectedMaskID = nil
            return true
        }
        if selectedZoomCueID != nil {
            selectedZoomCueID = nil
            return true
        }
        if selectedClipID != nil {
            selectedClipID = nil
            return true
        }
        return false
    }

    var hasCamera: Bool { cameraURL != nil }
    var isCameraVisible: Bool { cameraURL != nil && sceneAtPlayhead.needsCamera }
    var hasPointerCapture: Bool {
        guard let pointerCapture else { return false }
        return !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty
    }

    var clickPresses: [ClickHighlight] {
        (pointerCapture?.presses ?? []).map { ClickHighlight(time: $0.time, point: CGPoint(x: $0.x, y: $0.y)) }
    }
    var hasClicks: Bool { !clickPresses.isEmpty }
    var clickHighlightsEnabled = true
    var clickHighlightScale: CGFloat = 1

    var showsClickHighlights: Bool { clickHighlightsEnabled && hasClicks }

    static let clickHighlightRadiusFraction: CGFloat = 0.05

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSeek: (time: Double, precise: Bool)?
    @ObservationIgnored private var isSeekInFlight = false

    var trimmedDuration: Double { trimEnd - trimStart }

    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String { formatTime(trimmedDuration) }

    func loadVideo(from url: URL) {
        removeTimeObserver()
        loadTask?.cancel()
        thumbnailTask?.cancel()
        pendingSeek = nil
        isSeekInFlight = false
        thumbnails = []
        cameraPlayer?.pause()
        cameraPlayer = nil
        cameraURL = nil
        cameraLayout = CameraOverlayLayout()
        screenGrade = .neutral
        cameraGrade = .neutral
        pose = .neutral
        currentTime = 0
        trimStart = 0
        trimEnd = 0
        duration = 0

        let resolvedURL: URL
        if let record = HistoryStore.shared.records.first(where: {
            $0.beautifiedPath != nil && URL(fileURLWithPath: $0.beautifiedPath!) == url
        }) {
            resolvedURL = HistoryStore.shared.urlForRecord(record)
        } else {
            resolvedURL = url
        }
        sourceURL = resolvedURL
        config = AppPreferences.defaultBeautifierConfig
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        player?.actionAtItemEnd = .pause

        loadTask = Task { @MainActor [weak self] in
            let loaded = try? await asset.load(.duration)
            guard let self, !Task.isCancelled else { return }
            if let seconds = loaded?.seconds, seconds.isFinite, seconds > 0 {
                self.duration = seconds
                self.trimEnd = seconds
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                let transform = try? await track.load(.preferredTransform)
                guard !Task.isCancelled else { return }
                if let size, let transform {
                    let transformed = size.applying(transform)
                    self.videoWidth = Int(abs(transformed.width))
                    self.videoHeight = Int(abs(transformed.height))
                }
            }
            guard !Task.isCancelled else { return }
            self.loadPointerCapture()
            self.loadCameraSidecar()
            self.regenerateZoomCues()
            self.generateThumbnails()
            self.setupTimeObserver()
            self.loadTask = nil
        }
    }



    func viewportFrame(at time: Double) -> ViewportFrame {
        zoomEnabled ? viewportTimeline.frame(at: time) : .identity
    }

    func regenerateZoomCues() {
        zoomCues = ZoomCueSynthesizer.cues(from: pointerCapture ?? PointerCaptureFile(), duration: duration)
        selectedZoomCueID = nil
        rebuildViewportTimeline()
    }

    func addZoomCue(at time: Double) {
        guard duration > 0 else { return }
        let half: TimeInterval = 1.25
        let start = max(0, time - half)
        let end = min(duration, time + half)
        guard end - start >= ZoomCue.minimumDuration else { return }
        let anchor = pointerCapture.flatMap { nearestPointerPoint(in: $0, at: time) } ?? CGPoint(x: 0.5, y: 0.5)
        let cue = ZoomCue(start: start, end: end, anchorMode: .pointerAnchor, pinnedPoint: anchor)
        zoomCues.append(cue)
        zoomCues.sort { $0.start < $1.start }
        selectedZoomCueID = cue.id
        rebuildViewportTimeline()
    }

    func deleteZoomCue(_ id: UUID) {
        zoomCues.removeAll { $0.id == id }
        if selectedZoomCueID == id { selectedZoomCueID = nil }
        rebuildViewportTimeline()
    }

    func updateZoomCue(id: UUID, start: TimeInterval, end: TimeInterval) {
        guard let index = zoomCues.firstIndex(where: { $0.id == id }) else { return }
        zoomCues[index].start = max(0, start)
        zoomCues[index].end = min(duration, end)
        rebuildViewportTimeline()
    }

    func setZoomAmount(_ value: Double, forCueID id: UUID) {
        guard let index = zoomCues.firstIndex(where: { $0.id == id }) else { return }
        zoomCues[index].zoom = max(1, value)
        rebuildViewportTimeline()
    }

    private func nearestPointerPoint(in capture: PointerCaptureFile, at time: Double) -> CGPoint? {
        let travelPoints = capture.travel.map { ($0.time, CGPoint(x: $0.x, y: $0.y)) }
        let pressPoints = capture.presses.map { ($0.time, CGPoint(x: $0.x, y: $0.y)) }
        let candidates = travelPoints + pressPoints
        guard !candidates.isEmpty else { return nil }
        return candidates.min(by: { abs($0.0 - time) < abs($1.0 - time) })?.1
    }

    private func rebuildViewportTimeline() {
        viewportTimeline = ViewportTimeline.build(
            cues: zoomCues,
            capture: pointerCapture ?? PointerCaptureFile(),
            duration: duration
        )
    }

    private func pointerSidecarURL(for videoURL: URL) -> URL {
        URL(fileURLWithPath: videoURL.deletingPathExtension().path + ".pointer.json")
    }

    private func loadPointerCapture() {
        guard let sourceURL else {
            pointerCapture = nil
            return
        }
        let sidecarURL = pointerSidecarURL(for: sourceURL)
        guard let data = try? Data(contentsOf: sidecarURL),
              let decoded = try? JSONDecoder().decode(PointerCaptureFile.self, from: data) else {
            pointerCapture = nil
            return
        }
        pointerCapture = decoded
    }

    /// The face cam was recorded to its own file rather than burned into the screen capture, which is what lets the editor move it.
    private func loadCameraSidecar() {
        guard let sourceURL else { return }
        let url = ScreenRecordingManager.cameraSidecarURL(for: sourceURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        cameraURL = url
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        cameraPlayer = player
        syncPreviewFilters()
    }

    var selectedMask: VideoMask? {
        selectedMaskID.flatMap { id in masks.first { $0.id == id } }
    }

    /// Masks live in source time, the same clock the preview player runs on, so the playhead lands one straight into place.
    func addMask(kind: VideoMask.Kind) {
        let start = min(currentTime, max(0, duration - VideoMask.minimumDuration))
        var mask = VideoMask(
            start: start,
            end: min(start + VideoMask.defaultDuration, max(start + VideoMask.minimumDuration, duration))
        )
        mask.kind = kind
        masks.append(mask)
        selectedMaskID = mask.id
    }

    func updateMask(_ mask: VideoMask) {
        guard let index = masks.firstIndex(where: { $0.id == mask.id }) else { return }
        var clamped = mask
        clamped.rect = VideoMask.clampedRect(mask.rect)
        clamped.start = min(max(0, mask.start), max(0, duration - VideoMask.minimumDuration))
        clamped.end = min(max(clamped.start + VideoMask.minimumDuration, mask.end), max(duration, clamped.start + VideoMask.minimumDuration))
        masks[index] = clamped
    }

    func deleteMask(_ id: UUID) {
        masks.removeAll { $0.id == id }
        if selectedMaskID == id { selectedMaskID = nil }
    }

    func setCameraCenter(_ center: CGPoint, in card: CGRect) {
        cameraLayout.center = cameraLayout.clamping(center, in: card)
    }

    func setCameraDiameter(_ value: CGFloat) {
        cameraLayout.diameter = CameraOverlayLayout.clampedDiameter(value)
    }

    func applyGradePreset(_ preset: ColorGrade.Preset, toCamera: Bool) {
        if toCamera {
            cameraGrade = preset.grade
        } else {
            screenGrade = preset.grade
        }
    }

    /// The preview filters read a locked box, so a slider drag only swaps values: the composition is built once, when the frame first stops being untouched.
    private func syncPreviewFilters() {
        attachFilters(to: player?.currentItem, isIdle: screenGrade.isNeutral && masks.isEmpty) { [filterBox] source, time in
            let graded = filterBox.screenGrade.applied(to: source, extent: source.extent, frameTime: time)
            let masks = VideoMask.resolved(
                filterBox.screenMasks,
                atSourceTime: time,
                pixelScale: source.extent.height / VideoMask.referenceHeight,
                project: { Self.frameRect($0, in: source.extent) }
            )
            return ResolvedMask.applied(masks, to: graded, extent: source.extent)
        }
        attachFilters(to: cameraPlayer?.currentItem, isIdle: cameraGrade.isNeutral) { [filterBox] source, time in
            filterBox.cameraGrade.applied(to: source, extent: source.extent, frameTime: time)
        }
        guard !isPlaying else { return }
        enqueueSeek(currentTime, precise: true)
    }

    /// Masks are stored top-down like the screen, but Core Image paints y-up, so the rect flips on its way into the frame.
    nonisolated static func frameRect(_ normalized: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + (1 - normalized.maxY) * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        )
    }

    private func attachFilters(
        to item: AVPlayerItem?,
        isIdle: Bool,
        filter: @escaping @Sendable (CIImage, TimeInterval) -> CIImage
    ) {
        guard let item else { return }
        guard !isIdle else {
            item.videoComposition = nil
            return
        }
        guard item.videoComposition == nil else { return }
        item.videoComposition = AVMutableVideoComposition(asset: item.asset) { request in
            request.finish(with: filter(request.sourceImage, request.compositionTime.seconds), context: nil)
        }
    }

    /// A sped-up clip has to play sped up, so the rate follows whichever clip the playhead sits in.
    private func syncPlaybackRate() {
        guard let player, isPlaying else { return }
        let mode = clipTimeline.audioMode(atSourceTime: currentTime)
        player.isMuted = mode == .mute
        if player.currentItem?.audioTimePitchAlgorithm != mode.pitchAlgorithm {
            player.currentItem?.audioTimePitchAlgorithm = mode.pitchAlgorithm
        }
        let target = Float(clipTimeline.speed(atSourceTime: currentTime))
        if abs(player.rate - target) > 0.01 { player.rate = target }
        if let cameraPlayer, cameraPlayer.rate != 0, abs(cameraPlayer.rate - target) > 0.01 {
            cameraPlayer.rate = target
        }
    }

    /// Two players over one timeline drift, so the cam is nudged back whenever it strays past a few frames.
    private func syncCameraPlayback() {
        guard let cameraPlayer else { return }
        if isPlaying, cameraPlayer.rate == 0 {
            cameraPlayer.play()
        } else if !isPlaying, cameraPlayer.rate != 0 {
            cameraPlayer.pause()
        }
        let camTime = cameraPlayer.currentTime().seconds
        guard camTime.isFinite else { return }
        guard abs(camTime - currentTime) > 0.15 else { return }
        cameraPlayer.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(value: 1, timescale: 30)
        )
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= trimEnd {
                seekTo(trimStart)
            }
            player.play()
            isPlaying = true
        }
        syncCameraPlayback()
        syncPlaybackRate()
    }

    /// `precise` off is for scrubbing: a tolerant seek lands on the nearest decoded frame instead of forcing a full decode per pointer move.
    func seekTo(_ time: Double, precise: Bool = true) {
        let clamped = duration > 0 ? min(max(time, 0), duration) : max(time, 0)
        currentTime = clamped
        enqueueSeek(clamped, precise: precise)
        syncCameraPlayback()
    }

    func pauseForScrub() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        syncCameraPlayback()
    }

    /// One seek in flight at a time, with only the newest request queued behind it, so a drag never builds a backlog the player has to work through after the pointer stops.
    private func enqueueSeek(_ time: Double, precise: Bool) {
        pendingSeek = (time, precise)
        guard !isSeekInFlight else { return }
        dispatchPendingSeek()
    }

    private func dispatchPendingSeek() {
        guard let player, let next = pendingSeek else { return }
        pendingSeek = nil
        isSeekInFlight = true
        let tolerance = next.precise ? CMTime.zero : CMTime(value: 1, timescale: 10)
        player.seek(
            to: CMTime(seconds: next.time, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeekInFlight = false
                self.dispatchPendingSeek()
            }
        }
    }

    func stepForward() {
        seekTo(min(currentTime + 1.0, trimEnd))
    }

    func stepBackward() {
        seekTo(max(currentTime - 1.0, trimStart))
    }

    func setTrimStart(_ value: Double) {
        applyTrim(trimSelection.settingStart(value, duration: duration))
    }

    func setTrimEnd(_ value: Double) {
        applyTrim(trimSelection.settingEnd(value, duration: duration))
    }

    func beginCrop() {
        cropRectBeforeEditing = cropRect
        selectedClipID = nil
        selectedZoomCueID = nil
        pauseForScrub()
        isCropping = true
    }

    func commitCrop() { isCropping = false }

    func cancelCrop() {
        cropRect = cropRectBeforeEditing
        isCropping = false
    }

    func resetCrop() {
        cropRect = CropGeometry.identity
        cropRectBeforeEditing = CropGeometry.identity
    }

    var trimSelection: TrimSelection { TrimSelection(start: trimStart, end: trimEnd) }

    private func applyTrim(_ selection: TrimSelection) {
        trimStart = selection.start
        trimEnd = selection.end
        if currentTime < trimStart { seekTo(trimStart) }
        if currentTime > trimEnd { seekTo(trimEnd) }
    }

    /// The timeline has already clamped both bounds and the playhead together, so this writes them as one edit instead of round-tripping through the setters and seeking twice.
    func applyTrimDrag(_ selection: TrimSelection, playhead: Double, precise: Bool) {
        trimStart = selection.start
        trimEnd = selection.end
        seekTo(playhead, precise: precise)
    }

    func selectClip(_ id: UUID?) {
        selectedClipID = id
    }

    func splitAtPlayhead() {
        split(at: currentTime)
    }

    func split(at time: Double) {
        let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
        guard let result = ClipTimeline(clips: base).split(at: time) else { return }
        commitClips(result.clips, selecting: result.selectedID)
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID, let next = ClipTimeline(clips: clips).deleting(id: id) else { return }
        let removedIndex = clips.firstIndex(where: { $0.id == id }) ?? 0
        let selection = next.indices.contains(removedIndex) ? next[removedIndex].id : next.last?.id
        commitClips(next, selecting: selection)
    }

    func setSpeed(_ speed: Double, forClipID id: UUID) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        var updated = clip
        updated.speed = Clip.clampedSpeed(speed)
        commitClips(ClipTimeline(clips: clips).replacing(updated), selecting: id)
    }

    var activeSpeed: Double {
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) { return clip.speed }
        return clips.first?.speed ?? 1
    }

    /// Speed belongs to the whole recording until it is split, so the first change materializes the implicit clip.
    func setSpeed(_ speed: Double) {
        if let id = selectedClipID, clips.contains(where: { $0.id == id }) {
            setSpeed(speed, forClipID: id)
            return
        }
        let clamped = Clip.clampedSpeed(speed)
        guard !clips.isEmpty || clamped != 1 else { return }
        let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
        commitClips(base.map { clip in
            var updated = clip
            updated.speed = clamped
            return updated
        }, selecting: nil)
    }

    var activeAudioMode: ClipSpeedAudioMode {
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) { return clip.audioMode }
        return clips.first?.audioMode ?? .maintainPitch
    }

    /// Mirrors `setSpeed`: the mode belongs to the whole recording until the timeline is cut, then to the selected clip.
    func setAudioMode(_ mode: ClipSpeedAudioMode) {
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) {
            var updated = clip
            updated.audioMode = mode
            commitClips(ClipTimeline(clips: clips).replacing(updated), selecting: id)
            return
        }
        guard !clips.isEmpty || mode != .maintainPitch else { return }
        let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
        commitClips(base.map { clip in
            var updated = clip
            updated.audioMode = mode
            return updated
        }, selecting: nil)
        syncPlaybackRate()
    }

    var activeScene: SceneMode {
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) { return clip.scene }
        return clips.first?.scene ?? .screenAndCamera
    }

    /// Mirrors `setSpeed`: the scene belongs to the whole recording until the timeline is cut, then to the selected clip.
    func setScene(_ scene: SceneMode) {
        guard hasCamera || !scene.needsCamera else { return }
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) {
            var updated = clip
            updated.scene = scene
            commitClips(ClipTimeline(clips: clips).replacing(updated), selecting: id)
            return
        }
        guard !clips.isEmpty || scene != .screenAndCamera else { return }
        let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
        commitClips(base.map { clip in
            var updated = clip
            updated.scene = scene
            return updated
        }, selecting: nil)
    }

    var sceneAtPlayhead: SceneMode {
        guard hasCamera else { return .screenOnly }
        return clips.isEmpty ? .screenAndCamera : clipTimeline.scene(atSourceTime: currentTime)
    }

    private var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return clips.firstIndex { $0.id == id }
    }

    /// Only a clip with something before it can be handed over to, so the first clip never offers one.
    var canSetTransition: Bool { (selectedClipIndex ?? 0) > 0 }

    var activeTransition: ClipTransition? {
        guard let index = selectedClipIndex, index > 0 else { return nil }
        return clips[index].transitionIn
    }

    var maximumTransitionDuration: TimeInterval {
        guard let index = selectedClipIndex else { return 0 }
        return clipTimeline.maximumTransitionDuration(at: index)
    }

    func setTransition(_ transition: ClipTransition?) {
        guard let index = selectedClipIndex, index > 0 else { return }
        var updated = clips[index]
        updated.transitionIn = transition.map {
            var clamped = $0
            clamped.duration = min(max($0.duration, ClipTransition.minimumDuration), max(ClipTransition.minimumDuration, maximumTransitionDuration))
            return clamped
        }
        commitClips(ClipTimeline(clips: clips).replacing(updated), selecting: updated.id)
    }

    func beginClipTrim() {
        pushUndoSnapshot()
    }

    func updateClipTrim(_ id: UUID, start: Double, end: Double) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var updated = clips[index]
        let minStart = index > 0 ? clips[index - 1].sourceEnd : 0
        let maxEnd = index < clips.count - 1 ? clips[index + 1].sourceStart : duration
        updated.sourceStart = min(max(start, minStart), updated.sourceEnd - Clip.minimumDuration)
        updated.sourceEnd = max(min(end, maxEnd), updated.sourceStart + Clip.minimumDuration)
        clips[index] = updated
        syncTrimBoundsToClips()
    }

    func resetTrim() {
        pushUndoSnapshot()
        clips = []
        selectedClipID = nil
        trimStart = 0
        trimEnd = duration
        seekTo(0)
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restoreSnapshot(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restoreSnapshot(snapshot)
    }

    private func currentSnapshot() -> ClipEditSnapshot {
        ClipEditSnapshot(clips: clips, trimStart: trimStart, trimEnd: trimEnd, selectedClipID: selectedClipID)
    }

    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    private func commitClips(_ newClips: [Clip], selecting id: UUID?) {
        pushUndoSnapshot()
        applyClips(newClips, selecting: id)
    }

    private func applyClips(_ newClips: [Clip], selecting id: UUID?) {
        clips = newClips
        selectedClipID = id
        syncTrimBoundsToClips()
    }

    private func restoreSnapshot(_ snapshot: ClipEditSnapshot) {
        clips = snapshot.clips
        trimStart = snapshot.trimStart
        trimEnd = snapshot.trimEnd
        selectedClipID = snapshot.selectedClipID
        if currentTime < trimStart { seekTo(trimStart) }
        if currentTime > trimEnd { seekTo(trimEnd) }
    }

    private func syncTrimBoundsToClips() {
        guard let first = clips.first, let last = clips.last else { return }
        trimStart = first.sourceStart
        trimEnd = last.sourceEnd
        if currentTime < trimStart { seekTo(trimStart) }
        if currentTime > trimEnd { seekTo(trimEnd) }
    }

    func exportTrimmed(into directory: String? = nil) async throws -> URL {
        guard let sourceURL else { throw VideoExportError.noSourceRecording }
        let asset = AVURLAsset(url: sourceURL)

        let dir = directory ?? AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let outputPath = "\(dir)/bettershot_\(stamp).mp4"
        let outputURL = URL(fileURLWithPath: outputPath)

        var exportConfig = config
        if exportConfig.style != .none && exportConfig.padding <= 0 {
            exportConfig.padding = 0.06
        }

        let hasEffects = exportConfig.padding > 0 || exportConfig.cornerRadius > 0 || exportConfig.shadowStrength > 0
            || exportConfig.style != .none || exportConfig.aspectRatio != .auto
        let hasZoom = zoomEnabled

        if isClipMode || hasEffects || hasCrop || hasZoom || isCameraVisible || showsClickHighlights || !masks.isEmpty {
            return try await exportWithEffects(asset: asset, outputURL: outputURL, config: exportConfig)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.exportSessionUnavailable
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        await session.export()

        switch session.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw VideoExportError.exportCancelled
        default:
            throw VideoExportError.exportFailed(session.error)
        }
    }

    private func exportWithEffects(asset: AVURLAsset, outputURL: URL, config: BeautifierConfig) async throws -> URL {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(transform)
        let fullW = abs(transformed.width)
        let fullH = abs(transformed.height)

        let useZoom = zoomEnabled
        let canvas = ExportCanvasGeometry.canvas(
            videoWidth: fullW * cropRect.width,
            videoHeight: fullH * cropRect.height,
            paddingFraction: config.padding,
            aspectRatio: config.aspectRatio.numericValue
        )
        let vidW = canvas.videoWidth
        let vidH = canvas.videoHeight
        let offsetX = canvas.offsetX
        let offsetY = canvas.offsetY
        let canvasW = canvas.width
        let canvasH = canvas.height
        let shortEdge = min(vidW, vidH)
        let cornerRadius = config.cornerRadius * shortEdge

        let cameraSource = await loadCameraSource()

        let composition: AVMutableComposition
        let mapToSourceTime: @Sendable (TimeInterval) -> TimeInterval
        let mapToEditorTime: (TimeInterval) -> TimeInterval?
        var cameraTrackID: CMPersistentTrackID?
        var audioMix: AVAudioMix?
        var exportClips: [Clip] = []
        var laneTrackIDs: [CMPersistentTrackID] = []

        if isClipMode {
            let normalizedClips = ClipTimeline(clips: clips).normalized(to: duration)
            guard !normalizedClips.isEmpty else { throw VideoExportError.emptyClipTimeline }
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let built: ClipCompositionBuilder.Built
            do {
                built = try ClipCompositionBuilder.makeComposition(
                    videoTrack: videoTrack,
                    audioTracks: audioTracks,
                    camera: cameraSource,
                    clips: normalizedClips
                )
            } catch {
                throw VideoExportError.clipCompositionFailed(error)
            }
            composition = built.composition
            cameraTrackID = built.cameraTrackID
            audioMix = built.audioMix
            exportClips = normalizedClips
            laneTrackIDs = built.videoTrackIDs
            let timeline = ClipTimeline(clips: normalizedClips)
            mapToSourceTime = { timeline.sourceTime(at: $0) }
            mapToEditorTime = { timeline.editorTime(forSourceTime: $0) }
        } else {
            let legacyComposition = AVMutableComposition()

            guard let compVideoTrack = legacyComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoExportError.compositionTrackUnavailable
            }

            let timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            do {
                try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            } catch {
                throw VideoExportError.trimInsertFailed(error)
            }

            exportClips = [Clip(sourceStart: trimStart, sourceEnd: trimEnd)]
            laneTrackIDs = [compVideoTrack.trackID]

            if let cameraSource,
               let compCameraTrack = legacyComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                ClipCompositionBuilder.insertCamera(cameraSource, into: compCameraTrack, sourceRange: timeRange, at: .zero)
                cameraTrackID = compCameraTrack.trackID
            }

            for audioTrack in (try? await asset.loadTracks(withMediaType: .audio)) ?? [] {
                guard let compAudioTrack = legacyComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }

            composition = legacyComposition
            let baseTrimStart = trimStart
            let baseTrimEnd = trimEnd
            mapToSourceTime = { $0 + baseTrimStart }
            mapToEditorTime = { $0 >= baseTrimStart && $0 <= baseTrimEnd ? $0 - baseTrimStart : nil }
        }

        let laneTracks = laneTrackIDs.compactMap { id in
            composition.tracks(withMediaType: .video).first { $0.trackID == id }
        }
        guard !laneTracks.isEmpty, !exportClips.isEmpty else {
            throw VideoExportError.compositionTrackUnavailable
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: canvasW, height: canvasH)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let cropOrigin = CGPoint(x: fullW * cropRect.origin.x, y: fullH * cropRect.origin.y).applying(transform)
        let untranslatedOrigin = CGPoint.zero.applying(transform)
        let cropShift = CGAffineTransform(
            translationX: untranslatedOrigin.x - cropOrigin.x + offsetX,
            y: untranslatedOrigin.y - cropOrigin.y + offsetY
        )

        let timeline = viewportTimeline
        let cropFrame = cropRect

        @Sendable func frameTransform(atSourceTime sourceTime: TimeInterval) -> CGAffineTransform {
            let viewport = useZoom ? timeline.frame(at: sourceTime) : .identity
            let anchorDisplay = CGPoint(
                x: (cropFrame.origin.x + viewport.anchor.x * cropFrame.width) * fullW,
                y: (cropFrame.origin.y + viewport.anchor.y * cropFrame.height) * fullH
            )
            let magnification = max(1, viewport.magnification)
            let zoomTransform = CGAffineTransform(translationX: -anchorDisplay.x, y: -anchorDisplay.y)
                .concatenating(CGAffineTransform(scaleX: magnification, y: magnification))
                .concatenating(CGAffineTransform(translationX: anchorDisplay.x, y: anchorDisplay.y))
            return transform
                .concatenating(zoomTransform)
                .concatenating(cropShift)
        }

        @Sendable func frameTransform(atEditorTime editorTime: TimeInterval) -> CGAffineTransform {
            frameTransform(atSourceTime: mapToSourceTime(editorTime))
        }

        let exportTimeline = ClipTimeline(clips: exportClips)
        let exportStarts = exportTimeline.outputStarts

        func outputRange(_ start: TimeInterval, _ end: TimeInterval) -> CMTimeRange {
            CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }

        func layer(_ index: Int, span: CMTimeRange, fadingOut: Bool) -> AVMutableVideoCompositionLayerInstruction {
            let clip = exportClips[index]
            let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: laneTracks[index % laneTracks.count])
            let clipStart = exportStarts[index]
            let speed = Clip.clampedSpeed(clip.speed)
            let spanStart = span.start.seconds
            let spanEnd = CMTimeRangeGetEnd(span).seconds

            func placement(atOutputTime time: TimeInterval) -> CGAffineTransform {
                frameTransform(atSourceTime: clip.sourceStart + max(0, time - clipStart) * speed)
            }

            if useZoom, spanEnd > spanStart {
                let step: TimeInterval = 0.1
                var time = spanStart
                var previous = placement(atOutputTime: time)
                while time < spanEnd {
                    let next = min(time + step, spanEnd)
                    let target = placement(atOutputTime: next)
                    instruction.setTransformRamp(fromStart: previous, toEnd: target, timeRange: outputRange(time, next))
                    previous = target
                    time = next
                }
            } else {
                instruction.setTransform(placement(atOutputTime: spanStart), at: span.start)
            }

            if fadingOut {
                instruction.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: span)
            }
            return instruction
        }

        func spanInstruction(_ span: CMTimeRange, layers: [AVMutableVideoCompositionLayerInstruction]) -> AVMutableVideoCompositionInstruction {
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = span
            instruction.backgroundColor = CGColor.clear
            instruction.layerInstructions = layers
            return instruction
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var dimWindows: [TransitionDim] = []

        for index in exportClips.indices {
            let clipStart = exportStarts[index]
            var soloStart = clipStart
            if let handover = exportTimeline.effectiveTransition(at: index) {
                let middle = clipStart + handover.duration / 2
                let end = clipStart + handover.duration
                switch handover.kind {
                case .crossFade:
                    let span = outputRange(clipStart, end)
                    instructions.append(spanInstruction(span, layers: [
                        layer(index - 1, span: span, fadingOut: true),
                        layer(index, span: span, fadingOut: false)
                    ]))
                case .fadeThroughBlack:
                    let leaving = outputRange(clipStart, middle)
                    let arriving = outputRange(middle, end)
                    instructions.append(spanInstruction(leaving, layers: [layer(index - 1, span: leaving, fadingOut: false)]))
                    instructions.append(spanInstruction(arriving, layers: [layer(index, span: arriving, fadingOut: false)]))
                    dimWindows.append(TransitionDim(start: clipStart, duration: handover.duration))
                }
                soloStart = end
            }
            let soloEnd = clipStart + exportClips[index].editorDuration
                - (exportTimeline.effectiveTransition(at: index + 1)?.duration ?? 0)
            guard soloEnd > soloStart else { continue }
            let span = outputRange(soloStart, soloEnd)
            instructions.append(spanInstruction(span, layers: [layer(index, span: span, fadingOut: false)]))
        }

        guard let first = instructions.first else { throw VideoExportError.emptyClipTimeline }
        first.timeRange = CMTimeRange(start: .zero, end: CMTimeRangeGetEnd(first.timeRange))
        if let last = instructions.last, composition.duration > last.timeRange.start {
            last.timeRange = CMTimeRange(start: last.timeRange.start, end: composition.duration)
        }
        videoComposition.instructions = instructions

        let scenes = hasCamera
            ? exportClips.indices.map { index in
                SceneWindow(
                    start: exportStarts[index],
                    end: exportStarts[index] + exportClips[index].editorDuration,
                    mode: exportClips[index].scene
                )
            }
            : []

        let clicks = showsClickHighlights
            ? ClickHighlight.highlights(
                presses: clickPresses,
                editorTime: mapToEditorTime,
                project: { point, editorTime in
                    ClickHighlight.canvasPoint(
                        normalized: point,
                        videoSize: CGSize(width: fullW, height: fullH),
                        transform: frameTransform(atEditorTime: editorTime),
                        canvasHeight: canvasH
                    )
                }
            )
            : []

        let exportMasks = masks
        let sourceSize = CGSize(width: fullW, height: fullH)
        let resolveMasks: @Sendable (TimeInterval) -> [ResolvedMask] = { editorTime in
            VideoMask.resolved(
                exportMasks,
                atSourceTime: mapToSourceTime(editorTime),
                pixelScale: canvasH / VideoMask.referenceHeight
            ) { normalized in
                let placed = CGRect(
                    x: normalized.minX * sourceSize.width,
                    y: normalized.minY * sourceSize.height,
                    width: normalized.width * sourceSize.width,
                    height: normalized.height * sourceSize.height
                ).applying(frameTransform(atEditorTime: editorTime))
                return CGRect(x: placed.minX, y: canvasH - placed.maxY, width: placed.width, height: placed.height)
            }
        }

        let cardRect = CGRect(x: offsetX, y: offsetY, width: vidW, height: vidH)
        let exportConfig = VideoFrameExporter.Configuration(
            composition: composition,
            videoComposition: videoComposition,
            canvasSize: CGSize(width: canvasW, height: canvasH),
            cardRect: cardRect,
            cornerRadius: cornerRadius,
            backgroundStyle: config.style,
            shadowStrength: config.shadowStrength,
            outputURL: outputURL,
            camera: cameraTrackID.map {
                VideoFrameExporter.Configuration.Camera(trackID: $0, rect: cameraLayout.flippedRect(in: cardRect))
            },
            clicks: clicks,
            clickRadius: min(vidW, vidH) * Self.clickHighlightRadiusFraction * clickHighlightScale,
            audioMix: audioMix,
            screenGrade: screenGrade,
            cameraGrade: cameraGrade,
            dimWindows: dimWindows,
            scenes: scenes,
            pose: pose,
            resolveMasks: exportMasks.isEmpty ? nil : resolveMasks
        )

        return try await VideoFrameExporter().export(exportConfig) { [weak self] fraction in
            Task { @MainActor in self?.exportProgress = fraction }
        }
    }

    private func loadCameraSource() async -> CameraSource? {
        guard let cameraURL, clips.isEmpty || clips.contains(where: { $0.scene.needsCamera }) else { return nil }
        let asset = AVURLAsset(url: cameraURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration) else { return nil }
        return CameraSource(track: track, duration: duration)
    }

    func cleanup() {
        loadTask?.cancel()
        thumbnailTask?.cancel()
        pendingSeek = nil
        player?.pause()
        cameraPlayer?.pause()
        removeTimeObserver()
        player = nil
        cameraPlayer = nil
    }

    // MARK: - Private

    private func removeTimeObserver() {
        guard let observer = timeObserver else { return }
        player?.removeTimeObserver(observer)
        timeObserver = nil
    }

    private func setupTimeObserver() {
        guard let player else { return }
        removeTimeObserver()
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeekInFlight, self.pendingSeek == nil else { return }
                self.currentTime = time.seconds
                self.syncCameraPlayback()
                self.syncPlaybackRate()
                if self.isPlaying, let resume = self.clipTimeline.playbackTime(after: self.currentTime) {
                    self.seekTo(resume, precise: false)
                    return
                }
                if self.currentTime >= self.trimEnd && self.isPlaying {
                    self.player?.pause()
                    self.isPlaying = false
                    self.seekTo(self.trimStart)
                }
            }
        }
    }

    private func generateThumbnails() {
        thumbnailTask?.cancel()
        guard let sourceURL, duration > 0 else {
            thumbnails = []
            return
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)

        let count = 20
        let step = duration / Double(count)
        let times = (0..<count).map { CMTime(seconds: step * Double($0), preferredTimescale: 600) }

        thumbnailTask = Task { @MainActor [weak self] in
            var images: [NSImage] = []
            for await result in generator.images(for: times) {
                guard !Task.isCancelled else { return }
                guard let cgImage = try? result.image else { continue }
                images.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            }
            guard let self, !Task.isCancelled else { return }
            self.thumbnails = images
            self.thumbnailTask = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// The preview player filters on a background queue while the sliders move on the main actor, so what it draws lives behind a lock.
nonisolated final class PreviewFilterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var screen = ColorGrade.neutral
    private var camera = ColorGrade.neutral
    private var masks: [VideoMask] = []

    var screenGrade: ColorGrade {
        get { lock.withLock { screen } }
        set { lock.withLock { screen = newValue } }
    }

    var cameraGrade: ColorGrade {
        get { lock.withLock { camera } }
        set { lock.withLock { camera = newValue } }
    }

    var screenMasks: [VideoMask] {
        get { lock.withLock { masks } }
        set { lock.withLock { masks = newValue } }
    }
}
