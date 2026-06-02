import AppKit
import ScreenCaptureKit
import Vision

/// Handles all screenshot capture methods.
@MainActor
@Observable
final class ScreenCapture {
    static let shared = ScreenCapture()

    private(set) var isCapturing = false

    private init() {}

    // MARK: - Region (Interactive)

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let tempPath = makeTempPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempPath]

        try process.run()
        process.waitUntilExit()

        let url = URL(fileURLWithPath: tempPath)
        guard FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return url
    }

    // MARK: - Fullscreen

    func captureFullscreen() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let tempPath = makeTempPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", tempPath]

        try process.run()
        process.waitUntilExit()

        let url = URL(fileURLWithPath: tempPath)
        guard FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return url
    }

    // MARK: - Window

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let tempPath = makeTempPath()
        var args = ["-w", "-x"]
        if !includeShadow { args.append("-o") }
        args.append(tempPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        try process.run()
        process.waitUntilExit()

        let url = URL(fileURLWithPath: tempPath)
        guard FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return url
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
        if let sound = NSSound(named: "Blow") {
            sound.play()
        }
    }

    // MARK: - Helpers

    private func makeTempPath() -> String {
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(dir)bettershot_\(stamp).png"
    }
}
