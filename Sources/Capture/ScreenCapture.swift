import AppKit
import Vision
import CoreGraphics

/// Handles screenshot capture using CoreGraphics APIs where possible,
/// falling back to screencapture CLI for interactive selection.
@MainActor
@Observable
final class ScreenCapture {
    static let shared = ScreenCapture()

    private(set) var isCapturing = false

    private init() {}

    // MARK: - Fullscreen (CoreGraphics — no permission dialog)

    func captureFullscreen() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Let menu bar popover fully dismiss so it's not captured
        try? await Task.sleep(for: .milliseconds(200))

        let tempPath = makeTempPath()
        // -x: no sound, -m: main monitor only
        let exitCode = try await runScreenCapture(args: ["-x", "-m", tempPath])

        if exitCode != 0 {
            print("screencapture fullscreen exited with code \(exitCode)")
        }

        guard FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - Region (Interactive — uses screencapture CLI)

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(150))

        // Show custom selection overlay
        let overlay = RegionSelectionOverlay()
        guard let selectedRect = await overlay.selectRegion() else { return nil }
        guard selectedRect.width > 1, selectedRect.height > 1 else { return nil }

        // Capture the screen region at the selected coordinates
        guard let fullImage = CGWindowListCreateImage(
            selectedRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        let tempPath = makeTempPath()
        let url = URL(fileURLWithPath: tempPath)
        guard saveCGImage(fullImage, to: url) else { return nil }
        return url
    }

    // MARK: - Window (Interactive — uses screencapture CLI)

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(200))

        let tempPath = makeTempPath()
        var args = ["-w", "-x"]
        if !includeShadow { args.append("-o") }
        args.append(tempPath)

        let exitCode = try await runScreenCapture(args: args)

        if exitCode != 0 {
            print("screencapture window exited with code \(exitCode)")
        }

        guard FileManager.default.fileExists(atPath: tempPath) else { return nil }
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

        return try await performOCR(on: cgImage)
    }

    private func performOCR(on image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
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

    private func runScreenCapture(args: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func saveCGImage(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
