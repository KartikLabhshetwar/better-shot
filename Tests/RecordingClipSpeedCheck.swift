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

        // A Speed slider drag holds every tick and hands back only the final speed on release.
        let clipID = UUID()
        var draft = RecordingClipSpeedDraft()
        draft.begin()
        for speed in [1.25, 1.5, 1.75, 2] {
            precondition(!draft.propose(speed, forClipID: clipID), "A drag tick must not apply")
            precondition(draft.speed(forClipID: clipID) == speed, "The slider shows the dragged speed")
        }
        let change = draft.end()
        precondition(change?.clipID == clipID && change?.speed == 2, "Release applies the last speed once")
        precondition(draft.speed(forClipID: clipID) == nil && draft.end() == nil, "Release clears the draft")
        precondition(draft.propose(3, forClipID: clipID), "Outside a drag, a change applies immediately")

        let otherClipID = UUID()
        var retargetDraft = RecordingClipSpeedDraft()
        retargetDraft.begin()
        precondition(!retargetDraft.propose(1.5, forClipID: clipID), "The first tick starts the drag")
        precondition(!retargetDraft.propose(1.75, forClipID: otherClipID), "A different clip id must not retarget the draft")
        precondition(retargetDraft.speed(forClipID: otherClipID) == nil, "The other clip must not see a held value")
        precondition(retargetDraft.speed(forClipID: clipID) == 1.5, "The originally dragged clip keeps its held value")
        let retargetChange = retargetDraft.end()
        precondition(retargetChange?.clipID == clipID && retargetChange?.speed == 1.5,
                     "Release commits to the clip the drag started on")
        print("RecordingClipSpeedCheck: fractional timing, split, persistence, legacy decoding, and one-step speed drags passed")
    }
}
