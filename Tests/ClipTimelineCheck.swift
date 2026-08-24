import AVFoundation
import Foundation

@main
enum ClipTimelineCheck {
    static func main() {

        // MARK: - Split duration-sum invariant

        do {
            let original = Clip(sourceStart: 0, sourceEnd: 10)
            let timeline = ClipTimeline(clips: [original])
            guard let result = timeline.split(at: 4) else {
                fatalError("expected split at 4 to succeed")
            }
            assert(result.clips.count == 2, "split should produce two clips")
            assert(result.clips[0].sourceStart == 0 && result.clips[0].sourceEnd == 4, "leading clip range wrong")
            assert(result.clips[1].sourceStart == 4 && result.clips[1].sourceEnd == 10, "trailing clip range wrong")
            assert(result.clips[0].id == original.id, "leading clip should keep original id")
            assert(result.clips[1].id == result.selectedID, "trailing clip should be selected")

            let summedDuration = result.clips.reduce(0) { $0 + $1.editorDuration }
            assert(abs(summedDuration - original.editorDuration) < 1e-9, "split must preserve total duration, got \(summedDuration) vs \(original.editorDuration)")

            let tooCloseToStart = ClipTimeline(clips: [original]).split(at: 0.05)
            assert(tooCloseToStart == nil, "split too close to a clip edge must be rejected")
        }

        // MARK: - Delete shortens duration correctly

        do {
            let clips = [
                Clip(sourceStart: 0, sourceEnd: 3),
                Clip(sourceStart: 3, sourceEnd: 6),
                Clip(sourceStart: 6, sourceEnd: 10)
            ]
            let timeline = ClipTimeline(clips: clips)
            let beforeDuration = timeline.duration
            assert(abs(beforeDuration - 10) < 1e-9, "expected initial duration 10, got \(beforeDuration)")

            guard let afterDelete = timeline.deleting(id: clips[1].id) else {
                fatalError("expected delete of middle clip to succeed")
            }
            assert(afterDelete.count == 2, "delete should leave two clips")
            let afterDuration = ClipTimeline(clips: afterDelete).duration
            assert(abs(afterDuration - 7) < 1e-9, "expected duration 7 after deleting a 3s clip from 10s, got \(afterDuration)")

            let singleClipTimeline = ClipTimeline(clips: [clips[0]])
            assert(singleClipTimeline.deleting(id: clips[0].id) == nil, "cannot delete the last remaining clip")
        }

        // MARK: - Speed multiplier scales duration

        do {
            let base = Clip(sourceStart: 2, sourceEnd: 6, speed: 1)
            assert(abs(base.editorDuration - 4) < 1e-9, "1x speed should leave duration unchanged")

            var doubled = base
            doubled.speed = 2.0
            assert(abs(doubled.editorDuration - 2) < 1e-9, "2x speed should halve duration, got \(doubled.editorDuration)")

            var halved = base
            halved.speed = 0.5
            assert(abs(halved.editorDuration - 8) < 1e-9, "0.5x speed should double duration, got \(halved.editorDuration)")

            let timeline = ClipTimeline(clips: [base])
            let sped = timeline.replacing(doubled)
            assert(ClipTimeline(clips: sped).duration == doubled.editorDuration, "replacing should update the timeline's total duration")
        }

        // MARK: - Editor <-> source time round trip across a speed-changed clip

        do {
            let slow = Clip(sourceStart: 0, sourceEnd: 10, speed: 0.5)
            let fast = Clip(sourceStart: 10, sourceEnd: 20, speed: 2.0)
            let timeline = ClipTimeline(clips: [slow, fast])

            assert(abs(slow.editorDuration - 20) < 1e-9, "0.5x clip should occupy 20s of editor time")
            assert(abs(fast.editorDuration - 5) < 1e-9, "2x clip should occupy 5s of editor time")
            assert(abs(timeline.duration - 25) < 1e-9, "expected combined editor duration 25, got \(timeline.duration)")

            for editorTime in stride(from: 0.0, through: 25.0, by: 0.37) {
                let sourceTime = timeline.sourceTime(at: editorTime)
                guard let roundTripped = timeline.editorTime(forSourceTime: sourceTime) else {
                    fatalError("editorTime(forSourceTime:) unexpectedly returned nil for sourceTime \(sourceTime)")
                }
                assert(abs(roundTripped - editorTime) < 1e-6, "round trip mismatch at editorTime \(editorTime): got \(roundTripped) via sourceTime \(sourceTime)")
            }
        }

        // MARK: - Undo restores the previous clip list exactly

        do {
            struct Snapshot { var clips: [Clip] }

            let originalClips = [Clip(sourceStart: 0, sourceEnd: 10)]
            var undoStack: [Snapshot] = []
            var clips = originalClips

            func commit(_ newClips: [Clip]) {
                undoStack.append(Snapshot(clips: clips))
                clips = newClips
            }

            func undo() {
                guard let snapshot = undoStack.popLast() else { return }
                clips = snapshot.clips
            }

            guard let splitResult = ClipTimeline(clips: clips).split(at: 4) else {
                fatalError("expected split to succeed")
            }
            commit(splitResult.clips)
            assert(clips.count == 2, "expected two clips after split")
            assert(clips != originalClips, "clip list must actually change after split, or this test proves nothing")

            guard let trailingClip = clips.last else { fatalError("missing trailing clip") }
            var sped = trailingClip
            sped.speed = 2.0
            commit(ClipTimeline(clips: clips).replacing(sped))
            assert(clips.count == 2 && clips[1].speed == 2.0, "expected speed change to apply")

            undo()
            assert(clips.count == 2 && clips[1].speed == 1.0, "undo should revert the speed change")

            undo()
            assert(clips == originalClips, "undo should restore the exact original clip list, got \(clips) vs \(originalClips)")
            assert(undoStack.isEmpty, "undo stack should be empty after unwinding every commit")
        }

        // MARK: - Speed on an unsplit recording materializes one clip covering the trim range

        do {
            struct Editor {
                var clips: [Clip] = []
                var selectedClipID: UUID?
                var trimStart: TimeInterval = 1
                var trimEnd: TimeInterval = 9

                var activeSpeed: Double {
                    if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) { return clip.speed }
                    return clips.first?.speed ?? 1
                }

                mutating func setSpeed(_ speed: Double) {
                    if let id = selectedClipID, let index = clips.firstIndex(where: { $0.id == id }) {
                        clips[index].speed = Clip.clampedSpeed(speed)
                        return
                    }
                    let clamped = Clip.clampedSpeed(speed)
                    guard !clips.isEmpty || clamped != 1 else { return }
                    let base = clips.isEmpty ? [Clip(sourceStart: trimStart, sourceEnd: trimEnd)] : clips
                    clips = base.map { clip in
                        var updated = clip
                        updated.speed = clamped
                        return updated
                    }
                    selectedClipID = nil
                }
            }

            var editor = Editor()
            assert(editor.activeSpeed == 1, "an untouched recording plays at 1x")

            editor.setSpeed(1)
            assert(editor.clips.isEmpty, "setting 1x on an untouched recording must not materialize a clip")

            editor.setSpeed(2)
            assert(editor.clips.count == 1, "speed on an unsplit recording materializes exactly one clip")
            assert(editor.clips[0].sourceStart == 1 && editor.clips[0].sourceEnd == 9, "materialized clip must cover the trim range")
            assert(editor.activeSpeed == 2, "activeSpeed should report the whole-recording speed")
            assert(abs(ClipTimeline(clips: editor.clips).duration - 4) < 1e-9, "2x over an 8s trim is a 4s timeline")

            editor.setSpeed(99)
            assert(editor.clips[0].speed == Clip.maximumSpeed, "speed must clamp to the supported maximum")

            guard let split = ClipTimeline(clips: editor.clips).split(at: 5) else { fatalError("expected split") }
            editor.clips = split.clips
            editor.selectedClipID = split.selectedID
            editor.setSpeed(0.5)
            assert(editor.clips[0].speed == Clip.maximumSpeed, "a selected clip's speed change must not touch its siblings")
            assert(editor.clips[1].speed == 0.5, "speed should land on the selected clip")
            assert(editor.activeSpeed == 0.5, "activeSpeed follows the selection once the timeline is cut")
        }

        // MARK: - Playback rate follows whichever clip the playhead sits in

        do {
            let timeline = ClipTimeline(clips: [
                Clip(sourceStart: 0, sourceEnd: 4, speed: 1),
                Clip(sourceStart: 4, sourceEnd: 8, speed: 2)
            ])
            assert(timeline.speed(atSourceTime: 2) == 1, "playhead inside the first clip plays at its speed")
            assert(timeline.speed(atSourceTime: 6) == 2, "playhead inside the sped-up clip plays sped up")
            assert(timeline.speed(atSourceTime: 4) == 2, "a clip boundary belongs to the clip that starts there")
            assert(timeline.speed(atSourceTime: 99) == 1, "a playhead outside every clip falls back to 1x")
            assert(ClipTimeline(clips: []).speed(atSourceTime: 0) == 1, "an unsplit recording plays at 1x")
        }

        print("ClipTimelineCheck: all assertions passed")
    }
}
