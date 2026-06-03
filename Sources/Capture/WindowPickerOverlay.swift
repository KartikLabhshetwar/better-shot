import AppKit
import ScreenCaptureKit

@MainActor
final class WindowPickerOverlay {

    private let windows: [SCWindow]
    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<UInt32?, Never>?

    init(windows: [SCWindow]) {
        self.windows = windows
    }

    func pickWindow() async -> SCWindow? {
        let selectedID: UInt32? = await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
        guard let selectedID else { return nil }
        return windows.first { $0.windowID == selectedID }
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            let window = PickerWindow(
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

            let pickerView = WindowPickerView(
                screen: screen,
                windows: windows
            ) { [weak self] selected in
                self?.finishPick(selected)
            } onCancel: { [weak self] in
                self?.cancel()
            }

            window.contentView = pickerView
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.pointingHand.push()
    }

    private func finishPick(_ selected: SCWindow) {
        NSCursor.pop()
        closeOverlays()
        let windowID = selected.windowID
        continuation?.resume(returning: windowID)
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

// MARK: - Picker Window (borderless windows need canBecomeKey override)

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cursorUpdate(with event: NSEvent) {}
}

// MARK: - Picker View

private final class WindowPickerView: NSView {
    private let screen: NSScreen
    private let scWindows: [SCWindow]
    private let onSelect: (SCWindow) -> Void
    private let onCancel: () -> Void
    private var hoveredWindow: SCWindow?

    init(screen: NSScreen, windows: [SCWindow],
         onSelect: @escaping (SCWindow) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.scWindows = windows
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: screen.frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

        if let hovered = hoveredWindow {
            // Convert SCWindow frame (top-left origin) to NSView coords (bottom-left origin)
            let wFrame = hovered.frame
            let screenY = primaryHeight - wFrame.origin.y - wFrame.height
            let viewRect = CGRect(
                x: wFrame.origin.x - screen.frame.origin.x,
                y: screenY - screen.frame.origin.y,
                width: wFrame.width,
                height: wFrame.height
            ).intersection(bounds)

            guard !viewRect.isNull else { return }

            // Highlight the hovered window
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            viewRect.fill()

            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: viewRect)
            border.lineWidth = 2.5
            border.stroke()

            // Label
            let appName = hovered.owningApplication?.applicationName ?? "Window"
            let title = hovered.title ?? ""
            let labelText = title.isEmpty ? appName : "\(appName) — \(title)"
            let label = labelText as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let labelSize = label.size(withAttributes: attrs)
            let labelRect = CGRect(
                x: viewRect.midX - labelSize.width / 2 - 8,
                y: viewRect.maxY - labelSize.height - 16,
                width: labelSize.width + 16,
                height: labelSize.height + 8
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
            label.draw(at: NSPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attrs)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let cgPoint: CGPoint
        if let cgEvent = CGEvent(source: nil) {
            cgPoint = cgEvent.location
        } else {
            let loc = convert(event.locationInWindow, from: nil)
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            cgPoint = CGPoint(
                x: screen.frame.origin.x + loc.x,
                y: primaryHeight - (screen.frame.origin.y + loc.y)
            )
        }

        let hit = scWindows.first { w in
            w.frame.contains(cgPoint)
        }

        if hoveredWindow?.windowID != hit?.windowID {
            hoveredWindow = hit
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let hovered = hoveredWindow {
            onSelect(hovered)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }
}
