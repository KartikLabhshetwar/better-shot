import Foundation

private func approx(_ a: Double, _ b: Double, _ label: String) {
    assert(abs(a - b) < 0.0001, "\(label): \(a) != \(b)")
}

private let head = Clip(sourceStart: 0, sourceEnd: 2)
private let tail = Clip(sourceStart: 6, sourceEnd: 10)
private let cut = ClipTimeline(clips: [head, tail])

private func checkDeletedStretchTakesNoSpace() {
    approx(cut.duration, 6, "a ten second recording with four seconds cut out spans six")
    approx(cut.clampedEditorTime(forSourceTime: 0), 0, "the first clip still starts at the origin")
    approx(cut.clampedEditorTime(forSourceTime: 2), 2, "the first clip still ends where it did")
    approx(cut.clampedEditorTime(forSourceTime: 6), 2, "the second clip butts against the first")
    approx(cut.clampedEditorTime(forSourceTime: 10), 6, "the last frame lands at the timeline's end")
}

private func checkDeletedStretchCollapsesToTheCut() {
    for sourceTime in stride(from: 2.0, through: 6.0, by: 0.25) {
        approx(cut.clampedEditorTime(forSourceTime: sourceTime), 2, "every removed frame collapses onto the cut")
    }
    approx(cut.clampedEditorTime(forSourceTime: 40), 6, "past the end pins to the end")
}

private func checkSpeedCompressesTheAxis() {
    let fast = ClipTimeline(clips: [Clip(sourceStart: 0, sourceEnd: 8, speed: 2)])
    approx(fast.duration, 4, "a 2x clip occupies half the timeline")
    approx(fast.clampedEditorTime(forSourceTime: 8), 4, "the clip's end maps to the compressed end")

    for editorTime in stride(from: 0.0, through: 6.0, by: 0.3) {
        let roundTripped = cut.clampedEditorTime(forSourceTime: cut.sourceTime(at: editorTime))
        approx(roundTripped, editorTime, "editor to source and back is the identity inside the clips")
    }
}

private func checkPlaybackJumpsTheGap() {
    assert(cut.playbackTime(after: 1) == nil, "inside a clip there is nothing to skip")
    approx(cut.playbackTime(after: 3) ?? -1, 6, "a playhead in the removed stretch jumps to the next clip")
    approx(cut.playbackTime(after: 2) ?? -1, 6, "the boundary belongs to the gap, not the clip that ended there")
    assert(cut.playbackTime(after: 9) == nil, "the last clip plays to its end")
    assert(cut.playbackTime(after: 10) == nil, "past the end there is nowhere to jump")
    assert(ClipTimeline(clips: []).playbackTime(after: 3) == nil, "an uncut recording never skips")
}

@main
enum EditorTimelineAxisCheck {
    static func main() {
        checkDeletedStretchTakesNoSpace()
        checkDeletedStretchCollapsesToTheCut()
        checkSpeedCompressesTheAxis()
        checkPlaybackJumpsTheGap()
        print("EditorTimelineAxisCheck: cuts take no space on the timeline and playback steps over them")
    }
}
