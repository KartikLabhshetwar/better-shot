import CoreGraphics
import Foundation

nonisolated enum ExportCanvasGeometry {
    struct Canvas: Equatable, Sendable {
        var videoWidth: CGFloat
        var videoHeight: CGFloat
        var padding: CGFloat
        var width: CGFloat
        var height: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat
    }

    static func evenPixels(_ value: CGFloat) -> Int {
        guard value.isFinite, value >= 2 else { return 2 }
        return max(2, Int(value.rounded(.toNearestOrAwayFromZero)) & ~1)
    }

    static func canvas(
        videoWidth: CGFloat,
        videoHeight: CGFloat,
        paddingFraction: CGFloat,
        aspectRatio: CGFloat? = nil
    ) -> Canvas {
        let width = CGFloat(evenPixels(videoWidth))
        let height = CGFloat(evenPixels(videoHeight))
        let fraction = paddingFraction.isFinite ? max(0, paddingFraction) : 0
        let padding = (min(width, height) * fraction).rounded(.toNearestOrAwayFromZero)

        var canvasWidth = width + padding * 2
        var canvasHeight = height + padding * 2

        if let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            if canvasWidth / canvasHeight < aspectRatio {
                canvasWidth = canvasHeight * aspectRatio
            } else {
                canvasHeight = canvasWidth / aspectRatio
            }
            canvasWidth = CGFloat(evenPixels(canvasWidth))
            canvasHeight = CGFloat(evenPixels(canvasHeight))
        }

        return Canvas(
            videoWidth: width,
            videoHeight: height,
            padding: padding,
            width: canvasWidth,
            height: canvasHeight,
            offsetX: ((canvasWidth - width) / 2).rounded(.toNearestOrAwayFromZero),
            offsetY: ((canvasHeight - height) / 2).rounded(.toNearestOrAwayFromZero)
        )
    }
}
