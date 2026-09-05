//
//  AnnotationEditorWindow.swift
//  BetterShot
//
//  Created by Codex on 27/04/26.
//

import AppKit
import SwiftUI
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

    @State private var model = AnnotationEditorModel()
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

    var body: some View {
        mainContent
            .editorFullScreenByDefault()
            .navigationTitle("BetterShot Annotate")
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
                    if model.isCropping {
                        cropActions
                    } else {
                        editingActions
                    }
                }
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
            .onDeleteCommand {
                model.deleteSelectedAnnotation()
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
            .background(AnnotationKeyCommandHandler(
                onDelete: model.deleteSelectedAnnotation,
                onSave: saveEdits,
                onUndo: model.undo,
                onRedo: model.redo,
                onSelectAll: model.selectAllAnnotations,
                onSelectTool: model.selectTool,
                onZoomIn: { withAnimation(.canvasZoom) { model.zoomIn() } },
                onZoomOut: { withAnimation(.canvasZoom) { model.zoomOut() } },
                onFitCanvas: { withAnimation(.canvasZoom) { model.fitCanvas() } },
                onActualSize: { withAnimation(.canvasZoom) { model.setZoomPercent(100) } },
                onToggleCrop: { withAnimation(.snappy(duration: 0.2)) { model.toggleCropping() } },
                onApplyCrop: { withAnimation(.snappy(duration: 0.2)) { model.applyCrop() } },
                onCancelCrop: { withAnimation(.snappy(duration: 0.2)) { model.cancelCrop() } },
                isCropping: { model.isCropping }
            ))
            .inspector(isPresented: $isInspectorPresented) {
                AnnotationEditorInspector(
                    model: model,
                    wallpaperStore: wallpaperStore,
                    backgroundPresetStore: backgroundPresetStore,
                    focusedField: $focusedField,
                    onEditorAction: clearInspectorFocus,
                    onPickWallpaper: pickCustomWallpaper
                )
                .disabled(model.isCropping)
            }
    }

    // MARK: Toolbar actions

    /// The standard trailing actions shown when not cropping.
    @ViewBuilder
    private var editingActions: some View {
        Button(action: enterCrop) {
            Label("Crop", systemImage: "crop")
                .labelStyle(.titleAndIcon)
        }
        .help("Crop the screenshot")
        .disabled(model.previewImage == nil || model.imageSize == .zero)

        Button {
            model.deleteSelectedAnnotation()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(model.selectionCount == 0)
        .help("Delete selected annotation (⌫)")

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
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!model.hasUnsavedChanges || isSaving || isExporting)
        .help("Save your edits in BetterShot (⌘S)")

        if CloudUploader.shared.isConfigured {
            CloudUploadButton(
                suggestedTitle: model.sourceURL?.deletingPathExtension().lastPathComponent ?? "",
                onUpload: uploadAnnotation
            ) {
                Label("Share", systemImage: "link")
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
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(model.previewImage == nil || model.imageSize == .zero || isCopying || isExporting)
        .help("Copy the finished image to the clipboard (⇧⌘C)")

        Button(action: exportImage) {
            if isExporting {
                ProgressView().controlSize(.small)
            } else {
                Label("Export", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
        }
        .tint(.accentColor)
        .disabled(model.previewImage == nil || model.imageSize == .zero || isExporting || isSaving || isCopying || uploadPhase.isUploading)
        .accessibilityLabel(isExporting ? "Exporting image" : "Export image")
        .help("Save the finished image to your Mac")

        Button {
            clearInspectorFocus()
            isInspectorPresented.toggle()
        } label: {
            Image(systemName: "sidebar.right")
        }
        .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
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
        .buttonStyle(.borderedProminent)
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
        withAnimation(.snappy(duration: 0.22)) { model.beginCropping() }
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
        .frame(minWidth: 760, minHeight: 580)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if model.previewImage != nil, model.imageSize != .zero {
                HStack(spacing: 8) {
                    AnnotationZoomControl(model: model)

                    if model.isPreviewDownscaled {
                        LowResolutionPreviewNotice()
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.isCropping, model.imageSize != .zero {
                CropResolutionBadge(size: model.cropPixelSize)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
            }
        }
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
        .overlay(alignment: .bottom) {
            if let transferStatus {
                TransferStatusCard(
                    status: transferStatus,
                    onCancel: cancelUpload,
                    onRetry: retryUpload,
                    onDismiss: { uploadPhase = .idle }
                )
                .padding(.bottom, 16)
                .transition(transferCardTransition)
            }
        }
        .animation(RecordingMotion.showHideSpring, value: transferStatus)
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

    private var transferCardTransition: AnyTransition {
        RecordingMotion.reduceMotion
            ? .opacity
            : AnyTransition.offset(y: 24).combined(with: .opacity)
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
                ScreenshotHistoryStore.shared.setCloudURL(for: resultURL, cloudURL: result.url)
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
