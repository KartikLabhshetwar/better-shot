import Foundation

@main
struct RecordingMultiSourceCheck {
    static func main() throws {
        let first = RecordingProjectSource(displayName: "First", duration: 10)
        let second = RecordingProjectSource(displayName: "Second", duration: 8)
        let durations = [first.id: first.duration, second.id: second.duration]
        let firstClip = RecordingClipSegment(sourceID: first.id, sourceStart: 2, sourceEnd: 6, speed: 2)
        let secondClip = RecordingClipSegment(sourceID: second.id, sourceStart: 0, sourceEnd: 4)
        let timeline = try RecordingClipTimeline(segments: [secondClip, firstClip]).validated(sourceDurations: durations)
        precondition(timeline.segments.map(\.id) == [secondClip.id, firstClip.id])
        precondition(timeline.duration == 6)
        precondition(timeline.location(at: 4)?.sourceID == first.id)
        precondition(timeline.location(at: 5)?.sourceTime == 4)
        let split = timeline.split(at: 5)!.timeline
        precondition(split.segments.suffix(2).allSatisfy { $0.sourceID == first.id && $0.speed == 2 })
        let reordered = try timeline.reordered(clipIDs: [firstClip.id, secondClip.id])
        precondition(reordered.segments == [firstClip, secondClip])
        let decoded = try JSONDecoder().decode(RecordingClipTimeline.self, from: JSONEncoder().encode(reordered))
        precondition(decoded == reordered)
        let legacy = try JSONDecoder().decode(RecordingClipSegment.self,
            from: Data(#"{"sourceStart":0,"sourceEnd":10}"#.utf8))
        precondition(legacy.sourceID == nil && legacy.speed == 1)
        let repeated = try RecordingClipTimeline(segments: [firstClip,
            RecordingClipSegment(sourceID: first.id, sourceStart: 2, sourceEnd: 6)])
            .validated(sourceDurations: durations)
        precondition(repeated.segments.count == 2, "Repeating footage must not be trimmed away")

        func rejects(_ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Invalid multi-source project was accepted") }
            catch {}
        }
        rejects { _ = try timeline.reordered(clipIDs: [firstClip.id, firstClip.id]) }
        rejects { _ = try timeline.reordered(clipIDs: [firstClip.id]) }
        rejects { _ = try timeline.validated(sourceDurations: [first.id: 10]) }
        rejects { _ = try RecordingClipTimeline(segments: [firstClip, firstClip]).validated(sourceDurations: durations) }
        for (start, end, speed) in [(Double.nan, 4.0, 1.0), (0, Double.infinity, 1),
                                  (-1, 4, 1), (0, 11, 1), (0, 0.01, 1), (0, 4, Double.nan), (0, 4, 0.1)] {
            rejects {
                _ = try RecordingClipTimeline(segments: [
                    RecordingClipSegment(sourceID: first.id, sourceStart: start, sourceEnd: end, speed: speed)
                ]).validated(sourceDurations: durations)
            }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original.bettershotrec")
        let project = root.appendingPathComponent("Project.bettershotrec")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let screen = original.appendingPathComponent("screen.mov")
        let bytes = Data("original screen fixture".utf8)
        try bytes.write(to: screen)
        rejects { try first.validatePackage(in: project) }
        try Data("render cache".utf8).write(to: original.appendingPathComponent("final.mp4"))
        let stage = try first.stageCopy(from: original, in: project)
        precondition(!FileManager.default.fileExists(atPath: stage.appendingPathComponent("final.mp4").path))
        precondition(!FileManager.default.fileExists(atPath: first.sessionDirectory(in: project).path))
        try first.installStagedCopy(stage, in: project)
        try first.validatePackage(in: project)
        precondition(!FileManager.default.fileExists(atPath: stage.path))
        let preservedBytes = try Data(contentsOf: screen)
        precondition(preservedBytes == bytes, "Installing a copy never moves the original")
        let stageAgain = try first.stageCopy(from: original, in: project)
        rejects { try first.installStagedCopy(stageAgain, in: project) }
        try FileManager.default.removeItem(at: stageAgain)
        rejects { try second.installStagedCopy(original, in: project) }

        let symlink = original.appendingPathComponent("camera.mov")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: screen)
        rejects { _ = try second.stageCopy(from: original, in: project) }
        let children = try FileManager.default.contentsOfDirectory(atPath: project.appendingPathComponent("sources").path)
        precondition(!children.contains { $0.hasPrefix(".stage-") }, "A failed copy must not leave a staged package")
        try FileManager.default.removeItem(at: symlink)
        let edit = original.appendingPathComponent("edit.json")
        for document in ["not-json", #"{"sources":[]}"#,
                         #"{"replacementAudioFileName":"../outside.wav"}"#,
                         #"{"replacementAudioFileName":"missing.wav"}"#] {
            try Data(document.utf8).write(to: edit)
            rejects { _ = try second.stageCopy(from: original, in: project) }
        }
        try FileManager.default.removeItem(at: edit)
        let escapedProject = root.appendingPathComponent("Escaped.bettershotrec")
        try FileManager.default.createDirectory(at: escapedProject, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: escapedProject.appendingPathComponent("sources"), withDestinationURL: original)
        rejects { _ = try second.stageCopy(from: original, in: escapedProject) }
        try FileManager.default.removeItem(at: first.sessionDirectory(in: project).appendingPathComponent("screen.mov"))
        rejects { try first.validatePackage(in: project) }
        print("Multi-source foundations: legacy decoding, stable source/clip IDs, ordered timing/speed, strict validation, managed copies, and rollback passed")
    }
}
