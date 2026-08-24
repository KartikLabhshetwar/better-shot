import Foundation

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
