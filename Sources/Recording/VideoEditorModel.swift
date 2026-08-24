import AVFoundation
import AppKit
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
    var toastMessage: String?
    var thumbnails: [NSImage] = []
    var config = BeautifierConfig()

    var videoWidth: Int = 0
    var videoHeight: Int = 0

    var sourceURL: URL?

    var cameraURL: URL?
    var cameraLayout = CameraOverlayLayout()
    var cameraPlayer: AVPlayer?

    var isTrimming = false
    var isCropping = false
    var cropRect = CropGeometry.identity
    private var cropRectBeforeEditing = CropGeometry.identity

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
            || zoomEnabled
            || config.padding > 0 || config.cornerRadius > 0 || config.shadowStrength > 0
            || config.style != .none || config.aspectRatio != .auto
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
    var isCameraVisible: Bool { cameraURL != nil && cameraLayout.isVisible }
    var hasPointerCapture: Bool {
        guard let pointerCapture else { return false }
        return !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty
    }

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
    }

    func setCameraCenter(_ center: CGPoint, in card: CGRect) {
        cameraLayout.center = cameraLayout.clamping(center, in: card)
    }

    func setCameraDiameter(_ value: CGFloat) {
        cameraLayout.diameter = CameraOverlayLayout.clampedDiameter(value)
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
        updated.speed = min(max(speed, Clip.minimumSpeed), Clip.maximumSpeed)
        commitClips(ClipTimeline(clips: clips).replacing(updated), selecting: id)
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

        if isClipMode || hasEffects || hasCrop || hasZoom || isCameraVisible {
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
        let mapToSourceTime: (TimeInterval) -> TimeInterval
        var cameraTrackID: CMPersistentTrackID?

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
            let timeline = ClipTimeline(clips: normalizedClips)
            mapToSourceTime = { timeline.sourceTime(at: $0) }
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
            mapToSourceTime = { $0 + baseTrimStart }
        }

        guard let compVideoTrack = composition.tracks(withMediaType: .video).first(where: { $0.trackID != cameraTrackID }) else {
            throw VideoExportError.compositionTrackUnavailable
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: canvasW, height: canvasH)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.backgroundColor = CGColor.clear

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)

        let cropOrigin = CGPoint(x: fullW * cropRect.origin.x, y: fullH * cropRect.origin.y).applying(transform)
        let untranslatedOrigin = CGPoint.zero.applying(transform)
        let cropShift = CGAffineTransform(
            translationX: untranslatedOrigin.x - cropOrigin.x + offsetX,
            y: untranslatedOrigin.y - cropOrigin.y + offsetY
        )

        if useZoom {
            let timeline = viewportTimeline
            let compositionDuration = composition.duration.seconds
            let step: TimeInterval = 0.1

            func frameTransform(atEditorTime editorTime: TimeInterval) -> CGAffineTransform {
                let sourceTime = mapToSourceTime(editorTime)
                let viewport = timeline.frame(at: sourceTime)
                let anchorDisplay = CGPoint(
                    x: (cropRect.origin.x + viewport.anchor.x * cropRect.width) * fullW,
                    y: (cropRect.origin.y + viewport.anchor.y * cropRect.height) * fullH
                )
                let magnification = max(1, viewport.magnification)
                let zoomTransform = CGAffineTransform(translationX: -anchorDisplay.x, y: -anchorDisplay.y)
                    .concatenating(CGAffineTransform(scaleX: magnification, y: magnification))
                    .concatenating(CGAffineTransform(translationX: anchorDisplay.x, y: anchorDisplay.y))
                return transform
                    .concatenating(zoomTransform)
                    .concatenating(cropShift)
            }

            if compositionDuration > 0 {
                var t: TimeInterval = 0
                var previousTransform = frameTransform(atEditorTime: 0)
                while t < compositionDuration {
                    let nextT = min(t + step, compositionDuration)
                    let toTransform = frameTransform(atEditorTime: nextT)
                    let range = CMTimeRange(
                        start: CMTime(seconds: t, preferredTimescale: 600),
                        end: CMTime(seconds: nextT, preferredTimescale: 600)
                    )
                    layerInstruction.setTransformRamp(fromStart: previousTransform, toEnd: toTransform, timeRange: range)
                    previousTransform = toTransform
                    t = nextT
                }
            } else {
                layerInstruction.setTransform(frameTransform(atEditorTime: 0), at: .zero)
            }
        } else {
            layerInstruction.setTransform(transform.concatenating(cropShift), at: .zero)
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

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
            }
        )

        return try await VideoFrameExporter().export(exportConfig) { _ in }
    }

    private func loadCameraSource() async -> CameraSource? {
        guard isCameraVisible, let cameraURL else { return nil }
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

