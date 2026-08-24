import CoreGraphics
import Foundation

/// Maps between a timeline track's x coordinates and source time. Pure and `Sendable` so the drag math can be exercised without a view.
nonisolated struct TimelineGeometry: Equatable, Sendable {
    let trackMinX: CGFloat
    let trackWidth: CGFloat
    let duration: TimeInterval

    init(trackMinX: CGFloat, trackWidth: CGFloat, duration: TimeInterval) {
        self.trackMinX = trackMinX
        self.trackWidth = max(1, trackWidth.isFinite ? trackWidth : 1)
        self.duration = max(0, duration.isFinite ? duration : 0)
    }

    var isEmpty: Bool { duration <= 0 }

    func x(for time: TimeInterval) -> CGFloat {
        guard duration > 0 else { return trackMinX }
        return trackMinX + trackWidth * CGFloat(min(max(time / duration, 0), 1))
    }

    /// Clamped to the media, so a drag that runs past the edge of the view can never produce a negative or past-the-end time.
    func time(for x: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let fraction = Double((x - trackMinX) / trackWidth)
        return min(max(fraction, 0), 1) * duration
    }

    /// Seconds spanned by a pixel distance, so hit slop can be written in points.
    func seconds(forWidth width: CGFloat) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return Double(width / trackWidth) * duration
    }
}

/// A trim range plus the rules for dragging its edges. `Clip.minimumDuration` is the single floor the whole editor enforces, so a handle stops exactly where the timeline draws it stopping.
nonisolated struct TrimSelection: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    var duration: TimeInterval { max(0, end - start) }

    func settingStart(_ value: TimeInterval, duration: TimeInterval) -> TrimSelection {
        let ceiling = max(0, min(end, duration) - Clip.minimumDuration)
        return TrimSelection(start: min(max(value, 0), ceiling), end: end)
    }

    func settingEnd(_ value: TimeInterval, duration: TimeInterval) -> TrimSelection {
        let floor = min(start + Clip.minimumDuration, duration)
        return TrimSelection(start: start, end: max(min(value, duration), floor))
    }

    /// Slides the whole range at its current length and stops at the media edges, rather than squashing when it runs out of room.
    func shifted(by delta: TimeInterval, duration: TimeInterval) -> TrimSelection {
        let length = self.duration
        let maxStart = max(0, duration - length)
        let newStart = min(max(start + delta, 0), maxStart)
        return TrimSelection(start: newStart, end: newStart + length)
    }
}

nonisolated enum TrimDragTarget: Equatable, Sendable {
    case start
    case end
    case playhead
    case range
}

/// Resolves what a press landed on. Handles beat the playhead and the nearer handle beats the farther one, so a selection short enough for both handle targets to overlap is still trimmable from either end.
nonisolated struct TrimHitTester: Equatable, Sendable {
    let geometry: TimelineGeometry
    let slop: CGFloat

    init(geometry: TimelineGeometry, slop: CGFloat) {
        self.geometry = geometry
        self.slop = slop
    }

    func target(at x: CGFloat, selection: TrimSelection, playhead: TimeInterval) -> TrimDragTarget? {
        guard !geometry.isEmpty else { return nil }
        let startX = geometry.x(for: selection.start)
        let endX = geometry.x(for: selection.end)
        let toStart = abs(x - startX)
        let toEnd = abs(x - endX)

        if toStart <= slop || toEnd <= slop {
            return toStart <= toEnd ? .start : .end
        }
        guard x > startX, x < endX else { return nil }
        if abs(x - geometry.x(for: playhead)) <= slop { return .playhead }
        return .range
    }
}

/// One in-flight trim drag. Holds the grab offset so whatever was grabbed tracks the pointer 1:1 instead of snapping its center under the cursor on the first move.
nonisolated struct TrimDrag: Equatable, Sendable {
    let target: TrimDragTarget
    let grabOffset: TimeInterval
    let originalSelection: TrimSelection
    let originalPlayhead: TimeInterval

    init(target: TrimDragTarget, grabbedAt time: TimeInterval, selection: TrimSelection, playhead: TimeInterval) {
        self.target = target
        self.originalSelection = selection
        self.originalPlayhead = playhead
        switch target {
        case .start, .range: grabOffset = selection.start - time
        case .end: grabOffset = selection.end - time
        case .playhead: grabOffset = playhead - time
        }
    }

    func apply(at time: TimeInterval, duration: TimeInterval) -> (selection: TrimSelection, playhead: TimeInterval) {
        let target = time + grabOffset
        switch self.target {
        case .start:
            let next = originalSelection.settingStart(target, duration: duration)
            return (next, next.start)
        case .end:
            let next = originalSelection.settingEnd(target, duration: duration)
            return (next, next.end)
        case .playhead:
            return (originalSelection, min(max(target, originalSelection.start), originalSelection.end))
        case .range:
            let next = originalSelection.shifted(by: target - originalSelection.start, duration: duration)
            let playheadOffset = originalPlayhead - originalSelection.start
            return (next, min(max(next.start + playheadOffset, next.start), next.end))
        }
    }
}

/// Where a press landed on the clip timeline. Handles only exist on the selected clip, so a press resolves against the selection first.
nonisolated enum ClipDragTarget: Equatable, Sendable {
    case startHandle(UUID)
    case endHandle(UUID)
    case body(UUID)
}

nonisolated struct ClipHitTester: Sendable {
    let geometry: TimelineGeometry
    let slop: CGFloat

    init(geometry: TimelineGeometry, slop: CGFloat) {
        self.geometry = geometry
        self.slop = slop
    }

    /// The selected clip's handles are tested first so its edges stay grabbable where they butt against a neighbour, and the nearer of two candidate edges wins.
    func target(at x: CGFloat, clips: [Clip], selectedID: UUID?) -> ClipDragTarget? {
        guard !geometry.isEmpty, !clips.isEmpty else { return nil }

        let ordered = clips.filter { $0.id == selectedID } + clips.filter { $0.id != selectedID }
        for clip in ordered {
            let toStart = abs(x - geometry.x(for: clip.sourceStart))
            let toEnd = abs(x - geometry.x(for: clip.sourceEnd))
            guard toStart <= slop || toEnd <= slop else { continue }
            return toStart <= toEnd ? .startHandle(clip.id) : .endHandle(clip.id)
        }

        for clip in clips where x > geometry.x(for: clip.sourceStart) && x < geometry.x(for: clip.sourceEnd) {
            return .body(clip.id)
        }
        return nil
    }
}
