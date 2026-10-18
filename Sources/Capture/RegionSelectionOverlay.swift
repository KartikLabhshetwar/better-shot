import AppKit
import ScreenCaptureKit
import OSLog
import QuartzCore

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

    private let dimsOutsideSelection: Bool

    init(dimsOutsideSelection: Bool = true) {
        self.dimsOutsideSelection = dimsOutsideSelection
    }

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
    private var frozenFrames: [CGDirectDisplayID: FrozenScreenFrame] = [:]

    /// Returns once the app that was frontmost is active again, so captures show its windows as focused.
    func selectRegion(allowsWindowSelection: Bool = true, frozenFrames: [CGDirectDisplayID: FrozenScreenFrame] = [:]) async -> RegionSelectionOutcome {
        self.allowsWindowSelection = allowsWindowSelection
        self.frozenFrames = frozenFrames
        defer { self.frozenFrames = [:] }
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
        let started = ContinuousClock.now
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
            window.level = .screenSaver
            window.hasShadow = false
            window.animationBehavior = .none
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let previousRegion = (controlScreen == nil && AppPreferences.preselectPreviousRegion ? AppPreferences.lastRegionRect : nil)
                .flatMap { screen.frame.contains($0) ? RegionGeometry.localRect(global: $0, screenFrame: screen.frame) : nil }
            let overlayView = SelectionView(
                screen: screen,
                cursor: crosshair,
                selection: previousRegion,
                capturesOnRelease: capturesOnRelease,
                dimsOutsideSelection: dimsOutsideSelection
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
            if let frozenImage = ActiveDisplayResolver.displayID(for: screen).flatMap({ frozenFrames[$0]?.image }) {
                // The frozen frame covers the whole display. Let the window server
                // occlude the live windows behind it instead of blending with them.
                window.isOpaque = true
                window.backgroundColor = .black
                let backdrop = FrozenBackdropView(image: frozenImage, frame: NSRect(origin: .zero, size: screen.frame.size))
                overlayView.frame = backdrop.bounds
                overlayView.autoresizingMask = [.width, .height]
                backdrop.addSubview(overlayView)
                window.contentView = backdrop
            } else {
                window.contentView = overlayView
            }
            overlayWindows.append(window)
            selectionViews.append(overlayView)
        }

        if controlScreen == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Order independently of activation, which may still be pending when a
        // menu-bar shortcut invokes us. Hidden windows can defer their first draw.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            Logger(subsystem: "com.bettershot.app", category: "CaptureStartup").info(
                "Selector initial layer transaction completed in \(String(describing: started.duration(to: .now)), privacy: .public)"
            )
        }
        for window in overlayWindows {
            window.orderFrontRegardless()
            if controlScreen == nil { window.makeKey() }
            window.displayIfNeeded()
        }
        if controlScreen == nil {
            selectionViews.first(where: \.hasSelection)?.window?.makeKey()
        }
        CATransaction.commit()
        // This one-shot overlay needs its initial frame submitted immediately;
        // the crosshair must not get ahead of AppKit's deferred layer drawing.
        CATransaction.flush()
        crosshair.push()
        crosshair.set()
        Logger(subsystem: "com.bettershot.app", category: "CaptureStartup").info(
            "Selector window setup finished in \(String(describing: started.duration(to: .now)), privacy: .public)"
        )
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

// MARK: - Frozen Backdrop

private final class FrozenBackdropView: NSView {
    private let image: CGImage

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let backingLayer = super.makeBackingLayer()
        backingLayer.backgroundColor = NSColor.black.cgColor
        backingLayer.isOpaque = true
        backingLayer.contents = image
        return backingLayer
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = image
    }
}

// MARK: - Selection View

private final class SelectionView: NSView {
    private var firstDrawStarted: ContinuousClock.Instant? = .now
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
    private let dimsOutsideSelection: Bool
    private let dimLayers = (0..<4).map { _ in CALayer() }
    private let borderLayer = CALayer()
    private let guideLayers = (0..<2).map { _ in CALayer() }
    private let handleLayers = (0..<8).map { _ in CALayer() }
    private let selectionLabel = SelectionLabelView()
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void
    private let onWindow: () -> Void

    init(
        screen: NSScreen,
        cursor: NSCursor,
        selection: CGRect?,
        capturesOnRelease: Bool,
        dimsOutsideSelection: Bool,
        onSelect: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void,
        onWindow: @escaping () -> Void
    ) {
        self.screen = screen
        self.crosshairCursor = cursor
        self.selection = selection
        self.movesSelection = selection == nil
        self.capturesOnRelease = capturesOnRelease
        self.dimsOutsideSelection = dimsOutsideSelection
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onWindow = onWindow
        super.init(frame: screen.frame)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        wantsLayer = true
        configureLayers()
        updateLayer()
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

    // MARK: - Composited selection chrome

    // Solid layer rectangles need no screen-sized bitmap. Pointer movement only
    // changes their geometry; the frozen image remains the same layer contents.
    override var wantsUpdateLayer: Bool { true }

    private func configureLayers() {
        for dim in dimLayers {
            dim.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            layer?.addSublayer(dim)
        }
        for guide in guideLayers {
            guide.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            layer?.addSublayer(guide)
        }
        borderLayer.borderColor = NSColor.white.cgColor
        borderLayer.borderWidth = 1.5
        layer?.addSublayer(borderLayer)
        for handle in handleLayers {
            handle.backgroundColor = NSColor.white.cgColor
            handle.borderColor = NSColor.black.withAlphaComponent(0.5).cgColor
            handle.borderWidth = 1
            handle.cornerRadius = 4
            layer?.addSublayer(handle)
        }
        addSubview(selectionLabel)
    }

    override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        borderLayer.isHidden = true
        guideLayers.forEach { $0.isHidden = true }
        handleLayers.forEach { $0.isHidden = true }

        var visibleSelection: CGRect?
        if let start = dragStart, let current = dragCurrent {
            let rect = rectFromPoints(start, current)
            if rect.width > 2, rect.height > 2 {
                visibleSelection = rect
                showSelection(rect, adjustable: false)
            }
        } else if let selection {
            visibleSelection = selection
            showSelection(selection, adjustable: true)
        } else if let mouse = mouseLocation {
            guideLayers[0].frame = CGRect(x: mouse.x - 0.25, y: bounds.minY, width: 0.5, height: bounds.height)
            guideLayers[1].frame = CGRect(x: bounds.minX, y: mouse.y - 0.25, width: bounds.width, height: 0.5)
            guideLayers.forEach { $0.isHidden = false }
        }
        if visibleSelection == nil { selectionLabel.isHidden = true }
        updateDimming(excluding: visibleSelection)
        if let started = firstDrawStarted {
            firstDrawStarted = nil
            Logger(subsystem: "com.bettershot.app", category: "CaptureStartup").info(
                "Selector layers prepared in \(String(describing: started.duration(to: .now)), privacy: .public)"
            )
        }
    }

    private func updateDimming(excluding selection: CGRect?) {
        var rectangles = [bounds, .zero, .zero, .zero]
        if let hole = selection?.intersection(bounds), !hole.isEmpty, !hole.isNull {
            rectangles = [
                CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: hole.minY - bounds.minY),
                CGRect(x: bounds.minX, y: hole.maxY, width: bounds.width, height: bounds.maxY - hole.maxY),
                CGRect(x: bounds.minX, y: hole.minY, width: hole.minX - bounds.minX, height: hole.height),
                CGRect(x: hole.maxX, y: hole.minY, width: bounds.maxX - hole.maxX, height: hole.height),
            ]
        }
        for (dim, rect) in zip(dimLayers, rectangles) {
            dim.frame = rect
            dim.isHidden = !dimsOutsideSelection || rect.isEmpty
        }
    }

    private func showSelection(_ rect: CGRect, adjustable: Bool) {
        borderLayer.frame = rect.insetBy(dx: -0.75, dy: -0.75)
        borderLayer.isHidden = false
        if adjustable {
            for (layer, handle) in zip(handleLayers, RegionHandle.allCases.filter({ $0 != .move })) {
                let point = handle.point(in: rect)
                layer.frame = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                layer.isHidden = false
            }
        }
        let hint = movesSelection ? "drag to adjust" : "drag the edges to resize, or draw a new area"
        let text = adjustable ? "\(pixelSize(rect))  ·  ↩ to capture  ·  \(hint)  ·  esc" : pixelSize(rect)
        selectionLabel.show(text, below: rect, within: bounds)
    }

    private func pixelSize(_ rect: CGRect) -> String {
        "\(Int(rect.width * screen.backingScaleFactor)) × \(Int(rect.height * screen.backingScaleFactor))"
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
        guard #available(macOS 15.0, *) else {
            switch handle {
            case .move: return dragging ? .closedHand : .openHand
            case .top, .bottom: return .resizeUpDown
            case .left, .right: return .resizeLeftRight
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
            }
        }
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

/// Only the small dimension label uses AppKit bitmap drawing, never the display.
private final class SelectionLabelView: NSView {
    private var text = ""
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String, below rect: CGRect, within bounds: CGRect) {
        if self.text != text {
            self.text = text
            needsDisplay = true
        }
        let size = (text as NSString).size(withAttributes: attributes)
        let width = size.width + 12
        let height = size.height + 4
        frame = CGRect(
            x: min(max(rect.midX - width / 2, bounds.minX + 8), bounds.maxX - width - 8),
            y: max(rect.minY - height - 4, bounds.minY + 8),
            width: width,
            height: height
        )
        isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: 6, y: 2), withAttributes: attributes)
    }
}
