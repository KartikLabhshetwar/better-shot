import SwiftUI
import AVKit
import AVFoundation

struct AVPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private enum VideoSidebarTab: Hashable {
    case clip, zoom, style

    static let tabs: [InspectorTab<VideoSidebarTab>] = [
        InspectorTab(.clip, systemImage: "scissors", title: "Clip"),
        InspectorTab(.zoom, systemImage: "plus.magnifyingglass", title: "Zoom"),
        InspectorTab(.style, systemImage: "photo.on.rectangle.angled", title: "Style")
    ]
}

struct VideoEditorView: View {
    @State var model = VideoEditorModel()
    let url: URL

    @State private var shareCredentials = R2CredentialStore.shared
    @State private var shareUploader = R2Uploader.shared
    @State private var shareItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var hostWindow: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarTab: VideoSidebarTab = .clip
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")

                Button {
                    model.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")

                Spacer()

                Button("Cancel") {
                    model.cleanup()
                    hostWindow?.close()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .help("Delete this recording from disk")

                if shareCredentials.isConfigured && shareCredentials.enabled {
                    Button {
                        Task { await shareRecording() }
                    } label: {
                        if let shareItemID, shareUploader.uploadingItems.contains(shareItemID) {
                            HStack(spacing: 6) {
                                ProgressView(value: shareUploader.uploadProgress[shareItemID] ?? 0)
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                                Text("\(Int((shareUploader.uploadProgress[shareItemID] ?? 0) * 100))%")
                                    .font(.caption)
                            }
                        } else {
                            Label("Share", systemImage: "link")
                        }
                    }
                    .disabled(shareItemID != nil)
                }

                Button {
                    Task { await exportRecording() }
                } label: {
                    if model.isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .editorToast($model.toastMessage)
        .confirmationDialog("Delete this recording?", isPresented: $isConfirmingDelete) {
            Button("Delete Recording", role: .destructive) { deleteRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from disk. This cannot be undone.")
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear { model.loadVideo(from: url) }
        .onDisappear { model.cleanup() }
    }

    // MARK: - Inspector Sidebar

    private var videoInspector: some View {
        VStack(spacing: 0) {
            InspectorTabBar(tabs: VideoSidebarTab.tabs, selection: $sidebarTab)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch sidebarTab {
                    case .clip:
                        VideoTrimSection(model: model)
                        InspectorDivider()
                        VideoCropSection(model: model)
                    case .zoom:
                        VideoZoomSection(model: model)
                    case .style:
                        EffectsSection(config: $model.config)
                        InspectorDivider()
                        LayoutSection(config: $model.config, showsAlignment: false)
                        InspectorDivider()
                        BackgroundPickerSection(config: $model.config)
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
        }
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
            let videoAspect: CGFloat = model.videoWidth > 0 && model.videoHeight > 0
                ? CGFloat(model.videoWidth) / CGFloat(model.videoHeight)
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
                        .frame(width: videoW, height: videoH)
                        .scaleEffect(zoomFrame.magnification, anchor: UnitPoint(x: zoomFrame.anchor.x, y: zoomFrame.anchor.y))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .shadow(
                            color: config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength) * 0.4) : .clear,
                            radius: config.shadowStrength > 0 ? max(4, 20 * config.shadowStrength) : 0,
                            y: config.shadowStrength > 0 ? max(2, 8 * config.shadowStrength) : 0
                        )

                        if model.isCropping {
                            VideoCropOverlay(cropRect: $model.cropRect, videoSize: CGSize(width: videoW, height: videoH))
                        } else if model.hasCrop {
                            VideoCropPreview(cropRect: model.cropRect, videoSize: CGSize(width: videoW, height: videoH))
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
            }
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
            Toggle("Zoom", isOn: $model.zoomEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        } content: {
            if model.zoomEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    if model.hasPointerCapture {
                        InspectorPill("Auto Zoom", systemImage: "wand.and.stars", fillsWidth: true) {
                            model.regenerateZoomCues()
                        }
                    } else {
                        InspectorCaption("No cursor data recorded for this clip.")
                    }

                    HStack(spacing: 6) {
                        InspectorPill("Add", systemImage: "plus") {
                            model.addZoomCue(at: model.currentTime)
                        }

                        if let selectedCue {
                            InspectorPill("Delete", systemImage: "trash", role: .destructive) {
                                model.deleteZoomCue(selectedCue.id)
                            }
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

                    InspectorCaption("\(model.zoomCues.count) zoom cue\(model.zoomCues.count == 1 ? "" : "s"). Drag pills on the timeline to adjust.")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : InspectorMotion.reveal, value: model.zoomEnabled)
    }
}

// MARK: - Video Crop Section

private struct VideoCropSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        InspectorSection("Crop", collapsedByDefault: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    InspectorPill(
                        model.isCropping ? "Done" : "Crop",
                        systemImage: "crop",
                        isActive: model.isCropping,
                        fillsWidth: true
                    ) {
                        model.isCropping.toggle()
                    }

                    if model.hasCrop {
                        InspectorPill("Reset", systemImage: "arrow.counterclockwise") {
                            model.resetCrop()
                        }
                    }
                }

                if model.hasCrop {
                    let width = Int(CGFloat(model.videoWidth) * model.cropRect.width)
                    let height = Int(CGFloat(model.videoHeight) * model.cropRect.height)
                    Text("\(width) x \(height)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Video Crop Overlay

private struct VideoCropOverlay: View {
    @Binding var cropRect: CGRect
    let videoSize: CGSize

    private let handleSize: CGFloat = 10
    private let minCropFraction: CGFloat = 0.1
    @State private var startRect: CGRect = .zero

    var body: some View {
        Canvas { context, size in
            let crop = pixelRect(in: size)

            var dimPath = Path()
            dimPath.addRect(CGRect(origin: .zero, size: size))
            dimPath.addRect(crop)
            context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

            let border = crop.insetBy(dx: -1, dy: -1)
            context.stroke(Path(border), with: .color(.white), lineWidth: 1.5)

            let dashes: [CGFloat] = [4, 4]
            let thirdW = crop.width / 3
            let thirdH = crop.height / 3
            for i in 1...2 {
                var vLine = Path()
                vLine.move(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.minY))
                vLine.addLine(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.maxY))
                context.stroke(vLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))

                var hLine = Path()
                hLine.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH * CGFloat(i)))
                hLine.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH * CGFloat(i)))
                context.stroke(hLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))
            }
        }
        .allowsHitTesting(false)
        .frame(width: videoSize.width, height: videoSize.height)
        .overlay {
            GeometryReader { geo in
                let size = geo.size
                let crop = pixelRect(in: size)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .gesture(dragGesture(size: size))

                cornerHandle(at: CGPoint(x: crop.minX, y: crop.minY), corner: .topLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.minY), corner: .topRight, size: size)
                cornerHandle(at: CGPoint(x: crop.minX, y: crop.maxY), corner: .bottomLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.maxY), corner: .bottomRight, size: size)

                edgeHandle(at: CGPoint(x: crop.midX, y: crop.minY), edge: .top, size: size)
                edgeHandle(at: CGPoint(x: crop.midX, y: crop.maxY), edge: .bottom, size: size)
                edgeHandle(at: CGPoint(x: crop.minX, y: crop.midY), edge: .left, size: size)
                edgeHandle(at: CGPoint(x: crop.maxX, y: crop.midY), edge: .right, size: size)
            }
            .frame(width: videoSize.width, height: videoSize.height)
        }
    }

    private func pixelRect(in size: CGSize) -> CGRect {
        CGRect(
            x: cropRect.origin.x * size.width,
            y: cropRect.origin.y * size.height,
            width: cropRect.width * size.width,
            height: cropRect.height * size.height
        )
    }

    private func cornerHandle(at point: CGPoint, corner: Corner, size: CGSize) -> some View {
        Circle()
            .fill(.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch corner {
                        case .topLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.x = max(0, newX)
                            r.origin.y = max(0, newY)
                        case .topRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottomLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .bottomRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        }
                        cropRect = r
                    }
            )
    }

    private func edgeHandle(at point: CGPoint, edge: Edge, size: CGSize) -> some View {
        Capsule()
            .fill(.white)
            .frame(
                width: edge == .top || edge == .bottom ? 24 : 6,
                height: edge == .left || edge == .right ? 24 : 6
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch edge {
                        case .top:
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottom:
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .left:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                        case .right:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                        }
                        cropRect = r
                    }
            )
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if startRect == .zero { startRect = cropRect }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                var r = startRect
                r.origin.x = max(0, min(1 - r.width, startRect.origin.x + dx))
                r.origin.y = max(0, min(1 - r.height, startRect.origin.y + dy))
                cropRect = r
            }
            .onEnded { _ in startRect = .zero }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum Edge { case top, bottom, left, right }
}

// MARK: - Crop Preview (non-interactive, shows crop when not editing)

private struct VideoCropPreview: View {
    let cropRect: CGRect
    let videoSize: CGSize

    var body: some View {
        Canvas { context, size in
            let crop = CGRect(
                x: cropRect.origin.x * size.width,
                y: cropRect.origin.y * size.height,
                width: cropRect.width * size.width,
                height: cropRect.height * size.height
            )

            var dimPath = Path()
            dimPath.addRect(CGRect(origin: .zero, size: size))
            dimPath.addRect(crop)
            context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

            let border = crop.insetBy(dx: -1, dy: -1)
            context.stroke(Path(border), with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .frame(width: videoSize.width, height: videoSize.height)
    }
}
