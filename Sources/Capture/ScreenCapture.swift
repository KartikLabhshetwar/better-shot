import AppKit
import Vision
import CoreGraphics

@MainActor
@Observable
final class ScreenCapture {
    static let shared = ScreenCapture()

    private(set) var isCapturing = false

    private init() {}

    // MARK: - Fullscreen 

    func captureFullscreen(on screen: NSScreen? = nil) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(200))

        let tempPath = makeTempPath()
        var args = ["-x", "-t", "png"]
        // Without -D, screencapture always grabs the main display, regardless
        // of which one is actually active -- so on a multi-monitor setup a
        // capture triggered with the mouse on a secondary screen would
        // silently save the wrong display's content while the preview card
        // still showed up on the right one. Resolve the same screen the
        // caller already picked (or fall back to the same follow-mouse /
        // pinned-display resolution the preview card uses) and target it
        // explicitly.
        let targetDisplayID = screen.flatMap(ActiveDisplayResolver.displayID(for:))
            ?? ActiveDisplayResolver.screenForScreenshotCapture().flatMap(ActiveDisplayResolver.displayID(for:))
        if let targetDisplayID, let index = ActiveDisplayResolver.screencaptureDisplayIndex(for: targetDisplayID) {
            args.append(contentsOf: ["-D", String(index)])
        }
        args.append(tempPath)

        let success = await runScreencapture(args)
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - Region

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        switch await RegionSelectionOverlay().selectRegion() {
        case .cancelled:
            return nil
        case .window:
            return try await windowShot(includeShadow: false)
        case .region(let selection):
            return try await regionShot(selection.pointsRect)
        }
    }

    /// Captures the remembered rectangle straight away, no selection overlay.
    func captureLastRegion() async throws -> URL? {
        guard !isCapturing, let globalRect = AppPreferences.lastRegionRect else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let pointsRect = RegionGeometry.pointsRect(global: globalRect, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        return try await regionShot(pointsRect)
    }

    private func regionShot(_ pointsRect: CGRect) async throws -> URL? {
        try? await Task.sleep(for: .milliseconds(80))
        let tempPath = makeTempPath()
        let region = RegionGeometry.screencaptureArgument(pointsRect)
        let success = await runScreencapture(["-R", region, "-x", "-t", "png", tempPath])
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - Window (CLI screencapture -w)

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return try await windowShot(includeShadow: includeShadow)
    }

    private func windowShot(includeShadow: Bool) async throws -> URL? {
        let tempPath = makeTempPath()
        var args = ["-w"]
        if !includeShadow { args.append("-o") }
        args.append(contentsOf: ["-x", "-t", "png", tempPath])

        let success = await runScreencapture(args)
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - OCR Region

    func captureAndOCR() async throws -> String? {
        guard let url = try await captureRegion() else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return try await recognizeContent(in: cgImage)
    }

    private func recognizeContent(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true

            let barcodeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([textRequest, barcodeRequest])

                var parts: [String] = []

                // QR/Barcode results first
                if let barcodeResults = barcodeRequest.results {
                    for barcode in barcodeResults {
                        if let payload = barcode.payloadStringValue, !payload.isEmpty {
                            parts.append(payload)
                        }
                    }
                }

                // Text results
                if let textResults = textRequest.results {
                    let text = textResults
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    if !text.isEmpty {
                        parts.append(text)
                    }
                }

                continuation.resume(returning: parts.joined(separator: "\n"))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Sound

    func playShutterSound() {
        guard AppPreferences.playSound else { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let url = URL(fileURLWithPath: path)
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    // MARK: - Helpers

    private func makeTempPath() -> String {
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(dir)bettershot_\(stamp).png"
    }

    private func runScreencapture(_ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
