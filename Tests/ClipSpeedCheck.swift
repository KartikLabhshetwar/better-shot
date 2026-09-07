import Foundation

@main
struct ClipSpeedCheck {
    static func main() throws {
        for speed in [0.25, 0.5, 1.25, 1.5, 2.5, 8] {
            let clip = RecordingClipSegment(sourceStart: 2, sourceEnd: 12, speed: speed)
            let timeline = RecordingClipTimeline(segments: [clip]).normalized(to: 12)
            assert(timeline.segments[0].speed == speed)
            assert(abs(timeline.duration - 10 / speed) < 0.000_001)
            assert(abs(timeline.sourceTime(at: 5 / speed) - 7) < 0.000_001)
            assert(abs(timeline.editorTime(forSourceTime: 7)! - 5 / speed) < 0.000_001)
            let split = timeline.split(at: 5 / speed)!.timeline
            assert(split.segments.allSatisfy { $0.speed == speed })
            assert(abs(split.duration - timeline.duration) < 0.000_001)
            let slices = timeline.slices(overlapping: 4, sourceEnd: 8)
            assert(abs(slices[0].editorStart - 2 / speed) < 0.000_001)
            assert(abs(slices[0].editorEnd - 6 / speed) < 0.000_001)
            let data = try JSONEncoder().encode(timeline)
            let decoded = try JSONDecoder().decode(RecordingClipTimeline.self, from: data)
            assert(decoded.normalized(to: 12) == timeline)
        }
        for speed in [0, -1, Double.nan, Double.infinity, 99] {
            let clip = RecordingClipSegment(sourceStart: 0, sourceEnd: 10, speed: speed)
            let normalized = RecordingClipTimeline(segments: [clip]).normalized(to: 10)
            assert((0.25...8).contains(normalized.segments[0].speed))
            assert(normalized.duration.isFinite)
        }
        print("ClipSpeedCheck: fractional speeds, slow motion, and timeline preservation verified")
    }
}
