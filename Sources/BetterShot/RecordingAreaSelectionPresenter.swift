//
//  RecordingAreaSelectionPresenter.swift
//  BetterShot
//
//  Created by Codex on 01/05/26.
//

import AppKit
import ScreenCaptureKit

@MainActor
final class RecordingAreaSelectionPresenter {
    static let shared = RecordingAreaSelectionPresenter()

    private var panel: NSPanel?
    private var completion: ((CGRect?) -> Void)?
    private var display: SCDisplay?
    private var keyMonitor: Any?

    private init() {}

    func selectArea(on display: SCDisplay, completion: @escaping (CGRect?) -> Void) {
        cancel()

        guard let screen = ActiveDisplayResolver.screen(for: display.displayID) ?? NSScreen.main else {
            completion(nil)
            return
        }

        self.display = display
        self.completion = completion

        let panel = RecordingAreaSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        let selectionView = RecordingAreaSelectionView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            pixelScale: CGSize(
                width: CGFloat(display.width) / max(screen.frame.width, 1),
                height: CGFloat(display.height) / max(screen.frame.height, 1)
            )
        )
        selectionView.onCancel = { [weak self] in
            self?.finish(rect: nil)
        }
        selectionView.onSelect = { [weak self, weak panel] localRect in
            guard let self, let panel else {
                self?.finish(rect: nil)
                return
            }

            let globalRect = CGRect(
                x: panel.frame.minX + localRect.minX,
                y: panel.frame.minY + localRect.minY,
                width: localRect.width,
                height: localRect.height
            )
            self.finish(rect: globalRect)
        }

        panel.contentView = selectionView
        panel.makeFirstResponder(selectionView)
        self.panel = panel
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        selectionView.beginSelectionCursorSession()
    }

    func cancel() {
        finish(rect: nil)
    }

    private func finish(rect: CGRect?) {
        let completion = completion
        self.completion = nil
        display = nil
        removeKeyMonitor()
        (panel?.contentView as? RecordingAreaSelectionView)?.endSelectionCursorSession()
        panel?.orderOut(nil)
        panel = nil
        completion?(rect)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }

            self?.finish(rect: nil)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private final class RecordingAreaSelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

private final class RecordingAreaSelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private let pixelScale: CGSize
    private var didPushSelectionCursor = false

    override var acceptsFirstResponder: Bool {
        true
    }

    init(frame frameRect: NSRect, pixelScale: CGSize) {
        self.pixelScale = pixelScale
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        endSelectionCursorSession()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else { return }

        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)

        NSColor.white.withAlphaComponent(0.96).setStroke()
        let border = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
        border.lineWidth = 2
        border.stroke()

        drawSelectionSize(for: selectionRect)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .annotationPlus)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        if window != nil {
            beginSelectionCursorSession()
        } else {
            endSelectionCursorSession()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        beginSelectionCursorSession()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        beginSelectionCursorSession()
        return true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 16, rect.height >= 16 else {
            onCancel?()
            return
        }

        onSelect?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    func beginSelectionCursorSession() {
        if didPushSelectionCursor {
            NSCursor.annotationPlus.set()
        } else {
            NSCursor.annotationPlus.push()
            didPushSelectionCursor = true
        }
    }

    func endSelectionCursorSession() {
        guard didPushSelectionCursor else { return }

        NSCursor.pop()
        didPushSelectionCursor = false
    }

    private func drawSelectionSize(for rect: CGRect) {
        let pixelWidth = Int((rect.width * pixelScale.width).rounded())
        let pixelHeight = Int((rect.height * pixelScale.height).rounded())
        let label = "\(pixelWidth) x \(pixelHeight)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributedLabel = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributedLabel.size()
        let padding = CGSize(width: 10, height: 6)
        let badgeSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let badgeOrigin = badgeOrigin(for: rect, size: badgeSize)
        let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7).fill()

        attributedLabel.draw(
            at: CGPoint(
                x: badgeRect.minX + padding.width,
                y: badgeRect.minY + padding.height
            )
        )
    }

    private func badgeOrigin(for rect: CGRect, size: CGSize) -> CGPoint {
        let preferred = CGPoint(x: rect.minX, y: rect.minY - size.height - 8)
        if bounds.contains(CGRect(origin: preferred, size: size)) {
            return preferred
        }

        let fallbackY = min(rect.maxY + 8, bounds.maxY - size.height - 8)
        return CGPoint(
            x: min(max(rect.minX, bounds.minX + 8), bounds.maxX - size.width - 8),
            y: max(fallbackY, bounds.minY + 8)
        )
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
