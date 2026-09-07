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
        await captureAndProcess { try await ScreenCapture.shared.captureLastRegion() }
        await finishCaptures()
    }

    private func executeCapture(_ action: ShortcutService.Action) async {
        switch action {
        case .region:
            await captureAndProcess { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            await captureAndProcess { try await ScreenCapture.shared.captureFullscreen() }
        case .window:
            await captureAndProcess { try await ScreenCapture.shared.captureWindow() }
        case .ocr:
            await performOCR()
        case .colorPicker:
            await performColorPick()
        case .recording:
            break
        }
    }

    // MARK: - Private

    private func captureAndProcess(_ capture: () async throws -> URL?) async {
        let delay = AppPreferences.selfTimerDelay
        if delay != .off {
            await CountdownOverlay.shared.showCountdown(seconds: delay.rawValue, on: captureScreen)
        }

        do {
            guard let url = try await capture() else { return }

            ScreenCapture.shared.playShutterSound()

            if AppPreferences.keepInDeckUntilSaved, !AppPreferences.openEditorAfterCapture {
                await stageForDeck(url)
                return
            }

            guard let record = HistoryStore.shared.importCapture(from: url) else {
                // Keep this capture available even when the history directory is unwritable.
                lastCaptureURL = url
                PreviewOverlay.shared.show(url: url, on: captureScreen)
                ToastWindow.shared.show(title: "Couldn’t save capture", message: "The screenshot is still available in the preview.", systemIcon: "exclamationmark.triangle", on: captureScreen)
                return
            }
            let capturedURL = HistoryStore.shared.urlForRecord(record)
            lastCaptureURL = capturedURL
            await applyAndSave(capturedURL, recordID: record.id)
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

    private func performOCR() async {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
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

    private func stageForDeck(_ url: URL) async {
        let config = AppPreferences.defaultBeautifierConfig

        let stagedURL = await Task.detached { () -> URL? in
            guard (try? DeckStaging.prepareDirectory()) != nil,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let rendered = BeautifierRenderer.render(image: cgImage, config: config) else { return nil }
            return Self.saveImage(rendered, in: DeckStaging.directory.path)
        }.value

        guard let stagedURL else {
            lastCaptureURL = url
            PreviewOverlay.shared.show(url: url, on: captureScreen)
            ToastWindow.shared.show(title: "Couldn’t prepare capture", message: "The original screenshot is still available in the preview.", systemIcon: "exclamationmark.triangle", on: captureScreen)
            return
        }

        do {
            try FileManager.default.moveItem(at: url, to: DeckStaging.rawURL(for: stagedURL))
        } catch {
            // Preserve the original if staging its editable source fails.
            try? FileManager.default.removeItem(at: stagedURL)
            lastCaptureURL = url
            PreviewOverlay.shared.show(url: url, on: captureScreen)
            return
        }
        lastCaptureURL = stagedURL
        PreviewOverlay.shared.show(url: stagedURL, on: captureScreen)
    }

    private func applyAndSave(_ url: URL, recordID: UUID) async {
        let config = AppPreferences.defaultBeautifierConfig
        let saveDirectory = AppPreferences.saveDirectory

        let savedURL = await Task.detached { () -> URL? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let rendered = BeautifierRenderer.render(image: cgImage, config: config) else { return nil }
            return Self.saveImage(rendered, in: saveDirectory)
        }.value

        // A deleted capture must not reappear after a delayed render, even if saving failed.
        guard HistoryStore.shared.records.contains(where: { $0.id == recordID }) else {
            if let savedURL { try? FileManager.default.removeItem(at: savedURL) }
            return
        }
        if let savedURL {
            HistoryStore.shared.setBeautifiedPath(savedURL.path, for: recordID)
        } else {
            ToastWindow.shared.show(title: "Couldn’t save the edited image", message: "The original screenshot is still available in the preview.", systemIcon: "exclamationmark.triangle", on: captureScreen)
        }

        if AppPreferences.copyAfterSave, let savedURL {
            copyToClipboard(savedURL)
        }

        let displayURL = savedURL ?? url

        if savedURL != nil {
            let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
            ToastWindow.shared.show(
                message: AppPreferences.copyAfterSave ? "Screenshot saved & copied!" : "Screenshot saved!",
                icon: appIcon,
                on: captureScreen
            )
        }

        if AppPreferences.openEditorAfterCapture {
            PreviewPanelPresenter.shared.openEditor(for: displayURL)
        } else {
            PreviewOverlay.shared.show(url: displayURL, on: captureScreen)
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

    private func copyToClipboard(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }
}
