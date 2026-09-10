//
//  AnnotationEditorWindow.swift
//  BetterShot
//
//  Created by Codex on 27/04/26.
//

import AppKit
import SwiftUI
import TipKit
import UniformTypeIdentifiers

private enum AnnotationUploadPhase: Equatable {
    case idle
    case uploading(UUID)
    case finished(URL)
    case failed(String)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

struct AnnotationEditorWindow: View {
    @Binding var url: URL?

    @State private var model: AnnotationEditorModel
    @State private var wallpaperStore = AnnotationWallpaperStore.shared
    @State private var backgroundPresetStore = AnnotationBackgroundPresetStore.shared
    @State private var isInspectorPresented = true
    @State private var isSaving = false
    @State private var isExporting = false
    @State private var saveFlash = false
    @State private var isCopying = false
    @State private var copyFlash = false
    @State private var uploadPhase: AnnotationUploadPhase = .idle
    @State private var lastUploadOptions: CloudUploadOptions?
    @State private var closeGuard = EditorCloseGuard()
    @FocusState private var focusedField: AnnotationEditorFocusedField?
    @Environment(\.dismiss) private var dismissWindow

    init(url: Binding<URL?>, model: AnnotationEditorModel? = nil) {
        _url = url
        _model = State(initialValue: model ?? AnnotationEditorModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            imageTools
            Divider()
            HStack(spacing: 0) {
                if isInspectorPresented {
                    AnnotationEditorInspector(
                        model: model, wallpaperStore: wallpaperStore,
                        backgroundPresetStore: backgroundPresetStore,
                        focusedField: $focusedField, onEditorAction: clearInspectorFocus,
                        onPickWallpaper: pickCustomWallpaper
                    )
                    .frame(width: 300)
                    .disabled(model.isCropping)
                    Divider()
                }
                mainContent
            }
            Divider()
            imageFooter
        }
            .frame(minWidth: 980, minHeight: 640)
            .scrollIndicators(.hidden)
            .tint(EditorChrome.accent)
            .accentColor(EditorChrome.accent)
            .editorFullScreenByDefault()
            .navigationTitle(url?.deletingPathExtension().lastPathComponent ?? "Image Editor")
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        model.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndo)
                    .help(ShortcutService.shared.help("Undo", for: .imageUndo))

                    Button {
                        model.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!model.canRedo)
                    .help(ShortcutService.shared.help("Redo", for: .imageRedo))
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if model.isCropping {
                        cropActions
                    } else {
                        editingActions
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .task(id: url) {
                clearInspectorFocus()
                model.load(url: url, dismiss: dismissWindow)
            }
            .onAppear {
                Task { await wallpaperStore.reload() }
                AnnotationEditorActivationPolicy.enter(hidePreview: true)
            }
            .onDisappear {
                closeGuard.detach()
                model.releaseEditorResources()
                AnnotationEditorActivationPolicy.leave(restorePreview: true)
            }
            .onWindowChange { window in
                configureCloseGuard()
                closeGuard.attach(to: window)
                closeGuard.refreshDocumentEdited()
            }
            .onChange(of: model.revision) { _, _ in
                closeGuard.refreshDocumentEdited()
            }
            .onChange(of: model.backgroundSettings) { _, _ in
                closeGuard.refreshDocumentEdited()
            }
            .onChange(of: model.baseImageURL) { _, _ in
                // Cropping replaces the base image rather than touching the
                // engine, so it never bumps `revision`.
                closeGuard.refreshDocumentEdited()
            }
            .background(EditorShortcutHandler(scope: .image, intercept: { event in
                guard model.isCropping else { return false }
                if event.keyCode == 36 || event.keyCode == 76 { model.applyCrop() }
                else if event.keyCode == 53 || ShortcutService.shared.action(
                    keyCode: UInt32(event.keyCode), modifiers: ShortcutService.Shortcut.modifiers(from: event.modifierFlags),
                    scope: .image) == .imageCrop { model.cancelCrop() }
                return true
            }, perform: performShortcut))
    }

    private func performShortcut(_ action: ShortcutService.Action) -> Bool {
        if let tool = action.annotationTool {
            clearInspectorFocus()
            model.selectTool(tool)
            return true
        }
        switch action {
        case .imageBackground: isInspectorPresented.toggle()
        case .imageCrop: model.toggleCropping()
        case .imageSave: saveEdits()
        case .imageExport:
            guard model.previewImage != nil, !isExporting, !isSaving, !isCopying, !uploadPhase.isUploading else { return true }
            exportImage()
        case .imageCopy:
            guard model.previewImage != nil, !isCopying, !isExporting else { return true }
            copyToClipboard()
        case .imageUndo: model.undo()
        case .imageRedo: model.redo()
        case .imageSelectAll: model.selectAllAnnotations()
        case .imageDelete: model.deleteSelectedAnnotation()
        case .imageZoomIn: model.zoomIn()
        case .imageZoomOut: model.zoomOut()
        case .imageFit: model.fitCanvas()
        case .imageActualSize: model.setZoomPercent(100)
        case .imageIncreaseSize, .imageDecreaseSize:
            let delta: CGFloat = action == .imageIncreaseSize ? 1 : -1
            if model.isTextStyleAvailable { model.setTextFontSize(min(300, max(4, model.selectedTextFontSize + delta * 2))) }
            else if model.isStrokeStyleAvailable { model.setStrokeWidth(min(24, max(1, model.strokeWidth + delta))) }
        default: return false
        }
        return true
    }

    private var imageTools: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("Aspect Ratio", selection: $model.backgroundSettings.aspectRatio) {
                    ForEach(AnnotationBackgroundAspectRatio.allCases) { ratio in
                        Text(ratio.title).tag(ratio)
                    }
                }
            } label: {
                Label(model.backgroundSettings.aspectRatio.title, systemImage: "aspectratio")
            }
            .fixedSize()
            .frame(width: 110)

            Button(action: enterCrop) {
                Label("Crop", systemImage: "crop").labelStyle(.iconOnly)
            }
            .buttonStyle(EditorButtonStyle(selected: model.isCropping))
            .help("Crop Image — click again to cancel")
            Divider().frame(height: 24)

            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    clearInspectorFocus()
                    model.selectTool(tool)
                    if tool == .arrow { ImageEditingTip().invalidate(reason: .actionPerformed) }
                } label: {
                    Label(tool.title, systemImage: tool.systemImage).labelStyle(.iconOnly)
                }
                .buttonStyle(EditorButtonStyle(selected: model.selectedTool == tool, horizontalPadding: 6))
                .accessibilityAddTraits(model.selectedTool == tool ? .isSelected : [])
                .help(ShortcutService.shared.help(tool.helpText, for: ShortcutService.Action.allCases.first { $0.annotationTool == tool }))
                .popoverTip(tool == .arrow && !OnboardingState.shouldPresent() ? ImageEditingTip() : nil, arrowEdge: .bottom)
            }

            EditorPopover(title: "Smart Redaction", systemImage: "eye.slash") {
                AnnotationSmartRedactionControls(model: model, onEditorAction: clearInspectorFocus)
            }

            Divider().frame(height: 24)
            if model.hasInspectorStyleControls && !model.isCropping {
                annotationStyleBar
            }
            Spacer(minLength: 0)
            Button {
                clearInspectorFocus()
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.left").labelStyle(.iconOnly)
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            .accessibilityLabel("Toggle image inspector")
        }
        .buttonStyle(EditorButtonStyle())
        .padding(.horizontal, 16)
        .frame(height: 48)
        .studioGlass(cornerRadius: 0)
        .disabled(model.previewImage == nil || model.isCropping)
    }

    private var annotationStyleBar: some View {
        HStack(spacing: 8) {
            if model.isColorStyleAvailable {
                EditorPopover(title: "Color", systemImage: "paintpalette") {
                    AnnotationSwatchStrip(selectedSwatch: model.selectedSwatch) { swatch in
                        clearInspectorFocus()
                        model.setSwatch(swatch)
                    }
                }
                ColorPicker("Annotation color", selection: Binding(
                    get: { model.selectedSwatch.color },
                    set: { color in
                        clearInspectorFocus()
                        model.setSwatch(.custom(from: color))
                    }
                ))
                .labelsHidden()
                .fixedSize()
            }
            if model.isStrokeStyleAvailable {
                AnnotationStrokePicker(strokeWidth: model.strokeWidth) { width in
                    clearInspectorFocus()
                    model.setStrokeWidth(width)
                }
                    .frame(width: 140)
            }
            if model.isTextStyleAvailable {
                EditorPopover(title: "Text Style", systemImage: "textformat") {
                    AnnotationTextStyleControls(model: model)
                }
            }
            if model.isRedactionStyleAvailable {
                InspectorSlider("Strength", value: Binding(
                    get: { model.redactionDensity },
                    set: {
                        clearInspectorFocus()
                        model.setRedactionDensity($0)
                    }
                ), range: 0.15...1, format: .percent())
                .frame(width: 180)
            }
            Button { model.deleteSelectedAnnotation() } label: {
                Label("Delete Selection", systemImage: "trash").labelStyle(.iconOnly)
            }
            .buttonStyle(EditorButtonStyle())
            .disabled(model.selectionCount == 0)
            .help("Delete selected annotation (⌫)")
        }
    }

    // MARK: Toolbar actions

    /// The standard trailing actions shown when not cropping.
    @ViewBuilder
    private var editingActions: some View {
        Button(action: saveEdits) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else if saveFlash {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
        }
        .disabled(!model.hasUnsavedChanges || isSaving || isExporting)
        .help(ShortcutService.shared.help("Save your edits in BetterShot", for: .imageSave))

        Button(action: exportImage) {
            if isExporting {
                ProgressView().controlSize(.small)
            } else {
                Label("Export", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.previewImage == nil || model.imageSize == .zero || isExporting || isSaving || isCopying || uploadPhase.isUploading)
        .accessibilityLabel(isExporting ? "Exporting image" : "Export image")
        .help("Save the finished image to your Mac")


    }

    private var imageFooter: some View {
        HStack(spacing: 12) {
            AnnotationZoomControl(model: model)
            if model.isPreviewDownscaled { LowResolutionPreviewNotice() }
            Spacer()
            if model.isCropping {
                CropResolutionBadge(size: model.cropPixelSize)
            } else {
                if CloudUploader.shared.isConfigured {
                    CloudUploadButton(
                        suggestedTitle: model.sourceURL?.deletingPathExtension().lastPathComponent ?? "",
                        onUpload: uploadAnnotation, shortcutAction: .imageShare
                    ) {
                        Label("Share", systemImage: "icloud.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 6)
                    }
                    .help("Upload and copy a share link")
                    .disabled(model.previewImage == nil || model.imageSize == .zero || uploadPhase.isUploading || isExporting)
                }

                Button(action: copyToClipboard) {
                    if isCopying {
                        ProgressView().controlSize(.small)
                    } else if copyFlash {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    } else {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .disabled(model.previewImage == nil || model.imageSize == .zero || isCopying || isExporting)
                .help(ShortcutService.shared.help("Copy the finished image to the clipboard", for: .imageCopy))

            }
        }
        .buttonStyle(EditorButtonStyle())
        .padding(.horizontal, 16)
        .frame(height: 52)
        .studioGlass(cornerRadius: 0)
    }

    /// The crop controls that replace the trailing actions while cropping.
    @ViewBuilder
    private var cropActions: some View {
        Menu {
            Picker("Aspect Ratio", selection: aspectBinding) {
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
            clearInspectorFocus()
            withAnimation(.snappy(duration: 0.18)) { model.resetCrop() }
        } label: {
            Text("Reset").padding(.horizontal, 6)
        }
        .help("Reset the selection to the whole image")

        Button(action: exitCrop) {
            Text("Cancel").padding(.horizontal, 6)
        }
        .keyboardShortcut(.cancelAction)

        Button(action: applyCropAction) {
            Text("Crop").padding(.horizontal, 8)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.bordered)
    }

    private var aspectBinding: Binding<CropAspectRatio> {
        Binding(
            get: { model.cropAspect },
            set: { newValue in
                clearInspectorFocus()
                withAnimation(.snappy(duration: 0.18)) { model.setCropAspect(newValue) }
            }
        )
    }

    private func enterCrop() {
        clearInspectorFocus()
        model.toggleCropping()
    }

    private func exitCrop() {
        clearInspectorFocus()
        withAnimation(.snappy(duration: 0.22)) { model.cancelCrop() }
    }

    private func applyCropAction() {
        clearInspectorFocus()
        withAnimation(.snappy(duration: 0.22)) { model.applyCrop() }
    }

    private var mainContent: some View {
        ZStack {
            AnnotationEditorWorkspaceBackground()

            if let previewImage = model.previewImage, model.imageSize != .zero {
                AnnotationCanvas(
                    model: model,
                    image: previewImage,
                    onEditorInteraction: clearInspectorFocus
                )
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
            } else if let errorMessage = model.errorMessage {
                // A load failure (missing/unreadable source file, e.g. a stale
                // URL replayed by macOS window restoration) should never sit
                // behind an unexplained spinner with no way out.
                AnnotationLoadFailureView(message: errorMessage, onClose: closeAfterLoadFailure)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(minWidth: 600, minHeight: 440)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            // Only inline saves/uploads (which fail with an image already on
            // screen) land here; a load failure shows the full-canvas state
            // above instead of stacking a second copy of the same message.
            if let errorMessage = model.errorMessage, model.previewImage != nil {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .background(TransferToast(status: transferStatus, onCancel: cancelUpload,
                                  onRetry: retryUpload, onDismiss: { uploadPhase = .idle }))
    }

    private var transferStatus: TransferStatus? {
        switch uploadPhase {
        case .idle:
            return nil
        case .uploading(let itemID):
            let progress = CloudUploader.shared.uploadProgress[itemID]
            return .working(stage: .uploading, progress: (progress ?? 0) > 0 ? progress : nil)
        case .finished(let url):
            return .linkReady(url: url)
        case .failed(let message):
            return .failed(
                headline: "Upload failed",
                message: message,
                canRetry: lastUploadOptions != nil
            )
        }
    }

    private func retryUpload() {
        guard case .failed = uploadPhase, let lastUploadOptions else { return }
        uploadPhase = .idle
        uploadAnnotation(options: lastUploadOptions)
    }

    private func closeAfterLoadFailure() {
        model.releaseEditorResources()
        dismissWindow()
    }

    /// The clipboard route out of the editor: renders the current edits and hands
    /// them straight to the pasteboard, so a screenshot meant for a chat message
    /// costs no save panel and leaves no file to hunt down afterwards.
    private func copyToClipboard() {
        clearInspectorFocus()
        guard let sourceURL = model.sourceURL, !isCopying, !isExporting else { return }
        let baseURL = model.baseImageURL ?? sourceURL

        isCopying = true
        Task {
            defer { isCopying = false }
            do {
                let renderedURL = try await AnnotationRenderer.renderToTemporaryFileInBackground(
                    sourceURL: baseURL,
                    shapes: model.shapes,
                    backgroundSettings: model.backgroundSettings
                )
                // The render stays on disk: copyPNGToClipboard offers it as a file
                // reference too, which is what lets terminals and Slack paste it,
                // and that flavor is only good for as long as the file is.
                try ScreenshotFileActions.copyPNGToClipboard(from: renderedURL)
                flashCopyConfirmation()
            } catch {
                model.errorMessage = "Failed to copy annotation: \(error.localizedDescription)"
            }
        }
    }

    private func flashCopyConfirmation() {
        withAnimation(.snappy(duration: 0.2)) { copyFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.snappy(duration: 0.2)) { copyFlash = false }
        }
    }

    private func exportImage() {
        clearInspectorFocus()
        guard let sourceURL = model.sourceURL, !isExporting, !isSaving, !isCopying,
              !uploadPhase.isUploading else { return }
        let baseURL = model.baseImageURL ?? sourceURL
        let shapes = model.shapes
        let backgroundSettings = model.backgroundSettings
        let contentType = ScreenshotFileActions.exportContentType
        isExporting = true
        model.errorMessage = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.directoryURL = BetterShotPreferences.exportDirectory
        panel.nameFieldStringValue = ScreenshotFileActions.exportFileName(for: sourceURL)
        panel.canCreateDirectories = true
        panel.title = "Export Screenshot"

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else {
                isExporting = false
                return
            }
            Task {
                defer { isExporting = false }
                do {
                    try await AnnotationRenderer.renderInBackground(
                        sourceURL: baseURL,
                        shapes: shapes,
                        backgroundSettings: backgroundSettings,
                        destinationURL: destinationURL,
                        contentType: contentType
                    )
                } catch {
                    model.errorMessage = "Failed to export image: \(error.localizedDescription)"
                }
            }
        }
    }

    private func pickCustomWallpaper() {
        clearInspectorFocus()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Background Wallpaper"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let wallpaper = AnnotationCustomWallpaper(url: url)
            wallpaperStore.addRecentWallpaper(url)
            model.backgroundSettings.customWallpaper = wallpaper
            model.backgroundSettings.style = .customWallpaper(wallpaper)
        }
    }

    private func uploadAnnotation(options: CloudUploadOptions) {
        clearInspectorFocus()
        guard model.sourceURL != nil, !uploadPhase.isUploading, !isExporting else { return }

        let itemID = UUID()
        lastUploadOptions = options
        uploadPhase = .uploading(itemID)
        Task {
            do {
                // Persist the current annotations first so the uploaded file
                // matches what's saved in history, then upload that file. An
                // untouched screenshot has nothing to commit, so it uploads
                // as-is. The editor stays open.
                guard let sourceURL = model.sourceURL else {
                    uploadPhase = .idle
                    return
                }
                let resultURL = try await commitEdits() ?? sourceURL

                _ = ScreenshotPreviewStack.shared.applyAnnotation(
                    originalURL: sourceURL,
                    historyURL: resultURL
                )

                let result = try await CloudUploader.shared.upload(
                    itemID: itemID,
                    fileURL: resultURL,
                    title: options.trimmedTitleOrNil
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url, forType: .string)
                await ScreenshotHistoryStore.shared.setCloudURL(for: resultURL, cloudURL: result.url)
                if let shareURL = URL(string: result.url) {
                    uploadPhase = .finished(shareURL)
                } else {
                    uploadPhase = .idle
                }
            } catch is CancellationError {
                uploadPhase = .idle
            } catch let error as URLError where error.code == .cancelled {
                uploadPhase = .idle
            } catch {
                uploadPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelUpload() {
        if case .uploading(let itemID) = uploadPhase {
            CloudUploader.shared.cancelUpload(for: itemID)
            uploadPhase = .idle
        }
    }

    /// Renders the composite, writes the `.bettershot` sidecar, and repoints
    /// the editor at the preserved base image so continued edits don't re-bake
    /// annotations onto an already-composited picture. Returns nil when there
    /// is nothing to persist.
    ///
    /// This is the only thing that puts annotations on disk, so every route
    /// out of the editor - Done, Save, Upload, the close prompt - goes
    /// through it.
    @discardableResult
    private func commitEdits() async throws -> URL? {
        guard let sourceURL = model.sourceURL else { return nil }

        let baseURL = model.baseImageURL ?? sourceURL
        let shapes = model.shapes
        let bindings = model.bindings
        let backgroundSettings = model.backgroundSettings
        let hasContent = !shapes.isEmpty || backgroundSettings.hasRenderableContent || model.isCropped
        let hadDocument = ScreenshotHistoryStore.shared.hasEditDocument(for: sourceURL)

        // Nothing drawn and nothing previously saved: there is no work to lose.
        guard hasContent || hadDocument else {
            model.markSaved()
            return nil
        }

        let resultURL: URL
        if hasContent {
            let annotatedURL = try await AnnotationRenderer.renderToTemporaryFileInBackground(
                sourceURL: baseURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings
            )
            let document = AnnotationDocument(
                shapes: shapes,
                bindings: bindings,
                background: backgroundSettings
            )
            resultURL = ScreenshotHistoryStore.shared.commitAnnotations(
                displayURL: sourceURL,
                baseURL: baseURL,
                renderedURL: annotatedURL,
                document: document
            )
            model.sourceURL = resultURL
            model.baseImageURL = ScreenshotHistoryStore.baseImageURL(for: resultURL)
        } else {
            // All annotations were cleared on a previously-edited image:
            // restore the untouched original.
            resultURL = ScreenshotHistoryStore.shared.removeAnnotations(displayURL: sourceURL)
            model.baseImageURL = resultURL
        }

        model.markSaved()
        return resultURL
    }

    /// Cmd-S. Commits without closing, so long editing sessions have a
    /// checkpoint that isn't "press Done and start over".
    private func saveEdits() {
        clearInspectorFocus()
        // Committing re-renders the composite, so a Cmd-S with nothing
        // changed should cost nothing.
        guard model.sourceURL != nil, model.hasUnsavedChanges, !isSaving, !isExporting else { return }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                guard let sourceURL = model.sourceURL,
                      let resultURL = try await commitEdits() else { return }
                _ = ScreenshotPreviewStack.shared.applyAnnotation(
                    originalURL: sourceURL,
                    historyURL: resultURL
                )
                flashSaveConfirmation()
            } catch {
                model.errorMessage = "Failed to save annotation: \(error.localizedDescription)"
            }
        }
    }

    private func flashSaveConfirmation() {
        withAnimation(.snappy(duration: 0.2)) { saveFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.snappy(duration: 0.2)) { saveFlash = false }
        }
    }

    private func configureCloseGuard() {
        closeGuard.hasUnsavedChanges = { model.hasUnsavedChanges }
        // A screenshot is already in History whether or not it is annotated,
        // so there is no "delete the whole thing" case here.
        closeGuard.offersDelete = { false }
        closeGuard.projectName = { model.sourceURL?.lastPathComponent ?? "this screenshot" }
        closeGuard.onDecision = { decision, done in
            switch decision {
            case .save:
                Task {
                    do {
                        if let sourceURL = model.sourceURL,
                           let resultURL = try await commitEdits() {
                            _ = ScreenshotPreviewStack.shared.applyAnnotation(
                                originalURL: sourceURL,
                                historyURL: resultURL
                            )
                        }
                        model.releaseEditorResources()
                        done()
                    } catch {
                        model.errorMessage = "Failed to save annotation: \(error.localizedDescription)"
                    }
                }
            case .discard:
                model.releaseEditorResources()
                done()
            case .delete, .cancel:
                break
            }
        }
    }

    private func clearInspectorFocus() {
        focusedField = nil
    }
}

private struct AnnotationLoadFailureView: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
    }
}
