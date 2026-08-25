import CoreGraphics
import Foundation

/// A ring that pops out of each recorded click, so a viewer can see where the pointer acted.
nonisolated struct ClickHighlight: Equatable, Sendable {
    static let duration: TimeInterval = 0.55
    static let minimumScale: CGFloat = 0.35
    /// White alone vanishes on a light window, so the ring carries a dark halo under it and reads on any background.
    static let strokeFraction: CGFloat = 0.16
    static let strokeOpacity: CGFloat = 0.95
    static let haloOpacity: CGFloat = 0.4
    static let haloWidthScale: CGFloat = 2.2
    static let fillOpacity: CGFloat = 0.16

    var time: TimeInterval
    var point: CGPoint

    struct Phase: Equatable, Sendable {
        var scale: CGFloat
        var opacity: CGFloat
    }

    func phase(at frameTime: TimeInterval) -> Phase? {
        let elapsed = frameTime - time
        guard elapsed >= 0, elapsed < Self.duration else { return nil }
        let progress = CGFloat(elapsed / Self.duration)
        let eased = 1 - pow(1 - progress, 3)
        return Phase(
            scale: Self.minimumScale + (1 - Self.minimumScale) * eased,
            opacity: 1 - progress * progress
        )
    }

    /// Presses land on the source timeline, so cuts and speed changes have to move them before they can be drawn.
    static func highlights(
        presses: [ClickHighlight],
        editorTime: (TimeInterval) -> TimeInterval?,
        project: (CGPoint, TimeInterval) -> CGPoint
    ) -> [ClickHighlight] {
        presses.compactMap { press in
            guard let time = editorTime(press.time) else { return nil }
            return ClickHighlight(time: time, point: project(press.point, time))
        }
    }

    /// Presses are normalized top-down like the screen, but the compositor paints y-up, so the projection has to flip.
    static func canvasPoint(
        normalized: CGPoint,
        videoSize: CGSize,
        transform: CGAffineTransform,
        canvasHeight: CGFloat
    ) -> CGPoint {
        let projected = CGPoint(x: normalized.x * videoSize.width, y: normalized.y * videoSize.height)
            .applying(transform)
        return CGPoint(x: projected.x, y: canvasHeight - projected.y)
    }

    static func active(in highlights: [ClickHighlight], at frameTime: TimeInterval) -> [(ClickHighlight, Phase)] {
        highlights.compactMap { highlight in
            highlight.phase(at: frameTime).map { (highlight, $0) }
        }
    }
}
