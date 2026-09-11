import AppKit
import SwiftUI

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?
    private var captureInProgress = false
    private var pendingCaptures: [(ShortcutService.Action, NSScreen?)] = []
    private var captureScreen: NSScreen?

    private init() {}

    func performCapture(_ action: ShortcutService.Action, on screen: NSScreen? = nil) async {
        if captureInProgress {
            pendingCaptures.append((action, screen))
            return
        }
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
    }

    func captureLastRegion(on screen: NSScreen? = nil) async {
        guard !captureInProgress, AppPreferences.lastRegionRect != nil else { return }
        captureInProgress = true
        captureScreen = screen
        await RecordingBarPresenter.shared.hidePickerForCapture()
        await captureAndProcess { try await ScreenCapture.shared.captureLastRegion() }
        await finishCaptures()
    }

    private func executeCapture(_ action: ShortcutService.Action) async {
        if action != .recording {
            await RecordingBarPresenter.shared.hidePickerForCapture()
        }
        switch action {
        case .region, .timedRegion, .regionCopy, .regionSave, .regionEdit, .regionPin:
            await captureAndProcess(action: action) { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            await captureAndProcess { try await ScreenCapture.shared.captureFullscreen() }
        case .window:
            await captureAndProcess { try await ScreenCapture.shared.captureWindow() }
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
            print("Capture failed: \(error.localizedDescription)")
        }
    }


    private func performColorPick() async {
        let overlay = ColorPickerOverlay()
        guard let hex = await overlay.pickColor() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
        ScreenCapture.shared.playShutterSound()
        ToastWindow.shared.show(
            title: "Copied",
            message: "\(hex) copied to clipboard",
            systemIcon: "eyedropper",
            on: captureScreen
        )
    }

    private func performOCR(singleLine: Bool = false) async {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(singleLine ? text.split(whereSeparator: \.isNewline).joined(separator: " ") : text, forType: .string)
            ScreenCapture.shared.playShutterSound()
            ToastWindow.shared.show(
                title: "Copied",
                message: "Text copied to clipboard",
                systemIcon: "doc.text.viewfinder",
                on: captureScreen
            )
        } catch {
            print("OCR failed: \(error.localizedDescription)")
        }
    }

    /// Every screenshot starts in private staging; only an explicit Save exports it.
    func processCapturedImage(_ url: URL, action: ShortcutService.Action = .region) async {
        let stagedURL = await stageCapture(url)
        let displayURL = AppPreferences.keepInDeckUntilSaved ? stagedURL : DeckStaging.retain(stagedURL)
        if displayURL != stagedURL { DeckStaging.discard(stagedURL) }
        lastCaptureURL = displayURL

        if action == .regionCopy || (action != .regionSave && AppPreferences.copyAfterSave) {
            do {
                try ScreenshotFileActions.copyImageToClipboard(from: displayURL)
            } catch {
                ToastWindow.shared.show(title: "Copy Failed", message: error.localizedDescription,
                    systemIcon: "exclamationmark.triangle", on: captureScreen)
            }
        }

        PreviewOverlay.shared.show(url: displayURL, on: captureScreen)
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
            ToastWindow.shared.show(title: "Couldn’t prepare capture",
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
