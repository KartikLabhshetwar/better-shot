import Foundation

/// Cap's editor/context.ts timeline transform, expressed in seconds rather than a scale factor.
/// Adapted for native scroll views: no trailing overscroll beyond the recording.
nonisolated struct RecordingTimelineViewport: Equatable {
    private(set) var visibleSeconds: Double = 3
    private(set) var position: Double = 0

    static let maximumContentWidth: Double = 100_000

    static func zoomOutLimit(duration: Double) -> Double { max(1.0 / 60, duration) }

    static func zoomInLimit(duration: Double, viewportWidth: Double) -> Double {
        let fitted = zoomOutLimit(duration: duration)
        // Short recordings still get 16× magnification. Keep the earlier native lane-width cap.
        return min(fitted, max(min(3, fitted / 16), fitted * max(viewportWidth, 1) / maximumContentWidth))
    }

    mutating func fit(duration: Double) {
        visibleSeconds = Self.zoomOutLimit(duration: duration)
        position = 0
    }

    mutating func updateZoom(_ seconds: Double, origin: Double, duration: Double, viewportWidth: Double = 1) {
        guard seconds.isFinite, origin.isFinite, duration.isFinite else { return }
        let next = min(max(seconds, Self.zoomInLimit(duration: duration, viewportWidth: viewportWidth)),
                       Self.zoomOutLimit(duration: duration))
        let fraction = min(max((origin - position) / visibleSeconds, 0), 1)
        visibleSeconds = next
        setPosition(origin - next * fraction, duration: duration)
    }

    func zoomProgress(duration: Double, viewportWidth: Double) -> Double {
        let maximum = Self.zoomOutLimit(duration: duration)
        let minimum = Self.zoomInLimit(duration: duration, viewportWidth: viewportWidth)
        guard maximum > minimum else { return 0 }
        return min(max(log(maximum / visibleSeconds) / log(maximum / minimum), 0), 1)
    }

    mutating func updateZoomProgress(_ progress: Double, origin: Double, duration: Double, viewportWidth: Double) {
        guard progress.isFinite else { return }
        let maximum = Self.zoomOutLimit(duration: duration)
        let minimum = Self.zoomInLimit(duration: duration, viewportWidth: viewportWidth)
        let seconds = maximum * pow(minimum / maximum, min(max(progress, 0), 1))
        updateZoom(seconds, origin: origin, duration: duration, viewportWidth: viewportWidth)
    }

    mutating func setPosition(_ seconds: Double, duration: Double) {
        guard seconds.isFinite, duration.isFinite else { return }
        position = min(max(seconds, 0), max(0, duration - visibleSeconds))
    }

    /// Cap's ZoomTrack: an 80-point hover preview, at least one second, bounded by neighbors.
    static func newZoomRange(
        at time: Double, draggedTo end: Double? = nil, secondsPerPoint: Double,
        duration: Double, occupied: [ClosedRange<Double>]
    ) -> ClosedRange<Double>? {
        guard time.isFinite, time >= 0, time < duration, secondsPerPoint.isFinite,
              !occupied.contains(where: { $0.lowerBound <= time && time < $0.upperBound }) else { return nil }
        let lower = occupied.filter { $0.upperBound <= time }.map(\.upperBound).max() ?? 0
        let upper = occupied.filter { $0.lowerBound >= time }.map(\.lowerBound).min() ?? duration
        let minimum = max(1, 80 * secondsPerPoint)
        guard upper - lower >= minimum else { return nil }
        let start = min(time, upper - minimum)
        let finish = min(max(end ?? (start + minimum), start + minimum), upper)
        return max(lower, start)...finish
    }
    static func moving(_ range: ClosedRange<Double>, by delta: Double,
                       within bounds: ClosedRange<Double>) -> ClosedRange<Double> {
        let length = min(range.upperBound - range.lowerBound, bounds.upperBound - bounds.lowerBound)
        let start = min(max(range.lowerBound + delta, bounds.lowerBound), bounds.upperBound - length)
        return start...(start + length)
    }

    static func resizing(_ range: ClosedRange<Double>, leading: Bool, by delta: Double,
                         within bounds: ClosedRange<Double>, minimumDuration: Double) -> ClosedRange<Double> {
        guard delta.isFinite, minimumDuration.isFinite, minimumDuration > 0 else { return range }
        let available = leading ? range.upperBound - bounds.lowerBound : bounds.upperBound - range.lowerBound
        let minimum = min(minimumDuration, available)
        if leading {
            let start = min(max(range.lowerBound + delta, bounds.lowerBound), range.upperBound - minimum)
            return start...range.upperBound
        }
        let end = max(min(range.upperBound + delta, bounds.upperBound), range.lowerBound + minimum)
        return range.lowerBound...end
    }

}
