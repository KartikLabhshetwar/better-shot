//
//  RecordingStudioWindow.swift
//  BetterShot
//
//  The recording studio: a Screen Studio-style editor for screen recordings.
//  Left/center is the composited live preview (background, padded rounded
//  card, zoom-follow-pointer, draggable camera bubble) over a timeline with
//  editable zoom cues; the trailing inspector uses the annotation
//  editor's design system.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct RecordingStudioWindow: View {
    @Binding var url: URL?

    @State private var model: RecordingStudioModel?

    var body: some View {
        Group {
            if let model {
                RecordingStudioContent(model: model)
            } else {
                ProgressView()
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .task(id: url) {
            guard let url else { return }
            let newModel = RecordingStudioModel(url: url)
            model = newModel
            await newModel.load()
        }
        .onDisappear {
            model?.teardown()
        }
    }
}

private struct RecordingStudioContent: View {
    @Bindable var model: RecordingStudioModel
    @State private var isInspectorPresented = true
    @State private var closeGuard = EditorCloseGuard()

    var body: some View {
        VStack(spacing: 0) {
            if let loadError = model.loadError {
                ContentUnavailableView(
                    "Couldn't open recording",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudioCanvas(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AnnotationEditorWorkspaceBackground())
                    .overlay(alignment: .bottom) {
                        if let transferStatus {
                            TransferStatusCard(
                                status: transferStatus,
                                onCancel: cancelTransfer,
                                onRetry: retryTransfer,
                                onDismiss: dismissTransfer
                            )
                            .padding(.bottom, 18)
                            .transition(transferCardTransition)
                        }
                    }
                    .animation(RecordingMotion.showHideSpring, value: transferStatus)

                StudioTimelineEditor(model: model)
            }
        }
        .frame(minWidth: 980, minHeight: 720)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .inspector(isPresented: $isInspectorPresented) {
            StudioInspector(model: model)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    model.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .help("Redo (⇧⌘Z)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.isCroppingVideo {
                    cropActions
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            model.beginVideoCrop()
                        }
                    } label: {
                        Label("Crop", systemImage: "crop")
                    }
                    .disabled(!model.isLoaded)
                    .help("Crop the video")

                    if model.isProject {
                        saveStatus
                    }

                    if model.canShareToCloud {
                        shareStatus
                    }

                    exportStatus

                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
                }
            }
        }
        .navigationTitle(windowTitle)
        .onWindowChange { window in
            configureCloseGuard()
            closeGuard.attach(to: window)
            closeGuard.refreshDocumentEdited()
        }
        .onChange(of: model.hasUnsavedChanges) {
            configureCloseGuard()
            closeGuard.refreshDocumentEdited()
        }
        .onDeleteCommand {
            if let selectedCueID = model.selectedCueID {
                model.removeZoomCue(id: selectedCueID)
            } else if model.selectedClipID != nil {
                model.deleteSelectedClip()
            }
        }
        .onAppear {
            AppActivationPolicy.enter(hidePreview: true)
        }
        .onDisappear {
            closeGuard.detach()
            AppActivationPolicy.leave(restorePreview: true)
        }
    }

    @ViewBuilder
    private var cropActions: some View {
        Menu {
            Picker("Aspect Ratio", selection: cropAspectBinding) {
                ForEach(CropAspectRatio.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(model.cropAspect.title, systemImage: "aspectratio")
                .labelStyle(.titleAndIcon)
        }
        .help("Aspect ratio")

        Button {
            withAnimation(.snappy(duration: 0.18)) { model.resetVideoCropDraft() }
        } label: {
            Text("Reset").padding(.horizontal, 6)
        }
        .help("Reset the selection to the whole video")

        Button {
            withAnimation(.snappy(duration: 0.22)) { model.cancelVideoCrop() }
        } label: {
            Text("Cancel").padding(.horizontal, 6)
        }
        .keyboardShortcut(.cancelAction)

        Button {
            withAnimation(.snappy(duration: 0.22)) { model.applyVideoCrop() }
        } label: {
            Text("Crop").padding(.horizontal, 8)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
    }

    private var cropAspectBinding: Binding<CropAspectRatio> {
        Binding(
            get: { model.cropAspect },
            set: { newValue in
                withAnimation(.snappy(duration: 0.18)) { model.setVideoCropAspect(newValue) }
            }
        )
    }

    private var shareSuggestedTitle: String {
        model.projectDisplayName
    }

    /// AppKit already paints the unsaved dot in the close button; the title
    /// says it in words for anyone who reads the title bar first.
    private var windowTitle: String {
        model.hasUnsavedChanges
            ? "\(model.projectDisplayName) - Edited"
            : model.projectDisplayName
    }

    private func configureCloseGuard() {
        closeGuard.hasUnsavedChanges = { model.hasUnsavedChanges }
        closeGuard.offersDelete = { model.hasNeverBeenSaved }
        closeGuard.projectName = { model.projectDisplayName }
        closeGuard.onDecision = { decision, done in
            switch decision {
            case .save:
                model.saveProject()
                done()
            case .discard:
                Task {
                    await model.discardChanges()
                    done()
                }
            case .delete:
                model.deleteProject()
                done()
            case .cancel:
                break
            }
        }
    }

    /// Save is a plain toolbar button rather than a menu command: Studio is
    /// reached from a menu-bar app, where the main menu isn't a reliable
    /// place to look for ⌘S.
    @ViewBuilder
    private var saveStatus: some View {
        Button {
            model.saveProject()
        } label: {
            if model.saveFlash {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!model.hasUnsavedChanges)
        .help("Save your edits in BetterShot (⌘S)")
    }

    @ViewBuilder
    private var shareStatus: some View {
        CloudUploadButton(suggestedTitle: shareSuggestedTitle, onUpload: model.shareToCloud) {
            Label("Share", systemImage: "link")
                .labelStyle(.titleAndIcon)
        }
        .disabled(!model.isLoaded || model.exportState.isExporting || model.shareState.isBusy)
        .help("Upload and copy a share link")
    }

    @ViewBuilder
    private var exportStatus: some View {
        RecordingExportButton(
            currentSettings: model.exportSettings,
            onExport: model.export(settings:)
        ) {
            Label("Export", systemImage: "arrow.down.circle")
                .labelStyle(.titleAndIcon)
        }
        .tint(.accentColor)
        .disabled(!model.isLoaded || model.shareState.isBusy || model.exportState.isExporting)
        .help("Save the finished video to your Mac")
    }

    private var transferStatus: TransferStatus? {
        switch model.shareState {
        case .rendering(let progress):
            return .working(stage: .rendering, progress: progress)
        case .uploading:
            let progress = model.shareItemID.flatMap {
                CloudUploader.shared.uploadProgress[$0]
            }
            return .working(stage: .uploading, progress: (progress ?? 0) > 0 ? progress : nil)
        case .finished(let link):
            guard let url = URL(string: link) else { return nil }
            return .linkReady(url: url)
        case .failed(let message):
            return .failed(headline: "Share failed", message: message, canRetry: model.canRetryShare)
        case .idle:
            break
        }
        switch model.exportState {
        case .exporting(let progress):
            return .working(stage: .exporting, progress: progress)
        case .finished(let url):
            return .exported(url: url)
        case .failed(let message):
            return .failed(headline: "Export failed", message: message, canRetry: true)
        case .idle:
            return nil
        }
    }

    private var transferCardTransition: AnyTransition {
        RecordingMotion.reduceMotion
            ? .opacity
            : AnyTransition.offset(y: 24).combined(with: .opacity)
    }

    private func cancelTransfer() {
        if model.shareState.isBusy {
            model.cancelShare()
        } else {
            model.cancelExport()
        }
    }

    private func retryTransfer() {
        if case .failed = model.shareState {
            model.retryShare()
        } else if case .failed = model.exportState {
            model.export()
        }
    }

    private func dismissTransfer() {
        model.acknowledgeShareResult()
        model.acknowledgeExportResult()
    }
}

/// The determinate ring shared by every Studio progress affordance, so the
/// toolbar pills and the inspector's export button read as one control.
struct StudioProgressRing: View {
    let progress: Double

    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.15), value: progress)
    }
}

// MARK: - Canvas

private enum StudioCanvasCoordinateSpace {
    static let name = "StudioCanvasSpace"
}

private struct StudioCanvas: View {
    @Bindable var model: RecordingStudioModel

    var body: some View {
        GeometryReader { proxy in
            let available = CGSize(
                width: max(proxy.size.width - 68, 100),
                height: max(proxy.size.height - 56, 100)
            )
            let canvasSize = Self.aspectFit(model.previewCanvasSize, into: available)
            let layout = RecordingStudioLayout.make(
                canvasSize: canvasSize,
                style: model.style,
                includeBubble: model.hasCameraVideo,
                contentAspect: model.previewContentAspect,
                contentMode: model.previewContentMode
            )

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !model.isPlaying)) { _ in
                let state = model.previewViewportFrame(at: model.displayTime)
                let crop = model.effectivePreviewCrop
                let cropCenter = RecordingVideoCrop.point(CGPoint(x: 0.5, y: 0.5), in: crop)

                ZStack {
                    // Fixed frame + clip so a scaledToFill wallpaper can never
                    // inflate the ZStack bounds and shift the card off-center.
                    StudioBackgroundView(style: model.style.background)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .clipped()

                    // The recording card: video with the virtual camera
                    // transform, clipped to the rounded padded card. The
                    // synthetic cursor overlays inside the same clip so it
                    // pans, zooms, and crops exactly like the pixels below.
                    StudioPlayerLayerView(player: model.screenPlayer, gravity: .resize)
                        .frame(
                            width: layout.contentFillSize.width / crop.width,
                            height: layout.contentFillSize.height / crop.height
                        )
                        .scaleEffect(state.magnification)
                        .offset(
                            x: (cropCenter.x - state.anchor.x) * state.magnification * layout.contentFillSize.width,
                            y: (cropCenter.y - state.anchor.y) * state.magnification * layout.contentFillSize.height
                        )
                        .frame(width: layout.cardRect.width, height: layout.cardRect.height)
                        .overlay {
                            if let pointer = model.previewPointerFrame(at: model.displayTime) {
                                StudioCursorOverlay(
                                    pointer: pointer,
                                    artwork: model.artwork(id: pointer.artworkID),
                                    state: state,
                                    cardSize: layout.cardRect.size,
                                    contentSize: layout.contentFillSize,
                                    cursorScale: model.style.cursorScale,
                                    showsClickEffect: model.showsPressEffects
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
                        .overlay {
                            // Keystroke caption in card space: pinned to its
                            // edge, unaffected by the zoom transform.
                            if let caption = model.keystrokeCaption(at: model.displayTime) {
                                StudioKeystrokeCaptionView(
                                    caption: caption,
                                    placement: model.keystrokePlacement,
                                    cardSize: layout.cardRect.size
                                )
                            }
                        }
                        .shadow(
                            color: .black.opacity(model.style.background == .none ? 0 : 0.55 * model.style.shadow),
                            radius: min(canvasSize.width, canvasSize.height) * 0.045 * model.style.shadow,
                            y: min(canvasSize.width, canvasSize.height) * 0.016 * model.style.shadow
                        )
                        .position(x: layout.cardRect.midX, y: layout.cardRect.midY)

                    if model.isCameraVisible(at: model.displayTime), layout.bubbleRect.width > 0 {
                        StudioCameraBubble(model: model, layout: layout)
                    }

                    // Subtitle bar in canvas space - it can sit over the
                    // background below the card, not just over the video, so
                    // padded and portrait layouts keep their caption area.
                    if let subtitle = model.subtitleText(at: model.displayTime) {
                        StudioSubtitleBarView(
                            text: subtitle,
                            karaokeLine: model.subtitleKaraokeLine(at: model.displayTime),
                            style: model.subtitleStyle,
                            canvasSize: canvasSize
                        )
                    }

                    if model.isCroppingVideo {
                        CropAdjustmentOverlay(
                            imageFrame: layout.frameRect(for: .identity),
                            coordinateSpaceName: StudioCanvasCoordinateSpace.name,
                            cropRect: model.cropDraft.standardized,
                            showsEdgeHandles: !model.cropAspect.locksAspect,
                            onResize: { handle, point in
                                model.updateVideoCropDraft(handle: handle, toNormalized: point)
                            },
                            onMove: { start, delta in
                                model.moveVideoCropDraft(from: start, byNormalized: delta)
                            }
                        )
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .coordinateSpace(.named(StudioCanvasCoordinateSpace.name))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private static func aspectFit(_ size: CGSize, into bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Recorded pointer artwork, placed through the same viewport transform the
/// video card uses (see RecordingPointerTimeline for why it is reconstructed).
private struct StudioCursorOverlay: View {
    let pointer: PointerFrame
    let artwork: PointerArtwork?
    let state: ViewportFrame
    let cardSize: CGSize
    /// The video's draw size at magnification 1 - equal to the card
    /// normally, larger when a reframe aspect-fills it.
    var contentSize: CGSize?
    let cursorScale: CGFloat
    let showsClickEffect: Bool

    var body: some View {
        let content = contentSize ?? cardSize
        let tip = CGPoint(
            x: cardSize.width / 2 + content.width * state.magnification * (pointer.location.x - state.anchor.x),
            y: cardSize.height / 2 + content.height * state.magnification * (pointer.location.y - state.anchor.y)
        )

        ZStack(alignment: .topLeading) {
            if showsClickEffect, let press = pointer.press {
                let pressTip = CGPoint(
                    x: cardSize.width / 2
                        + content.width * state.magnification * (press.location.x - state.anchor.x),
                    y: cardSize.height / 2
                        + content.height * state.magnification * (press.location.y - state.anchor.y)
                )
                let effect = PointerPressEffectStyle.geometry(
                    progress: press.progress,
                    referenceHeight: content.height,
                    cursorScale: cursorScale
                )
                let accent = PointerPressEffectStyle.color
                Circle()
                    .fill(
                        Color(red: accent.red, green: accent.green, blue: accent.blue)
                            .opacity(effect.impactOpacity)
                    )
                    .frame(width: effect.impactRadius * 2, height: effect.impactRadius * 2)
                    .position(x: pressTip.x, y: pressTip.y)
                Circle()
                    .stroke(
                        Color(red: accent.red, green: accent.green, blue: accent.blue)
                            .opacity(effect.rippleOpacity),
                        lineWidth: effect.rippleLineWidth
                    )
                    .frame(width: effect.rippleRadius * 2, height: effect.rippleRadius * 2)
                    .position(x: pressTip.x, y: pressTip.y)
            }

            if let artwork,
               let image = StudioCursorImageCache.image(for: artwork) {
                let anchor = artwork.normalizedAnchor
                let height = content.height
                    * PointerArtworkMetrics.heightRatio
                    * cursorScale
                    * artwork.intrinsicScale
                let size = CGSize(
                    width: height * artwork.aspectRatio,
                    height: height
                )
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(
                        CGFloat(pointer.magnification),
                        anchor: UnitPoint(x: anchor.x, y: anchor.y)
                    )
                    .rotationEffect(
                        .degrees(pointer.tiltDegrees),
                        anchor: UnitPoint(x: anchor.x, y: anchor.y)
                    )
                    .position(
                        x: tip.x + (0.5 - anchor.x) * size.width,
                        y: tip.y + (0.5 - anchor.y) * size.height
                    )
                    .opacity(pointer.opacity)
                    .blur(radius: CGFloat(pointer.blurRadius))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .allowsHitTesting(false)
    }
}

/// The keystroke caption pill: one rounded container with the chord's
/// modifiers and key. Geometry comes from KeystrokeCaptionMetrics so the
/// exporter draws the identical pill.
private struct StudioKeystrokeCaptionView: View {
    let caption: KeystrokeCaptionFrame
    let placement: RecordingKeystrokePlacement
    let cardSize: CGSize

    var body: some View {
        let metrics = KeystrokeCaptionMetrics(cardHeight: cardSize.height)
        let (modifiers, key) = KeystrokeCaptionMetrics.text(for: caption)

        (Text(modifiers).foregroundStyle(.white.opacity(KeystrokeCaptionMetrics.modifierAlpha))
            + Text(key).foregroundStyle(.white))
            .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, metrics.paddingHorizontal)
            .padding(.vertical, metrics.paddingVertical)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.black.opacity(KeystrokeCaptionMetrics.backgroundAlpha))
            )
            .scaleEffect(caption.scale)
            .opacity(caption.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)
            .padding(metrics.margin)
            .frame(width: cardSize.width, height: cardSize.height)
            .allowsHitTesting(false)
    }
}

/// The narration subtitle bar: rounded black bar, white text, center-locked
/// horizontally at the style's vertical position on the full canvas
/// (background included). Geometry comes from SubtitleBarMetrics so the
/// exporter draws the identical bar.
private struct StudioSubtitleBarView: View {
    let text: String
    var karaokeLine: KaraokeTimeline.Line?
    let style: SubtitleBarStyle
    let canvasSize: CGSize

    var body: some View {
        let metrics = SubtitleBarMetrics(canvasSize: canvasSize, style: style)

        barText
            .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
            // Long lines wrap into centered lines on narrow canvases,
            // matching the exporter's framesetter layout; the scale
            // factor only kicks in past the shared line cap.
            .lineLimit(SubtitleBarMetrics.maximumLineCount)
            .multilineTextAlignment(.center)
            .lineSpacing(metrics.fontSize * (SubtitleBarMetrics.lineSpacingFactor - 1))
            .minimumScaleFactor(0.4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, metrics.paddingHorizontal)
            .padding(.vertical, metrics.paddingVertical)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.black.opacity(SubtitleBarMetrics.backgroundAlpha))
            )
            // Invisible width cap: constrains where the text wraps while
            // the pill above hugs the text, so the bar never spans the
            // canvas.
            .frame(
                maxWidth: metrics.maximumTextWidth(canvasWidth: canvasSize.width)
                    + metrics.paddingHorizontal * 2
            )
            .position(
                x: canvasSize.width / 2,
                y: canvasSize.height * CGFloat(style.clampedVerticalPosition)
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .allowsHitTesting(false)
    }

    /// Plain white cue text, or karaoke-colored words matching the
    /// exporter's palette exactly (SubtitleBarMetrics.karaoke*).
    private var barText: Text {
        guard let karaokeLine, !karaokeLine.words.isEmpty else {
            return Text(text).foregroundStyle(.white)
        }
        var combined = Text(verbatim: "")
        for (index, word) in karaokeLine.words.enumerated() {
            let color: Color
            if index == karaokeLine.activeIndex {
                color = Color(cgColor: SubtitleBarMetrics.karaokeAccent)
            } else if index < karaokeLine.spokenCount {
                color = .white
            } else {
                color = .white.opacity(SubtitleBarMetrics.karaokeUpcomingAlpha)
            }
            let piece = Text(verbatim: index > 0 ? " \(word)" : word)
                .foregroundStyle(color)
            combined = combined + piece
        }
        return combined
    }
}

/// One editable subtitle line: a timestamp plus the cue text as a free-form
/// field. Hovering a row skims the preview to that cue, clicking or editing
/// commits the playhead there (paused), and the row under the playhead is
/// highlighted so the list follows the video.
private struct StudioSubtitleRow: View {
    @Bindable var model: RecordingStudioModel
    let cue: RecordingSubtitleCue
    let isActive: Bool

    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                model.seekToSubtitle(cue)
            } label: {
                Text(timestamp ?? "–:––")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(editorTime == nil)
            .help(editorTime == nil ? "This subtitle's audio was cut out" : "Jump to this subtitle")

            TextField(
                "Subtitle",
                text: Binding(
                    get: { cue.text },
                    set: { model.updateSubtitleText(id: cue.id, text: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.inspectorValue)
            .focused($isEditing)
            .onChange(of: isEditing) { _, editing in
                // Starting to edit parks the paused preview on this cue so
                // the correction is visible in context while typing.
                if editing {
                    model.seekToSubtitle(cue)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? Color.accentColor.opacity(0.14) : .clear)
        .contentShape(Rectangle())
        .opacity(editorTime == nil ? 0.5 : 1)
        .onTapGesture {
            model.seekToSubtitle(cue)
        }
        .onHover { hovering in
            // Hover skims the paused preview like the timeline strip does;
            // leaving hands the frame back to the real playhead.
            guard !model.isPlaying, let editorTime else { return }
            if hovering {
                model.hoverPreviewTime = editorTime
            } else if model.hoverPreviewTime == editorTime {
                model.hoverPreviewTime = nil
            }
        }
    }

    /// Where this cue lands on the edited timeline; nil when its audio was
    /// cut out entirely.
    private var editorTime: TimeInterval? {
        model.editorTime(forSourceTime: cue.start)
            ?? model.editorTime(forSourceTime: (cue.start + cue.end) / 2)
    }

    private var timestamp: String? {
        guard let editorTime else { return nil }
        let total = max(0, Int(editorTime.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Descript-style transcript editing: the narration as flowing words.
/// Clicking a word jumps the playhead there, shift-clicking selects a
/// passage, and cutting the selection removes that stretch of the video.
/// Words whose footage is already cut render struck-through; filler words
/// carry a dotted underline so the bulk action's targets are visible.
private struct StudioTranscriptEditPanel: View {
    @Bindable var model: RecordingStudioModel

    @State private var selection: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    transcriptFlow
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: model.activeTranscriptWordIndex) { _, activeIndex in
                    // Follow playback through the transcript, but never yank
                    // it around while the user is selecting a passage.
                    guard let activeIndex, model.isPlaying, selection == nil else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(activeIndex, anchor: .center)
                    }
                }
            }

            if let selection {
                cutSelectionRow(selection)
            }
        }
        .onDeleteCommand(perform: cutSelection)
        .onExitCommand { selection = nil }
    }

    private var transcriptFlow: some View {
        let activeIndex = model.activeTranscriptWordIndex
        return TranscriptFlowLayout() {
            ForEach(model.transcriptWords.indices, id: \.self) { index in
                StudioTranscriptWordView(
                    text: model.transcriptWords[index].displayText,
                    isSelected: selection?.contains(index) ?? false,
                    isActive: index == activeIndex,
                    isCut: !model.transcriptWordSurvives(index),
                    isFiller: model.isFillerWord(index)
                ) {
                    handleTap(on: index)
                }
                .id(index)
            }
        }
    }

    private func cutSelectionRow(_ selection: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Button {
                cutSelection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .medium))
                    Text(selection.count == 1 ? "Cut Word" : "Cut \(selection.count) Words")
                        .font(.inspectorValue)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .inspectorField(height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.88))

            InspectorClearButton(help: "Clear selection") {
                self.selection = nil
            }
        }
    }

    private func handleTap(on index: Int) {
        let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if shiftHeld, let selection {
            self.selection = min(selection.lowerBound, index)...max(selection.upperBound, index)
        } else {
            selection = index...index
            model.seekToTranscriptWord(at: index)
        }
    }

    private func cutSelection() {
        guard let selection else { return }
        model.cutTranscriptWords(in: selection)
        self.selection = nil
    }
}

/// One word in the transcript editor, drawn so the flow reads as a plain
/// paragraph: the chip's side padding doubles as the inter-word space
/// (layout spacing is zero), which also makes a multi-word selection's
/// highlight contiguous like real text selection. The font weight never
/// changes with state - a width change would reflow the whole paragraph
/// on every playback tick. Kept to plain stored values so ticks only
/// re-render the words whose state actually changed.
private struct StudioTranscriptWordView: View {
    let text: String
    let isSelected: Bool
    let isActive: Bool
    let isCut: Bool
    let isFiller: Bool
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(foreground)
            .strikethrough(isCut, color: .secondary.opacity(0.6))
            .padding(.horizontal, 1.5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private var foreground: Color {
        isCut ? Color.secondary.opacity(0.45) : Color.primary
    }

    private var background: Color {
        if isSelected {
            Color.accentColor.opacity(isCut ? 0.12 : 0.24)
        } else if isActive, !isCut {
            Color.accentColor.opacity(0.2)
        } else if isFiller, !isCut {
            Color.orange.opacity(0.16)
        } else {
            Color.clear
        }
    }
}

/// Minimal left-aligned wrapping layout for the transcript's word chips.
/// Horizontal spacing lives inside the chips (see StudioTranscriptWordView),
/// so the layout only separates lines.
private struct TranscriptFlowLayout: Layout {
    var spacingX: CGFloat = 0
    var spacingY: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacingY
                rowHeight = 0
            }
            x += size.width + spacingX
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacingY
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacingX
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Small hover-circle icon button matching InspectorClearButton, for section
/// header actions that aren't a plain "clear".
private struct StudioInspectorIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(isHovering ? Color.primary.opacity(0.10) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

private extension RecordingKeystrokePlacement {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topCenter: .top
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }
}

@MainActor
private enum StudioCursorImageCache {
    private static var capturedImages: [String: NSImage] = [:]

    static func image(for artwork: PointerArtwork) -> NSImage? {
        let cacheKey = "\(artwork.artworkID)-\(artwork.imageData.hashValue)"
        if let cached = capturedImages[cacheKey] {
            return cached
        }
        guard let image = NSImage(data: artwork.imageData) else { return nil }
        capturedImages[cacheKey] = image
        return image
    }
}

private struct StudioCameraBubble: View {
    @Bindable var model: RecordingStudioModel
    let layout: RecordingStudioLayout

    @State private var dragStartCenter: CGPoint?

    var body: some View {
        StudioPlayerLayerView(player: model.cameraPlayer, gravity: .resizeAspectFill)
            .frame(width: layout.bubbleRect.width, height: layout.bubbleRect.height)
            .clipShape(RoundedRectangle(cornerRadius: layout.bubbleCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: layout.bubbleCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(0.35),
                radius: min(layout.canvasSize.width, layout.canvasSize.height) * 0.022,
                y: min(layout.canvasSize.width, layout.canvasSize.height) * 0.009
            )
            .position(x: layout.bubbleRect.midX, y: layout.bubbleRect.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartCenter == nil {
                            dragStartCenter = model.style.camera.center
                        }
                        guard let dragStartCenter else { return }
                        let next = CGPoint(
                            x: dragStartCenter.x + value.translation.width / layout.canvasSize.width,
                            y: dragStartCenter.y + value.translation.height / layout.canvasSize.height
                        )
                        model.style.camera.center = CGPoint(
                            x: min(max(next.x, 0), 1),
                            y: min(max(next.y, 0), 1)
                        )
                    }
                    .onEnded { _ in
                        dragStartCenter = nil
                    }
            )
    }
}

/// Renders an AnnotationBackgroundStyle as a live SwiftUI layer.
private struct StudioBackgroundView: View {
    let style: AnnotationBackgroundStyle

    var body: some View {
        switch style {
        case .none:
            Color(white: 0.04)
        case .solid(let color):
            color.color
        case .gradient(let gradient):
            LinearGradient(
                colors: gradient.colors.map(\.color),
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )
        case .customWallpaper(let wallpaper):
            if let image = NSImage(contentsOf: wallpaper.url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.04)
            }
        }
    }
}

/// AVPlayerLayer host for the preview canvas.
private struct StudioPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> StudioPlayerContainerView {
        let view = StudioPlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateNSView(_ nsView: StudioPlayerContainerView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        nsView.playerLayer.videoGravity = gravity
    }
}

final class StudioPlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Timeline

private struct StudioTimelineEditor: View {
    @Bindable var model: RecordingStudioModel

    /// Horizontal scale of the lanes, as a multiplier over "the whole
    /// recording fits the viewport". Zoom 1 is the timeline's original
    /// fixed-width layout; anything above it scrolls.
    @State private var zoom: Double = 1
    @State private var viewportWidth: CGFloat = 1
    @State private var scrollX: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    /// Step per zoom button press / keyboard shortcut.
    private static let zoomStep: Double = 1.6
    /// How close to the viewport edge the playhead may drift before the
    /// lanes scroll to keep it in sight.
    private static let followMargin: CGFloat = 48

    private var scale: StudioTimelineScale {
        StudioTimelineScale(
            viewportWidth: viewportWidth,
            duration: model.duration,
            zoom: zoom
        )
    }

    var body: some View {
        VStack(spacing: StudioTimelineMetrics.rowSpacing) {
            transport
            lanes
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private var lanes: some View {
        GeometryReader { proxy in
            // The proxy width leads the stored one by a frame, so lay the
            // lanes out from it and keep the state copy for the controls.
            let scale = StudioTimelineScale(
                viewportWidth: max(proxy.size.width, 1),
                duration: model.duration,
                zoom: zoom
            )

            VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                    Color.clear
                        .frame(height: StudioTimelineMetrics.playheadLaneHeight)

                    StudioTimelineRuler(
                        duration: model.duration,
                        pointsPerSecond: scale.pointsPerSecond,
                        scrollX: scrollX
                    )
                    .frame(height: StudioTimelineMetrics.rulerHeight)

                    scrollingLanes(scale: scale)
                }
                .overlay {
                    StudioTimelinePlayhead(
                        time: model.currentTime,
                        scale: scale,
                        scrollX: scrollX
                    ) { time in
                        model.pause()
                        model.seek(to: time)
                    }
                }

                StudioTimelineMinimap(
                    scale: scale,
                    scrollX: scrollX,
                    playheadTime: model.currentTime,
                    onScroll: { x in scroll(to: x, in: scale) }
                )
            }
            .onChange(of: proxy.size.width, initial: true) { _, width in
                viewportWidth = max(width, 1)
                clampZoom()
            }
        }
        .frame(height: StudioTimelineMetrics.lanesHeight)
        .onChange(of: model.duration) { _, _ in clampZoom() }
        .onChange(of: model.currentTime) { _, time in followPlayhead(to: time) }
    }

    /// The two lanes that carry real edit targets live in a horizontal scroll
    /// view sized to the zoomed timeline. The ruler, playhead and lane chrome
    /// stay viewport-sized and redraw against `scrollX` instead - a rounded
    /// rectangle or Canvas tens of thousands of points wide would be a single
    /// oversized layer, while an AppKit view only ever draws its visible rect.
    private func scrollingLanes(scale: StudioTimelineScale) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                Color.clear
                    .frame(height: StudioTimelineMetrics.clipLaneHeight)
                StudioZoomLaneBackground()
                    .frame(height: StudioTimelineMetrics.zoomLaneHeight)
                Color.clear
                    .frame(height: StudioTimelineMetrics.scrollerGutter)
            }

            ScrollView(.horizontal) {
                VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                    clipLane
                        .frame(
                            width: scale.contentWidth,
                            height: StudioTimelineMetrics.clipLaneHeight
                        )

                    StudioZoomLane(
                        model: model,
                        scale: scale,
                        visibleRange: scale.visibleRange(scrollX: scrollX)
                    )
                    .frame(
                        width: scale.contentWidth,
                        height: StudioTimelineMetrics.zoomLaneHeight
                    )

                    Color.clear
                        .frame(height: StudioTimelineMetrics.scrollerGutter)
                }
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(scale.isScrollable ? .visible : .never)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                if abs(offset - scrollX) > 0.01 {
                    scrollX = offset
                }
            }
        }
        .frame(height: StudioTimelineMetrics.scrollingLanesHeight)
        .mask(edgeFadeMask(scale: scale))
    }

    /// Fades scrolled-out lane content at the viewport edges instead of
    /// cutting it off hard; each side only fades while there is more content
    /// past it.
    private func edgeFadeMask(scale: StudioTimelineScale) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fade = StudioTimelineMetrics.edgeFadeWidth
            let span = min(fade / width, 0.25)
            let leading = min(max(scrollX, 0) / fade, 1)
            let trailing = min(
                max(scale.contentWidth - scale.viewportWidth - scrollX, 0) / fade,
                1
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(Double(1 - leading)), location: 0),
                    .init(color: .black, location: span),
                    .init(color: .black, location: 1 - span),
                    .init(color: .black.opacity(Double(1 - trailing)), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var clipLane: some View {
        RecordingClipTimelineView(
            selectedClipID: $model.selectedClipID,
            playheadTime: $model.currentTime,
            timeline: model.clipTimeline,
            sourceDuration: model.sourceDuration,
            thumbnails: model.timelineThumbnails,
            onSelect: { model.selectClip(id: $0) },
            onSeek: { time in
                model.pause()
                model.seek(to: time)
            },
            onHover: { time in
                model.timelineHoverTime = time
                model.hoverPreviewTime = time
            },
            onSplit: { model.splitClip(at: $0) },
            onDelete: { deleteSelection() },
            onTrim: { model.trimClip($0) },
            onZoom: { factor, anchorTime in
                applyZoom(factor: factor, anchorTime: anchorTime)
            }
        )
    }

    // MARK: Zoom & scroll

    /// Rescales around `anchorTime`, keeping that moment under the same
    /// screen position so pinching or ⌘-scrolling doesn't shove the edit
    /// you were aiming at out of the viewport.
    private func applyZoom(factor: Double, anchorTime: TimeInterval?) {
        let current = scale
        guard current.duration > 0, factor.isFinite, factor > 0 else { return }
        let anchor = anchorTime ?? current.time(forX: scrollX + viewportWidth / 2)
        let anchorViewportX = current.x(for: anchor) - scrollX
        let next = min(max(zoom * factor, 1), current.maxZoom)
        guard abs(next - zoom) > 0.0001 else { return }

        // A pinch arrives as dozens of small steps; let the storyboard scale
        // with the lane and resample once the gesture settles.
        model.timelineThumbnails.deferSampling()
        zoom = next
        var zoomed = current
        zoomed.zoom = next
        scroll(to: zoomed.x(for: anchor) - anchorViewportX, in: zoomed)
    }

    private func fitTimeline() {
        guard zoom > 1 else { return }
        zoom = 1
        scrollX = 0
        scrollPosition.scrollTo(edge: .leading)
    }

    /// Keeps the zoom inside range after the viewport or the edited duration
    /// changes - a cut or a wider window can leave the old scale past the cap.
    private func clampZoom() {
        let clamped = min(max(zoom, 1), scale.maxZoom)
        if abs(clamped - zoom) > 0.0001 {
            zoom = clamped
        }
    }

    private func followPlayhead(to time: TimeInterval) {
        let current = scale
        guard current.isScrollable else { return }
        let x = current.x(for: time)
        guard x < scrollX + Self.followMargin
            || x > scrollX + viewportWidth - Self.followMargin else { return }
        // While playing, land the playhead a third in so there is room to
        // watch what is coming; a seek just centers it.
        let inset = model.isPlaying ? viewportWidth / 3 : viewportWidth / 2
        scroll(to: x - inset, in: current)
    }

    private func scroll(to x: CGFloat, in scale: StudioTimelineScale) {
        let clamped = min(max(x, 0), max(0, scale.contentWidth - scale.viewportWidth))
        scrollX = clamped
        scrollPosition.scrollTo(x: clamped)
    }

    /// Zoom buttons keep the playhead pinned when it is on screen, so the
    /// scale grows around the edit point rather than the viewport middle.
    private var buttonZoomAnchor: TimeInterval {
        let x = scale.x(for: model.currentTime)
        if x >= scrollX, x <= scrollX + viewportWidth {
            return model.currentTime
        }
        return scale.time(forX: scrollX + viewportWidth / 2)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            timelineButton("Zoom Out", systemImage: "minus.magnifyingglass") {
                applyZoom(factor: 1 / Self.zoomStep, anchorTime: buttonZoomAnchor)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoom <= 1.0001)

            timelineButton("Zoom In", systemImage: "plus.magnifyingglass") {
                applyZoom(factor: Self.zoomStep, anchorTime: buttonZoomAnchor)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(zoom >= scale.maxZoom - 0.0001)

            timelineButton("Fit Timeline", systemImage: "arrow.left.and.right") {
                fitTimeline()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoom <= 1.0001)

            if zoom > 1.0001 {
                Text(String(format: "%.1f×", zoom))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        ZStack {
            zoomControls

            HStack(spacing: 2) {
                Spacer(minLength: 0)

                timelineButton("Split at Playhead", systemImage: "scissors") {
                    model.splitClip(at: model.currentTime)
                }

                timelineButton("Delete Selection", systemImage: "trash") {
                    deleteSelection()
                }
                .disabled(!canDeleteSelection)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 6)

                timelineButton("Undo", systemImage: "arrow.uturn.backward") {
                    model.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)

                timelineButton("Redo", systemImage: "arrow.uturn.forward") {
                    model.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)

                timelineButton("Reset Clips", systemImage: "arrow.counterclockwise") {
                    model.resetClips()
                }
                .disabled(!model.hasClipEdits)
            }

            HStack(spacing: 10) {
                Text(studioPreciseTimecode(model.displayTime))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.9))

                HStack(spacing: 2) {
                    timelineButton("Back to Start", systemImage: "backward.end.fill") {
                        model.pause()
                        model.seek(to: 0)
                    }

                    Button {
                        model.togglePlayback()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.primary.opacity(0.07)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(model.isPlaying ? "Pause" : "Play")
                    .disabled(!model.isLoaded)

                    timelineButton("Skip to End", systemImage: "forward.end.fill") {
                        model.pause()
                        model.seek(to: model.duration)
                    }
                }

                Text(studioPreciseTimecode(model.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 32)
    }

    private var canDeleteSelection: Bool {
        model.selectedCueID != nil || model.canDeleteSelectedClip
    }

    private func deleteSelection() {
        if let cueID = model.selectedCueID {
            model.removeZoomCue(id: cueID)
        } else if model.selectedClipID != nil {
            model.deleteSelectedClip()
        }
    }

    private func timelineButton(
        _ help: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(TransportIconButtonStyle())
        .help(help)
    }
}

private struct TransportIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                .primary.opacity(
                    isEnabled ? (configuration.isPressed ? 0.95 : 0.6) : 0.22
                )
            )
    }
}

private enum StudioTimelineMetrics {
    static let rowSpacing: CGFloat = 8
    static let playheadLaneHeight: CGFloat = 14
    static let rulerHeight: CGFloat = 16
    static let clipLaneHeight: CGFloat = 52
    static let zoomLaneHeight: CGFloat = 32
    static let minimapHeight: CGFloat = 12
    /// Room under the lanes for the horizontal scroller, so it never sits on
    /// top of a zoom block.
    static let scrollerGutter: CGFloat = 8
    /// Width of the fade masking scrolled-out lane content at each edge.
    static let edgeFadeWidth: CGFloat = 32

    static let scrollingLanesHeight = clipLaneHeight + zoomLaneHeight
        + scrollerGutter + rowSpacing * 2
    static let lanesHeight = playheadLaneHeight + rulerHeight
        + scrollingLanesHeight + minimapHeight + rowSpacing * 3
}

/// Duration-spanning overview strip under the lanes. The chip mirrors the
/// scrolled viewport and drags to pan it; grabbing empty track centers the
/// viewport on the pointer.
private struct StudioTimelineMinimap: View {
    let scale: StudioTimelineScale
    let scrollX: CGFloat
    let playheadTime: TimeInterval
    let onScroll: (CGFloat) -> Void

    @State private var grabOffset: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let chipWidth = max(24, width * scale.viewportWidth / max(scale.contentWidth, 1))
            let maxChipX = max(0, width - chipWidth)
            let scrollableWidth = max(scale.contentWidth - scale.viewportWidth, 1)
            let chipX = min(max(scrollX / scrollableWidth, 0), 1) * maxChipX
            let playheadX = scale.duration > 0
                ? CGFloat(min(max(playheadTime / scale.duration, 0), 1)) * width
                : 0

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                if scale.isScrollable {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                        }
                        .frame(width: chipWidth)
                        .offset(x: chipX)
                }

                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 1.5)
                    .offset(x: playheadX - 0.75)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard scale.isScrollable else { return }
                        let offset: CGFloat
                        if let grabOffset {
                            offset = grabOffset
                        } else {
                            let startedInChip = value.startLocation.x >= chipX
                                && value.startLocation.x <= chipX + chipWidth
                            offset = startedInChip
                                ? value.startLocation.x - chipX
                                : chipWidth / 2
                            grabOffset = offset
                        }
                        let targetChipX = min(max(value.location.x - offset, 0), maxChipX)
                        onScroll(targetChipX / max(maxChipX, 1) * scrollableWidth)
                    }
                    .onEnded { _ in grabOffset = nil }
            )
        }
        .frame(height: StudioTimelineMetrics.minimapHeight)
    }
}

/// Shared horizontal scale for every lane in the Studio timeline. `zoom` is a
/// multiplier over "the whole recording fits the viewport", so zoom 1 keeps
/// the original fixed-width timeline and higher values widen the lanes into a
/// scrolling surface where cuts, trim handles and zoom blocks stay grabbable
/// on long recordings.
private struct StudioTimelineScale: Equatable {
    /// Finest scale worth offering; past this a single frame is wider than a
    /// thumbnail tile.
    static let maximumPointsPerSecond: CGFloat = 240
    /// Ceiling on lane width, which is what actually bounds the scale on long
    /// recordings. A 30-minute take still reaches ~55 points per second here.
    static let maximumContentWidth: CGFloat = 100_000

    var viewportWidth: CGFloat
    var duration: TimeInterval
    var zoom: Double

    var contentWidth: CGFloat {
        max(viewportWidth, viewportWidth * CGFloat(zoom))
    }

    var pointsPerSecond: CGFloat {
        duration > 0 ? contentWidth / CGFloat(duration) : 0
    }

    var secondsPerPoint: Double {
        pointsPerSecond > 0 ? 1 / Double(pointsPerSecond) : 0
    }

    var isScrollable: Bool {
        contentWidth > viewportWidth + 0.5
    }

    var maxZoom: Double {
        guard duration > 0, viewportWidth > 1 else { return 1 }
        let widest = min(
            Self.maximumContentWidth,
            Self.maximumPointsPerSecond * CGFloat(duration)
        )
        return max(1, Double(widest / viewportWidth))
    }

    func x(for time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(time, 0), duration)) * pointsPerSecond
    }

    func time(forX x: CGFloat) -> TimeInterval {
        guard pointsPerSecond > 0 else { return 0 }
        return min(max(Double(x / pointsPerSecond), 0), duration)
    }

    /// Editor time span currently on screen, padded a little so lane content
    /// culled against it never pops in at the edges.
    func visibleRange(scrollX: CGFloat) -> ClosedRange<TimeInterval> {
        let margin: CGFloat = 120
        let lower = time(forX: scrollX - margin)
        let upper = time(forX: scrollX + viewportWidth + margin)
        return lower...max(lower, upper)
    }
}

/// Full-height playhead with a grabbable crown pin in the lane above the
/// ruler. The crown is the only hit target - everywhere else the overlay
/// passes clicks through to the tracks underneath.
private struct StudioTimelinePlayhead: View {
    let time: TimeInterval
    let scale: StudioTimelineScale
    let scrollX: CGFloat
    let onScrub: (TimeInterval) -> Void

    private enum Metrics {
        static let crownWidth: CGFloat = 11
        static let crownHeight: CGFloat = 13
        static let hitWidth: CGFloat = 26
        static let hitHeight: CGFloat = 22
        static let lineWidth: CGFloat = 1.5
    }

    private static let coordinateSpace = "studio.playheadLane"

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            // Viewport space: the playhead overlay never scrolls, it just
            // tracks the scrolled lanes underneath it. Off-screen positions
            // clamp to the viewport edge instead of vanishing, so the
            // playhead always shows which side the current time sits on.
            let rawX = scale.x(for: time) - scrollX
            let x = min(max(rawX, 0), width)
            let isClamped = x != rawX

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(
                        width: Metrics.lineWidth,
                        height: max(0, proxy.size.height - Metrics.crownHeight + 2)
                    )
                    .offset(x: x - Metrics.lineWidth / 2, y: Metrics.crownHeight - 2)
                    .allowsHitTesting(false)
                    .opacity(isClamped ? 0.35 : 1)

                Color.clear
                    .frame(width: Metrics.hitWidth, height: Metrics.hitHeight)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        PlayheadCrownShape()
                            .fill(Color.accentColor)
                            .frame(width: Metrics.crownWidth, height: Metrics.crownHeight)
                            .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                    }
                    .offset(x: x - Metrics.hitWidth / 2, y: 0)
                    .opacity(isClamped ? 0.35 : 1)
                    .gesture(
                        DragGesture(
                            minimumDistance: 0,
                            coordinateSpace: .named(Self.coordinateSpace)
                        )
                        .onChanged { value in
                            onScrub(scale.time(forX: value.location.x + scrollX))
                        }
                    )
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
    }
}

/// Rounded flag with a pointed tail, the classic editor playhead pin.
private struct PlayheadCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 3
        let tailHeight: CGFloat = 4
        let bodyBottom = rect.maxY - tailHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: bodyBottom),
            control: CGPoint(x: rect.maxX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bodyBottom - cornerRadius),
            control: CGPoint(x: rect.minX, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Absolute-time ruler above the clip lane. The ruler itself never scrolls: it
/// draws only the time span currently on screen, so a deeply zoomed timeline
/// costs the same to render as a fitted one.
private struct StudioTimelineRuler: View {
    let duration: Double
    let pointsPerSecond: CGFloat
    let scrollX: CGFloat

    var body: some View {
        Canvas { context, size in
            guard duration > 0.2, pointsPerSecond > 0, size.width > 60 else { return }

            let step = Self.labelStep(forPointsPerSecond: pointsPerSecond)
            let startTime = max(0, Double(scrollX / pointsPerSecond))
            let endTime = min(duration, Double((scrollX + size.width) / pointsPerSecond))
            let endpointLabel = Self.label(for: duration, step: step)
            var lastLabelMaxX = -CGFloat.greatestFiniteMagnitude

            func x(for time: Double) -> CGFloat {
                CGFloat(time) * pointsPerSecond - scrollX
            }

            /// `anchorX` is the tick position; `trailing` right-aligns the
            /// label onto it instead of centering, which is how the endpoint
            /// label stays inside the viewport.
            func drawLabel(_ text: String, at anchorX: CGFloat, trailing: Bool = false) {
                let label = context.resolve(
                    Text(text)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                )
                let labelSize = label.measure(in: size)
                let labelX = trailing ? anchorX - labelSize.width : anchorX - labelSize.width / 2
                let clampedX = min(max(labelX, 0), max(0, size.width - labelSize.width))
                guard clampedX >= lastLabelMaxX + 8 else { return }
                context.draw(label, in: CGRect(
                    x: clampedX,
                    y: size.height - 5 - labelSize.height,
                    width: labelSize.width,
                    height: labelSize.height
                ))
                lastLabelMaxX = clampedX + labelSize.width
            }

            var index = max(0, Int(floor(startTime / step)))
            let lastIndex = Int(ceil(endTime / step))
            while index <= lastIndex {
                let time = Double(index) * step
                index += 1
                guard time <= duration else { break }
                let tickX = x(for: time)

                context.fill(
                    Path(CGRect(x: tickX - 0.5, y: size.height - 4, width: 1, height: 4)),
                    with: .color(.primary.opacity(0.30))
                )

                let minorTime = time + step / 2
                if minorTime < duration {
                    context.fill(
                        Path(CGRect(
                            x: x(for: minorTime) - 0.5,
                            y: size.height - 2.5,
                            width: 1,
                            height: 2.5
                        )),
                        with: .color(.primary.opacity(0.16))
                    )
                }

                // A final whole-second tick can format identically to a
                // fractional endpoint (for example 4.2 -> 00:04). Let the
                // actual endpoint own that label.
                let timeLabel = Self.label(for: time, step: step)
                if time == 0 || timeLabel != endpointLabel {
                    drawLabel(timeLabel, at: tickX)
                }
            }

            // The end of the recording always gets a tick, right-aligned when
            // it lands at the trailing edge of the viewport.
            let endpointX = x(for: duration)
            if endpointX >= -1, endpointX <= size.width + 1 {
                context.fill(
                    Path(CGRect(
                        x: min(endpointX, size.width - 0.5) - 0.5,
                        y: size.height - 4,
                        width: 1,
                        height: 4
                    )),
                    with: .color(.primary.opacity(0.30))
                )
                drawLabel(endpointLabel, at: endpointX, trailing: true)
            }
        }
    }

    /// Smallest "nice" interval whose labels stay comfortably apart at the
    /// current scale. Sub-second steps unlock once a zoomed lane spreads a
    /// single second across most of the viewport.
    private static func labelStep(forPointsPerSecond pointsPerSecond: CGFloat) -> Double {
        let candidates: [Double] = [
            0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800
        ]
        for candidate in candidates where CGFloat(candidate) * pointsPerSecond >= 64 {
            return candidate
        }
        return candidates.last ?? 60
    }

    private static func label(for time: Double, step: Double) -> String {
        step < 1 ? studioPreciseTimecode(time) : studioTimecode(time)
    }
}

private func studioTimecode(_ seconds: Double) -> String {
    let safe = max(0, seconds.isFinite ? seconds : 0)
    let total = Int(safe.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remainingSeconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        : String(format: "%02d:%02d", minutes, remainingSeconds)
}

private func studioPreciseTimecode(_ seconds: Double) -> String {
    let safe = max(0, seconds.isFinite ? seconds : 0)
    let totalMinutes = Int(safe) / 60
    let remaining = safe.truncatingRemainder(dividingBy: 60)
    return String(format: "%02d:%04.1f", totalMinutes, remaining)
}

/// Frame around the zoom lane. It stays pinned to the viewport while the cue
/// blocks scroll inside it, so the lane reads as a fixed track no matter how
/// far the timeline is zoomed.
private struct StudioZoomLaneBackground: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: StudioZoomLaneMetrics.laneCornerRadius,
            style: .continuous
        )
            .fill(Color.primary.opacity(0.055))
            .overlay {
                RoundedRectangle(
                    cornerRadius: StudioZoomLaneMetrics.laneCornerRadius,
                    style: .continuous
                )
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
    }
}

private struct StudioZoomLane: View {
    @Bindable var model: RecordingStudioModel
    let scale: StudioTimelineScale
    let visibleRange: ClosedRange<TimeInterval>

    /// Below this many dragged points, a gesture on blank lane space is
    /// still treated as a click-to-seek rather than a zoom-creating drag.
    private static let dragCreateThreshold: CGFloat = 4

    /// Held as a time rather than a position so a zoom change mid-drag can't
    /// reinterpret where the drag began.
    @State private var dragStartTime: TimeInterval?
    @State private var pendingZoomRange: ClosedRange<TimeInterval>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Contentless hit surface: the lane can be tens of thousands of
            // points wide, and the visible frame is drawn by the chrome behind
            // the scroll view.
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard scale.pointsPerSecond > 0 else { return }
                            let time = scale.time(forX: value.location.x)

                            if dragStartTime == nil {
                                model.pause()
                                dragStartTime = time
                            }
                            guard let startTime = dragStartTime else { return }

                            if pendingZoomRange == nil,
                               abs(value.location.x - scale.x(for: startTime))
                                   < Self.dragCreateThreshold {
                                // Still within click tolerance: scrub the
                                // playhead, same as a plain click always has.
                                model.seek(to: time)
                                return
                            }

                            pendingZoomRange = pendingRange(from: startTime, to: time)
                        }
                        .onEnded { _ in
                            // A range clamped to nothing means the drag ran
                            // entirely into a neighboring block; there is no
                            // gap here to put a zoom in.
                            if let range = pendingZoomRange,
                               range.upperBound - range.lowerBound > 0.001 {
                                model.addZoomCue(
                                    fromEditorTime: range.lowerBound,
                                    toEditorTime: range.upperBound
                                )
                            }
                            dragStartTime = nil
                            pendingZoomRange = nil
                        }
                )

            if let pendingZoomRange {
                let lowX = scale.x(for: pendingZoomRange.lowerBound)
                let highX = scale.x(for: pendingZoomRange.upperBound)
                RoundedRectangle(
                    cornerRadius: StudioZoomLaneMetrics.blockCornerRadius,
                    style: .continuous
                )
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(2, highX - lowX), height: StudioZoomLaneMetrics.blockHeight)
                    .offset(x: lowX, y: StudioZoomLaneMetrics.blockInset)
                    .allowsHitTesting(false)
            }

            // Click ticks and cue blocks are culled to the visible span: an
            // hour-long take can hold thousands of clicks, and only a screenful
            // of them can ever be seen.
            ForEach(Array(visiblePressTimes.enumerated()), id: \.offset) { _, pressTime in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.38))
                    .frame(width: 1, height: 10)
                    .offset(x: scale.x(for: pressTime), y: 11)
                    .allowsHitTesting(false)
            }

            ForEach(visibleBlocks) { block in
                StudioZoomCueBlock(model: model, block: block, scale: scale)
            }
        }
        .contextMenu {
            Button("Add Zoom at Playhead") {
                model.addZoomCue(at: model.currentTime)
            }
        }
    }

    /// The range a drag-created zoom would cover, stopped at the blocks on
    /// either side of where the drag began so the preview matches the cue the
    /// model will actually allow.
    private func pendingRange(
        from startTime: TimeInterval,
        to currentTime: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        let blocks = model.zoomTimelineBlocks
        let lowerLimit = blocks
            .filter { $0.editorEnd <= startTime }
            .map(\.editorEnd)
            .max() ?? 0
        let upperLimit = blocks
            .filter { $0.editorStart >= startTime }
            .map(\.editorStart)
            .min() ?? model.duration
        let low = max(min(startTime, currentTime), lowerLimit)
        let high = min(max(startTime, currentTime), upperLimit)
        return low...max(low, high)
    }

    private var visiblePressTimes: [TimeInterval] {
        model.visibleRecordedPressTimes.filter { visibleRange.contains($0) }
    }

    private var visibleBlocks: [RecordingZoomTimelineBlock] {
        model.zoomTimelineBlocks.filter {
            $0.editorEnd >= visibleRange.lowerBound && $0.editorStart <= visibleRange.upperBound
        }
    }
}

private enum StudioZoomLaneMetrics {
    static let laneInset: CGFloat = 4
    static let blockCornerRadius: CGFloat = 6
    static let laneCornerRadius = blockCornerRadius + laneInset
    static let selectionRingPadding: CGFloat = 1
    static let selectionRingCornerRadius = blockCornerRadius + selectionRingPadding
    static let blockHeight: CGFloat = 24
    static let blockInset: CGFloat = 4
}

private struct StudioZoomCueBlock: View {
    @Bindable var model: RecordingStudioModel
    let block: RecordingZoomTimelineBlock
    let scale: StudioTimelineScale

    /// Frozen at drag start. The live block re-derives on every model update,
    /// so measuring the drag against it would compound the translation each
    /// event and send the block flying.
    private struct DragBase {
        let cue: ZoomCue
        let editorStart: TimeInterval
        let editorEnd: TimeInterval
    }

    @State private var dragBase: DragBase?

    private var isSelected: Bool {
        model.selectedCueID == block.cue.id
    }

    var body: some View {
        guard scale.pointsPerSecond > 0 else { return AnyView(EmptyView()) }

        let cue = block.cue
        let blockDuration = block.editorEnd - block.editorStart
        // Short cues keep a grabbable minimum width even when the timeline is
        // fitted; zooming in is what makes them accurate to work with.
        let width = min(
            scale.contentWidth,
            max(24, CGFloat(blockDuration) * scale.pointsPerSecond)
        )
        let x = min(
            max(scale.x(for: block.editorStart), 0),
            max(0, scale.contentWidth - width)
        )

        return AnyView(
            HStack(spacing: 0) {
                resizeHandle(edge: .leading)
                Spacer(minLength: 0)
                Text(String(format: "%.1f×", cue.zoom))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                resizeHandle(edge: .trailing)
            }
            .frame(width: width, height: StudioZoomLaneMetrics.blockHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: StudioZoomLaneMetrics.blockCornerRadius,
                    style: .continuous
                )
                    .fill(Color.accentColor.opacity(isSelected ? 0.95 : 0.72))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: StudioZoomLaneMetrics.selectionRingCornerRadius,
                        style: .continuous
                    )
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        .padding(-StudioZoomLaneMetrics.selectionRingPadding)
                }
            }
            .offset(x: x, y: StudioZoomLaneMetrics.blockInset)
            .gesture(
                // Global coordinates: the block moves under the pointer while
                // dragging, so a local-space translation would chase its own
                // updates and jitter.
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragBase == nil {
                            dragBase = DragBase(
                                cue: cue,
                                editorStart: block.editorStart,
                                editorEnd: block.editorEnd
                            )
                            model.beginZoomCueEdit()
                            model.selectZoomCue(id: cue.id)
                        }
                        guard let dragBase else { return }
                        let delta = Double(value.translation.width) * scale.secondsPerPoint
                        var moved = dragBase.cue
                        let length = dragBase.cue.duration
                        let baseBlockDuration = dragBase.editorEnd - dragBase.editorStart
                        let editorStart = min(
                            max(0, dragBase.editorStart + delta),
                            max(0, model.duration - baseBlockDuration)
                        )
                        moved.start = min(
                            max(0, model.sourceTime(atEditorTime: editorStart)),
                            max(0, model.sourceDuration - length)
                        )
                        moved.end = min(model.sourceDuration, moved.start + length)
                        model.moveZoomCue(moved)
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endZoomCueEdit(actionName: "Move Zoom")
                    }
            )
            .onTapGesture {
                model.selectZoomCue(id: cue.id)
            }
            .contextMenu {
                Button("Remove Zoom", role: .destructive) {
                    model.removeZoomCue(id: cue.id)
                }
            }
        )
    }

    private func resizeHandle(edge: HorizontalEdge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 10, height: StudioZoomLaneMetrics.blockHeight)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(isSelected ? 0.9 : 0.45))
                    .frame(width: 2.5, height: 12)
            }
            .contentShape(Rectangle())
            .gesture(
                // Global coordinates - the handle itself moves while resizing,
                // so local-space translations feed back into the drag and jitter.
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragBase == nil {
                            dragBase = DragBase(
                                cue: block.cue,
                                editorStart: block.editorStart,
                                editorEnd: block.editorEnd
                            )
                            model.beginZoomCueEdit()
                            model.selectZoomCue(id: block.cue.id)
                        }
                        guard let dragBase else { return }
                        let delta = Double(value.translation.width) * scale.secondsPerPoint
                        var resized = dragBase.cue
                        switch edge {
                        case .leading:
                            let editorTime = dragBase.editorStart + delta
                            let sourceTime = model.sourceTime(atEditorTime: editorTime)
                            resized.start = min(
                                max(0, sourceTime),
                                dragBase.cue.end - ZoomCue.minimumDuration
                            )
                        case .trailing:
                            let editorTime = dragBase.editorEnd + delta
                            let sourceTime = model.sourceTime(atEditorTime: editorTime)
                            resized.end = max(
                                dragBase.cue.start + ZoomCue.minimumDuration,
                                min(model.sourceDuration, sourceTime)
                            )
                        }
                        model.updateZoomCue(resized)
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endZoomCueEdit(actionName: "Resize Zoom")
                    }
            )
    }
}

// MARK: - Inspector

private enum StudioBackgroundKind: String, CaseIterable, Identifiable {
    case color
    case gradient
    case wallpaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: "Color"
        case .gradient: "Gradient"
        case .wallpaper: "Wallpaper"
        }
    }
}

private extension ZoomAnchorMode {
    var inspectorTitle: String {
        switch self {
        case .pointerAnchor: "Pointer"
        case .smartAnchor: "Smart"
        case .pinnedAnchor: "Fixed"
        }
    }
}

private enum StudioInspectorSection: Hashable {
    case background
    case layout
    case motion
    case cursor
    case keystrokes
    case transcription
    case camera
    case audio
}

private enum StudioTranscriptTab: CaseIterable, Identifiable {
    case captions
    case edit

    var id: Self { self }

    var title: String {
        switch self {
        case .captions: "Captions"
        case .edit: "Edit Video"
        }
    }
}

private struct StudioInspector: View {
    @Bindable var model: RecordingStudioModel
    @State private var wallpaperStore = AnnotationWallpaperStore.shared
    @State private var stylePresetStore = RecordingStudioStylePresetStore.shared
    @State private var expandedSections: Set<StudioInspectorSection> = [
        .background, .layout, .motion
    ]
    @State private var transcriptTab: StudioTranscriptTab = .captions
    @Environment(\.colorScheme) private var colorScheme

    private let swatchColumns = [GridItem(.adaptive(minimum: 30, maximum: 44), spacing: 6)]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                InspectorDisclosureSection(
                    title: "Background",
                    isExpanded: expansionBinding(for: .background),
                    accessory: {
                        if model.style.background != .none {
                            InspectorClearButton(help: "Remove background") {
                                model.style.background = .none
                            }
                        }
                    }
                ) {
                    backgroundControls
                }

                InspectorDisclosureSection(
                    title: "Layout",
                    isExpanded: expansionBinding(for: .layout),
                    accessory: {
                        if !usesDefaultLayout {
                            InspectorClearButton(help: "Reset layout") {
                                model.style.padding = 0.06
                                model.style.cornerRadius = 0.02
                                model.style.shadow = 0.45
                            }
                        }
                    }
                ) {
                    layoutControls
                }

                // Selection editing surfaces here (between Layout and Zoom &
                // Clicks) whenever a zoom or clip is selected on the timeline.
                if let selected = model.selectedCue {
                    InspectorSection(
                        title: "Selected Zoom",
                        accessory: {
                            Toggle(
                                "Use this zoom",
                                isOn: Binding(
                                    get: { selected.isEnabled },
                                    set: { isEnabled in
                                        var updated = selected
                                        updated.isEnabled = isEnabled
                                        model.updateZoomCue(updated)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .help("Use this zoom")
                        }
                    ) {
                        selectedZoomControls(for: selected)
                    }
                    InspectorSectionDivider()
                } else if let selectedClip = model.selectedClip {
                    InspectorSection("Selected Clip") {
                        selectedClipControls(for: selectedClip)
                    }
                    InspectorSectionDivider()
                }

                InspectorDisclosureSection(
                    title: "Zoom & Clicks",
                    isExpanded: expansionBinding(for: .motion),
                    accessory: {
                        Toggle("Enable zooms", isOn: $model.zoomEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                ) {
                    zoomControls
                }

                if model.pointerIsSynthesized {
                    InspectorDisclosureSection(
                        title: "Cursor",
                        isExpanded: expansionBinding(for: .cursor),
                        accessory: {
                            if model.style.cursorScale != RecordingStudioStyle.defaultCursorScale {
                                InspectorClearButton(help: "Reset cursor size") {
                                    model.style.cursorScale = RecordingStudioStyle.defaultCursorScale
                                }
                            }
                        }
                    ) {
                        cursorControls
                    }
                }

                if model.hasKeystrokes {
                    InspectorDisclosureSection(
                        title: "Keystrokes",
                        isExpanded: expansionBinding(for: .keystrokes),
                        accessory: {
                            Toggle("Show keystrokes", isOn: $model.showsKeystrokes)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                    ) {
                        keystrokeControls
                    }
                }

                if model.canTranscribe || model.hasSubtitles {
                    InspectorDisclosureSection(
                        title: "Transcription",
                        isExpanded: expansionBinding(for: .transcription),
                        accessory: {
                            if model.hasSubtitles {
                                HStack(spacing: 2) {
                                    if model.transcriptionState.isTranscribing {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .frame(width: 18, height: 18)
                                    } else if model.canTranscribe {
                                        StudioInspectorIconButton(
                                            systemName: "arrow.clockwise",
                                            help: "Transcribe again"
                                        ) {
                                            model.transcribe()
                                        }
                                    }

                                    InspectorClearButton(help: "Remove subtitles") {
                                        model.removeTranscription()
                                    }

                                    Toggle("Show subtitles", isOn: $model.showsSubtitles)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    ) {
                        transcriptionControls
                    }
                }

                if model.hasCameraVideo {
                    InspectorDisclosureSection(
                        title: "Camera",
                        isExpanded: expansionBinding(for: .camera),
                        accessory: {
                            Toggle("Show camera", isOn: $model.style.camera.isVisible)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                    ) {
                        cameraControls
                    }
                }

                InspectorDisclosureSection(
                    title: "Audio",
                    isExpanded: expansionBinding(for: .audio),
                    accessory: {
                        if model.replacementAudio != nil {
                            InspectorClearButton(
                                help: model.hasRecordedAudio
                                    ? "Use the recorded audio again"
                                    : "Remove this audio"
                            ) {
                                model.removeReplacementAudio()
                            }
                        }
                    }
                ) {
                    audioControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, PreviewPeekTab.pillHeight * 1.1)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                RecordingStudioStylePresetBar(model: model, presetStore: stylePresetStore)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.45))
                    .frame(height: 0.5)
            }
            .background(sidebarBackground)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectSoftIfAvailable()
        .background(sidebarBackground)
        .inspectorColumnWidth(min: 260, ideal: 280, max: 440)
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await wallpaperStore.reload()
        }
    }

    // MARK: Background

    private var backgroundKind: StudioBackgroundKind? {
        switch model.style.background {
        case .none: nil
        case .solid: .color
        case .gradient: .gradient
        case .customWallpaper: .wallpaper
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorGroupLabel("Aspect")
            InspectorSegmented(
                options: ExportAspectPreset.allCases,
                isSelected: { $0 == model.exportAspect },
                onTap: { model.exportAspect = $0 },
                label: { preset in
                    Text(preset.title)
                        .font(.inspectorLabel)
                        .help(preset.help)
                }
            )
            if model.exportAspect != .original {
                InspectorSegmented(
                    options: ExportAspectContentMode.allCases,
                    isSelected: { $0 == model.exportAspectMode },
                    onTap: { model.exportAspectMode = $0 },
                    label: { mode in
                        Text(mode.title)
                            .font(.inspectorLabel)
                            .help(mode.help)
                    }
                )
                Text(
                    model.exportAspectMode == .fill
                        ? "Crops into the recording; the camera follows your cursor and zooms."
                        : "Shows the whole recording framed on the background."
                )
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            InspectorGroupLabel("Style")
            InspectorSegmented(
                options: StudioBackgroundKind.allCases,
                isSelected: { $0 == backgroundKind },
                onTap: { kind in
                    switch kind {
                    case .color:
                        model.style.background = .solid(.graphite)
                    case .gradient:
                        model.style.background = RecordingStudioStyle.defaultBackground
                    case .wallpaper:
                        if let wallpaper = BundledBackgrounds.macWallpapers.first
                            ?? wallpaperStore.recentWallpapers.first {
                            selectWallpaper(wallpaper)
                        } else {
                            pickWallpaper()
                        }
                    }
                },
                label: { Text($0.title).font(.inspectorLabel) }
            )

            if backgroundKind == .color {
                LazyVGrid(columns: swatchColumns, spacing: 6) {
                    ForEach(AnnotationBackgroundColor.plainPresets) { preset in
                        InspectorTile(
                            isSelected: model.style.background == .solid(preset),
                            action: { model.style.background = .solid(preset) }
                        ) {
                            preset.color
                        }
                    }
                }
            }

            if backgroundKind == .gradient {
                LazyVGrid(columns: swatchColumns, spacing: 6) {
                    ForEach(AnnotationBackgroundGradient.presets) { preset in
                        InspectorTile(
                            isSelected: model.style.background == .gradient(preset),
                            action: { model.style.background = .gradient(preset) }
                        ) {
                            LinearGradient(
                                colors: preset.colors.map(\.color),
                                startPoint: preset.startPoint,
                                endPoint: preset.endPoint
                            )
                        }
                    }
                }
            }

            if backgroundKind == .wallpaper {
                AnnotationWallpaperLibraryPicker(
                    wallpaperStore: wallpaperStore,
                    selected: selectedWallpaper,
                    onSelect: selectWallpaper,
                    onPickCustom: pickWallpaper
                )
            }
        }
    }

    private var selectedWallpaper: AnnotationCustomWallpaper? {
        guard case .customWallpaper(let wallpaper) = model.style.background else { return nil }
        return wallpaper
    }

    private func selectWallpaper(_ wallpaper: AnnotationCustomWallpaper) {
        wallpaperStore.addRecentWallpaper(wallpaper.url)
        model.style.background = .customWallpaper(wallpaper)
    }

    private func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Video Background Wallpaper"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            selectWallpaper(AnnotationCustomWallpaper(url: url))
        }
    }

    // MARK: Layout

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSlider(
                "Padding",
                value: $model.style.padding,
                range: 0...0.18,
                format: .percent()
            )
            InspectorSlider(
                "Corners",
                value: $model.style.cornerRadius,
                range: 0...0.08,
                format: .percent()
            )
            InspectorSlider(
                "Shadow",
                value: $model.style.shadow,
                range: 0...1,
                format: .percent()
            )
        }
    }

    // MARK: Zoom

    private var zoomControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            let pressCount = model.recordedPressTimes.count
            Text(pressCount == 1 ? "1 recorded click" : "\(pressCount) recorded clicks")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                inspectorAction("Auto Zoom", systemImage: "pointer.arrow.rays") {
                    model.resynthesizeZoomCues()
                }
                .disabled(pressCount == 0)

                inspectorAction("Add Zoom", systemImage: "plus.magnifyingglass") {
                    model.addZoomCue(at: model.currentTime)
                }
            }

            if model.selectedCue == nil {
                Text(model.zoomCues.isEmpty
                    ? "Click Auto Zoom to turn recorded clicks into smooth camera moves."
                    : "Select a zoom block on the timeline to adjust it.")
                    .font(.inspectorLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!model.zoomEnabled)
        .opacity(model.zoomEnabled ? 1 : 0.48)
    }

    private func selectedZoomControls(for selected: ZoomCue) -> some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Camera Focus")

                InspectorSegmented(
                    options: ZoomAnchorMode.allCases,
                    isSelected: { $0 == selected.anchorMode },
                    onTap: { anchorMode in
                        var updated = selected
                        updated.anchorMode = anchorMode
                        if anchorMode == .pinnedAnchor,
                           let pointer = model.pointerLocation(at: model.currentTime) {
                            updated.pinnedPoint = pointer
                        }
                        model.updateZoomCue(updated)
                    },
                    label: { Text($0.inspectorTitle).font(.inspectorLabel) }
                )
            }

            InspectorSlider(
                "Zoom Amount",
                value: Binding(
                    get: { CGFloat(selected.zoom) },
                    set: { newValue in
                        var updated = selected
                        updated.zoom = Double(newValue)
                        model.updateZoomCue(updated)
                    }
                ),
                range: 1.1...3,
                format: .magnification(fractionDigits: 1)
            )

            if selected.anchorMode == .pinnedAnchor {
                VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                    HStack(spacing: 8) {
                        InspectorGroupLabel("Target position")
                        Spacer(minLength: 0)
                        Text(zoomTargetPositionText(selected.pinnedPoint))
                            .font(.inspectorNumeric)
                            .foregroundStyle(.tertiary)
                    }

                    RecordingZoomFocusPad(
                        position: Binding(
                            get: { selected.pinnedPoint },
                            set: { target in
                                var updated = selected
                                updated.pinnedPoint = target
                                model.updateZoomCue(updated)
                            }
                        ),
                        magnification: selected.zoom
                    )
                }

                inspectorAction("Set Target to Pointer", systemImage: "scope") {
                    guard let pointer = model.pointerLocation(at: model.currentTime) else { return }
                    var updated = selected
                    updated.pinnedPoint = pointer
                    model.updateZoomCue(updated)
                }
            } else {
                InspectorSlider(
                    "Edge in Frame",
                    value: Binding(
                        get: { CGFloat(selected.boundsBias) },
                        set: { boundsBias in
                            var updated = selected
                            updated.boundsBias = Double(boundsBias)
                            model.updateZoomCue(updated)
                        }
                    ),
                    range: 0...1,
                    format: .percent()
                )
            }

            inspectorAction(
                "Remove Zoom",
                systemImage: "trash",
                role: .destructive
            ) {
                model.removeZoomCue(id: selected.id)
            }
            .help("Remove the selected zoom")
        }
        .disabled(!model.zoomEnabled)
        .opacity(model.zoomEnabled ? 1 : 0.48)
    }

    private func zoomTargetPositionText(_ position: CGPoint) -> String {
        let x = Int((position.x * 100).rounded())
        let y = Int((position.y * 100).rounded())
        return "\(x), \(y)"
    }

    // MARK: Selected clip

    private func selectedClipControls(for clip: RecordingClipSegment) -> some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSlider(
                "Speed",
                value: Binding(
                    get: { CGFloat(clip.speed) },
                    set: { model.setClipSpeed(Double($0.rounded()), forClipID: clip.id) }
                ),
                range: CGFloat(RecordingClipSegment.minimumSpeed)...CGFloat(RecordingClipSegment.maximumSpeed),
                format: .magnification(fractionDigits: 0)
            )

            if clip.speed != 1 {
                Text("Plays this clip \(Int(clip.speed))× faster. Audio speeds up with it.")
                    .font(.inspectorLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cursor

    private var cursorControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSlider(
                "Size",
                value: $model.style.cursorScale,
                range: 1...4,
                format: .magnification(fractionDigits: 1)
            )

            if model.canShowPressEffects {
                HStack(spacing: 8) {
                    Text("Click highlights")
                        .font(.inspectorLabel)
                        .foregroundStyle(.primary.opacity(0.82))

                    Spacer(minLength: 8)

                    Toggle("Click highlights", isOn: $model.showsClickEffects)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Keystrokes

    private var keystrokeControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Top")
                keystrokePlacementRow([.topLeft, .topCenter, .topRight])
            }
            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Bottom")
                keystrokePlacementRow([.bottomLeft, .bottomCenter, .bottomRight])
            }

            Text("Shortcuts you pressed while recording appear as a caption here.")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!model.showsKeystrokes)
        .opacity(model.showsKeystrokes ? 1 : 0.48)
    }

    private func keystrokePlacementRow(
        _ options: [RecordingKeystrokePlacement]
    ) -> some View {
        InspectorSegmented(
            options: options,
            isSelected: { $0 == model.keystrokePlacement },
            onTap: { model.keystrokePlacement = $0 },
            label: { Text($0.title).font(.inspectorLabel) }
        )
    }

    // MARK: Transcription

    @ViewBuilder
    private var transcriptionControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            switch model.transcriptionState {
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing narration…")
                        .font(.inspectorLabel)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message)
                    .font(.inspectorLabel)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                inspectorAction("Try Again", systemImage: "waveform") {
                    model.transcribe()
                }
            case .idle:
                if model.hasSubtitles {
                    subtitleEditor
                } else {
                    inspectorAction("Transcribe Narration", systemImage: "waveform") {
                        model.transcribe()
                    }

                    Text("Turns your microphone narration into subtitles, transcribed on this Mac.")
                        .font(.inspectorLabel)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var subtitleEditor: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSegmented(
                options: StudioTranscriptTab.allCases,
                isSelected: { $0 == transcriptTab },
                onTap: { transcriptTab = $0 },
                label: { tab in
                    Text(tab.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
            )

            switch transcriptTab {
            case .captions:
                captionControls
            case .edit:
                transcriptEditControls
            }
        }
    }

    private var captionControls: some View {
        let verticalRange = SubtitleBarStyle.verticalRange
        let fontScaleRange = SubtitleBarStyle.fontScaleRange
        return VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSlider(
                "Position",
                value: Binding(
                    get: { CGFloat(model.subtitleStyle.verticalPosition) },
                    set: { model.subtitleStyle.verticalPosition = Double($0) }
                ),
                range: CGFloat(verticalRange.lowerBound)...CGFloat(verticalRange.upperBound),
                format: .percent()
            )

            InspectorSlider(
                "Text Size",
                value: Binding(
                    get: { CGFloat(model.subtitleStyle.fontScale) },
                    set: { model.subtitleStyle.fontScale = Double($0) }
                ),
                range: CGFloat(fontScaleRange.lowerBound)...CGFloat(fontScaleRange.upperBound),
                format: .magnification(fractionDigits: 1)
            )

            if model.hasTranscriptWords {
                HStack(spacing: 8) {
                    Text("Highlight spoken word")
                        .font(.inspectorLabel)
                        .foregroundStyle(.primary.opacity(0.82))

                    Spacer(minLength: 8)

                    Toggle(
                        "Highlight spoken word",
                        isOn: $model.subtitleStyle.highlightsSpokenWord
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            subtitleList

            Text("Click a timestamp to jump there. Edit any line to fix the transcription.")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!model.showsSubtitles)
        .opacity(model.showsSubtitles ? 1 : 0.48)
    }

    @ViewBuilder
    private var transcriptEditControls: some View {
        if model.hasTranscriptWords {
            StudioTranscriptEditPanel(model: model)

            if model.removableFillerWordCount > 0 {
                inspectorAction(
                    "Remove Filler Words (\(model.removableFillerWordCount))",
                    systemImage: "scissors"
                ) {
                    model.removeFillerWords()
                }
            }

            if model.trimmableSilenceCount > 0 {
                inspectorAction(
                    "Trim Silences (\(model.trimmableSilenceCount))",
                    systemImage: "waveform.badge.minus"
                ) {
                    model.trimNarrationSilences()
                }
            }

            Text("Click a word to jump there. Shift-click to select a passage, then cut it to remove that part of the video.")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if model.canTranscribe {
                inspectorAction("Transcribe Again to Edit", systemImage: "waveform") {
                    model.transcribe()
                }
            }
            Text("This transcription predates editing by text. Transcribe again to cut the video from its transcript.")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitleList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    let cues = model.subtitleCues
                    ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                        StudioSubtitleRow(
                            model: model,
                            cue: cue,
                            isActive: model.activeSubtitleCue?.id == cue.id
                        )
                        .id(cue.id)

                        if index < cues.count - 1 {
                            Divider()
                                .padding(.leading, 10)
                                .opacity(0.6)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: model.activeSubtitleCue?.id) { _, activeID in
                // Follow playback through the list, but never yank the list
                // around while the user is scrubbing or editing.
                guard let activeID, model.isPlaying else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
        }
    }

    // MARK: Camera

    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            InspectorSlider(
                "Size",
                value: $model.style.camera.size,
                range: 0.12...0.45,
                format: .percent()
            )
            InspectorSlider(
                "Rounding",
                value: $model.style.camera.roundness,
                range: 0.05...0.5,
                format: .percent()
            )

            Text("Drag the camera directly on the canvas to place it.")
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!model.style.camera.isVisible)
        .opacity(model.style.camera.isVisible ? 1 : 0.48)
    }

    // MARK: Audio

    /// The round trip around tools that clean up speech but offer no API:
    /// write the cut's soundtrack out, run it through the tool, bring the
    /// result back in as the project's audio. Two buttons and a file chip -
    /// the explaining is left to tooltips.
    private var audioControls: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            // A silent recording has nothing to send out, but it can still
            // be given a soundtrack - so only the export half is withheld.
            if model.hasAudio {
                InspectorSegmented(
                    options: RecordingAudioFormat.allCases,
                    isSelected: { $0 == model.audioExportFormat },
                    onTap: { model.audioExportFormat = $0 },
                    label: { Text($0.title).font(.inspectorLabel) }
                )
            }

            HStack(spacing: 6) {
                if model.hasAudio {
                    audioExportButton
                }

                inspectorAction(
                    model.hasRecordedAudio ? "Replace" : "Add",
                    systemImage: "waveform.badge.plus"
                ) {
                    pickReplacementAudio()
                }
                .help(
                    model.hasRecordedAudio
                        ? "Swap in an audio file, aligned to the start of the edited timeline"
                        : "Lay an audio file over this silent recording"
                )
            }

            if let replacement = model.replacementAudio {
                replacementChip(for: replacement)
            }

            if let message = model.replacementAudioError {
                Text(message)
                    .font(.inspectorLabel)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One button carrying the whole export state, so progress and results
    /// never cost the section an extra row.
    @ViewBuilder
    private var audioExportButton: some View {
        switch model.audioExportState {
        case .idle:
            inspectorAction("Export", systemImage: "arrow.down.circle") {
                model.exportAudio()
            }
            .help("Export just the soundtrack of the current cut")
        case .exporting(let progress):
            audioExportChrome(help: "Cancel") {
                model.cancelAudioExport()
            } label: {
                StudioProgressRing(progress: progress, size: 12)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.inspectorValue.monospacedDigit())
                    .contentTransition(.numericText())
            }
        case .finished(let url):
            audioExportChrome(help: "Reveal \(url.lastPathComponent) in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Text("Reveal")
                    .font(.inspectorValue)
            }
        case .failed(let message):
            audioExportChrome(help: message) {
                model.exportAudio()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                Text("Retry")
                    .font(.inspectorValue)
            }
        }
    }

    /// Matches `inspectorAction`'s chrome for the export button's non-idle
    /// states, which carry richer content than a symbol and a title.
    private func audioExportChrome<Label: View>(
        help: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .inspectorField(height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func replacementChip(for replacement: RecordingReplacementAudio) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            Text(replacement.displayName)
                .font(.inspectorValue)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let drift = model.replacementAudioDrift {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .help(
                        drift > 0
                            ? "Runs \(Self.spanText(drift)) longer than the cut - the tail is dropped"
                            : "Runs \(Self.spanText(-drift)) shorter than the cut - the end plays silent"
                    )
            }

            Text(Self.clockText(replacement.duration))
                .font(.inspectorLabel.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .inspectorField(height: 30)
        .help(replacement.displayName)
    }

    private func pickReplacementAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = RecordingAudioFormat.importContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Replacement Audio"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.replaceAudio(with: url)
        }
    }

    private static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Short spans read better in seconds than as 0:00 timecode.
    private static func spanText(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        return value < 60 ? String(format: "%.1fs", value) : clockText(value)
    }

    private var usesDefaultLayout: Bool {
        abs(model.style.padding - 0.06) < 0.0001
            && abs(model.style.cornerRadius - 0.02) < 0.0001
            && abs(model.style.shadow - 0.45) < 0.0001
    }

    private var sidebarBackground: Color {
        InspectorControlPalette.panelBackground(for: colorScheme)
    }

    private func expansionBinding(for section: StudioInspectorSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private func inspectorAction(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.inspectorValue)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .inspectorField(height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red.opacity(0.88) : Color.primary)
    }
}
