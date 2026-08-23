import Foundation

nonisolated struct Clip: Identifiable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.2
    static let minimumSpeed: Double = 0.25
    static let maximumSpeed: Double = 4.0

    var id: UUID
    var sourceStart: TimeInterval
    var sourceEnd: TimeInterval
    var speed: Double

    init(id: UUID = UUID(), sourceStart: TimeInterval, sourceEnd: TimeInterval, speed: Double = 1) {
        self.id = id
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
    }

    var duration: TimeInterval { max(0, sourceEnd - sourceStart) }
    var editorDuration: TimeInterval { duration / min(max(speed, Self.minimumSpeed), Self.maximumSpeed) }
}

nonisolated struct ClipTimeline: Equatable, Sendable {
    var clips: [Clip]

    init(clips: [Clip]) { self.clips = clips }

    static func full(sourceDuration: TimeInterval) -> ClipTimeline {
        let safe = max(0, sourceDuration.isFinite ? sourceDuration : 0)
        guard safe > 0 else { return ClipTimeline(clips: []) }
        return ClipTimeline(clips: [Clip(sourceStart: 0, sourceEnd: safe)])
    }

    var duration: TimeInterval { clips.reduce(0) { $0 + $1.editorDuration } }

    func normalized(to sourceDuration: TimeInterval) -> [Clip] {
        let safe = max(0, sourceDuration.isFinite ? sourceDuration : 0)
        var seenIDs = Set<UUID>()
        return clips
            .compactMap { clip -> Clip? in
                let start = min(max(clip.sourceStart, 0), safe)
                let end = min(max(clip.sourceEnd, start), safe)
                guard end - start >= Clip.minimumDuration else { return nil }
                let id = seenIDs.insert(clip.id).inserted ? clip.id : UUID()
                let speed = min(max(clip.speed.isFinite ? clip.speed : 1, Clip.minimumSpeed), Clip.maximumSpeed)
                return Clip(id: id, sourceStart: start, sourceEnd: end, speed: speed)
            }
            .sorted { $0.sourceStart < $1.sourceStart }
    }

    func clipIndex(at sourceTime: TimeInterval) -> Int? {
        guard !clips.isEmpty else { return nil }
        if let index = clips.firstIndex(where: { $0.sourceStart <= sourceTime && sourceTime < $0.sourceEnd }) {
            return index
        }
        return sourceTime <= clips[0].sourceStart ? 0 : clips.count - 1
    }

    func editorRange(for id: UUID) -> Range<TimeInterval>? {
        var editorStart: TimeInterval = 0
        for clip in clips {
            let editorEnd = editorStart + clip.editorDuration
            if clip.id == id { return editorStart..<editorEnd }
            editorStart = editorEnd
        }
        return nil
    }

    func split(at sourceTime: TimeInterval) -> (clips: [Clip], selectedID: UUID)? {
        guard let index = clipIndex(at: sourceTime) else { return nil }
        let clip = clips[index]
        guard sourceTime - clip.sourceStart >= Clip.minimumDuration,
              clip.sourceEnd - sourceTime >= Clip.minimumDuration else { return nil }
        let trailingID = UUID()
        let leading = Clip(id: clip.id, sourceStart: clip.sourceStart, sourceEnd: sourceTime, speed: clip.speed)
        let trailing = Clip(id: trailingID, sourceStart: sourceTime, sourceEnd: clip.sourceEnd, speed: clip.speed)
        var next = clips
        next.replaceSubrange(index...index, with: [leading, trailing])
        return (next, trailingID)
    }

    func deleting(id: UUID) -> [Clip]? {
        guard clips.count > 1, clips.contains(where: { $0.id == id }) else { return nil }
        return clips.filter { $0.id != id }
    }

    func replacing(_ replacement: Clip) -> [Clip] {
        guard let index = clips.firstIndex(where: { $0.id == replacement.id }) else { return clips }
        var next = clips
        next[index] = replacement
        return next
    }

    func editorTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval? {
        var editorStart: TimeInterval = 0
        for clip in clips {
            if sourceTime >= clip.sourceStart - 0.000_001, sourceTime <= clip.sourceEnd + 0.000_001 {
                let offset = min(max(sourceTime - clip.sourceStart, 0), clip.duration)
                return editorStart + offset / min(max(clip.speed, Clip.minimumSpeed), Clip.maximumSpeed)
            }
            editorStart += clip.editorDuration
        }
        return nil
    }

    func sourceTime(at editorTime: TimeInterval) -> TimeInterval {
        guard !clips.isEmpty, duration > 0 else { return 0 }
        let clamped = min(max(editorTime, 0), duration)
        var editorStart: TimeInterval = 0
        for (index, clip) in clips.enumerated() {
            let editorEnd = editorStart + clip.editorDuration
            if clamped < editorEnd || index == clips.count - 1 {
                let offset = min(max(clamped - editorStart, 0), clip.editorDuration)
                let speed = min(max(clip.speed, Clip.minimumSpeed), Clip.maximumSpeed)
                return min(clip.sourceStart + offset * speed, clip.sourceEnd)
            }
            editorStart = editorEnd
        }
        return 0
    }
}

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

print("ClipTimelineCheck: all assertions passed")
