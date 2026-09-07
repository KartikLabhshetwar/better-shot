import Foundation

@main
struct RecordingTimelineInteractionCheck {
    static func main() {
        var viewport = RecordingTimelineViewport()
        viewport.fit(duration: 120)
        assert(viewport.visibleSeconds == 120 && viewport.position == 0)
        viewport.updateZoom(60, origin: 30, duration: 120)
        assert(viewport.visibleSeconds == 60 && viewport.position == 15, "Zoom must keep the origin at 25% of the viewport")
        viewport.updateZoom(30, origin: 75, duration: 120)
        assert(viewport.position == 45, "Left minimap handle must keep the right edge pinned")
        viewport.updateZoom(15, origin: 45, duration: 120)
        assert(viewport.position == 45, "Right minimap handle must keep the left edge pinned")
        viewport.setPosition(999, duration: 120)
        assert(viewport.position == 105)
        viewport.updateZoom(0, origin: 120, duration: 120)
        assert(viewport.visibleSeconds == 3 && viewport.position == 117)
        let valid = viewport
        viewport.updateZoom(.nan, origin: 0, duration: 120)
        assert(viewport == valid)
        viewport.fit(duration: 3600)
        assert(viewport.visibleSeconds == 600, "Long recordings open at Cap's ten-minute overview")
        viewport.fit(duration: 2)
        assert(viewport.visibleSeconds == 3 && viewport.position == 0)

        let occupied = [2.0...4.0, 7.0...9.0]
        func range(_ at: Double, end: Double? = nil, scale: Double = 0.01) -> ClosedRange<Double>? {
            RecordingTimelineViewport.newZoomRange(at: at, draggedTo: end, secondsPerPoint: scale,
                                                  duration: 12, occupied: occupied)
        }
        assert(range(0) == 0...1, "A click creates a one-second zoom")
        assert(range(3) == nil, "Clicking an existing zoom must not create another")
        assert(range(4) == 4...5, "The gap starts at the previous zoom's end")
        assert(range(5, end: 11) == 5...7, "Dragging must stop at the next zoom")
        assert(range(6.8) == 6...7, "The hover preview fits before the next zoom")
        assert(range(5, scale: 0.1) == nil, "Do not show an 80-point preview that cannot fit")
        assert(range(11.9) == 11...12, "A click near the end stays inside the recording")
        assert(range(12) == nil)
        assert(RecordingTimelineViewport.moving(4...6, by: 8, within: 2...10) == 8...10)
        assert(RecordingTimelineViewport.moving(4...6, by: -8, within: 2...10) == 2...4)
        assert(RecordingTimelineViewport.resizing(4...6, leading: true, by: -8, within: 2...10, secondsPerPoint: 0.01) == 2...6)
        assert(RecordingTimelineViewport.resizing(4...6, leading: false, by: -8, within: 2...10, secondsPerPoint: 0.01) == 4...5)
        assert(RecordingTimelineViewport.resizing(0...0.5, leading: true, by: 1, within: 0...2, secondsPerPoint: 0.01) == 0...0.5)
        print("RecordingTimelineInteractionCheck: anchored zoom, minimap edges, bounds, and zoom insertion passed")
    }
}
