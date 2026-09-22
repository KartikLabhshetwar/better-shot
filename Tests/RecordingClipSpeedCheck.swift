import Foundation

@main
struct RecordingClipSpeedCheck {
    static func main() throws {
        // A 10-second source must retain fractional rates through project loading and cuts.
        for (speed, duration) in [(0.25, 40.0), (0.5, 20.0), (1.25, 8.0), (1.5, 20.0 / 3), (2.5, 4.0)] {
            let timeline = RecordingClipTimeline(segments: [
                RecordingClipSegment(sourceStart: 0, sourceEnd: 10, speed: speed)
            ]).normalized(to: 10)
            precondition(abs(timeline.duration - duration) < 0.000_001,
                         "Fractional speed \(speed)× must produce \(duration) seconds")
            let restored = try JSONDecoder().decode(RecordingClipTimeline.self,
                from: JSONEncoder().encode(timeline)).normalized(to: 10)
            precondition(restored == timeline)
            precondition(abs(timeline.sourceTime(at: duration / 2) - 5) < 0.000_001)
            precondition(abs(timeline.editorTime(forSourceTime: 5)! - duration / 2) < 0.000_001)
            let split = timeline.split(at: duration / 2)!.timeline
            precondition(split.segments.allSatisfy { $0.speed == speed })
            precondition(abs(split.duration - duration) < 0.000_001)
        }
        for invalid in [0.0, -1, Double.nan, .infinity] {
            let timeline = RecordingClipTimeline(segments: [
                RecordingClipSegment(sourceStart: 0, sourceEnd: 10, speed: invalid)
            ]).normalized(to: 10)
            precondition(timeline.duration.isFinite && timeline.duration > 0)
        }
        let legacy = try JSONDecoder().decode(RecordingClipSegment.self,
            from: Data(#"{"sourceStart":0,"sourceEnd":10}"#.utf8))
        precondition(legacy.speed == 1 && legacy.editorDuration == 10)

        // A Speed slider drag applies once on release: one timeline rebuild
        // and one undo step. Each drag tick is its own input event in the app,
        // so every applied change gets its own undo group here.
        var timeline = RecordingClipTimeline(segments: [RecordingClipSegment(sourceStart: 0, sourceEnd: 10)])
        let clipID = timeline.segments[0].id
        let undo = UndoManager()
        undo.groupsByEvent = false
        func apply(_ speed: Double) {
            let previous = timeline
            undo.beginUndoGrouping()
            undo.registerUndo(withTarget: undo) { _ in timeline = previous }
            undo.endUndoGrouping()
            timeline = timeline.replacing(.init(id: clipID, sourceStart: 0, sourceEnd: 10, speed: speed))
        }
        var draft = RecordingClipSpeedDraft()
        draft.begin()
        for speed in [1.25, 1.5, 1.75, 2] {
            if draft.propose(speed, forClipID: clipID) { apply(speed) }
            precondition(draft.speed(forClipID: clipID) == speed, "The slider shows the dragged speed")
            precondition(timeline.duration == 10, "A drag tick must not rebuild the timeline")
        }
        if let change = draft.end() { apply(change.speed) }
        precondition(timeline.duration == 5 && draft.speed(forClipID: clipID) == nil)
        undo.undo()
        precondition(timeline.segments[0].speed == 1 && timeline.duration == 10,
                     "One undo restores the pre-drag speed")
        precondition(!undo.canUndo, "A drag is exactly one undo step")
        precondition(draft.propose(3, forClipID: clipID), "Outside a drag, a change applies immediately")
        print("RecordingClipSpeedCheck: fractional timing, split, persistence, legacy decoding, and one-step speed drags passed")
    }
}
