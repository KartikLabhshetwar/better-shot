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
        while let (next, nextScreen) = pendingCaptures.first {
            pendingCaptures.removeFirst()
            captureScreen = nextScreen
            await executeCapture(next)
        }
        captureScreen = nil
        captureInProgress = false
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

            let record = HistoryStore.shared.importCapture(from: url)
            if let record {
                lastCaptureURL = HistoryStore.shared.urlForRecord(record)
            }

            guard let capturedURL = lastCaptureURL else { return }

            await galleryApplyAndSave(capturedURL, recordID: record?.id)
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

    private func galleryApplyAndSave(_ url: URL, recordID: UUID? = nil) async {
        let config = AppPreferences.defaultBeautifierConfig

        let (didRender, savedURL) = await Task.detached { () -> (Bool, URL?) in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let rendered = BeautifierRenderer.render(image: cgImage, config: config) else { return (false, nil) }
            return (true, Self.saveImage(rendered))
        }.value

        guard didRender else { return }

        if let savedURL, let recordID {
            HistoryStore.shared.setBeautifiedPath(savedURL.path, for: recordID)
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
            let ext = displayURL.pathExtension.lowercased()
            if ext == "mov" || ext == "mp4" {
                VideoEditorWindowController.shared.open(url: displayURL, on: captureScreen)
            } else {
                EditorWindowController.shared.open(url: displayURL, on: captureScreen)
            }
        } else {
            PreviewOverlay.shared.show(url: displayURL, on: captureScreen)
        }
    }

    private nonisolated static func saveImage(_ cgImage: CGImage) -> URL? {
        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = AppPreferences.exportFormat.fileExtension
        let path = "\(dir)/bettershot_\(stamp).\(ext)"
        let url = URL(fileURLWithPath: path)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            AppPreferences.exportFormat.utType as CFString,
            1, nil
        ) else { return nil }

        var options: [CFString: Any] = [:]
        if AppPreferences.exportFormat == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = AppPreferences.exportQuality
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
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
