import AppKit
import Vision
import CoreGraphics
import ScreenCaptureKit

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
        } else {
            // Falling through here means screencapture grabs the main
            // display regardless of which one was actually active -- the
            // exact silent-wrong-display bug this whole fix exists to
            // prevent. Only expected to happen in a narrow race (e.g. the
            // target display disconnected between resolution and the sleep
            // above), but it should be diagnosable if it does.
            print("BetterShot: could not resolve target display for -D; screencapture will fall back to the main display")
        }
        args.append(tempPath)

        let success = try await runScreencapture(args)
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - Region

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let tempPath = makeTempPath()
        let success = try await runScreencapture(["-i", "-o", "-x", "-t", "png", tempPath])
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
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
        let success = try await runScreencapture(["-R", region, "-x", "-t", "png", tempPath])
        guard success, FileManager.default.fileExists(atPath: tempPath) else { return nil }
        return URL(fileURLWithPath: tempPath)
    }

    // MARK: - Window

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let selection = WindowScreenshotPicker()
        let picker = SCContentSharingPicker.shared
        let previousConfiguration = picker.defaultConfiguration
        let wasActive = picker.isActive
        defer {
            picker.remove(selection)
            picker.defaultConfiguration = previousConfiguration
            picker.isActive = wasActive
        }
        guard let filter = try await selection.select() else { return nil }
        return try await windowShot(filter: filter, includeShadow: includeShadow)
    }

    func windowShot(filter: SCContentFilter, includeShadow: Bool = false) async throws -> URL {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = !includeShadow
        configuration.captureResolution = .best
        // Capture directly in the app that owns the picker authorization. The
        // command-line window path can fail to start its capture stream on macOS 26.
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let url = URL(fileURLWithPath: makeTempPath())
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
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
        ScreenshotFileNaming.scratchURL("Capture", extension: "png").path
    }

    private func runScreencapture(_ arguments: [String]) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                let errors = Pipe()
                process.standardError = errors
                do {
                    try process.run()
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: try Self.validateCommandResult(
                        status: process.terminationStatus, diagnostic: String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Interactive cancellation has no diagnostic; actual failures must reach the user.
    nonisolated static func validateCommandResult(status: Int32, diagnostic: String) throws -> Bool {
        if status == 0 { return true }
        let message = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 1 && message.isEmpty { return false }
        throw NSError(domain: "BetterShot.ScreenCapture", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "\(message.isEmpty ? "macOS could not create the screenshot." : message) Try again. If this continues, quit and reopen BetterShot and check Screen & System Audio Recording permission in System Settings."
        ])
    }

}

/// One native selection per screenshot; Escape completes without creating a file.
@MainActor
private final class WindowScreenshotPicker: NSObject, SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<SCContentFilter?, Error>?

    func select() async throws -> SCContentFilter? {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.allowsChangingSelectedContent = false
        configuration.excludedWindowIDs = NSApp.windows.filter { $0.sharingType == .none }.map { $0.windowNumber }
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        return try await withCheckedThrowingContinuation {
            continuation = $0
            picker.present(using: .window)
        }
    }

    private func finish(_ result: Result<SCContentFilter?, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor in self.finish(.success(nil)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,
                                         didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor in self.finish(.success(filter)) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
