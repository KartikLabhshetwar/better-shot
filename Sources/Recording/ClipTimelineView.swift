import SwiftUI
import AppKit

struct ClipTimelineView: NSViewRepresentable {
    let model: VideoEditorModel

    func makeNSView(context: Context) -> ClipTimelineControl {
        let control = ClipTimelineControl()
        control.model = model
        return control
    }

    func updateNSView(_ nsView: ClipTimelineControl, context: Context) {
        nsView.model = model
        nsView.needsDisplay = true
    }
}

final class ClipTimelineControl: NSView {
    var model: VideoEditorModel?

    private enum DragTarget: Equatable {
        case startHandle(UUID)
        case endHandle(UUID)
        case body(UUID)
    }

    private var dragTarget: DragTarget?
    private var dragStartPoint: CGPoint = .zero
    private var dragDidActivate = false
    private var trackingArea: NSTrackingArea?

    private let handleWidth: CGFloat = 8
    private let handleHitSlop: CGFloat = 8
    private let gapWidth: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    private let dragActivationDistance: CGFloat = 3

    private var timelineRect: NSRect { bounds }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 54)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func xPosition(for seconds: Double) -> CGFloat {
        guard let model, model.duration > 0 else { return timelineRect.minX }
        return timelineRect.minX + timelineRect.width * CGFloat(seconds / model.duration)
    }

    private func time(for x: CGFloat) -> Double {
        guard let model, model.duration > 0 else { return 0 }
        let fraction = (x - timelineRect.minX) / timelineRect.width
        return max(0, min(model.duration, Double(fraction) * model.duration))
    }

    private func hitTarget(at point: CGPoint) -> DragTarget? {
        guard let model else { return nil }

        for clip in model.clips {
            let startX = xPosition(for: clip.sourceStart)
            if abs(point.x - startX) <= handleWidth / 2 + handleHitSlop {
                return .startHandle(clip.id)
            }
            let endX = xPosition(for: clip.sourceEnd)
            if abs(point.x - endX) <= handleWidth / 2 + handleHitSlop {
                return .endHandle(clip.id)
            }
        }

        for clip in model.clips {
            let startX = xPosition(for: clip.sourceStart)
            let endX = xPosition(for: clip.sourceEnd)
            if point.x > startX, point.x < endX {
                return .body(clip.id)
            }
        }

        return nil
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch hitTarget(at: point) {
        case .startHandle, .endHandle:
            NSCursor.resizeLeftRight.set()
        case .body:
            NSCursor.pointingHand.set()
        case .none:
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
        dragDidActivate = false

        switch dragTarget {
        case .startHandle, .endHandle:
            model.beginClipTrim()
        case .body(let id):
            model.selectClip(id)
            model.seekTo(time(for: point.x))
        case .none:
            model.selectClip(nil)
            model.seekTo(time(for: point.x))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let target = dragTarget else { return }
        let point = convert(event.locationInWindow, from: nil)

        if !dragDidActivate {
            let distance = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            guard distance >= dragActivationDistance else { return }
            dragDidActivate = true
        }

        let t = time(for: point.x)
        switch target {
        case .startHandle(let id):
            guard let clip = model.clips.first(where: { $0.id == id }) else { return }
            model.updateClipTrim(id, start: t, end: clip.sourceEnd)
        case .endHandle(let id):
            guard let clip = model.clips.first(where: { $0.id == id }) else { return }
            model.updateClipTrim(id, start: clip.sourceStart, end: t)
        case .body(let id):
            model.selectClip(id)
            model.seekTo(t)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch dragTarget {
        case .startHandle, .endHandle:
            model?.endClipTrim()
        default:
            break
        }
        dragTarget = nil
        dragDidActivate = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let ctx = NSGraphicsContext.current!.cgContext
        let tl = timelineRect

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(bgPath)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()

        let thumbCount = max(1, model.thumbnails.count)
        let thumbW = tl.width / CGFloat(thumbCount)
        for (i, thumb) in model.thumbnails.enumerated() {
            let thumbRect = NSRect(x: tl.minX + CGFloat(i) * thumbW, y: tl.minY, width: thumbW, height: tl.height)
            if let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgImage, in: thumbRect)
            }
        }

        for clip in model.clips {
            let startX = xPosition(for: clip.sourceStart)
            let endX = xPosition(for: clip.sourceEnd)
            let isSelected = clip.id == model.selectedClipID
            let borderColor = isSelected ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.5)

            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fill(CGRect(x: startX, y: 0, width: gapWidth, height: bounds.height))

            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(isSelected ? 2.5 : 1)
            ctx.stroke(CGRect(x: startX + gapWidth, y: 1, width: max(0, endX - startX - gapWidth * 2), height: bounds.height - 2))

            if clip.speed != 1 {
                drawSpeedBadge(ctx: ctx, clip: clip, startX: startX, endX: endX)
            }

            if isSelected {
                drawHandle(ctx: ctx, x: startX - handleWidth / 2)
                drawHandle(ctx: ctx, x: endX - handleWidth / 2)
            }
        }

        ctx.restoreGState()

        let playheadX = xPosition(for: model.currentTime)
        ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: playheadX - 1, y: -2, width: 2, height: bounds.height + 4))
        ctx.setShadow(offset: .zero, blur: 0)
    }

    private func drawHandle(ctx: CGContext, x: CGFloat) {
        let handleRect = CGRect(x: x, y: bounds.height / 2 - 10, width: handleWidth, height: 20)
        let path = CGPath(roundedRect: handleRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawSpeedBadge(ctx: CGContext, clip: Clip, startX: CGFloat, endX: CGFloat) {
        let label = String(format: "%.1fx", clip.speed) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        let badgeRect = CGRect(x: startX + 4, y: 4, width: size.width + 8, height: size.height + 4)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.addPath(CGPath(roundedRect: badgeRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        label.draw(at: CGPoint(x: badgeRect.minX + 4, y: badgeRect.minY + 2), withAttributes: attrs)
    }
}
