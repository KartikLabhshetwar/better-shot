//
//  RecordingSessionRenderer.swift
//  BetterShot
//
//  On-demand utility for workflows that require a single flattened movie.
//  The capture pipeline keeps screen and camera as separate safety masters;
//  this renderer must not run on the recording Stop/presentation path.
//

import AppKit
import AVFoundation
import CoreGraphics

@MainActor
enum RecordingSessionRenderer {
    private enum RenderError: LocalizedError {
        case missingCameraTrack
        case projectChanged
        case ambiguousProject
        case multiSourceRenderingUnavailable
        case invalidReplacementAudio

        var errorDescription: String? {
            switch self {
            case .missingCameraTrack:
                "The camera recording does not contain a readable video track."
            case .projectChanged:
                "The project changed while the video was rendering. Try again."
            case .ambiguousProject:
                "This recording is open in more than one editor. Close the other editor window and try again."
            case .invalidReplacementAudio:
                "The project's imported soundtrack is missing or unreadable. Restore it or choose another audio file in Studio."
            case .multiSourceRenderingUnavailable:
                "This project contains multiple recordings. Multi-recording playback and export are not available in this development build yet."
            }
        }
    }

    /// Creates a flattened deliverable when explicitly requested for a session
    /// whose raw screen master would not match what the user sees: a camera
    /// source, a cursor-hidden capture, or any saved Studio project. Only a
    /// never-edited, cursor-visible, camera-less capture is already its own
    /// complete result and skips the expensive second encode.
    static func ensureDeliverable(
        for session: RecordingSession,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let manifest = session.loadCaptureManifest()
        let pointerSynthesized = manifest?.pointerSynthesized == true
        // Draft edits count: a flatten made for an upload must show what the
        // user last saw in Studio, not the last state they pressed Save on.
        let openedSnapshot = StudioProjectRegistry.shared.snapshot(for: session.directoryURL)
        guard openedSnapshot != nil || !StudioProjectRegistry.shared.hasOpenProject(for: session.directoryURL) else {
            throw RenderError.ambiguousProject
        }
        let editDocument = openedSnapshot?.document ?? session.effectiveEditDocument()
        guard session.hasCamera || pointerSynthesized || editDocument != nil else {
            return session.screenURL
        }
        if let existing = session.freshFinalURL(matching: editDocument) { return existing }

        let configuration = try await configuration(for: session, document: editDocument)

        let temporaryURL = try await RecordingStudioExporter().export(configuration) { progress in
            onProgress?(progress)
        }
        do {
            guard canInstallRender(for: session, snapshot: openedSnapshot, renderedDocument: editDocument) else {
                throw RenderError.projectChanged
            }
            return try session.installFinalVideo(
                movingFrom: temporaryURL,
                renderedFrom: editDocument
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Shared authored-source configuration for project playback, previews, and exports.
    static func configuration(
        for session: RecordingSession,
        document: RecordingEditDocument?
    ) async throws -> RecordingStudioExporter.Configuration {
        guard document?.sources == nil, document?.clips?.contains(where: { $0.sourceID != nil }) != true else {
            throw RenderError.multiSourceRenderingUnavailable
        }
        let manifest = session.loadCaptureManifest()
        let pointerSynthesized = manifest?.pointerSynthesized == true
        let asset = AVURLAsset(url: session.screenURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }

        if session.hasCamera {
            let cameraAsset = AVURLAsset(url: session.cameraURL)
            guard try await !cameraAsset.loadTracks(withMediaType: .video).isEmpty else {
                throw RenderError.missingCameraTrack
            }
        }

        let canvasSize = try await outputSize(for: asset, manifest: manifest)
        let recordingPointScale = max(manifest?.pixelScale ?? 1, 1)
        let recordingPointSize = CGSize(
            width: canvasSize.width / CGFloat(recordingPointScale),
            height: canvasSize.height / CGFloat(recordingPointScale)
        )
        let capture = PointerStreamSanitizer.sanitize(
            session.loadPointerCapture() ?? PointerCaptureFile(),
            options: PointerSanitizeOptions(
                recordingSizeInPoints: recordingPointSize
            )
        ).sanitizedCapture
        var style = document?.style.value ?? RecordingStudioDefaults.style
        // Selecting a camera means the default delivered recording includes
        // it; a saved Studio project that explicitly hid the bubble wins.
        style.camera.isVisible = session.hasCamera && (document?.style.value.camera.isVisible ?? true)
        let zoomEnabled = document?.zoomEnabled ?? true
        let zoomCues = document?.zoomCues
            ?? ZoomCueSynthesizer.cues(from: capture, duration: duration)
        let clipTimeline: RecordingClipTimeline
        if let clips = document?.clips, !clips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: clips).normalized(to: duration)
        } else {
            clipTimeline = .legacyTrim(
                start: document?.trimStart,
                end: document?.trimEnd,
                sourceDuration: duration
            )
        }
        let viewportTimeline = zoomEnabled
            ? ViewportTimeline.build(cues: zoomCues, capture: capture, clipTimeline: clipTimeline)
            : .identity
        let showsPressEffects = pointerSynthesized
            && manifest?.pressEffectsBaked == false
            && (document?.showsClickEffects ?? manifest?.pressEffectsEnabled ?? true)
        let showsKeystrokes = (document?.showsKeystrokes ?? true) && !capture.keystrokes.isEmpty

        // One pointer timeline serves both jobs: drawing the synthetic
        // cursor and steering the reframe camera's focus.
        let hasPointerData = !capture.travel.isEmpty || !capture.presses.isEmpty
        let pointerTimeline = hasPointerData
            ? PointerTimeline.build(
                capture: capture,
                duration: duration,
                recordingSizeInPoints: recordingPointSize,
                fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
                clipTimeline: clipTimeline,
                options: style.cursor,
                overrideArtwork: PointerArtworkCapture.styledArtwork(style.cursor.appearance)
            )
            : nil

        let showsSubtitles = document?.showsSubtitles ?? true
        let cues = document?.subtitleCues ?? []
        let words = document?.subtitleWords ?? []

        var audioReplacementURL: URL?
        if let name = document?.replacementAudioFileName {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
                  URL(fileURLWithPath: name).lastPathComponent == name else {
                throw RenderError.invalidReplacementAudio
            }
            let url = session.directoryURL.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  await RecordingReplacementAudio.load(url: url, displayName: name) != nil else {
                throw RenderError.invalidReplacementAudio
            }
            audioReplacementURL = url
        }
        let crop = document?.cropValue ?? RecordingVideoCrop.unit
        let croppedSize = RecordingVideoCrop.croppedSize(canvasSize, crop: crop)
        let croppedViewport = viewportTimeline.cropped(to: crop)
        let aspect = document?.exportAspectPreset ?? .original
        let aspectMode = document?.exportAspectContentMode ?? .fill
        let reframe: ReframeTrack? = aspectMode == .fill
            ? ReframeTrack.build(
                preset: aspect,
                sourceSize: croppedSize,
                viewportTimeline: croppedViewport,
                duration: clipTimeline.duration
            ) { editorTime in
                guard let location = pointerTimeline?.location(at: editorTime) else { return nil }
                let point = RecordingVideoCrop.point(location, in: crop)
                return CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
            }
            : nil
        let fitContentAspect: CGFloat? =
            aspect != .original && aspectMode == .fit && croppedSize.height > 0
                ? croppedSize.width / croppedSize.height
                : nil

        return RecordingStudioExporter.Configuration(
            screenURL: session.screenURL,
            cameraURL: session.hasCamera ? session.cameraURL : nil,
            cameraOffset: manifest?.cameraLeadIn ?? 0,
            style: style,
            viewportTimeline: croppedViewport,
            pointerTimeline: pointerSynthesized ? pointerTimeline : nil,
            showsPressEffects: showsPressEffects,
            keystrokeTimeline: showsKeystrokes
                ? KeystrokeCaptionTimeline(events: capture.keystrokes)
                : nil,
            keystrokePlacement: document?.keystrokePlacement ?? .bottomCenter,
            subtitleTimeline: showsSubtitles && !cues.isEmpty
                ? SubtitleTimeline(cues: cues)
                : nil,
            subtitleStyle: document?.subtitleStyle ?? SubtitleBarStyle(),
            karaokeTimeline: showsSubtitles && !cues.isEmpty && !words.isEmpty
                ? KaraokeTimeline(cues: cues, words: words)
                : nil,
            canvasSize: aspect == .original
                ? croppedSize
                : aspect.canvasSize(for: croppedSize),
            clipTimeline: clipTimeline,
            exportSettings: document?.exportSettings ?? VideoCompressionSettings(),
            audioReplacementURL: audioReplacementURL,
            reframe: reframe,
            fitContentAspect: fitContentAspect,
            crop: crop,
            masks: document?.masks ?? [],
            timeline3D: Recording3DTimeline(shots: document?.shots3D ?? [], duration: clipTimeline.duration)
        )

    }

    /// A render may outlive its editor or an edit to the working document.
    /// Keep the package cache tied to the exact document used for its frames.
    static func canInstallRender(
        for session: RecordingSession,
        snapshot: RecordingStudioDocumentSnapshot?,
        renderedDocument: RecordingEditDocument?
    ) -> Bool {
        let current = StudioProjectRegistry.shared.snapshot(for: session.directoryURL)
        if let snapshot {
            return current == snapshot && renderedDocument == snapshot.document
        }
        return current == nil
            && !StudioProjectRegistry.shared.hasOpenProject(for: session.directoryURL)
            && session.effectiveEditDocument() == renderedDocument
    }

    static func presentFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The camera video could not be added"
        alert.informativeText = "Your screen, camera, and audio masters are safe in the recording project, but BetterShot could not create the combined video: \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func outputSize(
        for asset: AVURLAsset,
        manifest: CaptureManifest?
    ) async throws -> CGSize {
        if let manifest, manifest.pixelWidth > 0, manifest.pixelHeight > 0 {
            return CGSize(width: manifest.pixelWidth, height: manifest.pixelHeight)
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}
