import SwiftUI
import AppKit

/// `playhead` exists so the enclosing view's read of it is what schedules `updateNSView` while playback advances.
struct VideoTrimTimelineView: NSViewRepresentable {
    let model: VideoEditorModel
    let playhead: Double

    func makeNSView(context: Context) -> VideoTrimTimelineControl {
        let control = VideoTrimTimelineControl()
        control.model = model
        return control
    }

    func updateNSView(_ nsView: VideoTrimTimelineControl, context: Context) {
        nsView.model = model
        nsView.syncFromModel()
    }
}

final class VideoTrimTimelineControl: NSView {
    var model: VideoEditorModel? {
        didSet { syncFromModel() }
    }

    private struct RenderState: Equatable {
        var trimStart = Double.nan
        var trimEnd = Double.nan
        var playhead = Double.nan
        var duration = Double.nan
        var thumbnailCount = -1
        var activeTarget: TrimDragTarget?
        var hoverTarget: TrimDragTarget?
        var size = CGSize.zero
    }

    private var drag: TrimDrag?
    private var dragStartX: CGFloat = 0
    private var dragDidActivate = false
    private var hoverTarget: TrimDragTarget?
    private var trackingArea: NSTrackingArea?
    private var rendered = RenderState()
    private let filmstrip = TimelineFilmstrip()

    private let handleWidth: CGFloat = 12
    private let handleHitSlop: CGFloat = 14
    private let borderWidth: CGFloat = 2.5
    private let playheadWidth: CGFloat = 2
    private let cornerRadius: CGFloat = 8
    private let rangeDragThreshold: CGFloat = 3

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

    private var trackRect: NSRect {
        NSRect(x: handleWidth, y: 0, width: max(1, bounds.width - handleWidth * 2), height: bounds.height)
    }

    private var geometry: TimelineGeometry {
        TimelineGeometry(trackMinX: trackRect.minX, trackWidth: trackRect.width, duration: model?.duration ?? 0)
    }

    private var selection: TrimSelection {
        TrimSelection(start: model?.trimStart ?? 0, end: model?.trimEnd ?? 0)
    }

    private func hitTarget(at x: CGFloat) -> TrimDragTarget? {
        guard let model else { return nil }
        let tester = TrimHitTester(geometry: geometry, slop: handleWidth / 2 + handleHitSlop)
        return tester.target(at: x, selection: selection, playhead: model.currentTime)
    }

    // MARK: - Invalidation

    /// Redraws only when something visible actually changed: SwiftUI re-runs `updateNSView` for every unrelated edit, and playback alone ticks it thirty times a second.
    func syncFromModel() {
        guard let model else { return }
        let next = RenderState(
            trimStart: model.trimStart,
            trimEnd: model.trimEnd,
            playhead: model.currentTime,
            duration: model.duration,
            thumbnailCount: model.thumbnails.count,
            activeTarget: drag?.target,
            hoverTarget: hoverTarget,
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
        hoverTarget = hitTarget(at: point.x)
        applyCursor(for: hoverTarget, isDragging: false)
        syncFromModel()
    }

    override func mouseExited(with event: NSEvent) {
        hoverTarget = nil
        NSCursor.arrow.set()
        syncFromModel()
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let time = geometry.time(for: point.x)

        dragStartX = point.x
        dragDidActivate = false

        guard let target = hitTarget(at: point.x) else {
            model.seekTo(min(max(time, model.trimStart), model.trimEnd))
            syncFromModel()
            return
        }

        model.pauseForScrub()
        drag = TrimDrag(target: target, grabbedAt: time, selection: selection, playhead: model.currentTime)
        applyCursor(for: target, isDragging: true)
        syncFromModel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let drag else { return }
        let point = convert(event.locationInWindow, from: nil)

        if drag.target == .range, !dragDidActivate {
            guard abs(point.x - dragStartX) >= rangeDragThreshold else { return }
            dragDidActivate = true
        }

        let result = drag.apply(at: geometry.time(for: point.x), duration: model.duration)
        model.applyTrimDrag(result.selection, playhead: result.playhead, precise: false)
        syncFromModel()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let model, let drag {
            if drag.target == .range, !dragDidActivate {
                model.seekTo(min(max(geometry.time(for: point.x), model.trimStart), model.trimEnd))
            } else {
                model.seekTo(model.currentTime)
            }
        }
        drag = nil
        dragDidActivate = false
        hoverTarget = hitTarget(at: point.x)
        applyCursor(for: hoverTarget, isDragging: false)
        syncFromModel()
    }

    private func applyCursor(for target: TrimDragTarget?, isDragging: Bool) {
        switch target {
        case .start, .end, .playhead:
            NSCursor.resizeLeftRight.set()
        case .range:
            (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
        case nil:
            NSCursor.arrow.set()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let track = trackRect
        let startX = geometry.x(for: model.trimStart)
        let endX = geometry.x(for: model.trimEnd)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        ctx.fillPath()

        ctx.saveGState()
        let trackPath = CGPath(roundedRect: track, cornerWidth: cornerRadius - 2, cornerHeight: cornerRadius - 2, transform: nil)
        ctx.addPath(trackPath)
        ctx.clip()

        if let strip = filmstrip.image(for: model.thumbnails, size: track.size, scale: window?.backingScaleFactor ?? 2) {
            ctx.drawFlipped(strip, in: track)
        } else {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
            ctx.fill(track)
        }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        if startX > track.minX {
            ctx.fill(CGRect(x: track.minX, y: track.minY, width: startX - track.minX, height: track.height))
        }
        if endX < track.maxX {
            ctx.fill(CGRect(x: endX, y: track.minY, width: track.maxX - endX, height: track.height))
        }
        ctx.restoreGState()

        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.fill(CGRect(x: startX, y: 0, width: endX - startX, height: borderWidth))
        ctx.fill(CGRect(x: startX, y: bounds.height - borderWidth, width: endX - startX, height: borderWidth))

        drawHandle(ctx: ctx, x: startX - handleWidth, isStart: true, isActive: isEmphasized(.start))
        drawHandle(ctx: ctx, x: endX, isStart: false, isActive: isEmphasized(.end))

        if drag?.target != .start, drag?.target != .end {
            drawPlayhead(ctx: ctx, x: geometry.x(for: model.currentTime), within: startX...max(startX, endX))
        }
    }

    private func isEmphasized(_ target: TrimDragTarget) -> Bool {
        drag?.target == target || (drag == nil && hoverTarget == target)
    }

    private func drawPlayhead(ctx: CGContext, x: CGFloat, within range: ClosedRange<CGFloat>) {
        guard range.contains(x) else { return }
        ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: x - playheadWidth / 2, y: -2, width: playheadWidth, height: bounds.height + 4),
            cornerWidth: playheadWidth / 2,
            cornerHeight: playheadWidth / 2,
            transform: nil
        ))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
    }

    private func drawHandle(ctx: CGContext, x: CGFloat, isStart: Bool, isActive: Bool) {
        let rect = CGRect(x: x, y: 0, width: handleWidth, height: bounds.height)
        let path = CGMutablePath()
        let r = cornerRadius

        if isStart {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 3 * .pi / 2, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()

        let fill = isActive ? NSColor.systemOrange.blended(withFraction: 0.25, of: .white) ?? .systemOrange : .systemOrange
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        for dx in [CGFloat(-2.5), 2.5] {
            ctx.move(to: CGPoint(x: rect.midX + dx, y: rect.midY - 8))
            ctx.addLine(to: CGPoint(x: rect.midX + dx, y: rect.midY + 8))
            ctx.strokePath()
        }
    }
}

struct ZoomCueLaneView: View {
    let model: VideoEditorModel

    private let sideInset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(1, geo.size.width - sideInset * 2)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: trackWidth, height: geo.size.height)
                    .offset(x: sideInset)

                ForEach(model.zoomCues) { cue in
                    ZoomCuePillView(
                        model: model,
                        cue: cue,
                        trackWidth: trackWidth,
                        sideInset: sideInset,
                        laneHeight: geo.size.height
                    )
                }
            }
            .coordinateSpace(.named(ZoomCuePillView.laneSpace))
        }
    }
}

private struct ZoomCuePillView: View {
    static let laneSpace = "bs.zoomCueLane"

    let model: VideoEditorModel
    let cue: ZoomCue
    let trackWidth: CGFloat
    let sideInset: CGFloat
    let laneHeight: CGFloat

    @State private var dragOrigin: (start: TimeInterval, end: TimeInterval)?

    private enum DragKind { case move, resizeStart, resizeEnd }

    private var isSelected: Bool { model.selectedZoomCueID == cue.id }

    private var geometry: TimelineGeometry {
        TimelineGeometry(trackMinX: sideInset, trackWidth: trackWidth, duration: model.duration)
    }

    var body: some View {
        let startX = geometry.x(for: cue.start)
        let endX = geometry.x(for: cue.end)
        let width = max(6, endX - startX)
        let edgeWidth = min(6, width / 3)

        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.55))
                .frame(width: width, height: laneHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(kind: .move))
                .onTapGesture { model.selectedZoomCueID = cue.id }

            HStack {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: edgeWidth, height: laneHeight)
                    .gesture(dragGesture(kind: .resizeStart))
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: edgeWidth, height: laneHeight)
                    .gesture(dragGesture(kind: .resizeEnd))
            }
            .frame(width: width, height: laneHeight)
        }
        .frame(width: width, height: laneHeight)
        .position(x: startX + width / 2, y: laneHeight / 2)
    }

    private func dragGesture(kind: DragKind) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.laneSpace))
            .onChanged { value in
                let origin = dragOrigin ?? (cue.start, cue.end)
                dragOrigin = origin
                guard model.duration > 0 else { return }

                let dt = geometry.seconds(forWidth: value.translation.width)
                switch kind {
                case .move:
                    let moved = TrimSelection(start: origin.start, end: origin.end)
                        .shifted(by: dt, duration: model.duration)
                    model.updateZoomCue(id: cue.id, start: moved.start, end: moved.end)
                case .resizeStart:
                    let newStart = max(0, min(origin.start + dt, origin.end - ZoomCue.minimumDuration))
                    model.updateZoomCue(id: cue.id, start: newStart, end: origin.end)
                case .resizeEnd:
                    let newEnd = min(model.duration, max(origin.end + dt, origin.start + ZoomCue.minimumDuration))
                    model.updateZoomCue(id: cue.id, start: origin.start, end: newEnd)
                }
                model.selectedZoomCueID = cue.id
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }
}
