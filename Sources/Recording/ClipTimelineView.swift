import SwiftUI
import AppKit

/// `playhead` exists so the enclosing view's read of it is what schedules `updateNSView` while playback advances.
struct ClipTimelineView: NSViewRepresentable {
    let model: VideoEditorModel
    let playhead: Double

    func makeNSView(context: Context) -> ClipTimelineControl {
        let control = ClipTimelineControl()
        control.model = model
        return control
    }

    func updateNSView(_ nsView: ClipTimelineControl, context: Context) {
        nsView.model = model
        nsView.syncFromModel()
    }
}

final class ClipTimelineControl: NSView {
    var model: VideoEditorModel? {
        didSet { syncFromModel() }
    }

    private struct RenderState: Equatable {
        var clips: [Clip] = []
        var selectedClipID: UUID?
        var playhead = Double.nan
        var duration = Double.nan
        var thumbnailCount = -1
        var activeTarget: ClipDragTarget?
        var size = CGSize.zero
    }

    private struct ClipDrag {
        let target: ClipDragTarget
        let grabOffset: TimeInterval
    }

    private var drag: ClipDrag?
    private var trackingArea: NSTrackingArea?
    private var rendered = RenderState()
    private let filmstrip = TimelineFilmstrip()

    private let handleWidth: CGFloat = 8
    private let handleHitSlop: CGFloat = 8
    private let gapWidth: CGFloat = 2
    private let cornerRadius: CGFloat = 8

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 54)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    // MARK: - Geometry

    private var geometry: TimelineGeometry {
        TimelineGeometry(trackMinX: bounds.minX, trackWidth: bounds.width, duration: model?.duration ?? 0)
    }

    private func hitTarget(at x: CGFloat) -> ClipDragTarget? {
        guard let model else { return nil }
        let tester = ClipHitTester(geometry: geometry, slop: handleWidth / 2 + handleHitSlop)
        return tester.target(at: x, clips: model.clips, selectedID: model.selectedClipID)
    }

    private func clip(with id: UUID) -> Clip? {
        model?.clips.first { $0.id == id }
    }

    // MARK: - Invalidation

    /// Same reason as the trim timeline: `updateNSView` fires for every model change, and the playhead alone ticks thirty times a second.
    func syncFromModel() {
        guard let model else { return }
        let next = RenderState(
            clips: model.clips,
            selectedClipID: model.selectedClipID,
            playhead: model.currentTime,
            duration: model.duration,
            thumbnailCount: model.thumbnails.count,
            activeTarget: drag?.target,
            size: bounds.size
        )
        guard next != rendered else { return }
        rendered = next
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncFromModel()
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch hitTarget(at: point.x) {
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
        let time = geometry.time(for: point.x)

        guard let target = hitTarget(at: point.x) else {
            model.selectClip(nil)
            model.seekTo(time)
            drag = nil
            syncFromModel()
            return
        }

        model.pauseForScrub()
        switch target {
        case .startHandle(let id):
            guard let clip = clip(with: id) else { return }
            model.selectClip(id)
            model.beginClipTrim()
            drag = ClipDrag(target: target, grabOffset: clip.sourceStart - time)
        case .endHandle(let id):
            guard let clip = clip(with: id) else { return }
            model.selectClip(id)
            model.beginClipTrim()
            drag = ClipDrag(target: target, grabOffset: clip.sourceEnd - time)
        case .body(let id):
            model.selectClip(id)
            model.seekTo(time)
            drag = ClipDrag(target: target, grabOffset: 0)
        }
        syncFromModel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let time = geometry.time(for: point.x) + drag.grabOffset

        switch drag.target {
        case .startHandle(let id):
            guard let clip = clip(with: id) else { return }
            model.updateClipTrim(id, start: time, end: clip.sourceEnd)
            model.seekTo(self.clip(with: id)?.sourceStart ?? time, precise: false)
        case .endHandle(let id):
            guard let clip = clip(with: id) else { return }
            model.updateClipTrim(id, start: clip.sourceStart, end: time)
            model.seekTo(self.clip(with: id)?.sourceEnd ?? time, precise: false)
        case .body:
            model.seekTo(geometry.time(for: point.x), precise: false)
        }
        syncFromModel()
    }

    override func mouseUp(with event: NSEvent) {
        if let model, drag != nil {
            model.seekTo(model.currentTime)
        }
        drag = nil
        syncFromModel()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bgPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        ctx.addPath(bgPath)
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()

        if let strip = filmstrip.image(for: model.thumbnails, size: bounds.size, scale: window?.backingScaleFactor ?? 2) {
            ctx.drawFlipped(strip, in: bounds)
        }

        for clip in model.clips {
            let startX = geometry.x(for: clip.sourceStart)
            let endX = geometry.x(for: clip.sourceEnd)
            let isSelected = clip.id == model.selectedClipID

            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fill(CGRect(x: startX, y: 0, width: gapWidth, height: bounds.height))

            ctx.setStrokeColor((isSelected ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.5)).cgColor)
            ctx.setLineWidth(isSelected ? 2.5 : 1)
            ctx.stroke(CGRect(x: startX + gapWidth, y: 1, width: max(0, endX - startX - gapWidth * 2), height: bounds.height - 2))

            if clip.speed != 1 {
                drawSpeedBadge(ctx: ctx, clip: clip, startX: startX)
            }

            if isSelected {
                drawHandle(ctx: ctx, x: startX - handleWidth / 2, isActive: isDragging(handleOf: clip.id, atStart: true))
                drawHandle(ctx: ctx, x: endX - handleWidth / 2, isActive: isDragging(handleOf: clip.id, atStart: false))
            }
        }

        ctx.restoreGState()

        let playheadX = geometry.x(for: model.currentTime)
        ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: playheadX - 1, y: -2, width: 2, height: bounds.height + 4), cornerWidth: 1, cornerHeight: 1, transform: nil))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
    }

    private func isDragging(handleOf id: UUID, atStart: Bool) -> Bool {
        switch drag?.target {
        case .startHandle(let dragged): return atStart && dragged == id
        case .endHandle(let dragged): return !atStart && dragged == id
        default: return false
        }
    }

    private func drawHandle(ctx: CGContext, x: CGFloat, isActive: Bool) {
        let rect = CGRect(x: x, y: bounds.height / 2 - 10, width: handleWidth, height: 20)
        let fill = isActive ? NSColor.systemOrange.blended(withFraction: 0.25, of: .white) ?? .systemOrange : .systemOrange
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
    }

    private func drawSpeedBadge(ctx: CGContext, clip: Clip, startX: CGFloat) {
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
