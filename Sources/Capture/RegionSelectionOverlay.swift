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

    private var allowsWindowSelection = true
    private var controlScreen: NSScreen?
    private var onControlSelection: ((RegionSelectionOutcome) -> Void)?

    func beginControlDrag(at point: CGPoint, completion: @escaping (RegionSelectionOutcome) -> Void) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { completion(.cancelled); return }
        controlScreen = screen
        onControlSelection = completion
        allowsWindowSelection = false
        showOverlays()
        selectionViews.first?.beginDrag(at: CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY))
    }

    func updateControlDrag(at point: CGPoint, ended: Bool = false) {
        guard let screen = controlScreen else { return }
        let local = CGPoint(x: min(max(point.x - screen.frame.minX, 0), screen.frame.width),
                            y: min(max(point.y - screen.frame.minY, 0), screen.frame.height))
        if ended { selectionViews.first?.endDrag(at: local) }
        else { selectionViews.first?.updateDrag(at: local) }
    }

    func cancelControlDrag() { if controlScreen != nil { finish(.cancelled) } }

    private var overlayWindows: [NSWindow] = []
    private var selectionViews: [SelectionView] = []
    private var continuation: CheckedContinuation<RegionSelectionOutcome, Never>?
    private var previousApp: NSRunningApplication?

    /// Returns once the app that was frontmost is active again, so captures show its windows as focused.
    func selectRegion(allowsWindowSelection: Bool = true) async -> RegionSelectionOutcome {
        self.allowsWindowSelection = allowsWindowSelection
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        let outcome = await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
        if let app = previousApp {
            previousApp = nil
            app.activate()
            for _ in 0..<25 where !app.isActive { try? await Task.sleep(for: .milliseconds(20)) }
        }
        return outcome
    }

    private func showOverlays() {
        let crosshair = NSCursor.crosshair
        let capturesOnRelease = controlScreen != nil || AppPreferences.captureRegionOnRelease

        for screen in controlScreen.map({ [$0] }) ?? NSScreen.screens {
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

            let previousRegion = (controlScreen == nil ? AppPreferences.lastRegionRect : nil)
                .flatMap { screen.frame.contains($0) ? RegionGeometry.localRect(global: $0, screenFrame: screen.frame) : nil }
            let overlayView = SelectionView(
                screen: screen,
                cursor: crosshair,
                selection: previousRegion,
                capturesOnRelease: capturesOnRelease
            ) { [weak self] rect in
                self?.finishSelection(rect: rect, screen: screen)
            } onCancel: { [weak self] in
                self?.finish(.cancelled)
            } onWindow: { [weak self] in
                if self?.allowsWindowSelection == true { self?.finish(.window) }
            }

            overlayView.onBeginSelection = { [weak self, weak overlayView] in
                self?.selectionViews.forEach { if $0 !== overlayView { $0.clearSelection() } }
            }
            window.contentView = overlayView
            if controlScreen != nil { window.orderFrontRegardless() }
            else { window.makeKeyAndOrderFront(nil) }
            overlayWindows.append(window)
            selectionViews.append(overlayView)
        }

        if controlScreen == nil {
            NSApp.activate(ignoringOtherApps: true)
            selectionViews.first(where: \.hasSelection)?.window?.makeKeyAndOrderFront(nil)
        }
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
        let callback = onControlSelection
        onControlSelection = nil
        controlScreen = nil
        callback?(outcome)
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        selectionViews.removeAll()
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
    private var selection: CGRect?
    private var movesSelection: Bool
    var hasSelection: Bool { selection != nil }
    private var activeHandle: RegionHandle?
    private var handleDragOrigin: NSPoint?
    private var handleDragRect: CGRect?
    var onBeginSelection: () -> Void = {}
    private var trackingArea: NSTrackingArea?
    private let screen: NSScreen
    private let crosshairCursor: NSCursor
    private let capturesOnRelease: Bool
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private let onWindow: () -> Void

    init(
        screen: NSScreen,
        cursor: NSCursor,
        selection: CGRect?,
        capturesOnRelease: Bool,
        onSelect: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void,
        onWindow: @escaping () -> Void
    ) {
        self.screen = screen
        self.crosshairCursor = cursor
        self.selection = selection
        self.movesSelection = selection == nil
        self.capturesOnRelease = capturesOnRelease
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onWindow = onWindow
        super.init(frame: screen.frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        } else if let selection {
            drawAdjustableSelection(selection)
        } else if let mouse = mouseLocation {
            drawGuideLines(at: mouse)
        }
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

    private func drawAdjustableSelection(_ rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        for handle in RegionHandle.allCases where handle != .move {
            let p = handle.point(in: rect)
            let dot = NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }

        let hint = movesSelection ? "drag to adjust" : "drag the edges to resize, or draw a new area"
        drawLabel("\(pixelSize(rect))  ·  ↩ to capture  ·  \(hint)  ·  esc", below: rect)
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
        let width = labelSize.width + 12
        let height = labelSize.height + 4
        let labelRect = CGRect(
            x: min(max(rect.midX - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: max(rect.minY - height - 4, bounds.minY + 8),
            width: width,
            height: height
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    // MARK: - Mouse Events

    func clearSelection() {
        selection = nil
        needsDisplay = true
    }

    /// The previous area only resizes from its edges, so a drag inside it can draw a new area.
    private func adjustmentHandle(at point: NSPoint) -> RegionHandle? {
        guard let selection, let handle = RegionAdjustment.handle(at: point, in: selection) else { return nil }
        return handle == .move && !movesSelection ? nil : handle
    }

    private func updateCursor(at point: NSPoint) {
        guard let handle = adjustmentHandle(at: point) else {
            crosshairCursor.set()
            return
        }
        Self.cursor(for: handle, dragging: false).set()
    }

    private static func cursor(for handle: RegionHandle, dragging: Bool) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .move: return dragging ? .closedHand : .openHand
        case .topLeft: position = .topLeft
        case .top: position = .top
        case .topRight: position = .topRight
        case .right: position = .right
        case .bottomRight: position = .bottomRight
        case .bottom: position = .bottom
        case .bottomLeft: position = .bottomLeft
        case .left: position = .left
        }
        return .frameResize(position: position, directions: .all)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        mouseLocation = loc
        updateCursor(at: loc)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    func beginDrag(at loc: CGPoint, clickCount: Int = 1) {
        mouseLocation = nil
        if clickCount == 2, let selection, selection.contains(loc) {
            onSelect(selection)
            return
        }
        if let selection, let handle = adjustmentHandle(at: loc) {
            activeHandle = handle
            handleDragOrigin = loc
            handleDragRect = selection
            Self.cursor(for: handle, dragging: true).set()
            return
        }
        crosshairCursor.set()
        dragStart = loc
        dragCurrent = loc
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(at: convert(event.locationInWindow, from: nil))
    }

    func updateDrag(at loc: CGPoint) {
        if let handle = activeHandle, let origin = handleDragOrigin, let base = handleDragRect {
            let delta = CGSize(width: loc.x - origin.x, height: loc.y - origin.y)
            selection = RegionAdjustment.apply(handle, delta: delta, to: base, within: bounds)
        } else {
            crosshairCursor.set()
            dragCurrent = loc
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        endDrag(at: convert(event.locationInWindow, from: nil))
    }

    func endDrag(at end: CGPoint) {
        if activeHandle != nil {
            activeHandle = nil
            handleDragOrigin = nil
            handleDragRect = nil
            updateCursor(at: end)
            return
        }
        guard let start = dragStart else { return }
        dragStart = nil
        dragCurrent = nil
        let rect = rectFromPoints(start, end)

        if rect.width > 3, rect.height > 3 {
            if capturesOnRelease {
                onSelect(rect)
                return
            }
            onBeginSelection()
            selection = rect
            movesSelection = true
            updateCursor(at: end)
        } else if selection == nil {
            onCancel()
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel()
        case 49:
            onWindow()
        case 36, 76:
            if let selection { onSelect(selection) }
        default:
            break
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
