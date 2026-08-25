import AppKit
import SwiftUI

/// One lane per kind of edit, in the order Cap stacks them, and a lane only exists once it has something in it.
enum TimelineRow: Equatable {
    case clips
    case zoom
    case text
    case mask
    case caption

    @MainActor static func rows(for model: VideoEditorModel?) -> [TimelineRow] {
        guard let model else { return [.clips] }
        var rows: [TimelineRow] = [.clips]
        if model.zoomEnabled { rows.append(.zoom) }
        if !model.texts.isEmpty { rows.append(.text) }
        if !model.masks.isEmpty { rows.append(.mask) }
        if !model.captions.isEmpty { rows.append(.caption) }
        return rows
    }

    var minimumDuration: TimeInterval {
        switch self {
        case .clips: 0
        case .zoom: ZoomCue.minimumDuration
        case .text: TextOverlay.minimumDuration
        case .mask: VideoMask.minimumDuration
        case .caption: 0.2
        }
    }
}

/// `playhead` exists so the enclosing view's read of it is what schedules `updateNSView` while playback advances.
struct CapTimelineView: NSViewRepresentable {
    let model: VideoEditorModel
    let playhead: Double

    static func height(model: VideoEditorModel) -> CGFloat {
        CapTimelineControl.height(rows: TimelineRow.rows(for: model))
    }

    func makeNSView(context: Context) -> CapTimelineControl {
        let control = CapTimelineControl()
        control.model = model
        return control
    }

    func updateNSView(_ nsView: CapTimelineControl, context: Context) {
        nsView.model = model
        nsView.syncFromModel()
    }
}

/// The whole timeline surface: minimap, ruler, clip and zoom lanes, playhead and split preview.
final class CapTimelineControl: NSView {
    enum Metrics {
        static let padding: CGFloat = 16
        static let headerHeight: CGFloat = 32
        static let playheadTop: CGFloat = 24
        static let trackHeight: CGFloat = 52
        static let laneHeight: CGFloat = 34
        static let trackGap: CGFloat = 8
        static let minimapTop: CGFloat = 2
        static let minimapHeight: CGFloat = 12
        static let segmentRadius: CGFloat = 12
        static let handleWidth: CGFloat = 20
        static let gripWidth: CGFloat = 3
        static let gripHeight: CGFloat = 32
        static let compactSegmentWidth: CGFloat = 40
        static let labelFullWidth: CGFloat = 100
        static let labelCompactWidth: CGFloat = 48
        static let labelGlyphWidth: CGFloat = 16
        static let startSnapPixels: CGFloat = 10
        static let bottomInset: CGFloat = 8
    }

    private enum Target: Equatable {
        case minimapChip
        case minimapLeftEdge
        case minimapRightEdge
        case minimapTrack
        case ruler
        case segmentStart(UUID)
        case segmentEnd(UUID)
        case segmentBody(UUID)
        case itemStart(TimelineRow, UUID)
        case itemEnd(TimelineRow, UUID)
        case itemBody(TimelineRow, UUID)
        case clipTrack
        case laneTrack(TimelineRow)
        case gutter
    }

    /// Every lane draws and drags the same way, so each one only has to say what it holds.
    private struct LaneItem: Equatable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
        let title: String
        let detail: String
    }

    private struct Segment: Equatable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
        let speed: Double
        let isTrim: Bool
        let index: Int
    }

    private struct DragState {
        let target: Target
        var grabTime: TimeInterval = 0
        var originSpeed: Double = 1
        var originStart: TimeInterval = 0
        var originEnd: TimeInterval = 0
        var originPosition: TimeInterval = 0
        var originZoom: TimeInterval = 0
        var grabX: CGFloat = 0
    }

    private struct RenderState: Equatable {
        var clips: [Clip] = []
        var lanes: [[LaneItem]] = []
        var laneSelections: [UUID?] = []
        var selectedClipID: UUID?
        var trim = TrimSelection(start: .nan, end: .nan)
        var playhead = Double.nan
        var duration = Double.nan
        var thumbnailCount = -1
        var transform = TimelineTransform(position: .nan, zoom: .nan)
        var splitMode = false
        var previewTime: TimeInterval?
        var splitPreview: TimeInterval?
        var splitSnapped = false
        var hoveredID: UUID?
        var rows: [TimelineRow] = []
        var size = CGSize.zero
    }

    private static let trimSegmentID = UUID()

    private static let splitCursor: NSCursor = {
        guard let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Split") else { return .crosshair }
        symbol.isTemplate = true
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let box = NSRect(x: 4, y: 4, width: 16, height: 16)
            symbol.draw(in: box)
            NSColor.white.set()
            box.fill(using: .sourceAtop)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    var model: VideoEditorModel? {
        didSet { syncFromModel() }
    }

    private var transform = TimelineTransform.fitting(duration: 0)
    private var fittedDuration: TimeInterval = -1
    private var previewTime: TimeInterval?
    private var splitPreview: (time: TimeInterval, snapped: Bool)?
    private var hoveredID: UUID?
    private var drag: DragState?
    private var trackingArea: NSTrackingArea?
    private var rendered = RenderState()
    private let filmstrip = TimelineFilmstrip()

    static func height(rows: [TimelineRow]) -> CGFloat {
        let stacked = rows.reduce(0) { $0 + rowHeight($1) }
        return Metrics.headerHeight + stacked + CGFloat(max(0, rows.count - 1)) * Metrics.trackGap + Metrics.bottomInset
    }

    private static func rowHeight(_ row: TimelineRow) -> CGFloat {
        row == .clips ? Metrics.trackHeight : Metrics.laneHeight
    }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height(rows: rows))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    // MARK: - Geometry

    private var rows: [TimelineRow] { TimelineRow.rows(for: model) }

    private var contentX: CGFloat { Metrics.padding }

    private var trackWidth: CGFloat { max(1, bounds.width - contentX - Metrics.padding) }

    /// The timeline draws the cut recording, so its axis is editor time and every model value crosses through the mapping below.
    private var duration: TimeInterval { model?.timelineDuration ?? 0 }

    private var sourceDuration: TimeInterval { model?.duration ?? 0 }

    private func rowRect(_ index: Int) -> CGRect {
        let stack = rows
        let top = stack.prefix(index).reduce(Metrics.headerHeight) { $0 + Self.rowHeight($1) + Metrics.trackGap }
        return CGRect(x: contentX, y: top, width: trackWidth, height: Self.rowHeight(stack[index]))
    }

    private func rowRect(for row: TimelineRow) -> CGRect? {
        guard let index = rows.firstIndex(of: row) else { return nil }
        return rowRect(index)
    }

    private var minimapRect: CGRect {
        CGRect(x: contentX, y: Metrics.minimapTop, width: trackWidth, height: Metrics.minimapHeight)
    }

    private var tracksBottom: CGFloat {
        rowRect(rows.count - 1).maxY
    }

    private func editorTime(_ sourceTime: TimeInterval) -> TimeInterval {
        model?.editorTime(forSourceTime: sourceTime) ?? sourceTime
    }

    private func sourceTime(_ editorTime: TimeInterval) -> TimeInterval {
        model?.sourceTime(atEditorTime: editorTime) ?? editorTime
    }

    private func x(editor time: TimeInterval) -> CGFloat {
        contentX + transform.x(for: time, trackWidth: trackWidth)
    }

    private func x(for sourceTime: TimeInterval) -> CGFloat {
        x(editor: editorTime(sourceTime))
    }

    /// Cap pulls the first ten pixels of the recording to zero, so the origin is always exactly reachable.
    private func time(at pointX: CGFloat) -> TimeInterval {
        let editor = transform.time(atOffset: pointX - contentX, trackWidth: trackWidth)
        let pixelsFromOrigin = CGFloat(editor / transform.secondsPerPixel(trackWidth: trackWidth))
        return sourceTime(pixelsFromOrigin <= Metrics.startSnapPixels ? 0 : max(0, editor))
    }

    private var segments: [Segment] {
        guard let model else { return [] }
        guard !model.clips.isEmpty else {
            return [Segment(id: Self.trimSegmentID, start: model.trimStart, end: model.trimEnd, speed: 1, isTrim: true, index: 0)]
        }
        return model.clips.enumerated().map {
            Segment(id: $1.id, start: $1.sourceStart, end: $1.sourceEnd, speed: $1.speed, isTrim: false, index: $0)
        }
    }

    private func segment(_ id: UUID) -> Segment? { segments.first { $0.id == id } }

    private func laneItems(_ row: TimelineRow) -> [LaneItem] {
        guard let model else { return [] }
        switch row {
        case .clips:
            return []
        case .zoom:
            return model.zoomCues.map {
                LaneItem(id: $0.id, start: $0.start, end: $0.end, title: "Zoom", detail: String(format: "%.1fx", $0.zoom))
            }
        case .text:
            return model.texts.map {
                LaneItem(id: $0.id, start: $0.start, end: $0.end, title: "Text", detail: Self.snippet($0.content, span: $0.end - $0.start))
            }
        case .mask:
            return model.masks.map {
                LaneItem(
                    id: $0.id,
                    start: $0.start,
                    end: $0.end,
                    title: $0.kind == .spotlight ? VideoMask.Kind.spotlight.title : $0.effect.title,
                    detail: Self.durationLabel($0.end - $0.start)
                )
            }
        case .caption:
            return model.captions.map {
                LaneItem(id: $0.id, start: $0.start, end: $0.end, title: "Caption", detail: Self.snippet($0.text, span: $0.end - $0.start))
            }
        }
    }

    private static func snippet(_ text: String, span: TimeInterval) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return durationLabel(span) }
        return trimmed.count <= 24 ? trimmed : trimmed.prefix(23) + "\u{2026}"
    }

    private func laneSelection(_ row: TimelineRow) -> UUID? {
        guard let model else { return nil }
        switch row {
        case .clips: return model.selectedClipID
        case .zoom: return model.selectedZoomCueID
        case .text: return model.selectedTextID
        case .mask: return model.selectedMaskID
        case .caption: return model.selectedCaptionID
        }
    }

    private func selectLaneItem(_ row: TimelineRow, _ id: UUID?) {
        guard let model else { return }
        switch row {
        case .clips: model.selectClip(id)
        case .zoom: model.selectedZoomCueID = id
        case .text: model.selectedTextID = id
        case .mask: model.selectedMaskID = id
        case .caption: model.selectedCaptionID = id
        }
    }

    private func updateLaneItem(_ row: TimelineRow, id: UUID, start: TimeInterval, end: TimeInterval) {
        guard let model else { return }
        switch row {
        case .clips:
            break
        case .zoom:
            model.updateZoomCue(id: id, start: start, end: end)
        case .text:
            guard var overlay = model.texts.first(where: { $0.id == id }) else { return }
            overlay.start = start
            overlay.end = end
            model.updateText(overlay)
        case .mask:
            guard var mask = model.masks.first(where: { $0.id == id }) else { return }
            mask.start = start
            mask.end = end
            model.updateMask(mask)
        case .caption:
            guard var cue = model.captions.first(where: { $0.id == id }) else { return }
            cue.start = start
            cue.end = end
            model.updateCaption(cue)
        }
    }

    private var snapCandidates: [TimeInterval] {
        guard let model else { return [] }
        return [model.currentTime] + model.zoomCues.flatMap { [$0.start, $0.end] }
    }

    // MARK: - Invalidation

    /// `updateNSView` fires for every model change and the playhead alone ticks thirty times a second, so redraws are gated on what actually changed.
    func syncFromModel() {
        guard let model else { return }

        if fittedDuration != model.duration {
            fittedDuration = model.duration
            transform = .fitting(duration: duration)
            invalidateIntrinsicContentSize()
        } else if transform.zoom > TimelineTransform.zoomOutLimit(duration: duration) {
            transform = .fitting(duration: duration)
        } else {
            transform = transform.positioned(at: transform.position, duration: duration)
        }

        let stack = rows
        let next = RenderState(
            clips: model.clips,
            lanes: stack.map(laneItems),
            laneSelections: stack.map(laneSelection),
            selectedClipID: model.selectedClipID,
            trim: model.trimSelection,
            playhead: model.currentTime,
            duration: duration,
            thumbnailCount: model.thumbnails.count,
            transform: transform,
            splitMode: model.timelineSplitMode,
            previewTime: previewTime,
            splitPreview: splitPreview?.time,
            splitSnapped: splitPreview?.snapped ?? false,
            hoveredID: hoveredID,
            rows: stack,
            size: bounds.size
        )
        guard next != rendered else { return }
        if next.rows != rendered.rows { invalidateIntrinsicContentSize() }
        rendered = next
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncFromModel()
    }

    // MARK: - Hit testing

    private func target(at point: CGPoint) -> Target {
        let slop = Metrics.handleWidth / 2

        if transform.isZoomedIn(duration: duration), minimapRect.insetBy(dx: 0, dy: -2).contains(point) {
            let chip = transform.minimapChip(barWidth: minimapRect.width, duration: duration)
            let left = minimapRect.minX + chip.x
            let right = left + chip.width
            if abs(point.x - left) <= 5 { return .minimapLeftEdge }
            if abs(point.x - right) <= 5 { return .minimapRightEdge }
            if point.x > left && point.x < right { return .minimapChip }
            return .minimapTrack
        }

        if point.y < Metrics.headerHeight {
            return point.x >= contentX - Metrics.startSnapPixels ? .ruler : .gutter
        }

        if let rect = rowRect(for: .clips), rect.insetBy(dx: 0, dy: -Metrics.trackGap / 2).contains(point) {
            let selected = model?.selectedClipID
            let ordered = segments.filter { $0.id == selected } + segments.filter { $0.id != selected }
            for candidate in ordered {
                let toStart = abs(point.x - x(for: candidate.start))
                let toEnd = abs(point.x - x(for: candidate.end))
                guard toStart <= slop || toEnd <= slop else { continue }
                return toStart <= toEnd ? .segmentStart(candidate.id) : .segmentEnd(candidate.id)
            }
            for candidate in segments where point.x > x(for: candidate.start) && point.x < x(for: candidate.end) {
                return .segmentBody(candidate.id)
            }
            return .clipTrack
        }

        for row in rows.dropFirst() {
            guard let rect = rowRect(for: row), rect.insetBy(dx: 0, dy: -Metrics.trackGap / 2).contains(point) else { continue }
            let items = laneItems(row)
            for candidate in items {
                let toStart = abs(point.x - x(for: candidate.start))
                let toEnd = abs(point.x - x(for: candidate.end))
                guard toStart <= slop || toEnd <= slop else { continue }
                return toStart <= toEnd ? .itemStart(row, candidate.id) : .itemEnd(row, candidate.id)
            }
            for candidate in items where point.x > x(for: candidate.start) && point.x < x(for: candidate.end) {
                return .itemBody(row, candidate.id)
            }
            return .laneTrack(row)
        }

        return .gutter
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
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hit = target(at: point)

        switch hit {
        case .segmentStart, .segmentEnd, .itemStart, .itemEnd, .minimapLeftEdge, .minimapRightEdge:
            NSCursor.resizeLeftRight.set()
        case .segmentBody where model.timelineSplitMode:
            Self.splitCursor.set()
        case .segmentBody, .itemBody, .minimapChip:
            NSCursor.pointingHand.set()
        default:
            NSCursor.arrow.set()
        }

        switch hit {
        case .segmentStart(let id), .segmentEnd(let id), .segmentBody(let id):
            hoveredID = id
        case .itemStart(_, let id), .itemEnd(_, let id), .itemBody(_, let id):
            hoveredID = id
        default:
            hoveredID = nil
        }

        let inTracks = point.y >= Metrics.headerHeight && point.y <= tracksBottom
        let overContent = point.x >= contentX && point.x <= contentX + trackWidth
        previewTime = (!model.isPlaying && (inTracks || hit == .ruler) && overContent)
            ? time(at: point.x)
            : nil

        splitPreview = model.timelineSplitMode ? splitCandidate(at: point) : nil
        syncFromModel()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        previewTime = nil
        splitPreview = nil
        hoveredID = nil
        syncFromModel()
    }

    private func splitCandidate(at point: CGPoint) -> (time: TimeInterval, snapped: Bool)? {
        guard case .segmentBody(let id) = target(at: point), let hit = segment(id) else { return nil }
        let snapper = SplitSnapper(
            clipStart: hit.start,
            clipEnd: hit.end,
            radius: transform.seconds(forWidth: SplitSnapper.snapPixels, trackWidth: trackWidth) * hit.speed
        )
        let result = snapper.snap(time(at: point.x), candidates: snapCandidates)
        guard result.time > hit.start + SplitSnapper.edgeEpsilon, result.time < hit.end - SplitSnapper.edgeEpsilon else { return nil }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hit = target(at: point)
        let pressTime = time(at: point.x)

        if model.timelineSplitMode, case .segmentBody = hit {
            guard let candidate = splitCandidate(at: point) else { return }
            model.split(at: candidate.time)
            model.timelineSplitMode = false
            splitPreview = nil
            syncFromModel()
            return
        }

        let windowDrag = DragState(
            target: hit,
            originPosition: transform.position,
            originZoom: transform.zoom,
            grabX: point.x
        )

        switch hit {
        case .gutter:
            return

        case .minimapTrack:
            transform = transform.positioned(
                at: transform.minimapClickPosition(x: point.x - minimapRect.minX, barWidth: minimapRect.width, duration: duration),
                duration: duration
            )
            drag = DragState(target: .minimapChip, originPosition: transform.position, originZoom: transform.zoom, grabX: point.x)

        case .minimapChip, .minimapLeftEdge, .minimapRightEdge:
            drag = windowDrag

        case .ruler, .clipTrack:
            model.pauseForScrub()
            if hit == .clipTrack { model.selectClip(nil) }
            model.seekTo(pressTime)
            drag = DragState(target: .ruler)

        case .laneTrack(let row):
            model.pauseForScrub()
            selectLaneItem(row, nil)
            model.seekTo(pressTime)
            drag = DragState(target: .ruler)

        case .segmentStart(let id), .segmentEnd(let id):
            guard let hitSegment = segment(id) else { return }
            model.pauseForScrub()
            model.beginClipTrim()
            if !hitSegment.isTrim { model.selectClip(id) }
            drag = DragState(
                target: hit,
                originSpeed: hitSegment.speed,
                originStart: hitSegment.start,
                originEnd: hitSegment.end,
                grabX: point.x
            )

        case .segmentBody(let id):
            model.pauseForScrub()
            if segment(id)?.isTrim == false { model.selectClip(id) }
            model.seekTo(pressTime)
            drag = DragState(target: .ruler)

        case .itemStart(let row, let id), .itemEnd(let row, let id), .itemBody(let row, let id):
            guard let item = laneItems(row).first(where: { $0.id == id }) else { return }
            selectLaneItem(row, id)
            drag = DragState(target: hit, grabTime: pressTime, originStart: item.start, originEnd: item.end)
        }

        syncFromModel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let pointerTime = time(at: point.x)

        switch drag.target {
        case .ruler:
            model.seekTo(pointerTime, precise: false)

        case .minimapChip:
            let scale = transform.minimapMoveScale(barWidth: minimapRect.width, duration: duration)
            transform = transform.positioned(
                at: drag.originPosition + Double(point.x - drag.grabX) * scale,
                duration: duration
            )

        case .minimapLeftEdge, .minimapRightEdge:
            resizeWindowFromMinimap(at: point, drag: drag)

        case .segmentStart(let id):
            applySegmentTrim(id: id, movingStart: true, to: drag.originStart + sourceDelta(to: point, drag: drag), opposite: drag.originEnd)

        case .segmentEnd(let id):
            applySegmentTrim(id: id, movingStart: false, to: drag.originEnd + sourceDelta(to: point, drag: drag), opposite: drag.originStart)

        case .itemStart(let row, let id):
            let delta = pointerTime - drag.grabTime
            let start = max(0, min(drag.originStart + delta, drag.originEnd - row.minimumDuration))
            updateLaneItem(row, id: id, start: start, end: drag.originEnd)

        case .itemEnd(let row, let id):
            let delta = pointerTime - drag.grabTime
            let end = min(sourceDuration, max(drag.originEnd + delta, drag.originStart + row.minimumDuration))
            updateLaneItem(row, id: id, start: drag.originStart, end: end)

        case .itemBody(let row, let id):
            let delta = pointerTime - drag.grabTime
            let moved = TrimSelection(start: drag.originStart, end: drag.originEnd).shifted(by: delta, duration: sourceDuration)
            updateLaneItem(row, id: id, start: moved.start, end: moved.end)

        default:
            break
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

    /// Dragging a minimap edge pins the opposite edge, which is what makes the chip read as a zoom control rather than a second scrollbar.
    private func resizeWindowFromMinimap(at point: CGPoint, drag: DragState) {
        let total = max(duration, TimelineTransform.minimumZoom)
        let secondsPerPixel = total / Double(max(1, minimapRect.width))
        let dragged = Double(point.x - drag.grabX) * secondsPerPixel

        if case .minimapLeftEdge = drag.target {
            let anchor = drag.originPosition + drag.originZoom
            transform = transform.zoomed(to: drag.originZoom - dragged, origin: anchor, duration: duration)
        } else {
            transform = transform.zoomed(to: drag.originZoom + dragged, origin: drag.originPosition, duration: duration)
        }
    }

    /// A pixel of the editor axis is one clip-speed of source second, so a handle keeps up with the pointer whatever the clip is playing at.
    private func sourceDelta(to point: CGPoint, drag: DragState) -> TimeInterval {
        transform.seconds(forWidth: point.x - drag.grabX, trackWidth: trackWidth) * drag.originSpeed
    }

    private func applySegmentTrim(id: UUID, movingStart: Bool, to edgeTime: TimeInterval, opposite: TimeInterval) {
        guard let model, let hit = segment(id) else { return }
        if hit.isTrim {
            let selection = movingStart
                ? model.trimSelection.settingStart(edgeTime, duration: sourceDuration)
                : model.trimSelection.settingEnd(edgeTime, duration: sourceDuration)
            model.applyTrimDrag(selection, playhead: movingStart ? selection.start : selection.end, precise: false)
        } else {
            model.updateClipTrim(id, start: movingStart ? edgeTime : opposite, end: movingStart ? opposite : edgeTime)
            let updated = segment(id)
            model.seekTo(movingStart ? (updated?.start ?? edgeTime) : (updated?.end ?? edgeTime), precise: false)
        }
    }

    // MARK: - Zoom and pan

    override func scrollWheel(with event: NSEvent) {
        guard duration > 0 else { return }

        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        if event.modifierFlags.contains(.control) {
            let origin = editorTime(previewTime ?? model?.currentTime ?? sourceTime(transform.position))
            let delta = Double(-event.scrollingDeltaY * scale) * transform.zoom.squareRoot() / 30
            transform = transform.zoomed(to: transform.zoom + delta, origin: origin, duration: duration)
        } else {
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 0.5
            let scroll = (horizontal || event.modifierFlags.contains(.shift)) ? event.scrollingDeltaX : event.scrollingDeltaY
            transform = transform.scrolled(
                by: -transform.seconds(forWidth: scroll * scale, trackWidth: trackWidth),
                duration: duration
            )
        }
        syncFromModel()
    }

    override func magnify(with event: NSEvent) {
        guard duration > 0 else { return }
        let origin = editorTime(previewTime ?? model?.currentTime ?? sourceTime(transform.position))
        transform = transform.zoomed(to: transform.zoom / (1 + event.magnification), origin: origin, duration: duration)
        syncFromModel()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(Palette.surface.cgColor)
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: Metrics.segmentRadius, cornerHeight: Metrics.segmentRadius, transform: nil))
        ctx.fillPath()

        drawMarkings(ctx: ctx)
        drawMinimap(ctx: ctx)

        for (index, row) in rows.enumerated() {
            let rect = rowRect(index)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: Metrics.segmentRadius, cornerHeight: Metrics.segmentRadius, transform: nil))
            ctx.clip()
            ctx.setFillColor(Palette.trackWell.cgColor)
            ctx.fill(rect)
            if row == .clips {
                drawClipTrack(ctx: ctx, rect: rect, model: model)
            } else {
                drawLane(ctx: ctx, rect: rect, row: row)
            }
            ctx.restoreGState()
        }

        drawPlayheads(ctx: ctx, model: model)
    }

    private enum Palette {
        static let surface = NSColor.black.withAlphaComponent(0.22)
        static let trackWell = NSColor.white.withAlphaComponent(0.05)
        static let clip = NSColor(srgbRed: 0.29, green: 0.45, blue: 0.98, alpha: 1)
        static let cue = NSColor(srgbRed: 0.62, green: 0.42, blue: 0.96, alpha: 1)
        static let text = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.24, alpha: 1)
        static let mask = NSColor(srgbRed: 0.18, green: 0.72, blue: 0.66, alpha: 1)
        static let caption = NSColor(srgbRed: 0.92, green: 0.36, blue: 0.55, alpha: 1)

        static func lane(_ row: TimelineRow) -> NSColor {
            switch row {
            case .clips, .zoom: cue
            case .text: text
            case .mask: mask
            case .caption: caption
            }
        }
        static let playhead = NSColor(srgbRed: 226 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)
        static let snap = NSColor(srgbRed: 0.29, green: 0.56, blue: 0.99, alpha: 1)
    }

    private func drawMarkings(ctx: CGContext) {
        let resolution = transform.markingResolution
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4)
        ]

        ctx.saveGState()
        ctx.clip(to: CGRect(x: contentX, y: 0, width: trackWidth, height: Metrics.headerHeight))
        for index in 0..<transform.markingCount {
            let time = transform.markingTime(index: index)
            guard time >= 0 else { continue }
            let markX = x(editor: time)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.fillEllipse(in: CGRect(x: markX - 1, y: Metrics.headerHeight - 8, width: 2, height: 2))

            guard time.truncatingRemainder(dividingBy: max(1, resolution)) == 0 else { continue }
            let label = Self.rulerLabel(time) as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: markX - (time == 0 ? 0 : size.width / 2), y: 4), withAttributes: attributes)
        }
        ctx.restoreGState()
    }

    private func drawMinimap(ctx: CGContext) {
        guard transform.isZoomedIn(duration: duration) else { return }
        let rect = minimapRect
        let radius = rect.height / 2

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()

        let total = max(duration, TimelineTransform.minimumZoom)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        for boundary in segments.dropFirst().map({ editorTime($0.start) }) {
            let tickX = rect.minX + rect.width * CGFloat(min(max(boundary / total, 0), 1))
            ctx.fill(CGRect(x: tickX - 0.5, y: rect.minY + 2, width: 1, height: rect.height - 4))
        }

        let chip = transform.minimapChip(barWidth: rect.width, duration: duration)
        let chipRect = CGRect(x: rect.minX + chip.x, y: rect.minY, width: chip.width, height: rect.height)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.24).cgColor)
        ctx.addPath(CGPath(roundedRect: chipRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
    }

    private func drawClipTrack(ctx: CGContext, rect: CGRect, model: VideoEditorModel) {
        drawFilmstrip(ctx: ctx, rect: rect, model: model)

        for segment in segments where transform.isVisible(start: editorTime(segment.start), end: editorTime(segment.end)) {
            let box = CGRect(
                x: x(for: segment.start),
                y: rect.minY,
                width: max(2, x(for: segment.end) - x(for: segment.start)),
                height: rect.height
            )
            let isSelected = segment.id == model.selectedClipID
            drawSegment(
                ctx: ctx,
                box: box,
                color: Palette.clip,
                filled: false,
                isSelected: isSelected,
                isHovered: hoveredID == segment.id,
                title: segment.isTrim ? "Video" : "Clip \(segment.index + 1)",
                detail: segment.speed == 1 ? Self.durationLabel(segment.end - segment.start) : "\(segment.speed.formatted())x"
            )
        }
    }

    private func drawLane(ctx: CGContext, rect: CGRect, row: TimelineRow) {
        let selected = laneSelection(row)
        for item in laneItems(row) where transform.isVisible(start: editorTime(item.start), end: editorTime(item.end)) {
            let box = CGRect(
                x: x(for: item.start),
                y: rect.minY,
                width: max(2, x(for: item.end) - x(for: item.start)),
                height: rect.height
            )
            drawSegment(
                ctx: ctx,
                box: box,
                color: Palette.lane(row),
                filled: true,
                isSelected: item.id == selected,
                isHovered: hoveredID == item.id,
                title: item.title,
                detail: item.detail
            )
        }
    }

    /// Drawn per segment against the source strip, so a cut hides the frames it removed instead of sliding them along.
    private func drawFilmstrip(ctx: CGContext, rect: CGRect, model: VideoEditorModel) {
        guard sourceDuration > 0 else { return }
        let referenceWidth: CGFloat = 2048
        guard let strip = filmstrip.image(
            for: model.thumbnails,
            size: CGSize(width: referenceWidth, height: rect.height),
            scale: 1
        ) else { return }

        let windowStart = sourceTime(transform.position)
        let windowEnd = sourceTime(transform.position + transform.zoom)

        ctx.saveGState()
        ctx.setAlpha(0.5)
        for segment in segments {
            let start = max(segment.start, windowStart)
            let end = min(segment.end, windowEnd)
            guard end > start else { continue }

            let source = CGRect(
                x: CGFloat(start / sourceDuration) * CGFloat(strip.width),
                y: 0,
                width: max(1, CGFloat((end - start) / sourceDuration) * CGFloat(strip.width)),
                height: CGFloat(strip.height)
            )
            guard let cropped = strip.cropping(to: source) else { continue }
            ctx.drawFlipped(cropped, in: CGRect(
                x: x(for: start),
                y: rect.minY,
                width: max(1, x(for: end) - x(for: start)),
                height: rect.height
            ))
        }
        ctx.restoreGState()
    }

    /// Cap's segment: rounded body, a border a shade darker than its fill, edge grips, and a label that sheds detail as it narrows.
    private func drawSegment(
        ctx: CGContext,
        box: CGRect,
        color: NSColor,
        filled: Bool,
        isSelected: Bool,
        isHovered: Bool,
        title: String,
        detail: String
    ) {
        let path = CGPath(roundedRect: box.insetBy(dx: 1, dy: 1), cornerWidth: Metrics.segmentRadius, cornerHeight: Metrics.segmentRadius, transform: nil)
        ctx.setFillColor(color.withAlphaComponent(filled ? (isSelected ? 0.95 : 0.6) : (isSelected ? 0.3 : 0.16)).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        let border = color.blended(withFraction: 0.42, of: .black) ?? color
        ctx.setStrokeColor((isSelected ? NSColor.white.withAlphaComponent(0.85) : border.withAlphaComponent(0.9)).cgColor)
        ctx.setLineWidth(isSelected ? 2 : 1)
        ctx.addPath(path)
        ctx.strokePath()

        drawSegmentLabel(ctx: ctx, box: box, title: title, detail: detail)

        let compact = box.width < Metrics.compactSegmentWidth
        let opacity: CGFloat = isHovered || isSelected ? 1 : (compact ? 0.55 : 0.35)
        for edge in [box.minX, box.maxX] {
            let grip = CGRect(
                x: edge - Metrics.gripWidth / 2,
                y: box.midY - Metrics.gripHeight / 2,
                width: Metrics.gripWidth,
                height: min(Metrics.gripHeight, box.height - 12)
            )
            ctx.setFillColor(NSColor.white.withAlphaComponent(opacity).cgColor)
            ctx.addPath(CGPath(roundedRect: grip, cornerWidth: Metrics.gripWidth / 2, cornerHeight: Metrics.gripWidth / 2, transform: nil))
            ctx.fillPath()
        }
    }

    private func drawSegmentLabel(ctx: CGContext, box: CGRect, title: String, detail: String) {
        guard box.width >= Metrics.labelGlyphWidth else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: box.insetBy(dx: 8, dy: 0))

        guard box.width >= Metrics.labelCompactWidth else {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.fillEllipse(in: CGRect(x: box.midX - 2, y: box.midY - 2, width: 4, height: 4))
            return
        }

        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]

        guard box.width >= Metrics.labelFullWidth else {
            let label = detail as NSString
            let size = label.size(withAttributes: detailAttributes)
            label.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: detailAttributes)
            return
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        guard box.height >= Metrics.trackHeight else {
            let label = "\(title)  \(detail)" as NSString
            let size = label.size(withAttributes: titleAttributes)
            label.draw(at: CGPoint(x: box.minX + 10, y: box.midY - size.height / 2), withAttributes: titleAttributes)
            return
        }
        (title as NSString).draw(at: CGPoint(x: box.minX + 10, y: box.minY + 8), withAttributes: titleAttributes)
        (detail as NSString).draw(at: CGPoint(x: box.minX + 10, y: box.maxY - 22), withAttributes: detailAttributes)
    }

    private func drawPlayheads(ctx: CGContext, model: VideoEditorModel) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: contentX - 8, y: 0, width: trackWidth + 16, height: bounds.height))

        if let previewTime, splitPreview == nil, !model.isPlaying {
            drawMarker(ctx: ctx, x: x(for: previewTime), color: NSColor.white.withAlphaComponent(0.55), head: .circle)
        }

        if let splitPreview {
            drawMarker(
                ctx: ctx,
                x: x(for: splitPreview.time),
                color: splitPreview.snapped ? Palette.snap : NSColor.white.withAlphaComponent(0.5),
                head: splitPreview.snapped ? .diamond : .none
            )
        }

        drawMarker(
            ctx: ctx,
            x: x(for: model.currentTime),
            color: Palette.playhead.withAlphaComponent(model.timelineSplitMode ? 0.5 : 1),
            head: .circle
        )
        ctx.restoreGState()
    }

    private enum MarkerHead { case circle, diamond, none }

    private func drawMarker(ctx: CGContext, x markerX: CGFloat, color: NSColor, head: MarkerHead) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: markerX - 0.5, y: Metrics.playheadTop, width: 1, height: tracksBottom - Metrics.playheadTop))

        switch head {
        case .circle:
            ctx.fillEllipse(in: CGRect(x: markerX - 6, y: Metrics.playheadTop - 8, width: 12, height: 12))
        case .diamond:
            ctx.saveGState()
            ctx.translateBy(x: markerX, y: Metrics.playheadTop)
            ctx.rotate(by: .pi / 4)
            ctx.fill(CGRect(x: -4, y: -4, width: 8, height: 8))
            ctx.restoreGState()
        case .none:
            break
        }
    }

    private static func rulerLabel(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        seconds < 60 ? String(format: "%.1fs", seconds) : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
