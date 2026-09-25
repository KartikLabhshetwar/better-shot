import AppKit
import SwiftUI

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?
    private(set) var captureInProgress = false
    private var pendingCaptures: [(ShortcutService.Action, NSScreen?)] = []
    private var captureScreen: NSScreen?

    private init() {}

    func performCapture(_ action: ShortcutService.Action, on screen: NSScreen? = nil) async {
        guard !NotchVoiceCapture.shared.isPreparing, !NotchQuickEditor.shared.listening else { return }
        if action == .scrollCapture, ScrollCaptureSessionPresenter.shared.isActive {
            ScrollCaptureSessionPresenter.shared.stop()
            return
        }
        if captureInProgress {
            pendingCaptures.append((action, screen))
            return
        }
        NotchPresenter.shared.suspendForCapture()
        captureInProgress = true
        captureScreen = screen
        await executeCapture(action)
        await finishCaptures()
    }

    private func finishCaptures() async {
        while let (next, nextScreen) = pendingCaptures.first {
            pendingCaptures.removeFirst()
            captureScreen = nextScreen
            await executeCapture(next)
        }
        captureScreen = nil
        captureInProgress = false
        NotchPresenter.shared.resumeAfterCapture()
    }

    func captureLastRegion(on screen: NSScreen? = nil) async {
        guard !captureInProgress, AppPreferences.lastRegionRect != nil else { return }
        NotchPresenter.shared.suspendForCapture()
        captureInProgress = true
        captureScreen = screen
        await RecordingBarPresenter.shared.hidePickerForCapture()
        await captureAndProcess { try await ScreenCapture.shared.captureLastRegion() }
        await finishCaptures()
    }

    private func performScrollCapture() async {
        let outcome = await RegionSelectionOverlay().selectRegion(allowsWindowSelection: false)
        guard case .region(let selection) = outcome,
              let selectedScreen = ActiveDisplayResolver.screen(for: selection.displayID) else { return }
        captureScreen = selectedScreen
        let rect = RegionGeometry.pointsRect(global: selection.pointsRect,
            primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        switch await ScrollCaptureSessionPresenter.shared.capture(rect: rect, on: selectedScreen) {
        case .completed(let image):
            do {
                let url = try await Self.writeScrollImage(image)
                ScreenCapture.shared.playShutterSound()
                await processCapturedImage(url, action: .scrollCapture)
            } catch {
                ToastWindow.shared.show(isError: true, title: "Couldn’t finish scrolling capture",
                    message: "The image could not be prepared. Select the area and try again. \(error.localizedDescription)",
                    systemIcon: "exclamationmark.triangle", duration: 10, on: selectedScreen)
            }
        case .failed:
            ToastWindow.shared.show(isError: true, title: "Couldn’t capture scrolling area",
                message: "Check Screen & System Audio Recording permission, then select the area and try again.",
                systemIcon: "exclamationmark.triangle", duration: 10, on: selectedScreen)
        case .cancelled:
            break
        }
    }

    private nonisolated static func writeScrollImage(_ image: CGImage) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bettershot_scroll_\(UUID().uuidString).png")
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url, options: .atomic)
            return url
        }.value
    }

    private func executeCapture(_ action: ShortcutService.Action) async {
        if action != .recording {
            await RecordingBarPresenter.shared.hidePickerForCapture()
        }
        switch action {
        case .region, .timedRegion, .regionCopy, .regionSave, .regionEdit, .regionPin:
            await captureAndProcess(action: action) { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            await captureAndProcess(action: action) { try await ScreenCapture.shared.captureFullscreen(on: captureScreen) }
        case .window:
            await captureAndProcess(action: action) { try await ScreenCapture.shared.captureWindow() }
        case .scrollCapture:
            await performScrollCapture()
        case .ocr, .ocrSingleLine:
            await performOCR(singleLine: action == .ocrSingleLine)
        case .colorPicker:
            await performColorPick()
        default:
            break
        }
    }

    // MARK: - Private

    private func captureAndProcess(action: ShortcutService.Action = .region, _ capture: () async throws -> URL?) async {
        let delay = action == .timedRegion ? max(3, AppPreferences.selfTimerDelay.rawValue) : AppPreferences.selfTimerDelay.rawValue
        if delay > 0 {
            await CountdownOverlay.shared.showCountdown(seconds: delay, on: captureScreen)
        }

        do {
            guard let url = try await capture() else { return }

            ScreenCapture.shared.playShutterSound()

            await processCapturedImage(url, action: action)
        } catch {
            ToastWindow.shared.show(isError: true, title: "Couldn’t capture screenshot", message: error.localizedDescription,
                systemIcon: "exclamationmark.triangle", duration: 10, on: captureScreen)
        }
    }


    private func performColorPick() async {
        do {
            let overlay = ColorPickerOverlay()
            guard let hex = try await overlay.pickColor() else { return }
            completeTextCapture(hex, action: .colorPicker)
        } catch {
            ToastWindow.shared.show(isError: true, title: "Couldn’t pick color", message: error.localizedDescription,
                systemIcon: "eyedropper", on: captureScreen)
        }
    }

    private func performOCR(singleLine: Bool = false) async {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR() else { return }
            completeTextCapture(text, action: singleLine ? .ocrSingleLine : .ocr)
        } catch {
            ToastWindow.shared.show(isError: true, title: "Couldn’t recognize text", message: error.localizedDescription,
                systemIcon: "doc.text.viewfinder", on: captureScreen)
        }
    }

    /// Keep the exact clipboard value available for copying again from the notch.
    func completeTextCapture(_ text: String, action: ShortcutService.Action, pasteboard: NSPasteboard = .general) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastWindow.shared.show(isError: true, title: "No text found", message: "Try selecting a clearer text area.",
                systemIcon: "doc.text.viewfinder", on: captureScreen)
            return
        }
        let value = action == .ocrSingleLine ? text.split(whereSeparator: \.isNewline).joined(separator: " ") : text
        let isColor = action == .colorPicker
        let notch = NotchPresenter.shared
        notch.captureIssue = nil
        if AppPreferences.presentationMode == .notch {
            if isColor { notch.colorHex = value } else { notch.ocrText = value }
            NotchShelfStore.shared.add(text: value, isColor: isColor)
        }
        let copied = Self.copyText(value, to: pasteboard)
        ScreenCapture.shared.playShutterSound()
        if AppPreferences.presentationMode == .notch {
            notch.show(on: captureScreen)
        }
        ToastWindow.shared.show(isError: !copied, title: copied ? "Copied" : "Couldn’t copy",
            message: copied ? (isColor ? "\(value) copied to clipboard" : "Text copied to clipboard") : "Try Copy again.",
            systemIcon: isColor ? "eyedropper" : "doc.text.viewfinder", on: captureScreen)
    }

    @discardableResult
    static func copyText(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Every screenshot starts privately; normal captures can opt into automatic saving.
    func processCapturedImage(_ url: URL, action: ShortcutService.Action = .region) async {
        let stagedURL = await stageCapture(url)
        var displayURL = AppPreferences.keepInDeckUntilSaved ? stagedURL : DeckStaging.retain(stagedURL)
        if displayURL != stagedURL { DeckStaging.discard(stagedURL) }
        let allowsAutomaticSave: Bool = switch action {
        case .region, .fullscreen, .window, .previousRegion, .timedRegion, .scrollCapture: true
        default: false
        }
        var saveFailed = false
        if allowsAutomaticSave && AfterCaptureActions.isEnabled(.save, for: .screenshot) {
            do {
                // A staging failure leaves only the original; keep it available for retry.
                guard DeckStaging.isStaged(stagedURL) else { throw CocoaError(.fileWriteUnknown) }
                let savedURL = try ScreenshotFileActions.saveCapture(from: displayURL)
                DeckStaging.discard(displayURL)
                displayURL = savedURL
            } catch {
                saveFailed = true
            }
        }
        lastCaptureURL = displayURL

        if action == .regionCopy || (action != .regionSave && AppPreferences.copyAfterSave) {
            do {
                try ScreenshotFileActions.copyImageToClipboard(from: displayURL)
            } catch {
                ToastWindow.shared.show(isError: true, title: "Copy Failed", message: error.localizedDescription,
                    systemIcon: "exclamationmark.triangle", on: captureScreen)
            }
        }

        PreviewOverlay.shared.show(url: displayURL, on: captureScreen)
        if saveFailed {
            PreviewOverlay.shared.showSaveFailure(for: displayURL)
            return
        }
        if action == .regionSave {
            PreviewOverlay.shared.save(displayURL)
        } else if action == .regionPin {
            let retainedURL = DeckStaging.retain(displayURL)
            guard !DeckStaging.isStaged(retainedURL) else { return }
            PinnedScreenshotController.shared.pin(url: retainedURL, on: captureScreen)
            PreviewOverlay.shared.remove(displayURL)
        } else if action == .regionEdit || (AppPreferences.openEditorAfterCapture && action != .regionCopy) {
            PreviewOverlay.shared.openAnnotateEditor(for: displayURL)
        }
    }

    private func stageCapture(_ url: URL) async -> URL {
        let config = AppPreferences.defaultBeautifierConfig
        let stagedURL = await Task.detached { () -> URL? in
            guard (try? DeckStaging.prepareDirectory()) != nil,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let rendered = BeautifierRenderer.render(image: cgImage, config: config) else { return nil }
            return Self.saveImage(rendered, in: DeckStaging.directory.path)
        }.value

        guard let stagedURL else {
            ToastWindow.shared.show(isError: true, title: "Couldn’t prepare capture",
                message: "The original screenshot is still available in the preview.",
                systemIcon: "exclamationmark.triangle", on: captureScreen)
            return url
        }
        do {
            try FileManager.default.moveItem(at: url, to: DeckStaging.rawURL(for: stagedURL))
            return stagedURL
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            return url
        }
    }

    nonisolated static func saveImage(_ cgImage: CGImage, in dir: String) -> URL? {
        let format = AppPreferences.exportFormat
        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        let url = directory.appendingPathComponent("bettershot_\(UUID().uuidString).\(format.fileExtension)")
        let stagingURL = directory.appendingPathComponent(".\(url.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            stagingURL as CFURL,
            format.utType as CFString,
            1, nil
        ) else { return nil }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = AppPreferences.exportQuality
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        do {
            // Rename only a complete image; moveItem refuses to overwrite an existing file.
            try FileManager.default.moveItem(at: stagingURL, to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Legacy home of duplicated raw copies. Nothing writes here any more; kept so old captures still resolve.
    static var baseStorageDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BetterShot/bases", isDirectory: true)
    }

    static func baseImageURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return baseStorageDir.appendingPathComponent("\(name).base.png")
    }

    /// Maps a saved/beautified image back to the untouched capture the editor should load.
    static func resolveRawSource(for url: URL) -> URL {
        let baseURL = baseImageURL(for: url)
        if FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        // Legacy: check alongside the file for old .base.png files
        let legacyDir = url.deletingLastPathComponent()
        let legacyName = url.deletingPathExtension().lastPathComponent
        let legacyURL = legacyDir.appendingPathComponent("\(legacyName).base.png")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        if let record = HistoryStore.shared.records.first(where: { $0.beautifiedPath == url.path }) {
            let rawURL = HistoryStore.shared.urlForRecord(record)
            if FileManager.default.fileExists(atPath: rawURL.path) {
                return rawURL
            }
        }
        return url
    }

}
