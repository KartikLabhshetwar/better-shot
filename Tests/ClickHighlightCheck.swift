import CoreGraphics
import Foundation

@main
enum ClickHighlightCheck {
    static func main() {
        let highlight = ClickHighlight(time: 2, point: CGPoint(x: 100, y: 50))

        assert(highlight.phase(at: 1.9) == nil, "a ring must not exist before its click")
        assert(highlight.phase(at: 2 + ClickHighlight.duration + 0.01) == nil, "a ring must be gone once its duration elapses")

        guard let start = highlight.phase(at: 2), let mid = highlight.phase(at: 2 + ClickHighlight.duration / 2) else {
            fatalError("expected a phase inside the ring's lifetime")
        }
        assert(start.scale == ClickHighlight.minimumScale, "the ring starts small, got \(start.scale)")
        assert(start.opacity == 1, "the ring starts opaque, got \(start.opacity)")
        assert(mid.scale > start.scale, "the ring must grow")
        assert(mid.opacity < start.opacity, "the ring must fade")

        var previousScale: CGFloat = 0
        var previousOpacity: CGFloat = 2
        var step: TimeInterval = 0
        while step < ClickHighlight.duration {
            guard let phase = highlight.phase(at: 2 + step) else { fatalError("expected a phase at \(step)") }
            assert(phase.scale >= previousScale, "scale must never shrink, broke at \(step)")
            assert(phase.opacity <= previousOpacity, "opacity must never rise, broke at \(step)")
            assert(phase.scale <= 1 && phase.opacity >= 0, "phase must stay in range, broke at \(step)")
            previousScale = phase.scale
            previousOpacity = phase.opacity
            step += 0.01
        }

        let presses = [
            ClickHighlight(time: 1, point: CGPoint(x: 0.25, y: 0.5)),
            ClickHighlight(time: 5, point: CGPoint(x: 0.75, y: 0.5))
        ]
        let mapped = ClickHighlight.highlights(
            presses: presses,
            editorTime: { $0 < 4 ? $0 - 0.5 : nil },
            project: { point, _ in CGPoint(x: point.x * 200, y: point.y * 100) }
        )
        assert(mapped.count == 1, "a press inside a cut region must be dropped, got \(mapped.count)")
        assert(mapped[0].time == 0.5, "press time must move onto the editor timeline, got \(mapped[0].time)")
        assert(mapped[0].point == CGPoint(x: 50, y: 50), "press position must project into canvas space, got \(mapped[0].point)")

        let overlapping = [ClickHighlight(time: 0, point: .zero), ClickHighlight(time: 0.1, point: .zero)]
        assert(ClickHighlight.active(in: overlapping, at: 0.15).count == 2, "overlapping clicks must both draw")
        assert(ClickHighlight.active(in: overlapping, at: 10).isEmpty, "no ring survives past its window")

        let video = CGSize(width: 1920, height: 1080)
        let cardShift = CGAffineTransform(translationX: 60, y: 40)
        let canvasHeight: CGFloat = 1080 + 80

        let nearTop = ClickHighlight.canvasPoint(
            normalized: CGPoint(x: 0.5, y: 0.1),
            videoSize: video,
            transform: cardShift,
            canvasHeight: canvasHeight
        )
        assert(nearTop.x == 1020, "x must not flip, got \(nearTop.x)")
        assert(nearTop.y == canvasHeight - 148, "a press near the top of the video must land near the top of a y-up canvas, got \(nearTop.y)")

        let nearBottom = ClickHighlight.canvasPoint(
            normalized: CGPoint(x: 0.5, y: 0.9),
            videoSize: video,
            transform: cardShift,
            canvasHeight: canvasHeight
        )
        assert(nearBottom.y < nearTop.y, "a lower press must sample lower on a y-up canvas, got \(nearBottom.y) vs \(nearTop.y)")

        let zoomed = ClickHighlight.canvasPoint(
            normalized: CGPoint(x: 0.5, y: 0.5),
            videoSize: video,
            transform: CGAffineTransform(scaleX: 2, y: 2).concatenating(cardShift),
            canvasHeight: canvasHeight
        )
        assert(zoomed == CGPoint(x: 1980, y: canvasHeight - 1120), "zoom must ride through the same transform, got \(zoomed)")

        print("ClickHighlightCheck: all assertions passed")
    }
}
