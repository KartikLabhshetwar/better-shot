import AppKit
import SwiftUI
@preconcurrency import ScreenCaptureKit

/// Scrolling capture (long screenshot) — CleanShot X style.
/// User selects a region, then scrolls manually (or lets the app auto-scroll);
/// frames are captured continuously and stitched vertically by pixel matching.
@MainActor
@Observable
final class ScrollingCaptureController {
    static let shared = ScrollingCaptureController()

    enum State { case idle, selecting, capturing }

    private(set) var state: State = .idle
    private(set) var stitchedHeightPoints: Int = 0
    private(set) var isAutoScrolling = false

    private var stitcher: ScrollStitcher?
    private var filter: SCContentFilter?
    private var sourceRect: CGRect = .zero
    private var capturePixelSize: CGSize = .zero
    private var regionPointsRect: CGRect = .zero   // global, top-left origin
    private var scaleFactor: CGFloat = 2

    private var captureTask: Task<Void, Never>?
    private var autoScrollTask: Task<Void, Never>?
    private var hudPanel: NSPanel?
    private var borderWindow: NSWindow?
    private var escMonitor: Any?
    private var targetScreen: NSScreen?

    private init() {}

    // MARK: - Lifecycle

    func start(on screen: NSScreen? = nil) async {
        guard state == .idle else { return }
        targetScreen = screen
        state = .selecting

        let overlay = RegionSelectionOverlay()
        guard let selection = await overlay.selectRegion() else {
            state = .idle
            return
        }

        do {
            try await prepareCapture(selection: selection)
        } catch {
            print("Scrolling capture setup failed: \(error.localizedDescription)")
            state = .idle
            return
        }

        regionPointsRect = selection.pointsRect
        scaleFactor = selection.scaleFactor
        stitcher = ScrollStitcher()
        stitchedHeightPoints = 0

        showBorder()
        showHUD()
        installEscMonitor()

        state = .capturing
        startFrameLoop()
    }

    func finish() {
        guard state == .capturing else { return }
        stopLoops()

        let stitcher = self.stitcher
        let screen = targetScreen
        cleanupUI()
        state = .idle

        guard let image = stitcher?.compose() else { return }

        Task {
            await CaptureOrchestrator.shared.finishExternalCapture(cgImage: image, on: screen)
        }
        self.stitcher = nil
    }

    func cancel() {
        stopLoops()
        cleanupUI()
        stitcher = nil
        state = .idle
    }

    func toggleAutoScroll() {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startAutoScroll()
        }
    }

    // MARK: - Capture Setup

    private func prepareCapture(selection: RegionSelection) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "BetterShot", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        // Exclude our own windows (HUD, border) so they never contaminate frames.
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let contentRect = try await filter.contentRect
        let pointPixelScale = try await filter.pointPixelScale
        let screenFrame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))

        let selRect = selection.pointsRect
        let scaleX = contentRect.width / screenFrame.width
        let scaleY = contentRect.height / screenFrame.height

        sourceRect = CGRect(
            x: contentRect.minX + (selRect.minX - screenFrame.minX) * scaleX,
            y: contentRect.minY + selRect.minY * scaleY,
            width: selRect.width * scaleX,
            height: selRect.height * scaleY
        )

        let scale = CGFloat(pointPixelScale)
        capturePixelSize = CGSize(
            width: (selRect.width * scale).rounded(),
            height: (selRect.height * scale).rounded()
        )
        self.filter = filter
    }

    private func grabFrame() async -> CGImage? {
        guard let filter else { return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(capturePixelSize.width)
        config.height = Int(capturePixelSize.height)
        config.showsCursor = false
        config.captureResolution = .best
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Frame Loop

    private func startFrameLoop() {
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .capturing else { return }
                if let frame = await self.grabFrame(), let stitcher = self.stitcher {
                    _ = stitcher.addFrame(frame)
                    self.stitchedHeightPoints = Int(CGFloat(stitcher.totalHeightPixels) / self.scaleFactor)
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    // MARK: - Auto Scroll

    private func startAutoScroll() {
        guard state == .capturing, !isAutoScrolling else { return }
        isAutoScrolling = true

        // Pause the manual frame loop; autoscroll drives its own capture rhythm.
        captureTask?.cancel()
        captureTask = nil

        let center = CGPoint(x: regionPointsRect.midX, y: regionPointsRect.midY)

        autoScrollTask = Task { [weak self] in
            var stagnantRounds = 0
            // Warp the pointer into the region so scroll events land in it.
            CGWarpMouseCursorPosition(center)

            while !Task.isCancelled {
                guard let self, self.state == .capturing else { return }

                if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -5, wheel2: 0, wheel3: 0) {
                    event.location = center
                    event.post(tap: .cghidEventTap)
                }

                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }

                var appended = false
                if let frame = await self.grabFrame(), let stitcher = self.stitcher {
                    appended = stitcher.addFrame(frame)
                    self.stitchedHeightPoints = Int(CGFloat(stitcher.totalHeightPixels) / self.scaleFactor)
                }

                if appended {
                    stagnantRounds = 0
                } else {
                    stagnantRounds += 1
                    if stagnantRounds >= 3 {
                        // Reached the end of the scrollable content — finish automatically.
                        self.finish()
                        return
                    }
                }
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrolling = false
        if state == .capturing, captureTask == nil {
            startFrameLoop()
        }
    }

    private func stopLoops() {
        captureTask?.cancel()
        captureTask = nil
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrolling = false
    }

    // MARK: - UI (border + HUD)

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Converts a global top-left-origin points rect to an AppKit (bottom-left) rect.
    private func appKitRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func showBorder() {
        let frame = appKitRect(regionPointsRect).insetBy(dx: -2, dy: -2)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let border = NSView(frame: NSRect(origin: .zero, size: frame.size))
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.controlAccentColor.cgColor
        border.layer?.borderWidth = 2
        border.layer?.cornerRadius = 3
        window.contentView = border
        window.orderFront(nil)
        borderWindow = window
    }

    private func showHUD() {
        let hudSize = CGSize(width: 380, height: 56)
        let region = appKitRect(regionPointsRect)
        let screenFrame = (targetScreen ?? NSScreen.main)?.visibleFrame ?? .zero

        var origin = CGPoint(x: region.midX - hudSize.width / 2, y: region.minY - hudSize.height - 12)
        if origin.y < screenFrame.minY {
            origin.y = region.maxY + 12
        }
        if origin.y + hudSize.height > screenFrame.maxY {
            origin.y = region.minY + 12
        }
        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - hudSize.width - 8))

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: hudSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: ScrollingCaptureHUDView(controller: self))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFront(nil)
        hudPanel = panel
    }

    private func installEscMonitor() {
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in self?.cancel() }
            }
        }
    }

    private func cleanupUI() {
        hudPanel?.orderOut(nil)
        hudPanel = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}

// MARK: - Stitcher

/// Stitches vertically scrolling frames by matching pixel-row signatures.
final class ScrollStitcher {
    private var strips: [CGImage] = []
    private var prevGray: [UInt8] = []      // downsampled grayscale of the last frame (rows × sampledWidth)
    private var prevRowSums: [Float] = []   // per-row averaged brightness of the last frame
    private var frameWidth = 0
    private var frameHeight = 0
    private var sampledWidth = 0

    private(set) var totalHeightPixels = 0

    private let colStride = 4
    private let maxTotalHeight = 40_000
    private let matchThreshold: Float = 3.0   // avg gray-level difference per row

    /// Adds a frame; returns true when new content was appended.
    func addFrame(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height

        guard let gray = grayscale(image) else { return false }
        let rowSums = rowSignature(gray, width: sampledWidthFor(w), height: h)

        defer {
            prevGray = gray
            prevRowSums = rowSums
        }

        if strips.isEmpty {
            frameWidth = w
            frameHeight = h
            sampledWidth = sampledWidthFor(w)
            strips.append(image)
            totalHeightPixels = h
            return true
        }

        guard w == frameWidth, h == frameHeight else { return false }
        guard totalHeightPixels < maxTotalHeight else { return false }
        guard !prevRowSums.isEmpty else { return false }

        guard let dy = findScrollOffset(prevSums: prevRowSums, nextSums: rowSums, prevGray: prevGray, nextGray: gray, height: h) else {
            return false
        }
        guard dy > 0 else { return false }

        let stripRect = CGRect(x: 0, y: h - dy, width: w, height: dy)
        guard let strip = image.cropping(to: stripRect) else { return false }
        strips.append(strip)
        totalHeightPixels += dy
        return true
    }

    func compose() -> CGImage? {
        guard !strips.isEmpty else { return nil }
        guard let context = CGContext(
            data: nil,
            width: frameWidth,
            height: totalHeightPixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left; strips are ordered top-to-bottom.
        var yTop = 0
        for strip in strips {
            let y = totalHeightPixels - yTop - strip.height
            context.draw(strip, in: CGRect(x: 0, y: y, width: strip.width, height: strip.height))
            yTop += strip.height
        }
        return context.makeImage()
    }

    // MARK: - Matching internals

    private func sampledWidthFor(_ width: Int) -> Int {
        // Skip the right edge (~24px) so overlay scrollbars don't break matching.
        max(1, (max(1, width - 24)) / colStride)
    }

    private func grayscale(_ image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        let sw = sampledWidthFor(w)

        var full = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &full,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Downsample columns. Row 0 of `full` is the TOP row of the image
        // (CGContext draws flipped into memory? No — first byte row is top).
        var sampled = [UInt8](repeating: 0, count: sw * h)
        for row in 0..<h {
            let base = row * w
            for col in 0..<sw {
                sampled[row * sw + col] = full[base + col * colStride]
            }
        }
        return sampled
    }

    private func rowSignature(_ gray: [UInt8], width: Int, height: Int) -> [Float] {
        var sums = [Float](repeating: 0, count: height)
        for row in 0..<height {
            var acc = 0
            let base = row * width
            for col in 0..<width {
                acc += Int(gray[base + col])
            }
            sums[row] = Float(acc) / Float(width)
        }
        return sums
    }

    /// Finds how many pixels the content moved up between frames (scroll down).
    private func findScrollOffset(prevSums: [Float], nextSums: [Float], prevGray: [UInt8], nextGray: [UInt8], height h: Int) -> Int? {
        let minOverlap = max(40, h / 8)

        // Quick no-change check.
        if signatureError(prevSums, nextSums, shift: 0, height: h) < 0.5 {
            return 0
        }

        var bestDy = 0
        var bestErr = Float.greatestFiniteMagnitude
        for dy in 1...(h - minOverlap) {
            let err = signatureError(prevSums, nextSums, shift: dy, height: h)
            if err < bestErr {
                bestErr = err
                bestDy = dy
            }
        }

        guard bestErr < matchThreshold, bestDy > 0 else { return nil }
        guard verify(prevGray: prevGray, nextGray: nextGray, dy: bestDy, height: h) else { return nil }
        return bestDy
    }

    /// Mean |prev[i+shift] - next[i]| over the overlapping rows.
    private func signatureError(_ prev: [Float], _ next: [Float], shift: Int, height h: Int) -> Float {
        let count = h - shift
        guard count > 0 else { return .greatestFiniteMagnitude }
        var acc: Float = 0
        for i in 0..<count {
            acc += abs(prev[i + shift] - next[i])
        }
        return acc / Float(count)
    }

    /// Verifies a candidate offset with a real pixel comparison over sampled rows.
    private func verify(prevGray: [UInt8], nextGray: [UInt8], dy: Int, height h: Int) -> Bool {
        let sw = sampledWidth
        guard sw > 0 else { return false }
        let overlap = h - dy
        let samples = min(30, overlap)
        guard samples > 0 else { return false }

        var acc = 0
        var counted = 0
        for s in 0..<samples {
            let row = s * overlap / samples
            let prevBase = (row + dy) * sw
            let nextBase = row * sw
            for col in stride(from: 0, to: sw, by: 8) {
                acc += abs(Int(prevGray[prevBase + col]) - Int(nextGray[nextBase + col]))
                counted += 1
            }
        }
        guard counted > 0 else { return false }
        return (Float(acc) / Float(counted)) < 8.0
    }
}

// MARK: - HUD View

private struct ScrollingCaptureHUDView: View {
    let controller: ScrollingCaptureController

    var body: some View {
        HStack(spacing: 10) {
            Button {
                controller.toggleAutoScroll()
            } label: {
                Label(
                    controller.isAutoScrolling ? "Stop Auto" : "Auto-scroll",
                    systemImage: controller.isAutoScrolling ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(controller.isAutoScrolling ? .orange : .accentColor)

            Text("\(controller.stitchedHeightPoints) px")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 64)

            Spacer(minLength: 0)

            Button {
                controller.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)

            Button {
                controller.finish()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(4)
    }
}
