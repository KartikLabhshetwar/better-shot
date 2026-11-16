import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenshotCompositionWindowController: NSObject, NSWindowDelegate {
    static let shared = ScreenshotCompositionWindowController()
    private var window: NSWindow?
    private var model: ScreenshotCompositionModel?
    private var exportBeforeClosing: (() -> Void)?
    private var captureTask: Task<Void, Never>?

    func open(on screen: NSScreen? = nil, images: [URL] = []) {
        if let window {
            if !images.isEmpty { model?.importImages(images) }
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let model = ScreenshotCompositionModel()
        self.model = model
        if !images.isEmpty { model.importImages(images) }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Compose Screenshots"
        window.minSize = CGSize(width: 980, height: 680)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ScreenshotCompositionWindow(model: model,
            onExportAvailable: { [weak self] action in self?.exportBeforeClosing = action }))
        self.window = window
        if let screen { window.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 590, y: screen.visibleFrame.midY - 390)) }
        else { window.center() }
        AppActivationPolicy.enter(hidePreview: true)
        window.makeKeyAndOrderFront(nil)
    }

    func captureWindow() {
        guard let window, let model, captureTask == nil else { return }
        guard !ScreenCapture.shared.isCapturing else {
            model.errorMessage = "Another capture is in progress. Finish it, then try again."
            return
        }
        guard ScreenCapturePermission.isReadyToCapture() else { return }
        window.orderOut(nil)
        captureTask = Task { @MainActor [weak self] in
            defer {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self?.captureTask = nil
            }
            do {
                // Native window selection, without a baked-in shadow: each
                // screenshot's editable shadow is drawn by the composer.
                if let url = try await ScreenCapture.shared.captureWindow(includeShadow: false) {
                    defer { try? FileManager.default.removeItem(at: url) }
                    model.importImages([url])
                }
            } catch { model.errorMessage = error.localizedDescription }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.hasUnexportedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Export this composition before closing?"
        alert.informativeText = "The canvas is kept only in this window. Export a PNG to keep the combined image; individual layers cannot be reopened from it."
        alert.addButton(withTitle: "Export PNG…")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: sender) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.exportBeforeClosing?() }
            else if response == .alertSecondButtonReturn { sender.close() }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        exportBeforeClosing = nil
        window = nil; model = nil
        AppActivationPolicy.leave(restorePreview: true)
    }
}

struct ScreenshotCompositionWindow: View {
    @Bindable var model: ScreenshotCompositionModel
    var onExportAvailable: (@escaping () -> Void) -> Void = { _ in }
    @State private var layout: ScreenshotCompositionLayout = .row
    @State private var exportScale: CGFloat = 0
    @State private var transferStatus: TransferStatus?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var dropTarget = false
    @State private var confirmRemove = false
    @State private var gestureFrame: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                inspector.frame(width: 290)
                Divider()
                canvas
            }
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 640)
        .tint(EditorChrome.accent)
        .background(EditorChrome.workspace)
        .background(TransferToast(status: transferStatus, onRetry: exportPNG,
            onDismiss: { transferStatus = nil }))
        .background(EditorShortcutHandler(scope: .image, perform: { action in
            switch action {
            case .imageUndo: model.undo()
            case .imageRedo: model.redo()
            case .imageSave, .imageExport: exportPNG()
            case .imageDelete:
                if model.selection != nil { confirmRemove = true }
            default: return false
            }
            return true
        }))
        .onAppear { onExportAvailable(exportPNG) }
        .alert("Remove this screenshot?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { model.removeSelection() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The source file is kept. You can undo this change.") }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget, perform: importDrop)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: importImages) { Label("Add Images…", systemImage: "photo.on.rectangle") }
                .disabled(isImporting)
            Button { ScreenshotCompositionWindowController.shared.captureWindow() } label: {
                Label("Capture Window", systemImage: "macwindow")
            }
            Divider().frame(height: 22)
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward").labelStyle(.iconOnly) }
                .disabled(!model.canUndo).help("Undo")
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward").labelStyle(.iconOnly) }
                .disabled(!model.canRedo).help("Redo")
            Spacer()
            Button(action: exportPNG) { Label("Export PNG…", systemImage: "arrow.down.circle") }
                .buttonStyle(.borderedProminent)
                .disabled(model.document.screenshots.isEmpty || isExporting)
        }
        .buttonStyle(EditorButtonStyle())
        .padding(.horizontal, 16).frame(height: 48).studioGlass(cornerRadius: 0)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Canvas") {
                    valueSlider("Width", value: Binding(get: { model.document.size.width }, set: {
                        model.resizeCanvas(CGSize(width: $0, height: model.document.size.height))
                    }), range: 400...6000)
                    valueSlider("Height", value: Binding(get: { model.document.size.height }, set: {
                        model.resizeCanvas(CGSize(width: model.document.size.width, height: $0))
                    }), range: 400...6000)
                    backgroundControls
                }
                section("Layout") {
                    HStack {
                        Picker("Layout", selection: $layout) {
                            ForEach(ScreenshotCompositionLayout.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                        Button("Arrange") { model.change { $0.arrange(layout) } }
                            .disabled(model.document.screenshots.isEmpty)
                    }
                    valueSlider("Padding", value: documentValue(\.padding),
                        range: 0...min(model.document.size.width, model.document.size.height) / 4)
                    valueSlider("Spacing", value: documentValue(\.spacing), range: 0...300)
                    Text("Padding keeps images inside the canvas. Spacing applies when you choose Arrange.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("Screenshots · \(model.document.screenshots.count)") {
                    if model.document.screenshots.isEmpty {
                        Text("Add images or capture a window to begin.").foregroundStyle(.secondary).font(.callout)
                    }
                    Text("Front to back").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.document.screenshots.reversed()) { item in
                        Button { model.selectedID = item.id } label: {
                            HStack(spacing: 8) {
                                Image(decorative: item.image, scale: 1).resizable().scaledToFit().frame(width: 42, height: 30)
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(EditorButtonStyle(selected: model.selectedID == item.id))
                        .accessibilityLabel("Select \(item.name)")
                        .accessibilityAddTraits(model.selectedID == item.id ? .isSelected : [])
                    }
                }
                if let selected = model.selection {
                    section("Selected Screenshot") {
                        Text(selected.name).font(.caption).lineLimit(2)
                        valueSlider("X", value: frameValue(\.origin.x), range: model.document.padding...max(model.document.padding, model.document.size.width - model.document.padding - selected.frame.width))
                        valueSlider("Y", value: frameValue(\.origin.y), range: model.document.padding...max(model.document.padding, model.document.size.height - model.document.padding - selected.frame.height))
                        valueSlider("Width", value: Binding(get: { model.selection?.frame.width ?? 1 }, set: { width in
                            guard let item = model.selection else { return }
                            var frame = item.frame
                            frame.size = CGSize(width: width, height: width * CGFloat(item.image.height) / CGFloat(item.image.width))
                            let fitted = model.document.fittedFrame(frame)
                            model.updateSelected { $0.frame = fitted }
                        }), range: 20...max(20, model.document.contentRect.width))
                        valueSlider("Corners", value: selectedValue(\.cornerRadius), range: 0...0.25, format: .percent())
                        valueSlider("Shadow", value: selectedValue(\.shadow), range: 0...1, format: .percent())
                        Picker("Shadow Style", selection: Binding(get: { model.selection?.shadowStyle ?? .soft }, set: { style in
                            model.updateSelected { $0.shadowStyle = style }
                        })) {
                            ForEach(AnnotationShadowStyle.allCases) { Text($0.title).tag($0) }
                        }
                        HStack {
                            Button("Backward", systemImage: "square.2.layers.3d.bottom.filled") { model.moveSelection(by: -1) }
                                .disabled(model.document.screenshots.first?.id == selected.id)
                            Button("Forward", systemImage: "square.2.layers.3d.top.filled") { model.moveSelection(by: 1) }
                                .disabled(model.document.screenshots.last?.id == selected.id)
                        }.controlSize(.small)
                        Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    }
                }
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Button("Dismiss") { model.errorMessage = nil }
                }
            }.padding(16)
        }
        .scrollIndicators(.hidden)
        .background(EditorChrome.panel)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Background", selection: Binding(get: { backgroundKind }, set: { kind in
                model.change {
                    $0.background = kind == 0 ? .none : kind == 1 ? .solid(.graphite) : .gradient(AnnotationBackgroundGradient.presets[0])
                }
            })) {
                Text("Transparent").tag(0)
                Text("Color").tag(1)
                Text("Gradient").tag(2)
                if backgroundKind == 3 { Text("Default Wallpaper").tag(3) }
            }
            if case .solid(let color) = model.document.background {
                ColorPicker("Color", selection: Binding(get: { color.color }, set: { color in
                    model.change { $0.background = .solid(.custom(from: color)) }
                }), supportsOpacity: false)
            }
            if case .gradient(let current) = model.document.background {
                Picker("Gradient", selection: Binding(get: { current.id }, set: { id in
                    if let preset = AnnotationBackgroundGradient.presets.first(where: { $0.id == id }) {
                        model.change { $0.background = .gradient(preset) }
                    }
                })) {
                    ForEach(AnnotationBackgroundGradient.presets) { Text($0.title).tag($0.id) }
                }
            }
        }
    }

    private var backgroundKind: Int {
        switch model.document.background {
        case .none: 0
        case .solid: 1
        case .gradient: 2
        case .customWallpaper: 3
        }
    }

    private func valueSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>,
                             format: InspectorValueFormat = .pixels) -> some View {
        InspectorSlider(title, value: value, range: range, format: format, onEditingChanged: {
            if $0 { model.beginEditing() } else { model.endEditing() }
        })
    }

    private func documentValue(_ key: WritableKeyPath<ScreenshotComposition, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { model.document[keyPath: key] }, set: { value in
            model.change { doc in
                doc[keyPath: key] = value
                for index in doc.screenshots.indices { doc.screenshots[index].frame = doc.fittedFrame(doc.screenshots[index].frame) }
            }
        })
    }

    private func selectedValue(_ key: WritableKeyPath<CompositionScreenshot, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { model.selection?[keyPath: key] ?? 0 }, set: { value in model.updateSelected { $0[keyPath: key] = value } })
    }

    private func frameValue(_ key: WritableKeyPath<CGRect, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { model.selection?.frame[keyPath: key] ?? 0 }, set: { value in
            guard var frame = model.selection?.frame else { return }
            frame[keyPath: key] = value
            let fitted = model.document.fittedFrame(frame)
            model.updateSelected { $0.frame = fitted }
        })
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let size = model.document.size
            let scale = max(0.01, min((proxy.size.width - 64) / size.width, (proxy.size.height - 64) / size.height))
            ZStack {
                EditorChrome.workspace
                ZStack(alignment: .topLeading) {
                    TransparencyGrid()
                    // The same renderer drives preview and export, so gradients,
                    // alpha, rounding and shadows cannot diverge between them.
                    if let image = try? ScreenshotCompositionRenderer.render(model.document, scale: scale) {
                        Image(decorative: image, scale: 1).resizable()
                    }
                    ForEach(model.document.screenshots) { item in
                        itemControls(item, scale: scale)
                    }
                    if model.document.screenshots.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle").font(.largeTitle)
                            Text("Drop screenshots here").font(.title3.weight(.semibold))
                            Text("Or use Add Images and Capture Window above.").font(.callout)
                        }.foregroundStyle(.secondary).frame(width: size.width * scale, height: size.height * scale)
                    }
                }
                .frame(width: size.width * scale, height: size.height * scale)
                .clipped()
                .coordinateSpace(name: "compositionCanvas")
                .overlay(Rectangle().stroke(dropTarget ? EditorChrome.accent : EditorChrome.border, lineWidth: dropTarget ? 3 : 1))
            }
        }
    }

    private func itemControls(_ item: CompositionScreenshot, scale: CGFloat) -> some View {
        let selected = model.selectedID == item.id
        return Rectangle().fill(.clear)
            .contentShape(Rectangle())
            .overlay { if selected { Rectangle().stroke(EditorChrome.accent, lineWidth: 2) } }
            .frame(width: item.frame.width * scale, height: item.frame.height * scale)
            .onTapGesture { model.selectedID = item.id }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("compositionCanvas")).onChanged { value in
                if gestureFrame == nil { model.selectedID = item.id; gestureFrame = item.frame; model.beginEditing() }
                guard let start = gestureFrame else { return }
                let frame = model.document.fittedFrame(start.offsetBy(dx: value.translation.width / scale, dy: value.translation.height / scale))
                model.updateSelected { $0.frame = frame }
            }.onEnded { _ in gestureFrame = nil; model.endEditing() })
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(EditorChrome.accent, in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Resize screenshot; use Width in the inspector for keyboard input")
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("compositionCanvas")).onChanged { value in
                            if gestureFrame == nil { gestureFrame = item.frame; model.beginEditing() }
                            guard var frame = gestureFrame else { return }
                            let ratio = CGFloat(item.image.height) / CGFloat(item.image.width)
                            let delta = (value.translation.width + value.translation.height * ratio) / (1 + ratio * ratio) / scale
                            frame.size.width = max(20, frame.width + delta)
                            frame.size.height = frame.width * ratio
                            let fitted = model.document.fittedFrame(frame)
                            model.updateSelected { $0.frame = fitted }
                        }.onEnded { _ in gestureFrame = nil; model.endEditing() })
                }
            }
            .offset(x: item.frame.minX * scale, y: item.frame.minY * scale)
    }

    private var resolvedExportScale: CGFloat {
        exportScale == 0 ? model.document.sourceResolutionScale : exportScale
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Drag to move · Drag the blue corner to resize").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker("Export Scale", selection: $exportScale) {
                Text("Auto").tag(CGFloat(0))
                Text("1×").tag(CGFloat(1)); Text("2×").tag(CGFloat(2)); Text("3×").tag(CGFloat(3))
            }.frame(width: 170)
                .help("Auto keeps screenshots at least at their original pixel dimensions. Choose 1×, 2×, or 3× for a fixed output size.")
            Text("\(Int((model.document.size.width * resolvedExportScale).rounded())) × \(Int((model.document.size.height * resolvedExportScale).rounded())) px")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).frame(height: 44).studioGlass(cornerRadius: 0)
    }

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add Images"
        isImporting = true
        panel.begin { response in
            isImporting = false
            if response == .OK { model.importImages(panel.urls) }
        }
    }

    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isImporting else { return false }
        isImporting = true
        Task { @MainActor in
            var urls: [URL] = []
            // Await in provider order so asynchronous decoding cannot reorder layers.
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            model.importImages(urls)
            if urls.isEmpty { model.errorMessage = "Drop image files from Finder, or use Add Images." }
            isImporting = false
        }
        return true
    }

    private func exportPNG() {
        guard !isExporting, !model.document.screenshots.isEmpty else { return }
        do { _ = try ScreenshotCompositionRenderer.outputSize(model.document, scale: resolvedExportScale) }
        catch { model.errorMessage = error.localizedDescription; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotFileNaming.fileName(template: ScreenshotFileNaming.template(), extension: "png")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let snapshot = model.document
            let scale = resolvedExportScale
            isExporting = true
            transferStatus = .working(stage: .exporting, progress: nil)
            Task { @MainActor in
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try ScreenshotCompositionRenderer.export(snapshot, scale: scale, to: url)
                    }.value
                    model.markExported(snapshot.revision)
                    transferStatus = .exported(url: url)
                } catch {
                    transferStatus = .failed(headline: "Export failed", message: error.localizedDescription, canRetry: true)
                }
                isExporting = false
            }
        }
    }
}
