import Foundation

private let geometry = TimelineGeometry(trackMinX: 12, trackWidth: 200, duration: 10)
private let slop: CGFloat = 20

private func approx(_ a: Double, _ b: Double, _ label: String) {
    assert(abs(a - b) < 0.0001, "\(label): \(a) != \(b)")
}

private func checkGeometryClamps() {
    approx(geometry.time(for: 112), 5, "midpoint maps to half the duration")
    approx(geometry.x(for: 5), 112, "half the duration maps to the midpoint")
    approx(geometry.time(for: -500), 0, "a drag off the left edge cannot produce a negative time")
    approx(geometry.time(for: 5000), 10, "a drag off the right edge cannot run past the media")
    approx(geometry.seconds(forWidth: 20), 1, "20pt is one second at this scale")
    assert(TimelineGeometry(trackMinX: 0, trackWidth: 0, duration: 0).time(for: 40) == 0, "an unloaded timeline maps everything to zero")
}

private func checkSelectionFloor() {
    let selection = TrimSelection(start: 2, end: 8)

    let pushedStart = selection.settingStart(9, duration: 10)
    approx(pushedStart.start, 8 - Clip.minimumDuration, "the start handle stops one minimum duration short of the end")
    approx(pushedStart.end, 8, "moving the start handle never moves the end")

    let pushedEnd = selection.settingEnd(0, duration: 10)
    approx(pushedEnd.end, 2 + Clip.minimumDuration, "the end handle stops one minimum duration past the start")

    approx(selection.settingStart(-4, duration: 10).start, 0, "the start handle stops at zero")
    approx(selection.settingEnd(40, duration: 10).end, 10, "the end handle stops at the media duration")

    let slid = selection.shifted(by: 6, duration: 10)
    approx(slid.duration, 6, "sliding the range keeps its length")
    approx(slid.start, 4, "sliding the range stops at the media end instead of squashing")
    approx(selection.shifted(by: -50, duration: 10).start, 0, "sliding the range stops at zero")
}

private func checkHitTesting() {
    let tester = TrimHitTester(geometry: geometry, slop: slop)
    let wide = TrimSelection(start: 2, end: 8)

    assert(tester.target(at: 52, selection: wide, playhead: 6) == .start, "pressing the start edge grabs the start handle")
    assert(tester.target(at: 172, selection: wide, playhead: 6) == .end, "pressing the end edge grabs the end handle")
    assert(tester.target(at: 132, selection: wide, playhead: 6) == .playhead, "pressing the playhead grabs the playhead")
    assert(tester.target(at: 100, selection: wide, playhead: 6) == .range, "pressing inside the selection clear of the playhead grabs the range")
    assert(tester.target(at: 25, selection: wide, playhead: 6) == nil, "pressing outside the selection grabs nothing")

    let tight = TrimSelection(start: 5, end: 5 + Clip.minimumDuration)
    assert(tester.target(at: 113, selection: tight, playhead: 5) == .start, "the nearer handle wins on the start side")
    assert(tester.target(at: 115, selection: tight, playhead: 5) == .end, "the nearer handle wins on the end side")
}

private func checkGrabOffset() {
    let selection = TrimSelection(start: 2, end: 8)

    let handle = TrimDrag(target: .start, grabbedAt: 2.5, selection: selection, playhead: 6)
    let moved = handle.apply(at: 4, duration: 10)
    approx(moved.selection.start, 3.5, "the start handle tracks the pointer 1:1")
    approx(moved.playhead, 3.5, "trimming the start parks the playhead on the new start")

    let end = TrimDrag(target: .end, grabbedAt: 7.5, selection: selection, playhead: 6)
    approx(end.apply(at: 9, duration: 10).selection.end, 9.5, "the end handle tracks the pointer 1:1")

    let range = TrimDrag(target: .range, grabbedAt: 3, selection: selection, playhead: 3)
    let slid = range.apply(at: 6, duration: 10)
    approx(slid.selection.start, 4, "the range stops at the media end")
    approx(slid.selection.duration, 6, "the range keeps its length while sliding")
    approx(slid.playhead, 5, "the playhead keeps its offset inside the range")

    let scrub = TrimDrag(target: .playhead, grabbedAt: 6, selection: selection, playhead: 6)
    approx(scrub.apply(at: 40, duration: 10).playhead, 8, "the playhead stays inside the selection")
    approx(scrub.apply(at: 0, duration: 10).playhead, 2, "the playhead stays inside the selection")
    approx(scrub.apply(at: 7, duration: 10).selection.start, 2, "scrubbing never moves the trim bounds")
}

private func checkClipHitTesting() {
    let first = Clip(sourceStart: 0, sourceEnd: 5)
    let second = Clip(sourceStart: 5, sourceEnd: 10)
    let clips = [first, second]
    let tester = ClipHitTester(geometry: geometry, slop: slop)
    let boundary = geometry.x(for: 5)

    assert(tester.target(at: boundary, clips: clips, selectedID: second.id) == .startHandle(second.id), "the selected clip's start handle wins at a shared boundary")
    assert(tester.target(at: boundary, clips: clips, selectedID: first.id) == .endHandle(first.id), "the selected clip's end handle wins at a shared boundary")
    assert(tester.target(at: geometry.x(for: 2.5), clips: clips, selectedID: nil) == .body(first.id), "pressing the middle of a clip selects it")
    assert(tester.target(at: 0, clips: [], selectedID: nil) == nil, "an empty timeline has nothing to grab")
}

@main
enum TimelineGeometryCheck {
    static func main() {
        checkGeometryClamps()
        checkSelectionFloor()
        checkHitTesting()
        checkGrabOffset()
        checkClipHitTesting()
        print("TimelineGeometryCheck: clamping, minimum-duration floor, hit ordering, and grab offsets all hold")
    }
}
