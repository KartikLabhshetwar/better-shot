import AppKit
import AVFoundation
import SwiftUI

/// A small editor uses the same canvas, undo, crop, lossless renderer and editable sidecars as Studio.
@MainActor @Observable
final class NotchQuickEditor: NSObject, NSWindowDelegate {
    static let shared = NotchQuickEditor()
    var model = AnnotationEditorModel()
    var busy = false
    var listening = false
    var status: String?
    var error: String?
    private(set) var panel: NSPanel?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var originalURL: URL?
    private var previousApp: NSRunningApplication?
    private var limitTask: Task<Void, Never>?
    private var finishAfterVoiceStarts = false
    var isOpen: Bool { panel != nil }
    var hasVoice: Bool { audioURL != nil }

    func open(_ url: URL, on screen: NSScreen? = nil, fullScreen: Bool = false) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        guard let screen = screen ?? NotchPresenter.shared.screen ?? NSScreen.main else { return }
        let retained = DeckStaging.retain(url)
        guard !DeckStaging.isStaged(retained) else {
            PreviewOverlay.shared.showSaveFailure(for: url)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        originalURL = url
        model = AnnotationEditorModel()
        model.load(url: retained)
        if fullScreen {
            model.backgroundSettings = AnnotationBackgroundSettings()
            if model.selectedTool != .freehand { model.selectTool(.freehand) }
            model.setSwatch(.red)
            model.markSaved()
        }
        error = model.errorMessage
        let panel = NotchQuickPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.title = "BetterShot quick editor"
        panel.identifier = .init("BetterShot.QuickEditor")
        panel.level = fullScreen ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1) : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = !fullScreen
        panel.contentView = NSHostingView(rootView: NotchQuickEditorView(editor: self, fullScreen: fullScreen))
        let visible = screen.visibleFrame
        let width = min(640, visible.width - 32)
        let height = min(460, visible.height - 60)
        panel.setFrame(fullScreen ? screen.frame : CGRect(x: visible.midX - width / 2,
            y: visible.maxY - height - 12, width: width, height: height), display: true)
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        self.panel = panel
        NotchPresenter.shared.collapse()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func startVoice() async {
        guard !busy, !listening, !ScreenRecordingManager.shared.isActive else { return }
        if hasVoice {
            let alert = NSAlert()
            alert.messageText = "Replace the voice note?"
            alert.informativeText = "The current audio will be discarded. Your annotations stay."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Record Again")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        discardVoice()
        busy = true
        defer {
            busy = false
            if finishAfterVoiceStarts {
                finishAfterVoiceStarts = false
                Task { await finish() }
            }
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "Allow Microphone access in System Settings → Privacy & Security, then try Voice again."
            return
        }
        guard panel != nil else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BetterShotVoice-\(UUID()).m4a")
            self.audioURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            self.audioURL = url
            listening = true
            error = nil
            status = "Listening · draw and speak"
            limitTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                self?.limitTask = nil
                await self?.finish()
            }
        } catch {
            discardVoice()
            self.error = "Couldn’t start the microphone. Check your input device and try again."
        }
    }

    func stopVoice() {
        limitTask?.cancel()
        limitTask = nil
        recorder?.stop()
        recorder = nil
        listening = false
        status = hasVoice ? "Voice recorded · Done to transcribe" : nil
    }

    /// Option can be released while microphone permission or startup is still
    /// finishing. Queue one completion instead of losing the held gesture.
    func requestFinish() {
        guard busy else {
            Task { await finish() }
            return
        }
        finishAfterVoiceStarts = true
    }

    func finish() async {
        guard !busy, let source = model.sourceURL else { return }
        stopVoice()
        busy = true
        error = nil
        defer { busy = false; status = nil }
        do {
            if model.isCropping { model.applyCrop() }
            var transcript: String?
            if let audioURL {
                status = "Transcribing on this Mac…"
                let result = try await RecordingTranscriptionService.transcribeAudio(at: audioURL)
                transcript = result.words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            status = "Saving to your library…"
            let result = try await Self.commit(model)
            if let transcript, !transcript.isEmpty {
                NotchShelfStore.shared.add(text: transcript, imageURL: result)
                guard NotchShelfStore.shared.error == nil else { throw CocoaError(.fileWriteUnknown) }
            }
            // Keep this private. Done never exports to the user's configured save folder.
            PreviewOverlay.shared.remove(originalURL ?? source)
            PreviewOverlay.shared.show(url: result, automaticallyDismiss: false)
            model.markSaved()
            close()
            NotchPresenter.shared.show()
        } catch {
            self.error = "\(error.localizedDescription) Try Done again, or keep the image without voice."
        }
    }

    static func commit(_ model: AnnotationEditorModel) async throws -> URL {
        guard let source = model.sourceURL else { throw CocoaError(.fileNoSuchFile) }
        let rendered = try await AnnotationRenderer.renderToTemporaryFileInBackground(
            sourceURL: model.baseImageURL ?? source, shapes: model.shapes, backgroundSettings: model.backgroundSettings)
        let result = ScreenshotHistoryStore.shared.commitAnnotations(displayURL: source,
            baseURL: model.baseImageURL ?? source, renderedURL: rendered,
            document: AnnotationDocument(shapes: model.shapes, bindings: model.bindings, background: model.backgroundSettings))
        guard result != rendered,
              ScreenshotHistoryStore.shared.hasEditDocument(for: result) else {
            // Keep the temporary render available if persistence fails; the editor retains the original too.
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: rendered)
        return result
    }

    func discardVoice() {
        stopVoice()
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        error = nil
        status = nil
    }

    func requestClose() {
        guard let panel, windowShouldClose(panel) else { return }
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !busy else { return false }
        if model.hasUnsavedChanges || audioURL != nil {
            let alert = NSAlert()
            alert.messageText = "Discard this quick edit?"
            alert.informativeText = "Your original screenshot stays in BetterShot. Unsaved annotations and voice will be discarded."
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Discard")
            return alert.runModal() == .alertSecondButtonReturn
        }
        return true
    }

    private func close() {
        discardVoice()
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel?.close()
        panel = nil
        model.releaseEditorResources()
        previousApp?.activate()
        previousApp = nil
    }
}

struct NotchQuickEditorView: View {
    @Bindable var editor: NotchQuickEditor
    var fullScreen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = editor.model.previewImage {
                AnnotationCanvas(model: editor.model, image: image, onEditorInteraction: {})
                    .allowsHitTesting(!editor.busy)
                    .padding(fullScreen ? 0 : 12).padding(.bottom, fullScreen ? 0 : 64)
            }
            if !fullScreen || !NotchVoiceCapture.shared.holdIndicatorActive || editor.error != nil || editor.busy {
            VStack(spacing: 6) {
                if let error = editor.error ?? editor.model.errorMessage {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Keep image without voice") { editor.discardVoice() }.disabled(editor.busy)
                }
                HStack(spacing: 6) {
                    ForEach([AnnotationTool.select, .freehand, .arrow, .blur]) { tool in
                        Button { editor.model.selectTool(tool) } label: { Label(tool.title, systemImage: tool.systemImage) }
                            .tint(editor.model.selectedTool == tool ? .blue : .primary).help(tool.title)
                    }
                    Button { editor.model.toggleCropping() } label: { Label("Crop", systemImage: "crop") }
                        .tint(editor.model.isCropping ? .blue : .primary)
                    if editor.model.isCropping {
                        Button("Apply crop", systemImage: "checkmark") { editor.model.applyCrop() }
                        Button("Cancel crop", systemImage: "xmark") { editor.model.cancelCrop() }
                    } else {
                        Button("Background", systemImage: "square.on.square") {
                            if editor.model.backgroundSettings.isEnabled {
                                editor.model.backgroundSettings = AnnotationBackgroundSettings()
                            } else {
                                editor.model.backgroundSettings = AppPreferences.defaultBeautifierConfig.annotationBackgroundSettings
                                if !editor.model.backgroundSettings.isEnabled { editor.model.backgroundSettings.style = .solid(.graphite) }
                            }
                        }
                        Button("Undo", systemImage: "arrow.uturn.backward") { editor.model.undo() }
                            .disabled(!editor.model.canUndo).keyboardShortcut("z", modifiers: .command)
                        Button(editor.listening ? "Stop voice" : editor.hasVoice ? "Record voice again" : "Voice", systemImage: editor.listening ? "stop.circle.fill" : "mic") {
                            if editor.listening { editor.stopVoice() } else { Task { await editor.startVoice() } }
                        }.tint(editor.listening ? .red : .primary)
                    }
                    Spacer(minLength: 4)
                    if editor.busy { ProgressView().controlSize(.small) }
                    Button("Done") { Task { await editor.finish() } }.labelStyle(.titleOnly)
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Close", systemImage: "xmark") { editor.requestClose() }
                }
                .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.small).disabled(editor.busy)
                if let status = editor.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(12)
            }
        }
        .background(fullScreen ? Color.black : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: fullScreen ? 0 : 22))
        .ignoresSafeArea()
        .onExitCommand {
            if editor.model.isCropping { editor.model.cancelCrop() } else { editor.requestClose() }
        }
    }
}

private final class NotchQuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
