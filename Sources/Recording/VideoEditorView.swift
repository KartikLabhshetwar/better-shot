import SwiftUI
import AVKit
import AVFoundation

struct AVPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PassthroughPlayerView {
        let view = PassthroughPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: PassthroughPlayerView, context: Context) {
        nsView.player = player
    }
}

/// AppKit hit testing runs before SwiftUI sees the click, so a plain player view swallows every drag aimed at the overlays stacked on top of it.
final class PassthroughPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct VideoEditorView: View {
    @State var model = VideoEditorModel()
    let url: URL

    @State private var shareCredentials = R2CredentialStore.shared
    @State private var shareUploader = R2Uploader.shared
    @State private var shareItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDiscard = false
    @State private var hostWindow: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("editor.video.timelineHeight") private var storedTimelineHeight = EditorPanelMetrics.defaultTimelineHeight

    private var timelineHeight: Binding<CGFloat> {
        Binding(get: { CGFloat(storedTimelineHeight) }, set: { storedTimelineHeight = Double($0) })
    }

    var body: some View {
        VStack(spacing: EditorPanelMetrics.gap) {
            HStack(spacing: EditorPanelMetrics.gap) {
                VStack(spacing: 0) {
                    VideoPreviewCanvas(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VideoTransportBar(model: model)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(InspectorBarMaterial())

                    TimelineResizeGrip(height: timelineHeight)
                }
                .frame(minWidth: 460, minHeight: EditorPanelMetrics.minPlayerHeight)
                .editorPanel()

                videoInspector
                    .frame(width: EditorPanelMetrics.sidebarWidth)
                    .editorPanel()
            }

            timelineSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: storedTimelineHeight)
                .editorPanel()
        }
        .padding(EditorPanelMetrics.gap)
        .background(EditorCanvasBackdrop())
        .hostWindow($hostWindow)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo (\u{2318}Z)")

                Button {
                    model.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo (\u{21E7}\u{2318}Z)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this recording from disk")

                Button {
                    attemptClose()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close without exporting (esc)")

                if shareCredentials.isConfigured && shareCredentials.enabled {
                    Button {
                        Task { await shareRecording() }
                    } label: {
                        if let shareItemID, shareUploader.uploadingItems.contains(shareItemID) {
                            ProgressView(value: shareUploader.uploadProgress[shareItemID] ?? 0)
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        } else {
                            Label("Share", systemImage: "link")
                        }
                    }
                    .disabled(shareItemID != nil || model.isExporting)
                    .help("Upload and copy a share link")
                }

                Button {
                    Task { await exportRecording() }
                } label: {
                    Label(model.isExporting ? "Exporting\u{2026}" : "Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting)
                .keyboardShortcut("s", modifiers: .command)
                .help("Render and save this recording (\u{2318}S)")
            }
        }
        .editorToast($model.toastMessage)
        .confirmationDialog("Delete this recording?", isPresented: $isConfirmingDelete) {
            Button("Delete Recording", role: .destructive) { deleteRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from disk. This cannot be undone.")
        }
        .confirmationDialog("Discard your edits?", isPresented: $isConfirmingDiscard) {
            Button("Discard Edits", role: .destructive) { closeNow() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The recording stays on disk, but these cuts, zooms and styling are not saved.")
        }
        .editorCloseGuard(window: hostWindow, hasEdits: model.hasEdits) { isConfirmingDiscard = true }
        .onEscapeKey { escapePressed() }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear { model.loadVideo(from: url) }
        .onDisappear { model.cleanup() }
    }

    // MARK: - Inspector Sidebar

    private var videoInspector: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VideoTrimSection(model: model)
                InspectorDivider()
                VideoZoomSection(model: model)
                if model.hasCamera {
                    InspectorDivider()
                    VideoCameraSection(model: model)
                }
                InspectorDivider()
                VideoCropSection(model: model)
                InspectorDivider()
                EffectsSection(config: $model.config)
                InspectorDivider()
                LayoutSection(config: $model.config, showsAlignment: false)
                InspectorDivider()
                BackgroundPickerSection(config: $model.config)

                Spacer(minLength: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .background(InspectorMaterial())
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 6) {
            clipToolbar

            CapTimelineView(model: model, playhead: model.currentTime)
                .frame(height: CapTimelineView.height(zoomEnabled: model.zoomEnabled))
        }
    }

    private var clipToolbar: some View {
        HStack(spacing: 6) {
            InspectorPill("Split", systemImage: "scissors", isActive: model.timelineSplitMode) {
                model.timelineSplitMode.toggle()
            }
            .help("Click a clip on the timeline to cut it")

            if let selectedClip = model.clips.first(where: { $0.id == model.selectedClipID }) {
                InspectorPill("Delete", systemImage: "trash", role: .destructive) {
                    model.deleteSelectedClip()
                }
                .disabled(!model.canDeleteSelectedClip)

                InspectorMenuField(
                    values: Self.speedOptions,
                    selection: Binding(
                        get: { selectedClip.speed },
                        set: { model.setSpeed($0, forClipID: selectedClip.id) }
                    ),
                    label: { "\($0.formatted())x" }
                )
                .frame(width: 76)
            }

            Spacer()

            if model.isClipMode {
                Text("\(model.clips.count) clips")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private static let speedOptions: [Double] = [0.5, 1.0, 1.5, 2.0]

    // MARK: - Actions

    private func deleteRecording() {
        guard let sourceURL = model.sourceURL else { return }
        if let record = HistoryStore.shared.records.first(where: {
            HistoryStore.shared.urlForRecord($0) == sourceURL
                || HistoryStore.shared.displayURLForRecord($0) == sourceURL
        }) {
            HistoryStore.shared.deleteRecord(record)
        }
        try? FileManager.default.removeItem(at: sourceURL)
        model.cleanup()
        hostWindow?.close()
    }

    private func shareRecording() async {
        guard let sourceURL = model.sourceURL else { return }
        let itemID = UUID()
        shareItemID = itemID
        defer { shareItemID = nil }

        guard model.hasEdits else {
            _ = await ShareService.shared.share(itemID: itemID, fileURL: sourceURL)
            return
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterShotShare-\(itemID.uuidString)")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let renderedURL: URL
        do {
            renderedURL = try await model.exportTrimmed(into: stagingDir.path)
        } catch {
            ToastWindow.shared.show(
                title: "Share Failed",
                message: error.localizedDescription,
                systemIcon: "exclamationmark.triangle"
            )
            return
        }
        _ = await ShareService.shared.share(itemID: itemID, fileURL: renderedURL)
    }

    /// Escape peels back the current operation first, so it only reaches the window once there is nothing left to cancel.
    private func escapePressed() -> Bool {
        if model.cancelCurrentOperation() { return true }
        attemptClose()
        return true
    }

    private func attemptClose() {
        if model.hasEdits {
            isConfirmingDiscard = true
        } else {
            closeNow()
        }
    }

    private func closeNow() {
        model.cleanup()
        hostWindow?.close()
    }

    private func exportRecording() async {
        model.isExporting = true
        defer { model.isExporting = false }
        let sourceURL = model.sourceURL

        let exportedURL: URL
        do {
            exportedURL = try await model.exportTrimmed()
        } catch {
            ToastWindow.shared.show(
                title: "Export Failed",
                message: error.localizedDescription,
                systemIcon: "exclamationmark.triangle"
            )
            return
        }

        if let sourceURL, let record = HistoryStore.shared.records.first(where: {
            HistoryStore.shared.urlForRecord($0) == sourceURL
                || HistoryStore.shared.displayURLForRecord($0) == sourceURL
        }) {
            HistoryStore.shared.setBeautifiedPath(exportedURL.path, for: record.id)
        } else {
            _ = HistoryStore.shared.referenceCapture(at: exportedURL, kind: .recording)
        }
        let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        ToastWindow.shared.show(message: "Recording exported!", icon: appIcon)
        model.cleanup()
        hostWindow?.close()
    }
}

// MARK: - Video Inspector Sections

/// The preview reads the playhead to place the zoom viewport, so it lives in its own view: reading it in `VideoEditorView.body` re-evaluated the inspector and toolbar thirty times a second.
private struct VideoPreviewCanvas: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let config = model.config
            let visible = model.isCropping ? CropGeometry.identity : model.cropRect
            let videoAspect: CGFloat = model.videoWidth > 0 && model.videoHeight > 0
                ? (CGFloat(model.videoWidth) * visible.width) / (CGFloat(model.videoHeight) * visible.height)
                : 16.0 / 9.0

            let effectivePadding = (config.style != .none && config.padding <= 0) ? CGFloat(0.06) : config.padding
            let layout = previewLayout(
                bounds: geo.size,
                videoAspect: videoAspect,
                paddingFraction: effectivePadding,
                canvasAspect: config.aspectRatio.numericValue
            )
            let videoW = layout.videoSize.width
            let videoH = layout.videoSize.height
            let canvasW = layout.canvasSize.width
            let canvasH = layout.canvasSize.height
            let cornerRadius = config.cornerRadius * min(videoW, videoH)
            let zoomFrame = model.viewportFrame(at: model.currentTime)

            ZStack {
                EditorCanvasBackdrop()

                ZStack {
                    videoBackground(config.style, size: CGSize(width: canvasW, height: canvasH))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    ZStack {
                        Group {
                            if let player = model.player {
                                AVPlayerRepresentable(player: player)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: videoW / visible.width, height: videoH / visible.height)
                        .offset(
                            x: -(visible.midX - 0.5) * videoW / visible.width,
                            y: -(visible.midY - 0.5) * videoH / visible.height
                        )
                        .frame(width: videoW, height: videoH)
                        .scaleEffect(zoomFrame.magnification, anchor: UnitPoint(x: zoomFrame.anchor.x, y: zoomFrame.anchor.y))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .shadow(
                            color: config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength) * 0.4) : .clear,
                            radius: config.shadowStrength > 0 ? max(4, 20 * config.shadowStrength) : 0,
                            y: config.shadowStrength > 0 ? max(2, 8 * config.shadowStrength) : 0
                        )

                        if model.isCameraVisible {
                            CameraBubbleOverlay(model: model, cardSize: CGSize(width: videoW, height: videoH))
                                .frame(width: videoW, height: videoH)
                        }

                        if model.isCropping {
                            CropBox(rect: $model.cropRect, frameSize: CGSize(width: videoW, height: videoH))
                        }
                    }
                }
                .frame(width: canvasW, height: canvasH)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: config.aspectRatio)
                .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88), value: visible)
                .animation(reduceMotion ? nil : InspectorMotion.reveal, value: model.isCropping)
            }
            .overlay(alignment: .bottom) {
                if model.isCropping {
                    CropToolbar(
                        dimensions: "\(Int(model.croppedSize.width)) x \(Int(model.croppedSize.height))",
                        canReset: model.hasCrop,
                        onReset: { withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.resetCrop() } },
                        onCancel: { withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.cancelCrop() } },
                        onApply: { withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.commitCrop() } }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : InspectorMotion.reveal, value: model.isCropping)
        }
    }

    private struct PreviewLayout {
        let videoSize: CGSize
        let canvasSize: CGSize
    }

    private func previewLayout(
        bounds: CGSize,
        videoAspect: CGFloat,
        paddingFraction: CGFloat,
        canvasAspect: CGFloat?
    ) -> PreviewLayout {
        let shortEdge = min(bounds.width, bounds.height) * 0.8
        var videoW = min(bounds.width * 0.7, shortEdge * videoAspect)
        var videoH = videoW / videoAspect
        let pad = min(videoW, videoH) * paddingFraction
        var canvasW = videoW + pad * 2
        var canvasH = videoH + pad * 2

        if let canvasAspect, canvasAspect > 0 {
            if canvasW / canvasH < canvasAspect {
                canvasW = canvasH * canvasAspect
            } else {
                canvasH = canvasW / canvasAspect
            }
        }

        let fit = min(1, bounds.width * 0.94 / max(canvasW, 1), bounds.height * 0.94 / max(canvasH, 1))
        videoW *= fit
        videoH *= fit
        canvasW *= fit
        canvasH *= fit

        return PreviewLayout(
            videoSize: CGSize(width: videoW, height: videoH),
            canvasSize: CGSize(width: canvasW, height: canvasH)
        )
    }

    @ViewBuilder
    private func videoBackground(_ style: BackgroundStyle, size: CGSize) -> some View {
        switch style {
        case .none:
            TransparencyGrid()
        case .solid(let color):
            Rectangle().fill(color.color)
        case .gradient(let preset):
            Rectangle().fill(preset.swiftUIGradient)
        case .wallpaper(let source):
            if let nsImage = ImageCache.shared.image(atPath: source.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle().fill(.quaternary)
            }
        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }

    // MARK: - Transport Controls
}

/// Same reason as the preview: the timecode ticks with playback and nothing else in the editor needs to.
private struct VideoTransportBar: View {
    let model: VideoEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            timecode(model.formattedCurrentTime, tint: .secondary)
                .frame(alignment: .leading)

            Spacer()

            HStack(spacing: 14) {
                transportButton("backward.fill", size: 13, label: "Step back") { model.stepBackward() }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.inspectorPress(scale: 0.9))
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .help(model.isPlaying ? "Pause" : "Play")

                transportButton("forward.fill", size: 13, label: "Step forward") { model.stepForward() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }

            Spacer()

            timecode(model.formattedDuration, tint: model.hasTrim ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .animation(reduceMotion ? nil : InspectorMotion.press, value: model.isPlaying)
    }

    private func timecode(_ text: String, tint: some ShapeStyle) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tint)
            .frame(width: 56)
    }

    private func transportButton(
        _ icon: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.inspectorPress(scale: 0.85))
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct VideoTrimSection: View {
    @Bindable var model: VideoEditorModel

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }

    var body: some View {
        InspectorSection("Trim") {
            if model.hasTrim {
                InspectorPill("Reset", systemImage: "arrow.counterclockwise") {
                    model.resetTrim()
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 4) {
                    readout("Start", formatTime(model.trimStart), highlighted: false)
                    readout("End", formatTime(model.trimEnd), highlighted: false)
                    readout("Duration", formatTime(model.trimmedDuration), highlighted: true)
                }

                InspectorCaption("Drag the clip handles on the timeline. Scroll to pan, hold Control to zoom.")
            }
        }
    }

    private func readout(_ title: String, _ value: String, highlighted: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(valueTint(highlighted: highlighted))
        }
    }

    private func valueTint(highlighted: Bool) -> AnyShapeStyle {
        guard model.hasTrim else { return AnyShapeStyle(.quaternary) }
        return highlighted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
    }
}

private struct VideoZoomSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedCue: ZoomCue? {
        guard let id = model.selectedZoomCueID else { return nil }
        return model.zoomCues.first { $0.id == id }
    }

    var body: some View {
        InspectorSection("Zoom") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    InspectorPill("Add Zoom", systemImage: "plus.magnifyingglass") {
                        model.addZoomCue(at: model.currentTime)
                    }

                    if let selectedCue {
                        InspectorPill("Delete", systemImage: "trash", role: .destructive) {
                            model.deleteZoomCue(selectedCue.id)
                        }
                    }
                }

                if model.hasPointerCapture {
                    InspectorPill("Auto Zoom", systemImage: "wand.and.stars", fillsWidth: true) {
                        model.regenerateZoomCues()
                    }
                }

                if let selectedCue {
                    InspectorSlider(
                        "Zoom Amount",
                        value: Binding(
                            get: { CGFloat(selectedCue.zoom) },
                            set: { model.setZoomAmount(Double($0), forCueID: selectedCue.id) }
                        ),
                        range: 1.0...4.0,
                        format: .magnification(fractionDigits: 1)
                    )
                }

                InspectorCaption(
                    model.zoomCues.isEmpty
                        ? "Adds a zoom at the playhead. Drag it on the timeline to adjust."
                        : "\(model.zoomCues.count) zoom cue\(model.zoomCues.count == 1 ? "" : "s"). Drag pills on the timeline to adjust."
                )
            }
        }
        .animation(reduceMotion ? nil : InspectorMotion.reveal, value: model.zoomCues.count)
    }
}

// MARK: - Camera Bubble

/// The face cam is a separate video track, so the editor can put it anywhere instead of living with wherever the bubble floated during the recording.
private struct CameraBubbleOverlay: View {
    @Bindable var model: VideoEditorModel
    let cardSize: CGSize

    @State private var dragStartCenter: CGPoint?
    @State private var resizeStartDiameter: CGFloat?
    @State private var isHovering = false

    private var card: CGRect { CGRect(origin: .zero, size: cardSize) }

    var body: some View {
        let rect = model.cameraLayout.rect(in: card)
        Group {
            if let player = model.cameraPlayer {
                CameraPlayerLayer(player: player)
            } else {
                Color.black
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(Circle())
        .contentShape(Circle())
        .gesture(moveGesture)
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1.5, rect.width * 0.022)).allowsHitTesting(false))
        .overlay(alignment: .bottomTrailing) { resizeHandle(onCircleOfDiameter: rect.width) }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .onHover { isHovering = $0 }
        .help("Drag to move the camera, drag the corner handle to resize")
        .position(x: rect.midX, y: rect.midY)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStartCenter ?? model.cameraLayout.center
                dragStartCenter = start
                model.setCameraCenter(
                    CGPoint(
                        x: start.x + value.translation.width / max(cardSize.width, 1),
                        y: start.y + value.translation.height / max(cardSize.height, 1)
                    ),
                    in: card
                )
            }
            .onEnded { _ in dragStartCenter = nil }
    }

    /// Sits on the circle's lower-right edge rather than the bounding box corner, which is where the eye expects a resize grip on a round bubble.
    private func resizeHandle(onCircleOfDiameter diameter: CGFloat) -> some View {
        let inset = 7 - diameter * 0.1465
        return Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .offset(x: inset, y: inset)
            .opacity(isHovering ? 1 : 0)
            .highPriorityGesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = resizeStartDiameter ?? model.cameraLayout.diameter
                resizeStartDiameter = start
                let shortEdge = max(min(cardSize.width, cardSize.height), 1)
                model.setCameraDiameter(start + (value.translation.width + value.translation.height) / shortEdge)
            }
            .onEnded { _ in resizeStartDiameter = nil }
    }
}

private struct CameraPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> CameraPlayerLayerView {
        CameraPlayerLayerView(player: player)
    }

    func updateNSView(_ nsView: CameraPlayerLayerView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class CameraPlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

// MARK: - Video Camera Section

private struct VideoCameraSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        InspectorSection("Camera") {
            VStack(alignment: .leading, spacing: 10) {
                InspectorPill(
                    model.cameraLayout.isVisible ? "Hide Camera" : "Show Camera",
                    systemImage: model.cameraLayout.isVisible ? "video.slash" : "video",
                    isActive: model.cameraLayout.isVisible,
                    fillsWidth: true
                ) {
                    model.cameraLayout.isVisible.toggle()
                }

                if model.cameraLayout.isVisible {
                    InspectorSlider(
                        "Size",
                        value: Binding(
                            get: { model.cameraLayout.diameter },
                            set: { model.setCameraDiameter($0) }
                        ),
                        range: CameraOverlayLayout.minDiameter...CameraOverlayLayout.maxDiameter,
                        format: .percent()
                    )

                    InspectorCaption("Drag the bubble in the preview to move it, or its corner handle to resize.")
                }
            }
        }
    }
}

// MARK: - Video Crop Section

private struct VideoCropSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Crop") {
            VStack(alignment: .leading, spacing: 8) {
                if model.isCropping {
                    InspectorCaption("Drag the frame on the preview, then press Done.")
                } else {
                    HStack(spacing: 6) {
                        InspectorPill("Crop Video", systemImage: "crop", fillsWidth: true) {
                            withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.beginCrop() }
                        }

                        if model.hasCrop {
                            InspectorPill("Reset", systemImage: "arrow.counterclockwise") {
                                withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.resetCrop() }
                            }
                        }
                    }

                    Text("\(Int(model.croppedSize.width)) x \(Int(model.croppedSize.height)) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}
