import CoreGraphics
import Foundation

/// Cap's windowed timeline: `zoom` is the visible span in seconds, `position` the time sitting at the left edge of the track.
nonisolated struct TimelineTransform: Equatable, Sendable {
    static let minimumZoom: TimeInterval = 3
    static let maximumZoom: TimeInterval = 600
    static let markingResolutions: [TimeInterval] = [0.5, 1, 2.5, 5, 10, 30]
    static let maximumMarkings = 20
    static let renderPadding: TimeInterval = 2
    static let trailingSlack: TimeInterval = 4
    static let minimumChipWidth: CGFloat = 20

    var position: TimeInterval
    var zoom: TimeInterval

    init(position: TimeInterval, zoom: TimeInterval) {
        self.zoom = zoom.isFinite ? max(zoom, Self.minimumZoom) : Self.minimumZoom
        self.position = position.isFinite ? max(position, 0) : 0
    }

    /// The widest window the timeline will ever show, so a ten minute recording still scrolls instead of squashing.
    static func zoomOutLimit(duration: TimeInterval) -> TimeInterval {
        let span = duration.isFinite ? max(duration, 0) : 0
        return max(minimumZoom, min(span, maximumZoom))
    }

    static func fitting(duration: TimeInterval) -> TimelineTransform {
        TimelineTransform(position: 0, zoom: zoomOutLimit(duration: duration))
    }

    func secondsPerPixel(trackWidth: CGFloat) -> Double {
        zoom / Double(max(1, trackWidth))
    }

    func x(for time: TimeInterval, trackWidth: CGFloat) -> CGFloat {
        CGFloat((time - position) / secondsPerPixel(trackWidth: trackWidth))
    }

    func time(atOffset x: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        position + secondsPerPixel(trackWidth: trackWidth) * Double(x)
    }

    func seconds(forWidth width: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        secondsPerPixel(trackWidth: trackWidth) * Double(width)
    }

    var visibleRange: ClosedRange<TimeInterval> {
        max(0, position - Self.renderPadding)...(position + zoom + Self.renderPadding)
    }

    func isVisible(start: TimeInterval, end: TimeInterval) -> Bool {
        let range = visibleRange
        return end >= range.lowerBound && start <= range.upperBound
    }

    /// The coarsest ruler step that still keeps the window under `maximumMarkings` ticks.
    var markingResolution: TimeInterval {
        Self.markingResolutions.first { zoom / $0 <= Double(Self.maximumMarkings) } ?? 30
    }

    var markingCount: Int {
        Int((2 + (zoom + 5) / markingResolution).rounded(.up))
    }

    func markingTime(index: Int) -> TimeInterval {
        let resolution = markingResolution
        return position - position.truncatingRemainder(dividingBy: resolution) + Double(index) * resolution
    }

    /// Keeps `origin` under the same pixel as the span changes, which is what makes cursor-anchored zoom feel attached to the pointer.
    func zoomed(to newZoom: TimeInterval, origin: TimeInterval, duration: TimeInterval) -> TimelineTransform {
        guard newZoom.isFinite, origin.isFinite else { return self }
        let clamped = max(min(newZoom, Self.zoomOutLimit(duration: duration)), Self.minimumZoom)
        let originFraction = min(1, max(0, (origin - position) / zoom))
        let zoomedIn = TimelineTransform(position: 0, zoom: clamped)
        return zoomedIn.positioned(at: origin - clamped * originFraction, duration: duration)
    }

    func scrolled(by delta: TimeInterval, duration: TimeInterval) -> TimelineTransform {
        positioned(at: position + delta, duration: duration)
    }

    func positioned(at value: TimeInterval, duration: TimeInterval) -> TimelineTransform {
        var next = self
        next.position = clampedPosition(value, duration: duration)
        return next
    }

    /// A little slack past the end so the last frame can be dragged away from the right edge.
    private func clampedPosition(_ value: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        let span = max(Self.zoomOutLimit(duration: duration), duration.isFinite ? max(duration, 0) : 0)
        return min(max(value, 0), max(0, span + Self.trailingSlack - zoom))
    }

    /// The scrollbar chip: its width is the visible share of the recording, its travel the remaining share.
    func minimapChip(barWidth: CGFloat, duration: TimeInterval) -> (x: CGFloat, width: CGFloat) {
        let total = max(duration.isFinite ? max(duration, 0) : 0, zoom)
        let pixelsPerSecond = Double(barWidth) / max(total, 0.001)
        let width = min(max(CGFloat(zoom * pixelsPerSecond), Self.minimumChipWidth), barWidth)
        let travel = max(barWidth - width, 0)
        let x = CGFloat(position / max(total - zoom, 0.001)) * travel
        return (min(max(x, 0), travel), width)
    }

    /// Seconds of window travel per point of chip travel, so a chip drag tracks the pointer instead of jumping.
    func minimapMoveScale(barWidth: CGFloat, duration: TimeInterval) -> Double {
        let total = max(duration.isFinite ? max(duration, 0) : 0, zoom)
        let travel = max(barWidth - minimapChip(barWidth: barWidth, duration: duration).width, 1)
        return (total - zoom) / Double(travel)
    }

    /// A click on the bar centres the window on the time under the pointer.
    func minimapClickPosition(x: CGFloat, barWidth: CGFloat, duration: TimeInterval) -> TimeInterval {
        let total = max(duration.isFinite ? max(duration, 0) : 0, zoom)
        return Double(x / max(barWidth, 1)) * total - zoom / 2
    }

    /// The minimap only means anything once the window is narrower than the recording, so it hides itself until then.
    func isZoomedIn(duration: TimeInterval) -> Bool {
        (duration.isFinite ? max(duration, 0) : 0) - zoom > 0.01
    }
}

/// Cap's split snapping: the playhead and every cue edge pull the cut, but never close enough to a clip edge to leave a sliver behind.
nonisolated struct SplitSnapper: Equatable, Sendable {
    static let edgeEpsilon: TimeInterval = 0.05
    static let snapPixels: CGFloat = 7

    let clipStart: TimeInterval
    let clipEnd: TimeInterval
    let radius: TimeInterval

    func snap(_ raw: TimeInterval, candidates: [TimeInterval]) -> (time: TimeInterval, snapped: Bool) {
        let lower = clipStart + Self.edgeEpsilon
        let upper = clipEnd - Self.edgeEpsilon
        var best: TimeInterval?
        var bestDistance = TimeInterval.infinity

        for candidate in candidates where candidate >= lower && candidate <= upper {
            let distance = abs(candidate - raw)
            guard distance <= radius else { continue }
            if distance < bestDistance || (distance == bestDistance && candidate < (best ?? .infinity)) {
                bestDistance = distance
                best = candidate
            }
        }

        guard let best else { return (raw, false) }
        return (best, true)
    }
}
