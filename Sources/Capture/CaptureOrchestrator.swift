import AppKit
import SwiftUI

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?

    private init() {}

    func performCapture(_ action: ShortcutService.Action) async {
        switch action {
        case .region:
            await captureAndProcess { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            await captureAndProcess { try await ScreenCapture.shared.captureFullscreen() }
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
        // Show countdown overlay for self-timer, then proceed with capture
        let delay = AppPreferences.selfTimerDelay
        if delay != .off {
            await CountdownOverlay.shared.showCountdown(seconds: delay.rawValue)
        }

        do {
            guard let url = try await capture() else { return }

            ScreenCapture.shared.playShutterSound()

            // Import to history
            let record = HistoryStore.shared.importCapture(from: url)
            if let record {
                lastCaptureURL = HistoryStore.shared.urlForRecord(record)
            }

            if AppPreferences.autoApplyBackground {
                // Auto-apply default background and save
                if let capturedURL = lastCaptureURL {
                    await autoApplyAndSave(capturedURL)
                }
            } else if AppPreferences.showOverlayAfterCapture {
                // Show floating preview
                if let capturedURL = lastCaptureURL {
                    PreviewOverlay.shared.show(url: capturedURL)
                }
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
    }

    private func performOCR() async {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            ScreenCapture.shared.playShutterSound()
        } catch {
            print("OCR failed: \(error.localizedDescription)")
        }
    }

    private func autoApplyAndSave(_ url: URL) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }

        let config = loadDefaultBeautifierConfig()
        let rendered = BeautifierRenderer.render(image: cgImage, config: config)

        guard let rendered else { return }

        let savedURL = saveImage(rendered)

        if AppPreferences.copyAfterSave, let savedURL {
            copyToClipboard(savedURL)
        }

        if let savedURL, AppPreferences.showOverlayAfterCapture {
            PreviewOverlay.shared.show(url: savedURL)
        }
    }

    private func loadDefaultBeautifierConfig() -> BeautifierConfig {
        AppPreferences.defaultBeautifierConfig
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
