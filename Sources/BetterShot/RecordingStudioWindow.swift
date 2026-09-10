//
//  RecordingStudioWindow.swift
//  BetterShot
//
//  The recording studio: a Screen Studio-style editor for screen recordings.
//  A left inspector, composited live preview, and full-width timeline share
//  the annotation editor's classic macOS chrome.
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

struct RecordingStudioContent: View {
    @Bindable var model: RecordingStudioModel
    @State private var isInspectorPresented = true
    @State private var closeGuard = EditorCloseGuard()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isInspectorPresented {
                    StudioInspector(model: model)
                        .frame(width: 360)
                    Divider()
                }
                Group {
                    if let loadError = model.loadError {
                        ContentUnavailableView(
                            "Couldn't open recording", systemImage: "exclamationmark.triangle",
                            description: Text(loadError)
                        )
                    } else {
                        StudioCanvas(model: model)
                            .background(AnnotationEditorWorkspaceBackground())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            }

            if model.loadError == nil {
                StudioTimelineEditor(model: model)
            }
        }
        .background(EditorChrome.workspace)
        .background(TransferToast(status: transferStatus, onCancel: cancelTransfer,
                                  onRetry: retryTransfer, onDismiss: dismissTransfer))
        .scrollIndicators(.hidden)
        .tint(EditorChrome.accent)
        .accentColor(EditorChrome.accent)
        .frame(minWidth: 1100, minHeight: 720)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .help(ShortcutService.shared.help("Undo", for: .videoUndo))

                Button {
                    model.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .help(ShortcutService.shared.help("Redo", for: .videoRedo))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.isCroppingVideo {
                    cropActions
                } else if model.isEditingMasks {
                    maskActions
                } else {
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
                        Image(systemName: "sidebar.left")
                    }
                    .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
                    .accessibilityLabel("Toggle video inspector")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .editorFullScreenByDefault()
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
        .background(EditorShortcutHandler(scope: .video, perform: performShortcut))
        .onAppear {
            AppActivationPolicy.enter(hidePreview: true)
        }
        .onDisappear {
            closeGuard.detach()
            AppActivationPolicy.leave(restorePreview: true)
        }
    }

    private func performShortcut(_ action: ShortcutService.Action) -> Bool {
        guard model.isLoaded else { return false }
        switch action {
        case .videoCrop: model.beginVideoCrop()
        case .videoBlur: model.toggleMaskTool(.blur)
        case .videoPixelate: model.toggleMaskTool(.pixelate)
        case .videoDelete:
            if model.isEditingMasks { model.deleteSelectedMask() }
            else if !model.isCroppingVideo {
                if let id = model.selectedCueID { model.removeZoomCue(id: id) }
                else { model.deleteSelectedClip() }
            }
        default:
            guard !model.isCroppingVideo, !model.isEditingMasks else { return true }
            switch action {
            case .videoSave: if model.isProject { model.saveProject() }
            case .videoUndo: model.undo()
            case .videoRedo: model.redo()
            case .videoInspector: isInspectorPresented.toggle()
            default: return false
            }
        }
        return true
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
        .buttonStyle(.bordered)
    }

    private var cropAspectBinding: Binding<CropAspectRatio> {
        Binding(
            get: { model.cropAspect },
            set: { newValue in
                withAnimation(.snappy(duration: 0.18)) { model.setVideoCropAspect(newValue) }
            }
        )
    }

    @ViewBuilder
    private var maskActions: some View {
        Button {
            model.addMask()
        } label: {
            Label("Add Mask", systemImage: "plus.rectangle")
        }
        .help("Add another mask")

        Picker("Effect", selection: maskEffectBinding) {
            Text("Blur").tag(RecordingMaskSegment.Effect.blur)
            Text("Pixelate").tag(RecordingMaskSegment.Effect.pixelate)
        }
        .pickerStyle(.segmented)
        .disabled(model.selectedMask == nil)

        Picker("Area", selection: Binding(
            get: { model.selectedMask.map { !RecordingVideoCrop.isUnit($0.rect) } ?? true },
            set: { model.setSelectedMaskCropOnly($0) }
        )) {
            Text("Crop Only").tag(true)
            Text("Full Frame").tag(false)
        }
        .pickerStyle(.segmented)
        .disabled(model.selectedMask == nil)
        .help("Crop Only limits the effect to the rectangle you draw")

        InspectorSlider("Strength", value: maskAmountBinding,
            range: CGFloat(RecordingMaskSegment.minimumAmount)...CGFloat(RecordingMaskSegment.maximumAmount),
            format: .integer)
        .frame(width: 190)
        .disabled(model.selectedMask == nil)
        .help("Effect strength")

        Button {
            model.deleteSelectedMask()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(model.selectedMask == nil)
        .help("Delete the selected mask")

        Button {
            withAnimation(.snappy(duration: 0.22)) { model.endMaskEditing() }
        } label: {
            Text("Done").padding(.horizontal, 8)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.bordered)
    }

    private var maskEffectBinding: Binding<RecordingMaskSegment.Effect> {
        Binding(
            get: { model.selectedMask?.effect ?? .blur },
            set: { model.setSelectedMaskEffect($0) }
        )
    }

    private var maskAmountBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(model.selectedMask?.amount ?? RecordingMaskSegment.defaultAmount) },
            set: { model.setSelectedMaskAmount(Double($0)) }
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
        .disabled(!model.hasUnsavedChanges)
        .help(ShortcutService.shared.help("Save your edits in BetterShot", for: .videoSave))
    }

    @ViewBuilder
    private var shareStatus: some View {
        CloudUploadButton(suggestedTitle: shareSuggestedTitle, onUpload: model.shareToCloud, shortcutAction: .videoShare) {
            Label("Share", systemImage: "icloud.and.arrow.up")
                .labelStyle(.titleAndIcon)
        }
        .disabled(!model.isLoaded || model.exportState.isExporting || model.shareState.isBusy)
        .help("Upload and copy a share link")
    }

    @ViewBuilder
    private var exportStatus: some View {
        RecordingExportButton(
            currentSettings: model.exportSettings,
            onExport: model.export(settings:), shortcutAction: .videoExport
        ) {
            Label("Export", systemImage: "arrow.down.circle")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
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

                    if model.isEditingMasks {
                        let imageFrame = layout.frameRect(for: .identity)
                        ForEach(model.maskSegments) { segment in
                            if segment.id != model.selectedMaskID,
                               segment.isActive(at: model.displayTime) {
                                let rect = Self.maskViewRect(segment.rect, in: imageFrame)
                                Rectangle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selectMask(id: segment.id) }
                            }
                        }
                        if let selected = model.selectedMask {
                            CropAdjustmentOverlay(
                                imageFrame: imageFrame,
                                coordinateSpaceName: StudioCanvasCoordinateSpace.name,
                                cropRect: selected.rect.standardized,
                                showsEdgeHandles: true,
                                showsChrome: false,
                                onResize: { handle, point in
                                    model.updateSelectedMask(handle: handle, toNormalized: point)
                                },
                                onMove: { start, delta in
                                    model.moveSelectedMask(from: start, byNormalized: delta)
                                }
                            )
                        }
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

    private static func maskViewRect(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + rect.minX * frame.width,
            y: frame.minY + rect.minY * frame.height,
            width: rect.width * frame.width,
            height: rect.height * frame.height
        )
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
                            .opacity(press.impactEnabled ? effect.impactOpacity : 0)
                    )
                    .frame(width: effect.impactRadius * 2, height: effect.impactRadius * 2)
                    .position(x: pressTip.x, y: pressTip.y)
                Circle()
                    .stroke(
                        Color(red: accent.red, green: accent.green, blue: accent.blue)
                            .opacity(press.rippleEnabled ? effect.rippleOpacity : 0),
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
                    .interpolation(.high)
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
                ScrollView(.vertical, showsIndicators: false) {
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
            if let preset = gradient.preset {
                GradientBackgroundView(preset: preset)
            } else {
            LinearGradient(
                colors: gradient.colors.map(\.color),
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )
            }
        case .customWallpaper(let wallpaper):
            AnnotationCustomWallpaperPreview(wallpaper: wallpaper, maxPixelSize: 2048)
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

    @State private var viewport = RecordingTimelineViewport()
    @State private var isSplitting = false
    @State private var viewportWidth: CGFloat = 1
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    private var scrollX: CGFloat { CGFloat(viewport.position) * scale.pointsPerSecond }
    private var scale: StudioTimelineScale {
        StudioTimelineScale(viewportWidth: viewportWidth, duration: model.duration,
                            visibleSeconds: viewport.visibleSeconds)
    }

    var body: some View {
        VStack(spacing: StudioTimelineMetrics.rowSpacing) {
            transport
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            lanes
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(EditorShortcutHandler(scope: .video, perform: performShortcut))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private func performShortcut(_ action: ShortcutService.Action) -> Bool {
        guard model.isLoaded else { return false }
        guard !model.isCroppingVideo, !model.isEditingMasks else { return false }
        switch action {
        case .videoPlay: model.togglePlayback()
        case .videoStart: model.pause(); model.seek(to: 0)
        case .videoEnd: model.pause(); model.seek(to: model.duration)
        case .videoSplitTool: isSplitting.toggle()
        case .videoCut:
            if NSApp.keyWindow?.firstResponder is RecordingClipTimelineControl { return false }
            model.splitClip(at: model.timelineHoverTime ?? model.currentTime)
        case .videoZoomIn: updateZoom(viewport.visibleSeconds / 1.6, origin: buttonZoomAnchor)
        case .videoZoomOut: updateZoom(viewport.visibleSeconds * 1.6, origin: buttonZoomAnchor)
        case .videoFit: viewport.fit(duration: model.duration); syncScroll()
        case .videoAddZoom: addZoomAtPlayhead()
        default: return false
        }
        return true
    }

    private func addZoomAtPlayhead() {
        if let range = RecordingTimelineViewport.newZoomRange(at: model.currentTime,
            secondsPerPoint: scale.secondsPerPoint, duration: model.duration,
            occupied: model.zoomTimelineBlocks.map { $0.editorStart...$0.editorEnd }) {
            model.addZoomCue(fromEditorTime: range.lowerBound, toEditorTime: range.upperBound)
        }
    }

    private var cutMarkers: [RecordingClipTimeline.CutMarker] {
        model.clipTimeline.cutMarkers(sourceDuration: model.sourceDuration)
    }

    private var cutMarkerLane: some View {
        GeometryReader { proxy in
            ForEach(cutMarkers, id: \.sourceStart) { marker in
                let x = scale.x(for: marker.editorTime) - scrollX
                let width: CGFloat = marker.removedDuration > 0 ? 64 : 28
                if x >= 0, x <= proxy.size.width {
                    StudioTimelineCutBadge(marker: marker, sourceURL: model.screenURL) {
                        model.pause()
                        model.seek(to: marker.editorTime)
                    }
                    .frame(width: width)
                    .position(x: min(max(x, width / 2), max(width / 2, proxy.size.width - width / 2)), y: 14)
                }
            }
        }
        .frame(height: StudioTimelineMetrics.cutLaneHeight)
    }

    private var lanes: some View {
        GeometryReader { proxy in
            // The proxy width leads the stored one by a frame, so lay the
            // lanes out from it and keep the state copy for the controls.
            let scale = StudioTimelineScale(
                viewportWidth: max(proxy.size.width, 1),
                duration: model.duration,
                visibleSeconds: viewport.visibleSeconds
            )

            VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                StudioTimelineMinimap(
                    viewport: viewport, duration: model.duration,
                    onPosition: { setPosition($0) },
                    onZoom: { updateZoom($0, origin: $1) }
                )
                VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                    Color.clear
                        .frame(height: StudioTimelineMetrics.playheadLaneHeight)

                    StudioTimelineRuler(
                        duration: model.duration,
                        pointsPerSecond: scale.pointsPerSecond,
                        scrollX: scrollX
                    )
                    .frame(height: StudioTimelineMetrics.rulerHeight)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        model.pause()
                        model.seek(to: scale.time(forX: value.location.x + scrollX))
                    })
                    .help("Click or drag to scrub the recording")

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
            }
            .onChange(of: proxy.size.width, initial: true) { _, width in
                viewportWidth = max(width, 1)
                viewport.updateZoom(viewport.visibleSeconds, origin: viewport.position,
                                    duration: model.duration, viewportWidth: Double(viewportWidth))
                syncScroll()
            }
        }
        .background(RecordingTimelineInput(
            onScroll: { delta, isZoom, x in
                if isZoom {
                    let origin = model.isPlaying ? model.currentTime : scale.time(forX: x + scrollX)
                    updateZoom(viewport.visibleSeconds + delta * sqrt(viewport.visibleSeconds) / 30, origin: origin)
                } else {
                    setPosition(viewport.position + delta * scale.secondsPerPoint)
                }
            },
            onMagnify: { amount, x in
                updateZoom(viewport.visibleSeconds / max(0.01, 1 + amount),
                           origin: scale.time(forX: x + scrollX))
            }
        ))
        .frame(height: StudioTimelineMetrics.lanesHeight(showsMaskLane: model.showsMaskLane))
        .onChange(of: model.duration, initial: true) { old, duration in
            if old == 0 || old == duration { viewport.fit(duration: duration) }
            else {
                viewport.updateZoom(viewport.visibleSeconds, origin: viewport.position,
                                    duration: duration, viewportWidth: Double(viewportWidth))
            }
            syncScroll()
        }
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
                StudioZoomLaneBackground()
                    .frame(height: StudioTimelineMetrics.zoomLaneHeight)
                Color.clear
                    .frame(height: StudioTimelineMetrics.clipLaneHeight)
                Color.clear
                    .frame(height: StudioTimelineMetrics.cutLaneHeight)
                if model.showsMaskLane {
                    StudioZoomLaneBackground()
                        .frame(height: StudioTimelineMetrics.maskLaneHeight)
                }
                Color.clear
                    .frame(height: StudioTimelineMetrics.scrollerGutter)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: StudioTimelineMetrics.rowSpacing) {
                    StudioZoomLane(
                        model: model,
                        scale: scale,
                        visibleRange: scale.visibleRange(scrollX: scrollX)
                    )
                    .frame(
                        width: scale.contentWidth,
                        height: StudioTimelineMetrics.zoomLaneHeight
                    )

                    clipLane
                        .frame(
                            width: scale.x(for: model.duration),
                            height: StudioTimelineMetrics.clipLaneHeight
                        )
                        .frame(width: scale.contentWidth, alignment: .leading)
                    Color.clear
                        .frame(height: StudioTimelineMetrics.cutLaneHeight)

                    if model.showsMaskLane {
                        StudioMaskLane(
                            model: model,
                            scale: scale,
                            visibleRange: scale.visibleRange(scrollX: scrollX)
                        )
                        .frame(
                            width: scale.contentWidth,
                            height: StudioTimelineMetrics.maskLaneHeight
                        )
                    }

                    Color.clear
                        .frame(height: StudioTimelineMetrics.scrollerGutter)
                }
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                if abs(offset - scrollX) > 0.01 {
                    viewport.setPosition(Double(offset) * scale.secondsPerPoint, duration: model.duration)
                }
            }
        }
        .frame(height: StudioTimelineMetrics.scrollingLanesHeight(showsMaskLane: model.showsMaskLane))
        .mask(edgeFadeMask(scale: scale))
        .overlay(alignment: .top) {
            cutMarkerLane
                .padding(.top, StudioTimelineMetrics.zoomLaneHeight + StudioTimelineMetrics.clipLaneHeight
                         + StudioTimelineMetrics.rowSpacing * 2)
        }
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
                updateZoom(viewport.visibleSeconds / factor, origin: anchorTime)
            },
            isSplitting: isSplitting,
            onToggleSplit: { isSplitting.toggle() }
        )
    }

    // Cap stores the left edge and visible span in seconds. All inputs use this transform.
    private func updateZoom(_ seconds: Double, origin: Double) {
        model.timelineThumbnails.deferSampling()
        viewport.updateZoom(seconds, origin: origin, duration: model.duration, viewportWidth: Double(viewportWidth))
        syncScroll()
    }

    private func setPosition(_ seconds: Double) {
        viewport.setPosition(seconds, duration: model.duration)
        syncScroll()
    }

    private func syncScroll() { scrollPosition.scrollTo(x: scrollX) }

    private func followPlayhead(to time: TimeInterval) {
        guard model.isPlaying else { return }
        if time < viewport.position || time > viewport.position + viewport.visibleSeconds {
            setPosition(time)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            timelineButton(ShortcutService.shared.help("Zoom Out", for: .videoZoomOut), systemImage: "minus.magnifyingglass") {
                updateZoom(viewport.visibleSeconds * 1.6, origin: buttonZoomAnchor)
            }
            .disabled(viewport.visibleSeconds >= RecordingTimelineViewport.zoomOutLimit(duration: model.duration))

            InspectorSlider("Zoom", value: Binding(
                get: { CGFloat(viewport.zoomProgress(duration: model.duration, viewportWidth: Double(viewportWidth))) },
                set: {
                    model.timelineThumbnails.deferSampling()
                    viewport.updateZoomProgress(Double($0), origin: buttonZoomAnchor, duration: model.duration,
                                                viewportWidth: Double(viewportWidth))
                    syncScroll()
                }
            ), range: 0...1, format: .percent())
            .frame(width: 170)
            .disabled(model.duration <= 0)
            .accessibilityLabel("Timeline zoom")
            .accessibilityValue("\(viewport.visibleSeconds.formatted(.number.precision(.fractionLength(1)))) seconds visible")
            .help("\(viewport.visibleSeconds.formatted(.number.precision(.fractionLength(1)))) seconds visible — pinch or ⌘-scroll to zoom")

            timelineButton(ShortcutService.shared.help("Zoom In", for: .videoZoomIn), systemImage: "plus.magnifyingglass") {
                updateZoom(viewport.visibleSeconds / 1.6, origin: buttonZoomAnchor)
            }
            .disabled(model.duration <= 0 || viewport.visibleSeconds <=
                      RecordingTimelineViewport.zoomInLimit(duration: model.duration, viewportWidth: Double(viewportWidth)))

            Button("Fit") {
                viewport.fit(duration: model.duration)
                syncScroll()
            }
            .buttonStyle(EditorButtonStyle())
            .help(ShortcutService.shared.help("Fit timeline", for: .videoFit))
        }
    }

    private var buttonZoomAnchor: Double {
        let end = viewport.position + viewport.visibleSeconds
        return (viewport.position...end).contains(model.currentTime)
            ? model.currentTime : viewport.position + viewport.visibleSeconds / 2
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isSplitting) {
                Label("Split", systemImage: "scissors").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .buttonStyle(EditorButtonStyle(selected: isSplitting))
            .help(ShortcutService.shared.help("Split tool — click again to select or trim clips", for: .videoSplitTool))
            .accessibilityLabel("Split tool")
            Divider().frame(height: 24)
            Text("\(studioTimecode(model.displayTime)) / \(studioTimecode(model.duration))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
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
                .help(model.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .disabled(!model.isLoaded)

                timelineButton("Skip to End", systemImage: "forward.end.fill") {
                    model.pause()
                    model.seek(to: model.duration)
                }
            }

            Spacer(minLength: 12)
            zoomControls
            Menu {
                Button("Delete Selection") {
                    deleteSelection()
                }
                .disabled(!canDeleteSelection)

                Divider()

                Button("Undo") {
                    model.undo()
                }
                .disabled(!model.canUndo)

                Button("Redo") {
                    model.redo()
                }
                .disabled(!model.canRedo)

                Button("Reset Clips") {
                    model.resetClips()
                }
                .disabled(!model.hasClipEdits)

                Button {
                    addZoomAtPlayhead()
                } label: {
                    Label("Add Zoom", systemImage: "plus")
                }
                .buttonStyle(EditorButtonStyle())
                .help("Add a zoom segment at the playhead")
                .disabled(RecordingTimelineViewport.newZoomRange(at: model.currentTime,
                    secondsPerPoint: scale.secondsPerPoint, duration: model.duration,
                    occupied: model.zoomTimelineBlocks.map { $0.editorStart...$0.editorEnd }) == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Timeline actions")
        }
        .frame(height: 36)
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
        .accessibilityLabel(help)
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

private struct StudioTimelineCutBadge: View {
    let marker: RecordingClipTimeline.CutMarker
    let sourceURL: URL
    let onSeek: () -> Void
    @State private var showsPreview = false

    private var durationLabel: String {
        marker.removedDuration < 0.1 ? "<0.1s"
            : "\(marker.removedDuration.formatted(.number.precision(.fractionLength(0...1))))s"
    }

    var body: some View {
        Button {
            onSeek()
            showsPreview = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scissors")
                if marker.removedDuration > 0 {
                    Text(durationLabel).monospacedDigit()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.12))
                    .frame(width: 6, height: 6).rotationEffect(.degrees(45)).offset(y: -3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(EditorChrome.border, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(showsPreview ? .primary : .secondary)
        .accessibilityLabel(marker.removedDuration > 0 ? "Removed \(durationLabel)" : "Split")
        .accessibilityHint("Show cut preview and go to this cut")
        .onHover { showsPreview = $0 }
        .popover(isPresented: $showsPreview, arrowEdge: .top) {
            StudioTimelineCutPreview(marker: marker, sourceURL: sourceURL)
        }
    }
}

struct StudioTimelineCutPreview: View {
    let marker: RecordingClipTimeline.CutMarker
    let sourceURL: URL
    @State private var preview: CGImage?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(marker.removedDuration > 0 ? "Removed footage" : "Split point").font(.headline)
            Group {
                if let preview {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit()
                } else if failed {
                    Text("Preview unavailable").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 240, height: 135)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Original: \(marker.sourceStart.formatted(.number.precision(.fractionLength(0...2))))s"
                 + (marker.removedDuration > 0 ? "–\(marker.sourceEnd.formatted(.number.precision(.fractionLength(0...2))))s" : ""))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12)
        .task(id: marker) {
            preview = nil
            failed = false
            do {
                let frame = try await Self.frame(sourceURL: sourceURL, marker: marker)
                try Task.checkCancellation()
                preview = frame
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    static func frame(sourceURL: URL, marker: RecordingClipTimeline.CutMarker) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }
        return try await generator.image(at: CMTime(
            seconds: marker.sourceStart + marker.removedDuration / 2, preferredTimescale: 600
        )).image
    }
}

private enum StudioTimelineMetrics {
    static let rowSpacing: CGFloat = 8
    static let playheadLaneHeight: CGFloat = 14
    static let rulerHeight: CGFloat = 16
    static let clipLaneHeight: CGFloat = 52
    static let cutLaneHeight: CGFloat = 28
    static let zoomLaneHeight: CGFloat = 36
    static let minimapHeight: CGFloat = 12
    /// Room under the lanes for the horizontal scroller, so it never sits on
    /// top of a zoom block.
    static let scrollerGutter: CGFloat = 8
    /// Width of the fade masking scrolled-out lane content at each edge.
    static let edgeFadeWidth: CGFloat = 32

    static let maskLaneHeight = zoomLaneHeight

    static func scrollingLanesHeight(showsMaskLane: Bool) -> CGFloat {
        clipLaneHeight + zoomLaneHeight + cutLaneHeight + scrollerGutter + rowSpacing * 3
            + (showsMaskLane ? maskLaneHeight + rowSpacing : 0)
    }

    static func lanesHeight(showsMaskLane: Bool) -> CGFloat {
        playheadLaneHeight + rulerHeight
            + scrollingLanesHeight(showsMaskLane: showsMaskLane)
            + minimapHeight + rowSpacing * 3
    }
}

/// Cap's Minimap: drag the viewport to pan, or either edge to change its visible span.
private struct StudioTimelineMinimap: View {
    let viewport: RecordingTimelineViewport
    let duration: Double
    let onPosition: (Double) -> Void
    let onZoom: (Double, Double) -> Void
    @State private var dragBase: RecordingTimelineViewport?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let pixelsPerSecond = width / max(duration, 0.001)
            let chipWidth = min(width, max(20, viewport.visibleSeconds * pixelsPerSecond))
            let travel = max(width - chipWidth, 1)
            let chipX = viewport.position / max(duration - viewport.visibleSeconds, 0.001) * travel
            if duration > viewport.visibleSeconds {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            onPosition(Double(location.x / width) * duration - viewport.visibleSeconds / 2)
                        }
                    Capsule().fill(Color.primary.opacity(0.18))
                        .overlay {
                            HStack {
                                handle(leading: true, pixelsPerSecond: pixelsPerSecond)
                                Spacer(minLength: 0)
                                handle(leading: false, pixelsPerSecond: pixelsPerSecond)
                            }
                        }
                        .frame(width: chipWidth)
                        .offset(x: chipX)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if dragBase == nil { dragBase = viewport }
                                guard let base = dragBase else { return }
                                onPosition(base.position + Double(value.translation.width / travel) * (duration - base.visibleSeconds))
                            }
                            .onEnded { _ in dragBase = nil })
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timeline overview")
                .accessibilityValue("\(viewport.position.formatted()) seconds from start")
                .accessibilityAdjustableAction { direction in
                    onPosition(viewport.position + (direction == .increment ? 1 : -1) * viewport.visibleSeconds / 4)
                }
            }
        }
        .frame(height: StudioTimelineMetrics.minimapHeight)
        .help("Drag to pan. Drag either edge to zoom the timeline.")
    }

    private func handle(leading: Bool, pixelsPerSecond: Double) -> some View {
        Capsule().fill(Color.primary.opacity(0.5))
            .frame(width: 2, height: 8)
            .frame(width: 10, height: StudioTimelineMetrics.minimapHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragBase == nil { dragBase = viewport }
                    guard let base = dragBase else { return }
                    let delta = Double(value.translation.width) / pixelsPerSecond
                    onZoom(base.visibleSeconds + (leading ? -delta : delta),
                           leading ? base.position + base.visibleSeconds : base.position)
                }
                .onEnded { _ in dragBase = nil })
    }
}

/// Drawing coordinates derived from Cap's seconds-visible transform.
private struct StudioTimelineScale: Equatable {
    var viewportWidth: CGFloat
    var duration: Double
    var visibleSeconds: Double
    var pointsPerSecond: CGFloat { viewportWidth / max(visibleSeconds, 0.001) }
    var secondsPerPoint: Double { 1 / max(Double(pointsPerSecond), 0.001) }
    var contentWidth: CGFloat { max(viewportWidth, CGFloat(duration) * pointsPerSecond) }
    var isScrollable: Bool { duration > visibleSeconds }
    func x(for time: Double) -> CGFloat { CGFloat(min(max(time, 0), duration)) * pointsPerSecond }
    func time(forX x: CGFloat) -> Double { min(max(Double(x) * secondsPerPoint, 0), duration) }
    func visibleRange(scrollX: CGFloat) -> ClosedRange<Double> {
        let start = max(0, Double(scrollX) * secondsPerPoint - 2)
        return start...max(start, min(duration, Double(scrollX + viewportWidth) * secondsPerPoint + 2))
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
                // Stop at the bottom of the zoom lane; the trailing row
                // spacing and scroller gutter are empty space, and a line
                // ending mid-air there reads as a stray second playhead.
                let tail = StudioTimelineMetrics.rowSpacing
                    + StudioTimelineMetrics.scrollerGutter
                Rectangle()
                    .fill(Color(nsColor: .systemRed))
                    .frame(
                        width: Metrics.lineWidth,
                        height: max(0, proxy.size.height - tail - Metrics.crownHeight + 2)
                    )
                    .offset(x: x - Metrics.lineWidth / 2, y: Metrics.crownHeight - 2)
                    .allowsHitTesting(false)
                    .opacity(isClamped ? 0.35 : 1)

                Color.clear
                    .frame(width: Metrics.hitWidth, height: Metrics.hitHeight)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        PlayheadCrownShape()
                            .fill(Color(nsColor: .systemRed))
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

            let visibleSeconds = Double(size.width / pointsPerSecond)
            let step = [0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300, 600, 1800, 3600]
                .first { visibleSeconds / $0 <= 10 } ?? ceil(visibleSeconds / 10)
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

    private static func label(for time: Double, step: Double) -> String {
        if step < 0.1 { return String(format: "%.2fs", time) }
        return step < 1 ? studioPreciseTimecode(time) : studioTimecode(time)
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

    @State private var dragStartTime: TimeInterval?
    @State private var hoverTime: TimeInterval?
    @State private var pendingZoomRange: ClosedRange<TimeInterval>?

    private var proposedRange: ClosedRange<Double>? {
        pendingZoomRange ?? hoverTime.flatMap { newRange(at: $0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Contentless hit surface: the lane can be tens of thousands of
            // points wide, and the visible frame is drawn by the chrome behind
            // the scroll view.
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverTime = scale.time(forX: location.x)
                        if !model.isPlaying { model.hoverPreviewTime = hoverTime }
                    case .ended:
                        hoverTime = nil
                        model.hoverPreviewTime = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartTime == nil {
                            model.pause()
                            dragStartTime = scale.time(forX: value.startLocation.x)
                        }
                        guard let start = dragStartTime else { return }
                        pendingZoomRange = newRange(at: start, draggedTo: scale.time(forX: value.location.x))
                    }
                    .onEnded { _ in
                        if let range = pendingZoomRange {
                            model.addZoomCue(fromEditorTime: range.lowerBound, toEditorTime: range.upperBound)
                            model.seek(to: range.lowerBound)
                        }
                        dragStartTime = nil
                        pendingZoomRange = nil
                        hoverTime = nil
                        model.hoverPreviewTime = nil
                    })

            if let range = proposedRange {
                RoundedRectangle(cornerRadius: StudioZoomLaneMetrics.blockCornerRadius)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay { Image(systemName: "plus").foregroundStyle(Color.accentColor) }
                    .frame(width: max(2, scale.x(for: range.upperBound) - scale.x(for: range.lowerBound)),
                           height: StudioZoomLaneMetrics.blockHeight)
                    .offset(x: scale.x(for: range.lowerBound), y: StudioZoomLaneMetrics.blockInset)
                    .allowsHitTesting(false)
            } else if model.zoomTimelineBlocks.isEmpty {
                Label("Click to add a zoom · Drag to set its duration", systemImage: "plus.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: scale.viewportWidth, height: StudioTimelineMetrics.zoomLaneHeight)
                    .offset(x: scale.x(for: visibleRange.lowerBound))
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

    private func newRange(at time: Double, draggedTo end: Double? = nil) -> ClosedRange<Double>? {
        RecordingTimelineViewport.newZoomRange(at: time, draggedTo: end,
            secondsPerPoint: scale.secondsPerPoint, duration: model.duration,
            occupied: model.zoomTimelineBlocks.map { $0.editorStart...$0.editorEnd })
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
    static let blockHeight: CGFloat = 28
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
        // Keep the drawn edges aligned with the segment's actual time range.
        let width = min(
            scale.contentWidth,
            max(2, CGFloat(blockDuration) * scale.pointsPerSecond)
        )
        let x = min(
            max(scale.x(for: block.editorStart), 0),
            max(0, scale.contentWidth - width)
        )

        return AnyView(
            HStack(spacing: 0) {
                resizeHandle(edge: .leading)
                Group {
                    if width >= 50 {
                        Text("Zoom \(Int((cue.zoom * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                resizeHandle(edge: .trailing)
            }
            .frame(width: width, height: StudioZoomLaneMetrics.blockHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: StudioZoomLaneMetrics.blockCornerRadius,
                    style: .continuous
                )
                    .fill(isSelected ? EditorChrome.accent : Color(nsColor: .secondaryLabelColor).opacity(0.45))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: StudioZoomLaneMetrics.selectionRingCornerRadius,
                        style: .continuous
                    )
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        .padding(-StudioZoomLaneMetrics.selectionRingPadding)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: x, y: StudioZoomLaneMetrics.blockInset)
            .onDisappear {
                if dragBase != nil {
                    dragBase = nil
                    model.endZoomCueEdit()
                }
            }
            .onTapGesture {
                model.selectZoomCue(id: cue.id)
                model.pause()
                model.seek(to: block.editorStart + blockDuration / 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(cue.anchorMode == .pinnedAnchor ? "Manual" : "Automatic") zoom, \(cue.zoom.formatted()) times")
            .accessibilityHint("Select to edit. Drag to move; drag either edge to resize.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .help("Select to edit zoom amount and focus. Drag to move; drag edges to resize.")
            .contextMenu {
                Button("Remove Zoom", role: .destructive) {
                    model.removeZoomCue(id: cue.id)
                }
            }
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
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
                var moved = dragBase.cue
                let range = RecordingTimelineViewport.moving(
                    dragBase.editorStart...dragBase.editorEnd, by: delta,
                    within: neighborRange)
                moved.start = model.sourceTime(atEditorTime: range.lowerBound)
                moved.end = model.sourceTime(atEditorTime: range.upperBound)
                model.updateZoomCue(moved)
            }
            .onEnded { _ in
                dragBase = nil
                model.endZoomCueEdit(actionName: "Move Zoom")
            }
    }


    private var neighborRange: ClosedRange<Double> {
        let others = model.zoomTimelineBlocks.filter { $0.cue.id != block.cue.id }
        let start = others.filter { $0.editorEnd <= block.editorStart }.map(\.editorEnd).max() ?? 0
        let end = others.filter { $0.editorStart >= block.editorEnd }.map(\.editorStart).min() ?? model.duration
        return start...max(start, end)
    }

    private func fill(edge: HorizontalEdge) {
        var cue = block.cue
        let others = model.zoomTimelineBlocks.filter { $0.cue.id != cue.id }
        model.beginZoomCueEdit()
        model.selectZoomCue(id: cue.id)
        if edge == .leading {
            let time = others.filter { $0.editorEnd <= block.editorStart }.map(\.editorEnd).max() ?? 0
            cue.start = model.sourceTime(atEditorTime: time)
        } else {
            let time = others.filter { $0.editorStart >= block.editorEnd }.map(\.editorStart).min() ?? model.duration
            cue.end = model.sourceTime(atEditorTime: time)
        }
        model.updateZoomCue(cue)
        model.endZoomCueEdit(actionName: "Extend Zoom")
    }

    private func resizeHandle(edge: HorizontalEdge) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: min(14, max(1, CGFloat(block.editorEnd - block.editorStart) * scale.pointsPerSecond / 2)),
                   height: StudioZoomLaneMetrics.blockHeight)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(isSelected ? 0.9 : 0.45))
                    .frame(width: 2.5, height: 12)
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onTapGesture(count: 2) { fill(edge: edge) }
            .help("Drag to resize. Double-click to extend to the next zoom or recording edge.")
            .gesture(
                // Global coordinates - the handle itself moves while resizing,
                // so local-space translations feed back into the drag and jitter.
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
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
                        let range = RecordingTimelineViewport.resizing(
                            dragBase.editorStart...dragBase.editorEnd, leading: edge == .leading,
                            by: delta, within: neighborRange, minimumDuration: ZoomCue.minimumDuration)
                        resized.start = model.sourceTime(atEditorTime: range.lowerBound)
                        resized.end = model.sourceTime(atEditorTime: range.upperBound)
                        model.updateZoomCue(resized)
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endZoomCueEdit(actionName: "Resize Zoom")
                    }
            )
    }
}

private struct StudioMaskLane: View {
    @Bindable var model: RecordingStudioModel
    let scale: StudioTimelineScale
    let visibleRange: ClosedRange<TimeInterval>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard scale.pointsPerSecond > 0 else { return }
                    let time = scale.time(forX: location.x)
                    model.beginMaskEditing()
                    model.addMask(at: time)
                }

            ForEach(visibleSegments) { segment in
                StudioMaskBlock(model: model, segment: segment, scale: scale)
            }
        }
        .contextMenu {
            Button("Add Mask at Playhead") {
                model.beginMaskEditing()
                model.addMask(at: model.currentTime)
            }
        }
    }

    private var visibleSegments: [RecordingMaskSegment] {
        model.maskSegments.filter {
            let range = $0.editorRange(duration: model.duration)
            return range.upperBound >= visibleRange.lowerBound
                && range.lowerBound <= visibleRange.upperBound
        }
    }
}

private struct StudioMaskBlock: View {
    @Bindable var model: RecordingStudioModel
    let segment: RecordingMaskSegment
    let scale: StudioTimelineScale

    private struct DragBase {
        let start: TimeInterval
        let end: TimeInterval
    }

    @State private var dragBase: DragBase?

    private var isSelected: Bool {
        model.selectedMaskID == segment.id
    }

    private var editorRange: ClosedRange<TimeInterval> {
        segment.editorRange(duration: model.duration)
    }

    var body: some View {
        guard scale.pointsPerSecond > 0 else { return AnyView(EmptyView()) }

        let range = editorRange
        let width = min(
            scale.contentWidth,
            max(24, CGFloat(range.upperBound - range.lowerBound) * scale.pointsPerSecond)
        )
        let x = min(
            max(scale.x(for: range.lowerBound), 0),
            max(0, scale.contentWidth - width)
        )

        return AnyView(
            HStack(spacing: 0) {
                resizeHandle(edge: .leading)
                Spacer(minLength: 0)
                Label(
                    segment.effect == .blur ? "Blur" : "Pixelate",
                    systemImage: "eye.slash"
                )
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
                    .fill(Color(nsColor: .darkGray).opacity(isSelected ? 1 : 0.85))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: StudioZoomLaneMetrics.selectionRingCornerRadius,
                        style: .continuous
                    )
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        .padding(-StudioZoomLaneMetrics.selectionRingPadding)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: x, y: StudioZoomLaneMetrics.blockInset)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragBase == nil {
                            dragBase = DragBase(start: range.lowerBound, end: range.upperBound)
                            model.beginMaskRangeEdit()
                            model.selectMask(id: segment.id)
                        }
                        guard let dragBase else { return }
                        let delta = Double(value.translation.width) * scale.secondsPerPoint
                        let length = dragBase.end - dragBase.start
                        let start = min(
                            max(0, dragBase.start + delta),
                            max(0, model.duration - length)
                        )
                        model.updateMaskRange(id: segment.id, start: start, end: start + length)
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endMaskRangeEdit(actionName: "Move Mask")
                    }
            )
            .onTapGesture {
                model.beginMaskEditing()
                model.selectMask(id: segment.id)
            }
            .contextMenu {
                Button("Remove Mask", role: .destructive) {
                    model.removeMask(id: segment.id)
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
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragBase == nil {
                            let range = editorRange
                            dragBase = DragBase(start: range.lowerBound, end: range.upperBound)
                            model.beginMaskRangeEdit()
                            model.selectMask(id: segment.id)
                        }
                        guard let dragBase else { return }
                        let delta = Double(value.translation.width) * scale.secondsPerPoint
                        switch edge {
                        case .leading:
                            model.updateMaskRange(
                                id: segment.id,
                                start: min(
                                    dragBase.start + delta,
                                    dragBase.end - RecordingMaskSegment.minimumDuration
                                ),
                                end: dragBase.end
                            )
                        case .trailing:
                            model.updateMaskRange(
                                id: segment.id,
                                start: dragBase.start,
                                end: max(
                                    dragBase.start + RecordingMaskSegment.minimumDuration,
                                    dragBase.end + delta
                                )
                            )
                        }
                    }
                    .onEnded { _ in
                        dragBase = nil
                        model.endMaskRangeEdit(actionName: "Resize Mask")
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
        case .pointerAnchor: "Auto"
        case .smartAnchor: "Smart"
        case .pinnedAnchor: "Manual"
        }
    }
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
    @State private var selectedTab: StudioInspectorTab = .background
    @State private var wallpaperStore = AnnotationWallpaperStore.shared
    @State private var stylePresetStore = RecordingStudioStylePresetStore.shared
    @State private var transcriptTab: StudioTranscriptTab = .captions
    @Environment(\.colorScheme) private var colorScheme

    private let swatchColumns = [GridItem(.adaptive(minimum: 30, maximum: 44), spacing: 6)]

    var body: some View {
        HStack(spacing: 0) {
            StudioInspectorTabs(selection: $selectedTab, isAvailable: isAvailable)
            Divider()
            inspectorContent
        }
        .background(EditorChrome.workspace)
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await wallpaperStore.reload()
        }
        .onChange(of: isAvailable(selectedTab)) { _, available in
            if !available { selectedTab = .background }
        }
        .onChange(of: model.selectedCueID, initial: true) { _, cue in
            if cue != nil { selectedTab = .zoom }
        }
        .onChange(of: model.selectedClipID) { _, clip in
            if clip != nil { selectedTab = .zoom }
        }
    }

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            inspectorHeader
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if selectedTab == .background {
                        StudioEffectSection(
                            title: "Background",
                            systemImage: "photo",
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

                        StudioAmountEffect(title: "Padding", systemImage: "rectangle.inset.filled",
                            value: $model.style.padding, range: 0...0.18, defaultValue: 0.06)
                        StudioAmountEffect(title: "Rounded Corners", systemImage: "rectangle.roundedtop",
                            value: $model.style.cornerRadius, range: 0...0.08, defaultValue: 0.02)
                        StudioAmountEffect(title: "Shadow", systemImage: "square.3.layers.3d",
                            value: $model.style.shadow, range: 0...1, defaultValue: 0.45)

                    }

                    if selectedTab == .zoom {
                        // Timeline selections reveal their existing controls in the Zoom tab.
                        if let selected = model.selectedCue {
                            InspectorSection(
                                title: "Selected Zoom",
                                accessory: {
                                    Toggle(
                                        "Use this zoom",
                                        isOn: Binding(
                                            get: { selected.isEnabled },
                                            set: { isEnabled in
                                                model.beginZoomCueEdit()
                                                var updated = selected
                                                updated.isEnabled = isEnabled
                                                model.updateZoomCue(updated)
                                                model.endZoomCueEdit(actionName: "Toggle Zoom")
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
                                    .id(selected.id)
                            }
                            .studioEffectCard()
                        } else if let selectedClip = model.selectedClip {
                            InspectorSection("Selected Clip") {
                                selectedClipControls(for: selectedClip)
                            }
                            .studioEffectCard()
                        }

                        StudioEffectSection(
                            title: "Zoom & Clicks",
                            systemImage: "plus.magnifyingglass",
                            accessory: {
                                Toggle("Enable zooms", isOn: $model.zoomEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                        ) {
                            zoomControls
                        }

                    }

                    if selectedTab == .cursor {
                        StudioEffectSection(
                            title: "Cursor",
                            systemImage: "cursorarrow",
                            accessory: {
                                Toggle("Show cursor", isOn: $model.style.cursor.isVisible)
                                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                                    .disabled(!model.pointerIsSynthesized)
                            }
                        ) {
                            cursorControls
                        }
                    }

                    if selectedTab == .effects && model.hasKeystrokes {
                        StudioEffectSection(
                            title: "Keystrokes",
                            systemImage: "keyboard",
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

                    if selectedTab == .effects && (model.canTranscribe || model.hasSubtitles) {
                        StudioEffectSection(
                            title: "Transcription",
                            systemImage: "captions.bubble",
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

                    if selectedTab == .camera {
                        StudioEffectSection(
                            title: "Camera",
                            systemImage: "web.camera",
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

                    if selectedTab == .effects {
                        StudioEffectSection(
                            title: "Audio",
                            systemImage: "speaker.wave.2",
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
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
                .padding(.bottom, PreviewPeekTab.pillHeight * 1.1)
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectSoftIfAvailable()
        }
    }

    private var effectActions: some View {
        HStack(spacing: 8) {
            Button { model.beginVideoCrop() } label: {
                Label("Crop", systemImage: "crop")
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditorButtonStyle(selected: model.isCroppingVideo, horizontalPadding: 4))
            .help("Crop the recording; click again to cancel changes")
            ForEach([RecordingMaskSegment.Effect.blur, .pixelate], id: \.self) { effect in
                Button { model.toggleMaskTool(effect) } label: {
                    Label(effect == .blur ? "Blur" : "Pixelate",
                                systemImage: effect == .blur ? "drop.fill" : "square.grid.3x3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorButtonStyle(selected: model.isEditingMasks && model.selectedMask?.effect == effect,
                                               horizontalPadding: 4))
                .help("Draw an area to " + (effect == .blur ? "blur" : "pixelate"))
            }
        }
        .buttonStyle(EditorButtonStyle())
        .controlSize(.large)
        .disabled(!model.isLoaded)
        .padding(.horizontal, 12)
    }

    private var inspectorHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedTab.title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(16)
            if selectedTab == .effects {
                effectActions.padding(.bottom, 12)
            }
            if selectedTab == .background {
                RecordingStudioStylePresetBar(model: model, presetStore: stylePresetStore)
            }

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 0.5)
        }
    }

    private func isAvailable(_ tab: StudioInspectorTab) -> Bool {
        switch tab {
        case .camera: model.hasCameraVideo
        default: true
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
                InspectorGroupLabel("Focus")

                InspectorSegmented(
                    options: ZoomAnchorMode.allCases,
                    isSelected: { $0 == selected.anchorMode },
                    onTap: { anchorMode in
                        model.beginZoomCueEdit()
                        var updated = selected
                        updated.anchorMode = anchorMode
                        if anchorMode == .pinnedAnchor,
                           let pointer = model.pointerLocation(at: model.currentTime) {
                            updated.pinnedPoint = pointer
                        }
                        model.updateZoomCue(updated)
                        model.endZoomCueEdit(actionName: "Change Zoom Mode")
                    },
                    label: { Text($0.inspectorTitle).font(.inspectorLabel) }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                InspectorSlider("Zoom", value: Binding(
                    get: { CGFloat(selected.zoom) },
                    set: { amount in
                        var updated = selected
                        updated.zoom = Double(amount)
                        model.updateZoomCue(updated)
                    }
                ), range: 1...4, format: .magnification(fractionDigits: 1), onEditingChanged: { editing in
                    if editing { model.beginZoomCueEdit() }
                    else { model.endZoomCueEdit(actionName: "Change Zoom Amount") }
                })
            }

            DisclosureGroup("Advanced") {
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
                            magnification: selected.zoom,
                            onEditingChanged: { editing in
                                if editing { model.beginZoomCueEdit() }
                                else { model.endZoomCueEdit(actionName: "Move Zoom Target") }
                            }
                        )
                    }

                    inspectorAction("Set Target to Pointer", systemImage: "scope") {
                        guard let pointer = model.pointerLocation(at: model.currentTime) else { return }
                        model.beginZoomCueEdit()
                        var updated = selected
                        updated.pinnedPoint = pointer
                        model.updateZoomCue(updated)
                        model.endZoomCueEdit(actionName: "Move Zoom Target")
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
                        format: .percent(),
                        onEditingChanged: { editing in
                            if editing { model.beginZoomCueEdit() }
                            else { model.endZoomCueEdit(actionName: "Change Zoom Framing") }
                        }
                    )
                }
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
                    set: { model.setClipSpeed(Double($0), forClipID: clip.id) }
                ),
                range: CGFloat(RecordingClipSegment.minimumSpeed)...CGFloat(RecordingClipSegment.maximumSpeed),
                format: .magnification(fractionDigits: 2)
            )

            if clip.speed != 1 {
                Text("Video and recorded audio play at \(clip.speed.formatted(.number.precision(.fractionLength(0...2))))× speed.")
                    .font(.inspectorLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cursor

    @ViewBuilder
    private var cursorControls: some View {
        if !model.pointerIsSynthesized {
            Text("Cursor editing needs a recording made with BetterShot. Cursors already in a video cannot be changed.")
                .font(.inspectorLabel).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSlider("Size", value: $model.style.cursorScale, range: 1...4,
                                format: .magnification(fractionDigits: 1))
                VStack(alignment: .leading, spacing: 8) {
                    InspectorGroupLabel("Style")
                    HStack(spacing: 6) {
                        ForEach(RecordingCursorAppearance.allCases, id: \.self) { appearance in
                            Button { model.style.cursor.appearance = appearance } label: {
                                VStack(spacing: 4) {
                                    if let artwork = PointerArtworkCapture.styledArtwork(appearance)
                                        ?? model.artwork(id: nil),
                                       let image = StudioCursorImageCache.image(for: artwork) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(height: 26)
                                    }
                                    Text(appearance.title).font(.system(size: 10)).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(EditorButtonStyle(selected: model.style.cursor.appearance == appearance,
                                                           horizontalPadding: 4))
                            .accessibilityLabel("\(appearance.title) cursor")
                            .accessibilityAddTraits(model.style.cursor.appearance == appearance ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    InspectorGroupLabel("Motion")
                    Picker("Motion", selection: $model.style.cursor.smoothMotion) {
                        Text("Natural").tag(false)
                        Text("Smooth").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if model.canShowPressEffects {
                    VStack(alignment: .leading, spacing: 8) {
                        InspectorGroupLabel("Clicks")
                        Toggle("Press effect", isOn: cursorEffectBinding(\.pressEffect))
                        Toggle("Ripple animation", isOn: cursorEffectBinding(\.rippleEffect))
                    }
                    .toggleStyle(.checkbox).font(.inspectorLabel)
                }
                Toggle("Hide when not moving", isOn: $model.style.cursor.hideWhenIdle)
                    .toggleStyle(.checkbox).font(.inspectorLabel)
                    .help("Fade the cursor after three seconds without movement or clicks")
            }
            .disabled(!model.style.cursor.isVisible)
        }
    }

    private func cursorEffectBinding(_ keyPath: WritableKeyPath<RecordingCursorOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.showsClickEffects && model.style.cursor[keyPath: keyPath] },
            set: { enabled in
                var options = model.style.cursor
                if !model.showsClickEffects {
                    options.pressEffect = false
                    options.rippleEffect = false
                }
                options[keyPath: keyPath] = enabled
                model.style.cursor = options
                model.showsClickEffects = true
            }
        )
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
            ScrollView(.vertical, showsIndicators: false) {
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
