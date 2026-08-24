import CoreGraphics
import Foundation

@main
enum CropGeometryCheck {
    static let tolerance: CGFloat = 1e-9

    static func expectClose(_ a: CGFloat, _ b: CGFloat, _ label: String) {
        precondition(abs(a - b) < tolerance, "\(label): \(a) != \(b)")
    }

    static func expectClose(_ a: CGRect, _ b: CGRect, _ label: String) {
        expectClose(a.minX, b.minX, "\(label).x")
        expectClose(a.minY, b.minY, "\(label).y")
        expectClose(a.width, b.width, "\(label).width")
        expectClose(a.height, b.height, "\(label).height")
    }

    static func expectValid(_ rect: CGRect, _ label: String) {
        precondition(rect.minX >= -tolerance, "\(label): origin.x escapes the frame \(rect)")
        precondition(rect.minY >= -tolerance, "\(label): origin.y escapes the frame \(rect)")
        precondition(rect.maxX <= 1 + tolerance, "\(label): maxX escapes the frame \(rect)")
        precondition(rect.maxY <= 1 + tolerance, "\(label): maxY escapes the frame \(rect)")
        precondition(rect.width >= CropGeometry.minFraction - tolerance, "\(label): collapsed width \(rect)")
        precondition(rect.height >= CropGeometry.minFraction - tolerance, "\(label): collapsed height \(rect)")
    }

    /// The same mapping `AnnotationItem.remapped(from:)` applies, so the check exercises what the editor actually does to coordinates.
    static func remap(_ point: CGPoint, from crop: CGRect) -> CGPoint {
        CGPoint(x: (point.x - crop.minX) / crop.width, y: (point.y - crop.minY) / crop.height)
    }

    static func checkResizeStaysValid() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let allEdges: [CropGeometry.Edges] = [
            .left, .right, .top, .bottom,
            [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]
        ]
        let targets = [
            CGPoint(x: -5, y: -5), CGPoint(x: 5, y: 5),
            CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.79, y: 0.79),
            CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0)
        ]
        for edges in allEdges {
            for target in targets {
                expectValid(CropGeometry.resized(start, edges: edges, to: target), "resize \(edges.rawValue) -> \(target)")
            }
        }

        expectClose(
            CropGeometry.resized(start, edges: [.left, .top], to: CGPoint(x: 0.1, y: 0.15)),
            CGRect(x: 0.1, y: 0.15, width: 0.7, height: 0.65),
            "resize top-left"
        )
        expectClose(
            CropGeometry.resized(start, edges: .right, to: CGPoint(x: 2, y: 0)),
            CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.6),
            "resize right clamps to the frame"
        )
    }

    static func checkMoveStaysInFrame() {
        let rect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        for dx in [-2.0, -0.1, 0.0, 0.1, 2.0] as [CGFloat] {
            for dy in [-2.0, -0.1, 0.0, 0.1, 2.0] as [CGFloat] {
                let moved = CropGeometry.moved(rect, by: CGSize(width: dx, height: dy))
                expectValid(moved, "move \(dx),\(dy)")
                expectClose(moved.width, rect.width, "move \(dx),\(dy) width")
                expectClose(moved.height, rect.height, "move \(dx),\(dy) height")
            }
        }
        expectClose(
            CropGeometry.moved(rect, by: CGSize(width: 0.5, height: -0.5)),
            CGRect(x: 0.6, y: 0, width: 0.4, height: 0.4),
            "move clamps against both walls"
        )
    }

    /// Cropping twice must land where a single crop of the composed rect would, or Reset restores the wrong framing.
    static func checkComposeMatchesSuccessiveCrops() {
        let first = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        let second = CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)
        let composed = CropGeometry.composed(first, second)
        expectValid(composed, "composed")

        for point in [CGPoint(x: 0.15, y: 0.25), CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.55, y: 0.55)] {
            expectClose(
                CGRect(origin: remap(remap(point, from: first), from: second), size: .zero),
                CGRect(origin: remap(point, from: composed), size: .zero),
                "successive crops of \(point)"
            )
        }

        expectClose(CropGeometry.composed(CropGeometry.identity, second), second, "identity is the left unit")
        expectClose(CropGeometry.composed(first, CropGeometry.identity), first, "identity is the right unit")
    }

    /// Reset remaps through the inverse, so crop-then-reset has to return every coordinate untouched.
    static func checkInverseUndoesTheCrop() {
        let crops = [
            CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            CGRect(x: 0, y: 0, width: 0.08, height: 0.08),
            CGRect(x: 0.92, y: 0.92, width: 0.08, height: 0.08),
            CropGeometry.identity
        ]
        for crop in crops {
            let inverse = CropGeometry.inverted(crop)
            for point in [CGPoint(x: 0, y: 0), CGPoint(x: 0.37, y: 0.62), CGPoint(x: 1, y: 1)] {
                let roundTripped = remap(remap(point, from: crop), from: inverse)
                expectClose(roundTripped.x, point.x, "inverse of \(crop) at \(point).x")
                expectClose(roundTripped.y, point.y, "inverse of \(crop) at \(point).y")
            }
        }
        expectClose(CropGeometry.inverted(.zero), CropGeometry.identity, "degenerate crop inverts to identity")
    }

    /// The exporter derives the render size from these pixels, so a crop of the whole frame must give the whole frame back.
    static func checkPixelsCoverTheSource() {
        let size = CGSize(width: 1920, height: 1080)
        expectClose(CropGeometry.pixels(CropGeometry.identity, in: size), CGRect(origin: .zero, size: size), "identity in pixels")
        expectClose(
            CropGeometry.pixels(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), in: size),
            CGRect(x: 960, y: 540, width: 960, height: 540),
            "bottom-right quadrant in pixels"
        )
    }

    static func main() {
        checkResizeStaysValid()
        checkMoveStaysInFrame()
        checkComposeMatchesSuccessiveCrops()
        checkInverseUndoesTheCrop()
        checkPixelsCoverTheSource()
        print("CropGeometryCheck: resize, move, compose, inverse and pixel mapping all hold")
    }
}
