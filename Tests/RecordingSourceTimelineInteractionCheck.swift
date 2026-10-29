import Foundation

@main
struct RecordingSourceTimelineInteractionCheck {
    static func main() throws {
        let a = UUID(), b = UUID()
        let first = RecordingClipSegment(sourceID: a, sourceStart: 4, sourceEnd: 7, speed: 2)
        let second = RecordingClipSegment(sourceID: b, sourceStart: 1, sourceEnd: 3)
        let repeatA = RecordingClipSegment(sourceID: a, sourceStart: 2, sourceEnd: 5)
        let last = RecordingClipSegment(sourceID: a, sourceStart: 8, sourceEnd: 10)
        let timeline = RecordingClipTimeline(segments: [first, second, repeatA, last])
        let durations = [a: 12.0, b: 4.0]
        assert(timeline.trimBounds(for: second.id, sourceDuration: 99, sourceDurations: durations) == 0...4,
               "A recording's edges cannot be constrained by unrelated neighboring clocks")
        assert(timeline.trimBounds(for: repeatA.id, sourceDuration: 99, sourceDurations: durations) == 0...12,
               "Repeated/reordered clips retain the whole authored source as trim bounds")
        assert(timeline.trimBounds(for: first.id, sourceDuration: 99, sourceDurations: [:]) == nil)
        let markers = timeline.cutMarkers(sourceDurations: durations)
        assert(markers.count == 5)
        assert(markers[0].sourceID == a && markers[0].removedDuration == 4)
        assert(markers[1].sourceID == b && markers[1].removedDuration == 0 && markers[1].editorTime == 1.5)
        assert(markers[2].sourceID == a && markers[2].removedDuration == 0)
        assert(markers[3].sourceID == a && markers[3].removedDuration == 3)
        assert(markers[4].removedDuration == 2 && markers[4].editorTime == timeline.duration)
        let backwards = RecordingClipTimeline(segments: [last, repeatA])
        assert(backwards.cutMarkers(sourceDurations: durations)[1].removedDuration == 0)
        let legacy = RecordingClipTimeline(segments: [
            RecordingClipSegment(sourceStart: 1, sourceEnd: 3),
            RecordingClipSegment(sourceStart: 5, sourceEnd: 8)
        ])
        assert(legacy.trimBounds(for: legacy.segments[1].id, sourceDuration: 10, sourceDurations: [:]) == 3...10)
        assert(legacy.cutMarkers(sourceDuration: 10).map(\.removedDuration) == [1, 2, 2])
        let reordered = try timeline.reordered(clipIDs: [last.id, first.id, second.id, repeatA.id])
        assert(reordered.segments.map(\.id) == [last.id, first.id, second.id, repeatA.id])
        print("RecordingSourceTimelineInteractionCheck: source bounds, clock-aware cut markers, repeated/backward order, and legacy behavior passed")
    }
}
