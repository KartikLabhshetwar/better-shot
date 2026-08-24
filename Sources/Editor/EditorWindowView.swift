import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct EditorWindowView: View {
    @Bindable var urlHolder: CurrentURL
    @State private var model = EditorModel()
    @State private var shareCredentials = R2CredentialStore.shared
    @State private var shareUploader = R2Uploader.shared
    @State private var shareItemID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HSplitView {
            EditorInspectorView(model: model)
                .frame(width: 280)

            EditorCanvasView(model: model)
                .frame(minWidth: 500, minHeight: 400)
                .background(EditorCanvasBackdrop())
        }
        .editorToast($model.toastMessage)
        .background {
            AnnotationKeyCommandHandler(
                onDelete: { model.deleteSelectedAnnotation() },
                onUndo: { model.undo() },
                onRedo: { model.redo() },
                onSelectAll: { model.selectAllAnnotations() },
                onSelectTool: { tool in model.selectTool(tool) }
            )
        }
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
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    deleteCapture()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await copyToClipboard() }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                if shareCredentials.isConfigured && shareCredentials.enabled {
                    Button {
                        Task { await shareImage() }
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
                    Task { await exportImage() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear {
            model.loadImage(from: urlHolder.url)
        }
        .onChange(of: urlHolder.url) { _, newURL in
            model.loadImage(from: newURL)
        }
    }

    private func shareImage() async {
        guard let rendered = model.renderFinal() else { return }

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
        guard let rendered = model.renderFinal() else { return }

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
        NSApp.keyWindow?.close()
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
        NSApp.keyWindow?.close()
    }

    private func copyToClipboard() async {
        guard let rendered = model.renderFinal() else { return }

        let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
        withAnimation { model.toastMessage = "Copied to clipboard" }
    }
}
