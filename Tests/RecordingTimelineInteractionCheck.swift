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
        assert(viewport.visibleSeconds == 3600, "Fit must show the entire recording")
        viewport.updateZoom(0, origin: 1800, duration: 3600, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 36, "Long recordings must retain the native lane-width cap")
        assert(3600 / viewport.visibleSeconds * 1000 <= RecordingTimelineViewport.maximumContentWidth)
        viewport.fit(duration: 2)
        assert(viewport.visibleSeconds == 2 && viewport.position == 0)
        viewport.updateZoom(2 / 1.6, origin: 1, duration: 2, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 1.25 && viewport.position == 0.375,
               "A short clip must zoom in and keep its midpoint anchored")
        viewport.updateZoom(viewport.visibleSeconds * 1.6, origin: 1, duration: 2, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 2 && viewport.position == 0, "Zoom out must return to Fit")
        viewport.updateZoomProgress(1, origin: 1, duration: 2, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 0.125 && viewport.zoomProgress(duration: 2, viewportWidth: 1000) == 1)
        viewport.updateZoomProgress(0.5, origin: 1, duration: 2, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 0.5 && viewport.zoomProgress(duration: 2, viewportWidth: 1000) == 0.5)
        viewport.updateZoomProgress(0, origin: 1, duration: 2, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 2 && viewport.position == 0, "Both slider endpoints must be reachable")
        viewport.fit(duration: 0.25)
        viewport.updateZoom(0, origin: 0, duration: 0.25, viewportWidth: 1000)
        assert(viewport.visibleSeconds == 0.25 / 16, "Subsecond clips must also zoom")

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
        assert(RecordingTimelineViewport.resizing(4...6, leading: true, by: -8, within: 2...10, minimumDuration: 0.5) == 2...6)
        assert(RecordingTimelineViewport.resizing(4...6, leading: false, by: -8, within: 2...10, minimumDuration: 0.5) == 4...4.5)
        assert(RecordingTimelineViewport.resizing(0...0.5, leading: true, by: 1, within: 0...2, minimumDuration: 0.5) == 0...0.5)
        assert(RecordingTimelineViewport.resizing(4...6, leading: true, by: 0.25, within: 2...10, minimumDuration: 0.5) == 4.25...6)
        assert(RecordingTimelineViewport.resizing(4...6, leading: false, by: 1.25, within: 2...7, minimumDuration: 0.5) == 4...7)
        assert(RecordingTimelineViewport.resizing(4...6, leading: false, by: 0, within: 2...10, minimumDuration: 0.5) == 4...6,
               "Grabbing an edge must not change its length")
        assert(RecordingTimelineViewport.resizing(4...6, leading: false, by: .nan, within: 2...10, minimumDuration: 0.5) == 4...6)
        print("RecordingTimelineInteractionCheck: anchored zoom, minimap edges, bounds, and zoom insertion passed")
    }
}
