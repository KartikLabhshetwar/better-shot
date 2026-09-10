import AppKit
import UniformTypeIdentifiers

extension ShortcutService {
    func performGlobal(_ action: Action) async {
        guard !isRecordingShortcut else { return }
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        let manager = ScreenRecordingManager.shared
        switch action {
        case .region, .fullscreen, .window, .ocr, .ocrSingleLine, .colorPicker,
             .timedRegion, .regionCopy, .regionSave, .regionEdit, .regionPin:
            await CaptureOrchestrator.shared.performCapture(action, on: screen)
        case .previousRegion:
            if AppPreferences.lastRegionRect != nil {
                await CaptureOrchestrator.shared.captureLastRegion(on: screen)
            } else {
                ToastWindow.shared.show(title: "No previous region", message: "Choose a region in the capture bar first.", systemIcon: "rectangle.dashed", on: screen)
            }
        case .recording, .recordingOptions:
            RecordingBarPresenter.shared.showPicker(recordingOptions: action == .recordingOptions)
        case .recordArea:
            guard !manager.isActive else { return }
            await RecordingBarPresenter.shared.hidePickerForCapture()
            RecordingCaptureEntry.recordArea()
        case .stopRecording:
            guard manager.state == .recording || manager.state == .paused else { return }
            manager.stopRecording()
        case .pauseRecording:
            if manager.state == .paused { manager.resumeRecording() }
            else if manager.state == .recording { manager.pauseRecording() }
        case .restartRecording, .discardRecording:
            guard manager.state == .recording || manager.state == .paused else { return }
            RecordingBarPresenter.shared.recordingConfirmation = action
        case .mediaGallery:
            MediaGalleryWindowController.shared.open(on: screen)
        case .openSettings:
            SettingsWindowController.shared.open(on: screen)
        case .restoreLastCapture, .pinLastCapture:
            let latest = CaptureOrchestrator.shared.lastCaptureURL
            let url = latest.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? HistoryStore.shared.records.first.map { HistoryStore.shared.displayURLForRecord($0) }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                ToastWindow.shared.show(title: "No capture available", message: "Take a screenshot or open Media Gallery to find a saved capture.", systemIcon: "photo", on: screen)
                return
            }
            if action == .pinLastCapture {
                PinnedScreenshotController.shared.pin(url: DeckStaging.promote(url), on: screen)
            } else {
                PreviewOverlay.shared.show(url: url, on: screen, automaticallyDismiss: false)
            }
        case .unpinAll:
            PinnedScreenshotController.shared.unpinAll()
        case .openImage:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = true
            panel.message = "Choose images to annotate in BetterShot."
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK {
                panel.urls.forEach { PreviewPanelPresenter.shared.openEditor(for: $0) }
            }
        case .togglePreviews:
            PreviewOverlay.shared.toggleVisibility()
        case .savePreviews:
            PreviewOverlay.shared.saveAll()
        case .closePreviews:
            let overlay = PreviewOverlay.shared
            if overlay.hasStagedItems {
                let alert = NSAlert()
                alert.messageText = "Close all captures in the deck?"
                alert.informativeText = "Unsaved captures in the deck will be discarded. Saved files are kept."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Discard Unsaved Captures")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertSecondButtonReturn else { return }
            }
            overlay.clearAll()
        default: break // Editor actions are dispatched only by their own window.
        }
    }
}
