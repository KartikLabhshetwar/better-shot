import AVFoundation
import AppKit
import SwiftUI
import CoreImage

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

    var isTrimming = false
    var isCropping = false
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var zoomEnabled = false
    var zoomCues: [ZoomCue] = []
    var selectedZoomCueID: UUID?
    private var pointerCapture: PointerCaptureFile?
    private var viewportTimeline: ViewportTimeline = .identity

    var clips: [Clip] = []
    var selectedClipID: UUID?
    private var undoStack: [ClipEditSnapshot] = []
    private var redoStack: [ClipEditSnapshot] = []

    var hasTrim: Bool { trimStart > 0.01 || (duration > 0 && trimEnd < duration - 0.01) }
    var hasCrop: Bool { cropRect != CGRect(x: 0, y: 0, width: 1, height: 1) }
    var isClipMode: Bool { !clips.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var canDeleteSelectedClip: Bool { clips.count > 1 && selectedClipID != nil }
    var hasEdits: Bool {
        hasTrim || hasCrop || isClipMode
            || (zoomEnabled && !zoomCues.isEmpty)
            || config.padding > 0 || config.cornerRadius > 0 || config.shadowStrength > 0 || config.style != .none
    }
    var hasPointerCapture: Bool {
        guard let pointerCapture else { return false }
        return !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty
    }

    private var timeObserver: Any?

    var trimmedDuration: Double { trimEnd - trimStart }

    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String { formatTime(trimmedDuration) }

    func loadVideo(from url: URL) {
        // Detach from the outgoing player before it is replaced — a periodic time observer
        // can only be removed by the AVPlayer that vended it.
        removeTimeObserver()

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

        Task {
            if let dur = try? await asset.load(.duration) {
                duration = dur.seconds
                trimEnd = duration
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                let transform = try? await track.load(.preferredTransform)
                if let size, let transform {
                    let transformed = size.applying(transform)
                    videoWidth = Int(abs(transformed.width))
                    videoHeight = Int(abs(transformed.height))
                }
            }
            loadPointerCapture()
            regenerateZoomCues()
            generateThumbnails()
            setupTimeObserver()
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
    }

    func seekTo(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func stepForward() {
        seekTo(min(currentTime + 1.0, trimEnd))
    }

    func stepBackward() {
        seekTo(max(currentTime - 1.0, trimStart))
    }

    func setTrimStart(_ value: Double) {
        trimStart = max(0, min(value, trimEnd - 1.0))
        if currentTime < trimStart { seekTo(trimStart) }
    }

    func resetCrop() { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) }

    func setTrimEnd(_ value: Double) {
        trimEnd = min(duration, max(value, trimStart + 1.0))
        if currentTime > trimEnd { seekTo(trimEnd) }
    }

    func selectClip(_ id: UUID?) {
        selectedClipID = id
    }

    func splitAtPlayhead() {
        let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
        guard let result = ClipTimeline(clips: base).split(at: currentTime) else { return }
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

    func endClipTrim() {}

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

    func exportTrimmed(into directory: String? = nil) async -> URL? {
        guard let sourceURL else { return nil }
        let asset = AVURLAsset(url: sourceURL)

        let dir = directory ?? AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let outputPath = "\(dir)/bettershot_\(stamp).mp4"
        let outputURL = URL(fileURLWithPath: outputPath)

        var exportConfig = config
        if exportConfig.style != .none && exportConfig.padding <= 0 {
            exportConfig.padding = 0.06
        }

        let hasEffects = exportConfig.padding > 0 || exportConfig.cornerRadius > 0 || exportConfig.shadowStrength > 0 || exportConfig.style != .none
        let hasZoom = zoomEnabled && !zoomCues.isEmpty

        if isClipMode || hasEffects || hasCrop || hasZoom {
            return await exportWithEffects(asset: asset, outputURL: outputURL, config: exportConfig)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        await session.export()

        if session.status == .completed {
            return outputURL
        }
        return nil
    }

    private func exportWithEffects(asset: AVURLAsset, outputURL: URL, config: BeautifierConfig) async -> URL? {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(transform)
        let fullW = abs(transformed.width)
        let fullH = abs(transformed.height)

        let useZoom = zoomEnabled
        let vidW = useZoom ? fullW : fullW * cropRect.width
        let vidH = useZoom ? fullH : fullH * cropRect.height

        let shortEdge = min(vidW, vidH)
        let pad = shortEdge * config.padding
        let canvasW = vidW + pad * 2
        let canvasH = vidH + pad * 2
        let cornerRadius = config.cornerRadius * shortEdge

        let composition: AVMutableComposition
        let mapToSourceTime: (TimeInterval) -> TimeInterval

        if isClipMode {
            let normalizedClips = ClipTimeline(clips: clips).normalized(to: duration)
            guard !normalizedClips.isEmpty else { return nil }
            let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
            guard let built = try? ClipCompositionBuilder.makeComposition(videoTrack: videoTrack, audioTrack: audioTrack, clips: normalizedClips) else { return nil }
            composition = built
            let timeline = ClipTimeline(clips: normalizedClips)
            mapToSourceTime = { timeline.sourceTime(at: $0) }
        } else {
            let legacyComposition = AVMutableComposition()

            guard let compVideoTrack = legacyComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }

            let timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            do {
                try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            } catch {
                return nil
            }

            if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
               let compAudioTrack = legacyComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }

            composition = legacyComposition
            let baseTrimStart = trimStart
            mapToSourceTime = { $0 + baseTrimStart }
        }

        guard let compVideoTrack = composition.tracks(withMediaType: .video).first else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: canvasW, height: canvasH)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.backgroundColor = CGColor.clear

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)

        if useZoom {
            let timeline = viewportTimeline
            let compositionDuration = composition.duration.seconds
            let step: TimeInterval = 0.1

            func frameTransform(atEditorTime editorTime: TimeInterval) -> CGAffineTransform {
                let sourceTime = mapToSourceTime(editorTime)
                let viewport = timeline.frame(at: sourceTime)
                let anchorDisplay = CGPoint(x: viewport.anchor.x * fullW, y: viewport.anchor.y * fullH)
                let magnification = max(1, viewport.magnification)
                let zoomTransform = CGAffineTransform(translationX: -anchorDisplay.x, y: -anchorDisplay.y)
                    .concatenating(CGAffineTransform(scaleX: magnification, y: magnification))
                    .concatenating(CGAffineTransform(translationX: anchorDisplay.x, y: anchorDisplay.y))
                return transform
                    .concatenating(zoomTransform)
                    .concatenating(CGAffineTransform(translationX: pad, y: pad))
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
            let cropOffsetX = fullW * cropRect.origin.x
            let cropOffsetY = fullH * cropRect.origin.y
            var finalTransform = transform
            let postCropTranslation: CGAffineTransform
            if transform == .identity {
                postCropTranslation = CGAffineTransform(translationX: -cropOffsetX + pad, y: -cropOffsetY + pad)
            } else {
                let originAfterTransform = CGPoint(x: cropOffsetX, y: cropOffsetY).applying(transform)
                let fullOriginAfterTransform = CGPoint.zero.applying(transform)
                let dx = fullOriginAfterTransform.x - originAfterTransform.x + pad
                let dy = fullOriginAfterTransform.y - originAfterTransform.y + pad
                postCropTranslation = CGAffineTransform(translationX: dx, y: dy)
            }
            finalTransform = finalTransform.concatenating(postCropTranslation)
            layerInstruction.setTransform(finalTransform, at: .zero)
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let bgLayer = CALayer()
        bgLayer.frame = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
        applyBackgroundToLayer(bgLayer, style: config.style, size: CGSize(width: canvasW, height: canvasH))

        if config.shadowStrength > 0 {
            let shadowContainer = CALayer()
            shadowContainer.frame = CGRect(x: pad, y: pad, width: vidW, height: vidH)
            shadowContainer.shadowColor = CGColor(gray: 0, alpha: 1)
            shadowContainer.shadowOpacity = Float(config.shadowStrength * 0.4)
            shadowContainer.shadowRadius = max(4, 20 * config.shadowStrength)
            shadowContainer.shadowOffset = CGSize(width: 0, height: -max(2, 8 * config.shadowStrength))
            shadowContainer.cornerRadius = cornerRadius

            let mask = CALayer()
            mask.frame = shadowContainer.bounds
            mask.cornerRadius = cornerRadius
            mask.backgroundColor = CGColor(gray: 0, alpha: 1)
            shadowContainer.mask = mask

            bgLayer.addSublayer(shadowContainer)
        }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)

        if cornerRadius > 0 {
            let maskLayer = CAShapeLayer()
            maskLayer.path = CGPath(roundedRect: CGRect(x: pad, y: pad, width: vidW, height: vidH), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            videoLayer.mask = maskLayer
        }

        let outputLayer = CALayer()
        outputLayer.frame = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
        outputLayer.addSublayer(bgLayer)
        outputLayer.addSublayer(videoLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: outputLayer
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition

        await session.export()

        return session.status == .completed ? outputURL : nil
    }

    private func applyBackgroundToLayer(_ layer: CALayer, style: BackgroundStyle, size: CGSize) {
        switch style {
        case .none:
            layer.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        case .solid(let color):
            layer.backgroundColor = color.cgColor
        case .gradient(let preset):
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = CGRect(origin: .zero, size: size)
            gradientLayer.colors = preset.stops.map {
                CGColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
            }
            gradientLayer.startPoint = CGPoint(x: preset.startPoint.x, y: preset.startPoint.y)
            gradientLayer.endPoint = CGPoint(x: preset.endPoint.x, y: preset.endPoint.y)
            layer.addSublayer(gradientLayer)
        case .wallpaper(let source):
            if let image = NSImage(contentsOfFile: source.path),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cgImage
                layer.contentsGravity = .resizeAspectFill
            }
        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image,
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cgImage
                layer.contentsGravity = .resizeAspectFill
            }
        }
    }

    func cleanup() {
        player?.pause()
        removeTimeObserver()
        player = nil
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
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                if self.currentTime >= self.trimEnd && self.isPlaying {
                    self.player?.pause()
                    self.isPlaying = false
                    self.seekTo(self.trimStart)
                }
            }
        }
    }

    private func generateThumbnails() {
        guard let sourceURL, duration > 0 else { return }
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 120, height: 68)
        generator.appliesPreferredTrackTransform = true

        let count = 20
        let step = duration / Double(count)

        Task.detached { [weak self] in
            var images: [NSImage] = []
            for i in 0..<count {
                let time = CMTime(seconds: step * Double(i), preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    images.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                }
            }
            await MainActor.run { self?.thumbnails = images }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
