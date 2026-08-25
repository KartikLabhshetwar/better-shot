import CoreGraphics
import Foundation

/// An axis-aligned bounding box.
struct Box: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(_ x: Double = 0, _ y: Double = 0, _ w: Double = 0, _ h: Double = 0) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }
    var width: Double { w }
    var height: Double { h }

    var point: Vec { Vec(x, y) }
    var center: Vec { Vec(midX, midY) }

    /// Corners in clockwise order from the top left.
    var corners: [Vec] {
        [Vec(minX, minY), Vec(maxX, minY), Vec(maxX, maxY), Vec(minX, maxY)]
    }

    var sides: [(Vec, Vec)] {
        let c = corners
        return [(c[0], c[1]), (c[1], c[2]), (c[2], c[3]), (c[3], c[0])]
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    static func fromPoints(_ points: [Vec]) -> Box {
        guard !points.isEmpty else { return Box() }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = Swift.min(minX, p.x)
            minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x)
            maxY = Swift.max(maxY, p.y)
        }
        return Box(minX, minY, maxX - minX, maxY - minY)
    }

    static func common(_ boxes: [Box]) -> Box {
        guard let first = boxes.first else { return Box() }
        var minX = first.minX, minY = first.minY, maxX = first.maxX, maxY = first.maxY
        for b in boxes.dropFirst() {
            minX = Swift.min(minX, b.minX)
            minY = Swift.min(minY, b.minY)
            maxX = Swift.max(maxX, b.maxX)
            maxY = Swift.max(maxY, b.maxY)
        }
        return Box(minX, minY, maxX - minX, maxY - minY)
    }

    func containsPoint(_ p: Vec, margin: Double = 0) -> Bool {
        !(p.x < minX - margin || p.y < minY - margin || p.x > maxX + margin || p.y > maxY + margin)
    }

    func contains(_ other: Box) -> Bool {
        other.minX >= minX && other.minY >= minY && other.maxX <= maxX && other.maxY <= maxY
    }

    func collides(_ other: Box) -> Bool {
        !(other.maxX < minX || other.minX > maxX || other.maxY < minY || other.minY > maxY)
    }

    func expandBy(_ n: Double) -> Box {
        Box(x - n, y - n, w + n * 2, h + n * 2)
    }
}
