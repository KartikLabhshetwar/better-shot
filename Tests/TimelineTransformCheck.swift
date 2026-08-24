import CoreGraphics
import Foundation

private func approx(_ a: Double, _ b: Double, _ label: String, tolerance: Double = 0.0001) {
    assert(abs(a - b) < tolerance, "\(label): \(a) != \(b)")
}

private func checkZoomLimits() {
    approx(TimelineTransform.zoomOutLimit(duration: 0), 3, "an unloaded timeline still shows the minimum window")
    approx(TimelineTransform.zoomOutLimit(duration: 12), 12, "a short recording fits whole")
    approx(TimelineTransform.zoomOutLimit(duration: 4000), 600, "a long recording caps at ten minutes")
    approx(TimelineTransform.fitting(duration: 45).zoom, 45, "the timeline opens fitted to the recording")
    approx(TimelineTransform.fitting(duration: 45).position, 0, "the timeline opens at the start")
}

private func checkPixelMapping() {
    let transform = TimelineTransform(position: 10, zoom: 20)
    approx(transform.secondsPerPixel(trackWidth: 200), 0.1, "20s across 200pt is a tenth of a second per point")
    approx(Double(transform.x(for: 20, trackWidth: 200)), 100, "the middle of the window lands at the middle of the track")
    approx(transform.time(atOffset: 100, trackWidth: 200), 20, "the middle of the track maps back to the middle of the window")
    approx(transform.time(atOffset: -50, trackWidth: 200), 5, "times left of the window stay addressable for off-screen drags")
    approx(transform.seconds(forWidth: 70, trackWidth: 200), 7, "a pixel radius converts to a snap radius in seconds")
}

private func checkZoomAnchoring() {
    let transform = TimelineTransform(position: 10, zoom: 20)
    let width: CGFloat = 200
    let origin: TimeInterval = 15
    let before = transform.x(for: origin, trackWidth: width)
    let zoomed = transform.zoomed(to: 8, origin: origin, duration: 120)

    approx(zoomed.zoom, 8, "the requested span is applied")
    approx(Double(zoomed.x(for: origin, trackWidth: width)), Double(before), "the anchored time keeps its pixel", tolerance: 0.01)

    approx(transform.zoomed(to: 0.2, origin: origin, duration: 120).zoom, 3, "zooming in stops at the three second floor")
    approx(transform.zoomed(to: 9000, origin: origin, duration: 45).zoom, 45, "zooming out stops at the recording length")
}

private func checkPositionClamp() {
    let transform = TimelineTransform(position: 0, zoom: 10)
    approx(transform.positioned(at: -40, duration: 60).position, 0, "the window cannot scroll before the start")
    approx(transform.positioned(at: 9000, duration: 60).position, 54, "the window stops four seconds past the end")
    approx(transform.scrolled(by: 5, duration: 60).position, 5, "scrolling moves the window by the requested seconds")
    approx(TimelineTransform(position: .nan, zoom: .nan).zoom, 3, "a non-finite transform falls back to the minimum window")
}

private func checkMarkings() {
    approx(TimelineTransform(position: 0, zoom: 5).markingResolution, 0.5, "a five second window rules in half seconds")
    approx(TimelineTransform(position: 0, zoom: 45).markingResolution, 2.5, "a forty-five second window rules in 2.5s steps")
    approx(TimelineTransform(position: 0, zoom: 600).markingResolution, 30, "a ten minute window rules in half minutes")

    let transform = TimelineTransform(position: 7, zoom: 20)
    let first = transform.markingTime(index: 0)
    assert(first <= transform.position, "the first tick sits at or before the left edge")
    approx(first.truncatingRemainder(dividingBy: transform.markingResolution), 0, "ticks land on multiples of the resolution")
    assert(transform.markingTime(index: transform.markingCount - 1) >= transform.position + transform.zoom, "the ticks reach past the right edge")
}

private func checkMinimap() {
    let transform = TimelineTransform(position: 30, zoom: 20)
    let chip = transform.minimapChip(barWidth: 400, duration: 100)
    approx(Double(chip.width), 80, "the chip is as wide as the visible share of the recording")
    approx(Double(chip.x), 0.375 * 320, "the chip sits at the scrolled share of its travel")
    approx(transform.minimapMoveScale(barWidth: 400, duration: 100), 0.25, "dragging the chip across its travel scrolls the whole recording")
    approx(transform.minimapClickPosition(x: 200, barWidth: 400, duration: 100), 40, "clicking the bar centres the window on that time")

    let tiny = TimelineTransform(position: 0, zoom: 3).minimapChip(barWidth: 400, duration: 4000)
    approx(Double(tiny.width), 20, "the chip never shrinks below a grabbable width")

    assert(!TimelineTransform.fitting(duration: 100).isZoomedIn(duration: 100), "a fitted window hides the minimap")
    assert(transform.isZoomedIn(duration: 100), "a narrowed window shows the minimap")
}

private func checkSplitSnapping() {
    let snapper = SplitSnapper(clipStart: 0, clipEnd: 10, radius: 0.3)

    let pulled = snapper.snap(5.1, candidates: [5, 8])
    approx(pulled.time, 5, "a cut near the playhead snaps to it")
    assert(pulled.snapped, "the snap is reported so the timeline can flag it")

    let free = snapper.snap(6.5, candidates: [5, 8])
    approx(free.time, 6.5, "a cut clear of every candidate stays where it was dropped")
    assert(!free.snapped, "an unsnapped cut is not flagged")

    approx(snapper.snap(4.9, candidates: [5, 4.95]).time, 4.95, "the nearest candidate wins")
    approx(snapper.snap(5, candidates: [5.2, 4.8]).time, 4.8, "a tie resolves to the earlier candidate")

    let edge = SplitSnapper(clipStart: 0, clipEnd: 10, radius: 1)
    approx(edge.snap(0.1, candidates: [0.01]).time, 0.1, "snapping never leaves a sliver at the clip start")
    approx(edge.snap(9.9, candidates: [9.99]).time, 9.9, "snapping never leaves a sliver at the clip end")
}

@main
enum TimelineTransformCheck {
    static func main() {
        checkZoomLimits()
        checkPixelMapping()
        checkZoomAnchoring()
        checkPositionClamp()
        checkMarkings()
        checkMinimap()
        checkSplitSnapping()
        print("TimelineTransformCheck: zoom anchoring, position clamps, ruler steps, minimap and split snapping all hold")
    }
}
