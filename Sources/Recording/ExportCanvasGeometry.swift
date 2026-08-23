import CoreGraphics
import Foundation

nonisolated enum ExportCanvasGeometry {
    struct Canvas: Equatable, Sendable {
        var videoWidth: CGFloat
        var videoHeight: CGFloat
        var padding: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    static func evenPixels(_ value: CGFloat) -> Int {
        guard value.isFinite, value >= 2 else { return 2 }
        return max(2, Int(value.rounded(.toNearestOrAwayFromZero)) & ~1)
    }

    static func canvas(videoWidth: CGFloat, videoHeight: CGFloat, paddingFraction: CGFloat) -> Canvas {
        let width = CGFloat(evenPixels(videoWidth))
        let height = CGFloat(evenPixels(videoHeight))
        let fraction = paddingFraction.isFinite ? max(0, paddingFraction) : 0
        let padding = (min(width, height) * fraction).rounded(.toNearestOrAwayFromZero)
        return Canvas(
            videoWidth: width,
            videoHeight: height,
            padding: padding,
            width: width + padding * 2,
            height: height + padding * 2
        )
    }
}
