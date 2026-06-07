import SwiftUI
import AppKit

struct VideoTrimTimelineView: NSViewRepresentable {
    let model: VideoEditorModel

    func makeNSView(context: Context) -> VideoTrimTimelineControl {
        let control = VideoTrimTimelineControl()
        control.model = model
        return control
    }

    func updateNSView(_ nsView: VideoTrimTimelineControl, context: Context) {
        nsView.model = model
        nsView.needsDisplay = true
    }
}

final class VideoTrimTimelineControl: NSView {
    var model: VideoEditorModel?

    private enum DragTarget {
        case startHandle
        case endHandle
        case playhead
        case selectedRange
    }

    private var dragTarget: DragTarget?
    private var dragStartPoint: CGPoint = .zero
    private var dragStartSelection: (start: Double, end: Double) = (0, 0)
    private var dragStartPlayhead: Double = 0
    private var dragDidActivate = false
    private var trackingArea: NSTrackingArea?

    private let handleWidth: CGFloat = 12
    private let handleHitSlop: CGFloat = 14
    private let gripBarWidth: CGFloat = 2
    private let gripBarSpacing: CGFloat = 3
    private let borderWidth: CGFloat = 3
    private let playheadWidth: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    private let dragActivationDistance: CGFloat = 3

    private var timelineRect: NSRect {
        NSRect(x: handleWidth, y: 0, width: bounds.width - handleWidth * 2, height: bounds.height)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 54)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Coordinate conversion

    private func xPosition(for seconds: Double) -> CGFloat {
        guard let model, model.duration > 0 else { return timelineRect.minX }
        return timelineRect.minX + timelineRect.width * CGFloat(seconds / model.duration)
    }

    private func time(for x: CGFloat) -> Double {
        guard let model, model.duration > 0 else { return 0 }
        return Double((x - timelineRect.minX) / timelineRect.width) * model.duration
    }

    // MARK: - Hit testing

    private func hitTarget(at point: CGPoint) -> DragTarget? {
        guard let model else { return nil }

        let startX = xPosition(for: model.trimStart)
        if abs(point.x - startX) <= handleWidth / 2 + handleHitSlop {
            return .startHandle
        }

        let endX = xPosition(for: model.trimEnd)
        if abs(point.x - endX) <= handleWidth / 2 + handleHitSlop {
            return .endHandle
        }

        let playheadX = xPosition(for: model.currentTime)
        if abs(point.x - playheadX) <= 10 && point.x > startX && point.x < endX {
            return .playhead
        }

        if point.x > startX && point.x < endX {
            return .selectedRange
        }

        return nil
    }

    // MARK: - Mouse events

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let target = hitTarget(at: point) {
            switch target {
            case .startHandle, .endHandle:
                NSCursor.resizeLeftRight.set()
            case .playhead:
                NSCursor.resizeLeftRight.set()
            case .selectedRange:
                NSCursor.openHand.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)

        dragTarget = hitTarget(at: point)
        dragStartPoint = point
        dragStartSelection = (model.trimStart, model.trimEnd)
        dragStartPlayhead = model.currentTime
        dragDidActivate = false

        if dragTarget == nil {
            let t = time(for: point.x)
            let clamped = max(model.trimStart, min(t, model.trimEnd))
            DispatchQueue.main.async { model.seekTo(clamped) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let target = dragTarget else { return }
        let point = convert(event.locationInWindow, from: nil)

        if !dragDidActivate {
            let dist = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            if dist < dragActivationDistance { return }
            dragDidActivate = true
            if target == .selectedRange {
                NSCursor.closedHand.set()
            }
        }

        let t = time(for: point.x)
        let minDuration = 0.25

        DispatchQueue.main.async {
            switch target {
            case .startHandle:
                let newStart = max(0, min(t, model.trimEnd - minDuration))
                model.setTrimStart(newStart)
                model.seekTo(newStart)

            case .endHandle:
                let newEnd = min(model.duration, max(t, model.trimStart + minDuration))
                model.setTrimEnd(newEnd)
                model.seekTo(newEnd)

            case .playhead:
                let clamped = max(model.trimStart, min(t, model.trimEnd))
                model.seekTo(clamped)

            case .selectedRange:
                let dx = point.x - self.dragStartPoint.x
                let dt = Double(dx / self.timelineRect.width) * model.duration
                let rangeDuration = self.dragStartSelection.end - self.dragStartSelection.start
                var newStart = self.dragStartSelection.start + dt
                newStart = max(0, min(newStart, model.duration - rangeDuration))
                model.trimStart = newStart
                model.trimEnd = newStart + rangeDuration

                let relativePlayhead = self.dragStartPlayhead - self.dragStartSelection.start
                model.seekTo(newStart + relativePlayhead)
            }
            self.needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragTarget == .selectedRange && !dragDidActivate {
            let point = convert(event.locationInWindow, from: nil)
            let t = time(for: point.x)
            if let model {
                let clamped = max(model.trimStart, min(t, model.trimEnd))
                DispatchQueue.main.async { model.seekTo(clamped) }
            }
        }

        dragTarget = nil
        let point = convert(event.locationInWindow, from: nil)
        if let target = hitTarget(at: point) {
            switch target {
            case .startHandle, .endHandle, .playhead:
                NSCursor.resizeLeftRight.set()
            case .selectedRange:
                NSCursor.openHand.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let ctx = NSGraphicsContext.current!.cgContext

        let startX = xPosition(for: model.trimStart)
        let endX = xPosition(for: model.trimEnd)
        let tl = timelineRect

        // 1. Background
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // 2. Thumbnails
        ctx.saveGState()
        let clipPath = CGPath(roundedRect: tl, cornerWidth: cornerRadius - 2, cornerHeight: cornerRadius - 2, transform: nil)
        ctx.addPath(clipPath)
        ctx.clip()

        let thumbCount = max(1, model.thumbnails.count)
        let thumbW = tl.width / CGFloat(thumbCount)
        for (i, thumb) in model.thumbnails.enumerated() {
            let thumbRect = NSRect(x: tl.minX + CGFloat(i) * thumbW, y: tl.minY, width: thumbW, height: tl.height)
            if let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgImage, in: thumbRect)
            }
        }
        ctx.restoreGState()

        // 3. Dimmed regions outside selection
        ctx.saveGState()
        ctx.addPath(clipPath)
        ctx.clip()

        let dimColor = NSColor.black.withAlphaComponent(0.6).cgColor
        if startX > tl.minX {
            ctx.setFillColor(dimColor)
            ctx.fill(CGRect(x: tl.minX, y: 0, width: startX - tl.minX, height: bounds.height))
        }
        if endX < tl.maxX {
            ctx.setFillColor(dimColor)
            ctx.fill(CGRect(x: endX, y: 0, width: tl.maxX - endX, height: bounds.height))
        }
        ctx.restoreGState()

        // 4. Selection border (top and bottom lines)
        let selColor = NSColor.systemOrange.cgColor
        ctx.setFillColor(selColor)
        ctx.fill(CGRect(x: startX, y: 0, width: endX - startX, height: borderWidth))
        ctx.fill(CGRect(x: startX, y: bounds.height - borderWidth, width: endX - startX, height: borderWidth))

        // 5. Start handle
        drawHandle(ctx: ctx, x: startX - handleWidth, isStart: true)

        // 6. End handle
        drawHandle(ctx: ctx, x: endX, isStart: false)

        // 7. Playhead
        if dragTarget != .startHandle && dragTarget != .endHandle {
            let playheadX = xPosition(for: model.currentTime)
            if playheadX >= startX && playheadX <= endX {
                ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
                ctx.setFillColor(NSColor.white.cgColor)
                let playheadRect = CGRect(
                    x: playheadX - playheadWidth / 2,
                    y: -2,
                    width: playheadWidth,
                    height: bounds.height + 4
                )
                ctx.fill(playheadRect)
                ctx.setShadow(offset: .zero, blur: 0)
            }
        }
    }

    private func drawHandle(ctx: CGContext, x: CGFloat, isStart: Bool) {
        let handleRect = CGRect(x: x, y: 0, width: handleWidth, height: bounds.height)
        let handleColor = NSColor.systemOrange.cgColor

        let path = CGMutablePath()
        let r = cornerRadius
        if isStart {
            path.move(to: CGPoint(x: handleRect.minX + r, y: handleRect.minY))
            path.addLine(to: CGPoint(x: handleRect.maxX, y: handleRect.minY))
            path.addLine(to: CGPoint(x: handleRect.maxX, y: handleRect.maxY))
            path.addLine(to: CGPoint(x: handleRect.minX + r, y: handleRect.maxY))
            path.addArc(center: CGPoint(x: handleRect.minX + r, y: handleRect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            path.addLine(to: CGPoint(x: handleRect.minX, y: handleRect.minY + r))
            path.addArc(center: CGPoint(x: handleRect.minX + r, y: handleRect.minY + r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        } else {
            path.move(to: CGPoint(x: handleRect.minX, y: handleRect.minY))
            path.addLine(to: CGPoint(x: handleRect.maxX - r, y: handleRect.minY))
            path.addArc(center: CGPoint(x: handleRect.maxX - r, y: handleRect.minY + r), radius: r, startAngle: 3 * .pi / 2, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: handleRect.maxX, y: handleRect.maxY - r))
            path.addArc(center: CGPoint(x: handleRect.maxX - r, y: handleRect.maxY - r), radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
            path.addLine(to: CGPoint(x: handleRect.minX, y: handleRect.maxY))
        }
        path.closeSubpath()

        ctx.setFillColor(handleColor)
        ctx.addPath(path)
        ctx.fillPath()

        // Grip bars
        let centerX = handleRect.midX
        let centerY = handleRect.midY
        let barHeight: CGFloat = 16

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(gripBarWidth)
        ctx.setLineCap(.round)

        let offset = gripBarSpacing
        for dx in [-offset, offset] {
            ctx.move(to: CGPoint(x: centerX + dx, y: centerY - barHeight / 2))
            ctx.addLine(to: CGPoint(x: centerX + dx, y: centerY + barHeight / 2))
            ctx.strokePath()
        }
    }
}
