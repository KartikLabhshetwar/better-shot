import AppKit
import ScreenCaptureKit

@MainActor
final class RegionSelectionOverlay {

    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            let window = NSWindow(
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

            let overlayView = SelectionView(screen: screen) { [weak self] rect in
                self?.finishSelection(rect: rect, screen: screen)
            } onCancel: { [weak self] in
                self?.cancelSelection()
            }

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    private func finishSelection(rect: CGRect, screen: NSScreen) {
        NSCursor.pop()
        let scaleFactor = screen.backingScaleFactor

        // Convert from window coordinates (origin bottom-left) to screen coordinates
        let screenRect = CGRect(
            x: (screen.frame.origin.x + rect.origin.x) * scaleFactor,
            y: (screen.frame.maxY - rect.origin.y - rect.height) * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )

        closeOverlays()
        continuation?.resume(returning: screenRect)
        continuation = nil
    }

    private func cancelSelection() {
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

// MARK: - Selection View

private final class SelectionView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private let screen: NSScreen
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void

    init(screen: NSScreen, onSelect: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: screen.frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim the entire screen
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let start = dragStart, let current = dragCurrent else { return }

        let selectionRect = rectFromPoints(start, current)
        guard selectionRect.width > 2, selectionRect.height > 2 else { return }

        // Clear the selection area (show the screen through)
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // Draw selection border
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // Draw dimension label
        let w = Int(selectionRect.width * screen.backingScaleFactor)
        let h = Int(selectionRect.height * screen.backingScaleFactor)
        let label = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelRect = CGRect(
            x: selectionRect.midX - labelSize.width / 2 - 6,
            y: selectionRect.minY - labelSize.height - 8,
            width: labelSize.width + 12,
            height: labelSize.height + 4
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        dragStart = loc
        dragCurrent = loc
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = rectFromPoints(start, end)

        if rect.width > 3, rect.height > 3 {
            onSelect(rect)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel()
        }
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
