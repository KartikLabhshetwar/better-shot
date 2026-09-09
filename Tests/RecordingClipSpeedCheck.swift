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
        print("RecordingClipSpeedCheck: fractional timing, split, persistence, and legacy decoding passed")
    }
}
