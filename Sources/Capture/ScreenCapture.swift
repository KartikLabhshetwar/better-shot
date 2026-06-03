import AppKit
import ScreenCaptureKit
import Vision
import CoreGraphics

@MainActor
@Observable
final class ScreenCapture {
    static let shared = ScreenCapture()

    private(set) var isCapturing = false
    private(set) var lastRegionSelection: RegionSelection?

    private init() {}

    // MARK: - Fullscreen (SCScreenshotManager)

    func captureFullscreen() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(200))

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = displayUnderCursor(from: content.displays) ?? content.displays.first else { return nil }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsDisplay = true
        config.ignoreGlobalClipDisplay = true

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let tempPath = makeTempPath()
        let url = URL(fileURLWithPath: tempPath)
        guard saveCGImage(cgImage, to: url) else { return nil }
        return url
    }

    // MARK: - Region (capture full display, crop in code — pixel-perfect, no scaling)

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(150))

        let overlay = RegionSelectionOverlay()
        guard let selection = await overlay.selectRegion() else { return nil }
        guard selection.pointsRect.width > 1, selection.pointsRect.height > 1 else { return nil }
        lastRegionSelection = selection

        // Wait for overlay windows to fully dismiss from the window server
        try? await Task.sleep(for: .milliseconds(400))

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { display in
            let displayRect = CGRect(x: display.frame.origin.x, y: display.frame.origin.y,
                                     width: display.frame.width, height: display.frame.height)
            return displayRect.intersects(selection.pointsRect)
        }) ?? displayUnderCursor(from: content.displays) ?? content.displays.first else { return nil }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let scale = CGFloat(filter.pointPixelScale)

        // Capture the FULL display at native retina resolution — no sourceRect, no scaling
        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsDisplay = true
        config.ignoreGlobalClipDisplay = true

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // Crop to the selected region in pixel coordinates — zero interpolation
        let displayOrigin = display.frame.origin
        let localPoints = CGRect(
            x: selection.pointsRect.origin.x - displayOrigin.x,
            y: selection.pointsRect.origin.y - displayOrigin.y,
            width: selection.pointsRect.width,
            height: selection.pointsRect.height
        )

        let cropRect = CGRect(
            x: localPoints.origin.x * scale,
            y: localPoints.origin.y * scale,
            width: localPoints.width * scale,
            height: localPoints.height * scale
        ).integral

        guard let croppedImage = fullImage.cropping(to: cropRect) else { return nil }

        let tempPath = makeTempPath()
        let url = URL(fileURLWithPath: tempPath)
        guard saveCGImage(croppedImage, to: url) else { return nil }
        return url
    }

    // MARK: - Repeat Region (reuse last selection)

    func repeatRegionCapture() async throws -> URL? {
        guard let selection = lastRegionSelection else { return try await captureRegion() }
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        try? await Task.sleep(for: .milliseconds(200))

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { display in
            let displayRect = CGRect(x: display.frame.origin.x, y: display.frame.origin.y,
                                     width: display.frame.width, height: display.frame.height)
            return displayRect.intersects(selection.pointsRect)
        }) ?? displayUnderCursor(from: content.displays) ?? content.displays.first else { return nil }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        config.captureResolution = .best
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsDisplay = true
        config.ignoreGlobalClipDisplay = true

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let displayOrigin = display.frame.origin
        let localPoints = CGRect(
            x: selection.pointsRect.origin.x - displayOrigin.x,
            y: selection.pointsRect.origin.y - displayOrigin.y,
            width: selection.pointsRect.width,
            height: selection.pointsRect.height
        )
        let cropRect = CGRect(
            x: localPoints.origin.x * scale,
            y: localPoints.origin.y * scale,
            width: localPoints.width * scale,
            height: localPoints.height * scale
        ).integral

        guard let croppedImage = fullImage.cropping(to: cropRect) else { return nil }

        let tempPath = makeTempPath()
        let url = URL(fileURLWithPath: tempPath)
        guard saveCGImage(croppedImage, to: url) else { return nil }
        return url
    }

    // MARK: - Window (SCScreenshotManager + window picker)

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let capturable = content.windows.filter {
            $0.owningApplication?.bundleIdentifier != ownBundleID
            && $0.isOnScreen
            && $0.frame.width >= 50
            && $0.frame.height >= 50
        }

        guard !capturable.isEmpty else { return nil }

        let picker = WindowPickerOverlay(windows: capturable)
        guard let selected = await picker.pickWindow() else { return nil }

        try? await Task.sleep(for: .milliseconds(350))

        let freshContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let freshWindow = freshContent.windows.first { $0.windowID == selected.windowID }
        let targetWindow = freshWindow ?? selected

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)

        let scale = CGFloat(filter.pointPixelScale)
        let contentSize = filter.contentRect.size
        let w = Int(contentSize.width * scale)
        let h = Int(contentSize.height * scale)
        guard w > 0, h > 0 else { return nil }

        let config = SCStreamConfiguration()
        config.width = w % 2 == 0 ? w : w + 1
        config.height = h % 2 == 0 ? h : h + 1
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.backgroundColor = .clear
        config.shouldBeOpaque = false
        config.ignoreShadowsSingleWindow = !includeShadow
        config.ignoreGlobalClipSingleWindow = true
        if #available(macOS 14.2, *) {
            config.includeChildWindows = true
        }

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let tempPath = makeTempPath()
        let url = URL(fileURLWithPath: tempPath)
        guard saveCGImage(cgImage, to: url) else { return nil }
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
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(dir)bettershot_\(stamp).png"
    }

    private func saveCGImage(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func displayUnderCursor(from displays: [SCDisplay]) -> SCDisplay? {
        var mousePoint = CGPoint.zero
        let event = CGEvent(source: nil)
        if let event {
            mousePoint = event.location
        }

        return displays.first { display in
            CGDisplayBounds(display.displayID).contains(mousePoint)
        }
    }
}
