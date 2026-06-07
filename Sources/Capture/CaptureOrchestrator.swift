import AppKit
import SwiftUI

/// Result of a capture request, returned to programmatic callers (e.g. App Intents)
/// so they can chain the artifact (image file or extracted text) into other workflows.
enum CaptureResult {
    case image(URL)
    case text(String)
    case none
}

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?
    private var captureInProgress = false
    private var pendingCaptures: [(action: ShortcutService.Action, screen: NSScreen?, continuation: CheckedContinuation<CaptureResult, Never>?)] = []
    private var captureScreen: NSScreen?

    private init() {}

    @discardableResult
    func performCapture(_ action: ShortcutService.Action, on screen: NSScreen? = nil) async -> CaptureResult {
        if captureInProgress {
            return await withCheckedContinuation { continuation in
                pendingCaptures.append((action, screen, continuation))
            }
        }
        captureInProgress = true
        captureScreen = screen
        let result = await executeCapture(action)
        while let next = pendingCaptures.first {
            pendingCaptures.removeFirst()
            captureScreen = next.screen
            let nextResult = await executeCapture(next.action)
            next.continuation?.resume(returning: nextResult)
        }
        captureScreen = nil
        captureInProgress = false
        return result
    }

    private func executeCapture(_ action: ShortcutService.Action) async -> CaptureResult {
        switch action {
        case .region:
            return await captureAndProcess { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            return await captureAndProcess { try await ScreenCapture.shared.captureFullscreen() }
        case .window:
            return await captureAndProcess { try await ScreenCapture.shared.captureWindow() }
        case .ocr:
            return await performOCR()
        case .colorPicker:
            return await performColorPick()
        case .recording:
            return .none
        }
    }

    // MARK: - Private

    private func captureAndProcess(_ capture: () async throws -> URL?) async -> CaptureResult {
        let delay = AppPreferences.selfTimerDelay
        if delay != .off {
            await CountdownOverlay.shared.showCountdown(seconds: delay.rawValue)
        }

        do {
            guard let url = try await capture() else { return .none }

            ScreenCapture.shared.playShutterSound()

            let record = HistoryStore.shared.importCapture(from: url)
            if let record {
                lastCaptureURL = HistoryStore.shared.urlForRecord(record)
            }

            guard let capturedURL = lastCaptureURL else { return .none }

            let displayURL = await galleryApplyAndSave(capturedURL, recordID: record?.id)
            return .image(displayURL ?? capturedURL)
        } catch {
            print("Capture failed: \(error.localizedDescription)")
            return .none
        }
    }


    private func performColorPick() async -> CaptureResult {
        let overlay = ColorPickerOverlay()
        guard let hex = await overlay.pickColor() else { return .none }
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
        return .text(hex)
    }

    private func performOCR() async -> CaptureResult {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR() else { return .none }
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
            return .text(text)
        } catch {
            print("OCR failed: \(error.localizedDescription)")
            return .none
        }
    }

    @discardableResult
    private func galleryApplyAndSave(_ url: URL, recordID: UUID? = nil) async -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let config = AppPreferences.defaultBeautifierConfig
        let rendered = BeautifierRenderer.render(image: cgImage, config: config)

        guard let rendered else { return nil }

        let savedURL = saveImage(rendered)

        if let savedURL {
            saveBaseImage(rawURL: url, alongside: savedURL)

            if let recordID {
                HistoryStore.shared.setBeautifiedPath(savedURL.path, for: recordID)
            }
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

        PreviewOverlay.shared.show(url: displayURL, on: captureScreen)
        return displayURL
    }

    private func saveImage(_ cgImage: CGImage) -> URL? {
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

    private func saveBaseImage(rawURL: URL, alongside beautifiedURL: URL) {
        let baseURL = Self.baseImageURL(for: beautifiedURL)
        try? FileManager.default.copyItem(at: rawURL, to: baseURL)
    }

    private static var baseStorageDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BetterShot/bases", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func baseImageURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return baseStorageDir.appendingPathComponent("\(name).base.png")
    }

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
