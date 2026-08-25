import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct EditorWindowView: View {
    @Bindable var urlHolder: CurrentURL
    @State private var model = EditorModel()
    @State private var shareCredentials = R2CredentialStore.shared
    @State private var shareUploader = R2Uploader.shared
    @State private var shareItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDiscard = false
    @State private var hostWindow: NSWindow?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: EditorPanelMetrics.gap) {
            EditorCanvasView(model: model)
                .frame(minWidth: 500, minHeight: 400)
                .background(EditorCanvasBackdrop())
                .editorPanel()

            EditorInspectorView(model: model)
                .frame(width: EditorPanelMetrics.sidebarWidth)
                .editorPanel()
        }
        .padding(EditorPanelMetrics.gap)
        .background(EditorCanvasBackdrop())
        .hostWindow($hostWindow)
        .editorCloseGuard(window: hostWindow, hasEdits: model.hasEdits) { isConfirmingDiscard = true }
        .editorToast($model.toastMessage)
        .confirmationDialog("Delete this capture?", isPresented: $isConfirmingDelete) {
            Button("Delete Capture", role: .destructive) { deleteCapture() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from disk. This cannot be undone.")
        }
        .confirmationDialog("Discard your edits?", isPresented: $isConfirmingDiscard) {
            Button("Discard Edits", role: .destructive) { hostWindow?.close() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The capture stays on disk, but these annotations and styling are not saved.")
        }
        .background {
            AnnotationKeyCommandHandler(
                onDelete: { model.deleteSelectedAnnotation() },
                onUndo: { model.undo() },
                onRedo: { model.redo() },
                onSelectAll: { model.selectAllAnnotations() },
                onSelectTool: { tool in model.selectTool(tool) }
            )
        }
        .onEscapeKey { escapePressed() }
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
                .help("Delete this capture from disk")

                Button {
                    attemptClose()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close without exporting (esc)")

                Button {
                    Task { await copyToClipboard() }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the edited image (\u{21E7}\u{2318}C)")

                if shareCredentials.isConfigured && shareCredentials.enabled {
                    Button {
                        Task { await shareImage() }
                    } label: {
                        if let shareItemID, shareUploader.uploadingItems.contains(shareItemID) {
                            ProgressView(value: shareUploader.uploadProgress[shareItemID] ?? 0)
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        } else {
                            Label("Share", systemImage: "link")
                        }
                    }
                    .disabled(shareItemID != nil)
                    .help("Upload and copy a share link")
                }

                Button {
                    Task { await exportImage() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .help("Export to \(AppPreferences.exportFormat.fileExtension.uppercased()) (\u{2318}S)")
            }
        }
        .onAppear {
            model.loadImage(from: urlHolder.url)
        }
        .onChange(of: urlHolder.url) { _, newURL in
            model.loadImage(from: newURL)
        }
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
            hostWindow?.close()
        }
    }

    private func shareImage() async {
        guard let rendered = await model.renderFinal() else { return }

        let itemID = UUID()
        shareItemID = itemID
        defer { shareItemID = nil }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterShotShare-\(itemID.uuidString)")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let name = model.sourceURL?.deletingPathExtension().lastPathComponent ?? "screenshot"
        let fileURL = stagingDir.appendingPathComponent("\(name).png")

        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            ToastWindow.shared.show(
                title: "Share Failed",
                message: "Could not encode the image for upload.",
                systemIcon: "exclamationmark.triangle"
            )
            return
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            ToastWindow.shared.show(
                title: "Share Failed",
                message: "Could not write the image for upload.",
                systemIcon: "exclamationmark.triangle"
            )
            return
        }

        _ = await ShareService.shared.share(itemID: itemID, fileURL: fileURL, title: name)
    }

    private func exportImage() async {
        guard let rendered = await model.renderFinal() else { return }

        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = AppPreferences.exportFormat.fileExtension
        let path = "\(dir)/bettershot_\(stamp).\(ext)"
        let url = URL(fileURLWithPath: path)

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            AppPreferences.exportFormat.utType as CFString,
            1, nil
        ) else { return }

        var options: [CFString: Any] = [:]
        if AppPreferences.exportFormat == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = AppPreferences.exportQuality
        }

        CGImageDestinationAddImage(dest, rendered, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }

        if let record = HistoryStore.shared.records.first(where: {
            HistoryStore.shared.urlForRecord($0) == model.sourceURL
                || HistoryStore.shared.displayURLForRecord($0) == model.sourceURL
        }) {
            HistoryStore.shared.setBeautifiedPath(url.path, for: record.id)
        } else {
            _ = HistoryStore.shared.referenceCapture(at: url, kind: .screenshot)
        }

        if AppPreferences.copyAfterSave {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let nsImage = NSImage(contentsOf: url) {
                pb.writeObjects([nsImage])
            }
        }

        withAnimation { model.toastMessage = "Exported" }
        try? await Task.sleep(for: .seconds(1.0))
        hostWindow?.close()
    }

    private func deleteCapture() {
        let url = urlHolder.url
        if let record = HistoryStore.shared.records.first(where: {
            HistoryStore.shared.urlForRecord($0) == url
                || HistoryStore.shared.displayURLForRecord($0) == url
        }) {
            HistoryStore.shared.deleteRecord(record)
        }
        try? FileManager.default.removeItem(at: url)
        hostWindow?.close()
    }

    private func copyToClipboard() async {
        guard let rendered = await model.renderFinal() else { return }

        let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
        withAnimation { model.toastMessage = "Copied to clipboard" }
    }
}
