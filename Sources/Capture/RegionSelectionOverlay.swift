import AppKit
import ScreenCaptureKit

struct RegionSelection {
    let pointsRect: CGRect  // In global display points (top-left origin, matching SCK coordinates)
    let scaleFactor: CGFloat
    let displayID: CGDirectDisplayID
}

enum RegionSelectionOutcome {
    case region(RegionSelection)
    case window
    case cancelled
}

@MainActor
final class RegionSelectionOverlay {

    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<RegionSelectionOutcome, Never>?

    func selectRegion() async -> RegionSelectionOutcome {
        await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
    }

    private func showOverlays() {
        let crosshair = CrosshairCursor.shared.makeCursor()

        for screen in NSScreen.screens {
            let window = OverlayWindow(
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

            let ghost = AppPreferences.lastRegionRect
                .flatMap { screen.frame.contains($0) ? RegionGeometry.localRect(global: $0, screenFrame: screen.frame) : nil }
            let overlayView = SelectionView(screen: screen, cursor: crosshair, ghost: ghost) { [weak self] rect in
                self?.finishSelection(rect: rect, screen: screen)
            } onCancel: { [weak self] in
                self?.finish(.cancelled)
            } onWindow: { [weak self] in
                self?.finish(.window)
            }

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        crosshair.push()
        crosshair.set()
    }

    private func finishSelection(rect: CGRect, screen: NSScreen) {
        let globalRect = RegionGeometry.globalRect(local: rect, screenFrame: screen.frame)
        AppPreferences.lastRegionRect = globalRect

        let selection = RegionSelection(
            pointsRect: RegionGeometry.pointsRect(global: globalRect, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height),
            scaleFactor: screen.backingScaleFactor,
            displayID: ActiveDisplayResolver.displayID(for: screen) ?? CGMainDisplayID()
        )
        finish(.region(selection))
    }

    private func finish(_ outcome: RegionSelectionOutcome) {
        NSCursor.pop()
        closeOverlays()
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}

// MARK: - Custom Crosshair "+" Cursor (matches macOS screenshot tool)

@MainActor
final class CrosshairCursor {
    static let shared = CrosshairCursor()

    func makeCursor() -> NSCursor {
        let size: CGFloat = 40
        let center = size / 2
        let lineLength: CGFloat = 16
        let gap: CGFloat = 4

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSGraphicsContext.current?.shouldAntialias = true

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        shadow.set()

        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round

        // Horizontal line (left segment)
        path.move(to: NSPoint(x: center - lineLength, y: center))
        path.line(to: NSPoint(x: center - gap, y: center))
        // Horizontal line (right segment)
        path.move(to: NSPoint(x: center + gap, y: center))
        path.line(to: NSPoint(x: center + lineLength, y: center))
        // Vertical line (bottom segment)
        path.move(to: NSPoint(x: center, y: center - lineLength))
        path.line(to: NSPoint(x: center, y: center - gap))
        // Vertical line (top segment)
        path.move(to: NSPoint(x: center, y: center + gap))
        path.line(to: NSPoint(x: center, y: center + lineLength))

        path.stroke()

        // Draw center "+" cross
        let plusPath = NSBezierPath()
        plusPath.lineWidth = 1.5
        plusPath.lineCapStyle = .round
        let plusSize: CGFloat = 2.5
        plusPath.move(to: NSPoint(x: center - plusSize, y: center))
        plusPath.line(to: NSPoint(x: center + plusSize, y: center))
        plusPath.move(to: NSPoint(x: center, y: center - plusSize))
        plusPath.line(to: NSPoint(x: center, y: center + plusSize))
        plusPath.stroke()

        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }
}

// MARK: - Overlay Window (prevents AppKit cursor resets)

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cursorUpdate(with event: NSEvent) {
        // Swallow cursor updates — we manage the cursor ourselves in SelectionView
    }
}

// MARK: - Selection View

private final class SelectionView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var mouseLocation: NSPoint?
    private var trackingArea: NSTrackingArea?
    private let screen: NSScreen
    private let crosshairCursor: NSCursor
    private let ghost: CGRect?
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private let onWindow: () -> Void

    init(
        screen: NSScreen,
        cursor: NSCursor,
        ghost: CGRect?,
        onSelect: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void,
        onWindow: @escaping () -> Void
    ) {
        self.screen = screen
        self.crosshairCursor = cursor
        self.ghost = ghost
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onWindow = onWindow
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
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: crosshairCursor)
        crosshairCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        crosshairCursor.set()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if let start = dragStart, let current = dragCurrent {
            drawSelection(start: start, current: current)
        } else {
            if let ghost {
                drawGhost(ghost)
            }
            if let mouse = mouseLocation {
                drawGuideLines(at: mouse)
            }
        }
    }

    private func drawGhost(_ rect: CGRect) {
        let hovered = mouseLocation.map(rect.contains) ?? false
        NSColor.white.withAlphaComponent(hovered ? 0.16 : 0.08).setFill()
        rect.fill()

        NSColor.white.withAlphaComponent(hovered ? 1 : 0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        drawLabel("\(pixelSize(rect))  ·  ↩ / A / click to reuse", below: rect)
    }

    private func drawGuideLines(at point: NSPoint) {
        let lineColor = NSColor.white.withAlphaComponent(0.4)
        lineColor.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 0.5

        // Vertical guide line
        path.move(to: NSPoint(x: point.x, y: bounds.minY))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))

        // Horizontal guide line
        path.move(to: NSPoint(x: bounds.minX, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))

        path.stroke()
    }

    private func drawSelection(start: NSPoint, current: NSPoint) {
        let selectionRect = rectFromPoints(start, current)
        guard selectionRect.width > 2, selectionRect.height > 2 else { return }

        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        drawLabel(pixelSize(selectionRect), below: selectionRect)
    }

    private func pixelSize(_ rect: CGRect) -> String {
        "\(Int(rect.width * screen.backingScaleFactor)) × \(Int(rect.height * screen.backingScaleFactor))"
    }

    private func drawLabel(_ text: String, below rect: CGRect) {
        let label = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelRect = CGRect(
            x: rect.midX - labelSize.width / 2 - 6,
            y: rect.minY - labelSize.height - 8,
            width: labelSize.width + 12,
            height: labelSize.height + 4
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        crosshairCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        crosshairCursor.set()
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        crosshairCursor.set()
        let loc = convert(event.locationInWindow, from: nil)
        dragStart = loc
        dragCurrent = loc
        mouseLocation = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        crosshairCursor.set()
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = rectFromPoints(start, end)

        if rect.width > 3, rect.height > 3 {
            onSelect(rect)
        } else if let ghost, ghost.contains(end) {
            onSelect(ghost)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel()
        case 49:
            onWindow()
        case 36, 76:
            reuseGhost()
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "a" {
                reuseGhost()
            }
        }
    }

    private func reuseGhost() {
        guard let ghost else { return }
        onSelect(ghost)
    }

    private func rectFromPoints(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
