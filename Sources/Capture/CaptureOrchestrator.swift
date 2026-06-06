import AppKit
import SwiftUI

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?
    private var captureInProgress = false
    private var pendingCaptures: [ShortcutService.Action] = []

    private init() {}

    func performCapture(_ action: ShortcutService.Action) async {
        if captureInProgress {
            pendingCaptures.append(action)
            return
        }
        captureInProgress = true
        await executeCapture(action)
        while let next = pendingCaptures.first {
            pendingCaptures.removeFirst()
            await executeCapture(next)
        }
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
        case .repeatRegion:
            await captureAndProcess { try await ScreenCapture.shared.repeatRegionCapture() }
        }
    }

    // MARK: - Private

    private func captureAndProcess(_ capture: () async throws -> URL?) async {
        let delay = AppPreferences.selfTimerDelay
        if delay != .off {
            await CountdownOverlay.shared.showCountdown(seconds: delay.rawValue)
        }

        do {
            guard let url = try await capture() else { return }

            ScreenCapture.shared.playShutterSound()

            let record = HistoryStore.shared.importCapture(from: url)
            if let record {
                lastCaptureURL = HistoryStore.shared.urlForRecord(record)
            }

            guard let capturedURL = lastCaptureURL else { return }

            switch AppPreferences.screenshotMode {
            case .editor:
                EditorWindowController.shared.open(url: capturedURL)
            case .gallery:
                await galleryApplyAndSave(capturedURL)
            }
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
            systemIcon: "eyedropper"
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
                systemIcon: "doc.text.viewfinder"
            )
        } catch {
            print("OCR failed: \(error.localizedDescription)")
        }
    }

    private func galleryApplyAndSave(_ url: URL) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }

        let config = AppPreferences.defaultBeautifierConfig
        let rendered = BeautifierRenderer.render(image: cgImage, config: config)

        guard let rendered else { return }

        let savedURL = saveImage(rendered)

        if AppPreferences.copyAfterSave, let savedURL {
            copyToClipboard(savedURL)
        }

        if let savedURL, AppPreferences.showOverlayAfterCapture {
            PreviewOverlay.shared.show(url: savedURL)
        }

        if savedURL != nil {
            let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
            ToastWindow.shared.show(message: "Screenshot saved to gallery!", icon: appIcon)
        }
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

    private func copyToClipboard(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }
}
