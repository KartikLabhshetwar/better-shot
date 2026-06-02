import SwiftUI

struct EditorWindowView: View {
    let imageURL: URL
    @State private var model = EditorModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HSplitView {
            // Canvas area
            EditorCanvasView(model: model)
                .frame(minWidth: 500, minHeight: 400)
                .background(Color(nsColor: .windowBackgroundColor))

            // Inspector panel
            EditorInspectorView(model: model)
                .frame(width: 280)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    model.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    Task { await copyToClipboard() }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    Task { await exportImage() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear {
            model.loadImage(from: imageURL)
        }
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

        if AppPreferences.copyAfterSave {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let nsImage = NSImage(contentsOf: url) {
                pb.writeObjects([nsImage])
            }
        }

        dismiss()
    }

    private func copyToClipboard() async {
        guard let rendered = model.renderFinal() else { return }

        let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }
}
