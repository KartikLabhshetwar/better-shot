import AppKit
import CoreGraphics

@available(macOS, deprecated: 14.0, message: "CGWindowListCreateImage wrapper for real-time loupe")
private func captureScreenRect(_ rect: CGRect) -> CGImage? {
    CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
}

@MainActor
final class ColorPickerOverlay {

    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<String?, Never>?

    func pickColor() async -> String? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            let window = ColorPickerWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]

            let loupeView = ColorLoupeView(screen: screen) { [weak self] hex in
                self?.finish(hex: hex)
            } onCancel: { [weak self] in
                self?.cancel()
            }

            window.contentView = loupeView
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        NSCursor.crosshair.set()
    }

    private func finish(hex: String) {
        NSCursor.pop()
        closeOverlays()
        continuation?.resume(returning: hex)
        continuation = nil
    }

    private func cancel() {
        NSCursor.pop()
        closeOverlays()
        continuation?.resume(returning: nil)
        continuation = nil
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}

private final class ColorPickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cursorUpdate(with event: NSEvent) {}
}

// MARK: - Loupe View

private final class ColorLoupeView: NSView {

    private let screen: NSScreen
    private let onPick: (String) -> Void
    private let onCancel: () -> Void
    private var mouseLocation: NSPoint?
    private var trackingArea: NSTrackingArea?

    private let loupeRadius: CGFloat = 60
    private let sampleSize = 11
    private var cachedScreenshot: CGImage?
    private var lastSampleTime: CFTimeInterval = 0

    init(screen: NSScreen, onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.onPick = onPick
        self.onCancel = onCancel
        super.init(frame: screen.frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        NSCursor.crosshair.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        guard let mouse = mouseLocation else { return }

        let globalPos = NSPoint(
            x: screen.frame.origin.x + mouse.x,
            y: screen.frame.origin.y + mouse.y
        )
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgY = screenHeight - globalPos.y

        let now = CACurrentMediaTime()
        if cachedScreenshot == nil || (now - lastSampleTime) > 0.03 {
            let half = CGFloat(sampleSize / 2) + 1
            let captureRect = CGRect(
                x: globalPos.x - half,
                y: cgY - half,
                width: CGFloat(sampleSize) + 2,
                height: CGFloat(sampleSize) + 2
            )
            cachedScreenshot = captureScreenRect(captureRect)
            lastSampleTime = now
        }

        guard let screenshot = cachedScreenshot else { return }

        let centerColor = extractCenterColor(from: screenshot)
        let hexString = hexFromColor(centerColor)

        drawLoupe(at: mouse, screenshot: screenshot, centerColor: centerColor, hex: hexString)
    }

    private func drawLoupe(at point: NSPoint, screenshot: CGImage, centerColor: NSColor, hex: String) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let loupeCenter = NSPoint(x: point.x, y: point.y + loupeRadius + 20)
        let loupeRect = CGRect(
            x: loupeCenter.x - loupeRadius,
            y: loupeCenter.y - loupeRadius,
            width: loupeRadius * 2,
            height: loupeRadius * 2
        )

        ctx.saveGState()

        // Clip to circle
        let clipPath = CGPath(ellipseIn: loupeRect, transform: nil)
        ctx.addPath(clipPath)
        ctx.clip()

        // Draw magnified pixels with nearest-neighbor interpolation
        ctx.interpolationQuality = .none
        ctx.draw(screenshot, in: loupeRect)

        // Draw grid lines
        let cellSize = loupeRect.width / CGFloat(sampleSize)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(0.5)
        for i in 0...sampleSize {
            let offset = CGFloat(i) * cellSize
            ctx.move(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.minY))
            ctx.addLine(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.maxY))
            ctx.move(to: CGPoint(x: loupeRect.minX, y: loupeRect.minY + offset))
            ctx.addLine(to: CGPoint(x: loupeRect.maxX, y: loupeRect.minY + offset))
        }
        ctx.strokePath()

        // Highlight center pixel
        let centerCellX = loupeRect.minX + CGFloat(sampleSize / 2) * cellSize
        let centerCellY = loupeRect.minY + CGFloat(sampleSize / 2) * cellSize
        let centerCellRect = CGRect(x: centerCellX, y: centerCellY, width: cellSize, height: cellSize)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(centerCellRect)

        ctx.restoreGState()

        // Loupe border
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: loupeRect.insetBy(dx: 1.5, dy: 1.5))

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: loupeRect)

        // Color swatch + hex label below loupe
        let labelHeight: CGFloat = 26
        let labelWidth: CGFloat = 100
        let labelRect = CGRect(
            x: loupeCenter.x - labelWidth / 2,
            y: loupeRect.minY - labelHeight - 6,
            width: labelWidth,
            height: labelHeight
        )

        // Background pill
        let pillPath = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.8).setFill()
        pillPath.fill()

        // Color swatch circle
        let swatchRect = CGRect(x: labelRect.minX + 6, y: labelRect.midY - 8, width: 16, height: 16)
        ctx.setFillColor(centerColor.cgColor)
        ctx.fillEllipse(in: swatchRect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: swatchRect)

        // Hex text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let hexNS = hex as NSString
        let textPoint = NSPoint(x: swatchRect.maxX + 6, y: labelRect.minY + 5)
        hexNS.draw(at: textPoint, withAttributes: attrs)
    }

    private func extractCenterColor(from image: CGImage) -> NSColor {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return .black }

        let centerX = w / 2
        let centerY = h / 2

        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return .black
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        let offset = centerY * bytesPerRow + centerX * bytesPerPixel

        guard offset + 3 < CFDataGetLength(data) else { return .black }

        let b = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let r = CGFloat(ptr[offset + 2]) / 255.0

        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func hexFromColor(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let mouse = mouseLocation else { onCancel(); return }

        let globalPos = NSPoint(
            x: screen.frame.origin.x + mouse.x,
            y: screen.frame.origin.y + mouse.y
        )
        let screenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgY = screenHeight - globalPos.y

        let captureRect = CGRect(x: globalPos.x, y: cgY, width: 1, height: 1)
        guard let image = captureScreenRect(captureRect) else {
            onCancel()
            return
        }

        let color = extractCenterColor(from: image)
        onPick(hexFromColor(color))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }
    }
}
