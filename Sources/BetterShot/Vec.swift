import CoreGraphics
import Foundation

/// A 2d vector with a third `z` channel, used by the freehand engine to carry pressure.
struct Vec: Equatable, Codable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 1) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ point: CGPoint) {
        self.init(Double(point.x), Double(point.y))
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    static let zero = Vec(0, 0)

    // MARK: - Instance math

    var len2: Double { x * x + y * y }
    var len: Double { (x * x + y * y).squareRoot() }

    /// The unit vector. Zero-length vectors are returned unchanged.
    var uni: Vec {
        let l = len
        if l == 0 { return Vec(x, y, z) }
        return Vec(x / l, y / l, z)
    }

    /// Perpendicular (rotated 90° clockwise in a y-down space).
    var per: Vec { Vec(y, -x, z) }

    var isNaN: Bool { x.isNaN || y.isNaN }
    var isFinite: Bool { x.isFinite && y.isFinite }

    func angle(_ b: Vec) -> Double { atan2(b.y - y, b.x - x) }

    // MARK: - Static math

    static func add(_ a: Vec, _ b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y, a.z) }
    static func addXY(_ a: Vec, _ x: Double, _ y: Double) -> Vec { Vec(a.x + x, a.y + y, a.z) }
    static func sub(_ a: Vec, _ b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y, a.z) }
    static func subXY(_ a: Vec, _ x: Double, _ y: Double) -> Vec { Vec(a.x - x, a.y - y, a.z) }
    static func mul(_ a: Vec, _ s: Double) -> Vec { Vec(a.x * s, a.y * s, a.z) }
    static func mulV(_ a: Vec, _ b: Vec) -> Vec { Vec(a.x * b.x, a.y * b.y, a.z) }
    static func div(_ a: Vec, _ s: Double) -> Vec { Vec(a.x / s, a.y / s, a.z) }
    static func neg(_ a: Vec) -> Vec { Vec(-a.x, -a.y, a.z) }

    static func med(_ a: Vec, _ b: Vec) -> Vec { Vec((a.x + b.x) / 2, (a.y + b.y) / 2) }
    static func lrp(_ a: Vec, _ b: Vec, _ t: Double) -> Vec {
        Vec(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    static func dist2(_ a: Vec, _ b: Vec) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
    static func dist(_ a: Vec, _ b: Vec) -> Double { dist2(a, b).squareRoot() }
    static func manhattanDist(_ a: Vec, _ b: Vec) -> Double { abs(a.x - b.x) + abs(a.y - b.y) }

    /// True when `a` and `b` are closer together than `n`.
    static func distMin(_ a: Vec, _ b: Vec, _ n: Double) -> Bool { dist2(a, b) < n * n }

    static func len(_ a: Vec) -> Double { a.len }
    static func uni(_ a: Vec) -> Vec { a.uni }
    static func per(_ a: Vec) -> Vec { a.per }

    /// The unit vector pointing from `b` towards `a`.
    static func tan(_ a: Vec, _ b: Vec) -> Vec { sub(a, b).uni }

    /// Move `a` towards `b` by `distance`.
    static func nudge(_ a: Vec, _ b: Vec, _ distance: Double) -> Vec {
        add(a, mul(tan(b, a), distance))
    }

    static func angle(_ a: Vec, _ b: Vec) -> Double { atan2(b.y - a.y, b.x - a.x) }

    static func fromAngle(_ radians: Double, _ length: Double = 1) -> Vec {
        Vec(cos(radians) * length, sin(radians) * length)
    }

    /// The signed angle between two vectors treated as directions from the origin.
    static func angleBetween(_ a: Vec, _ b: Vec) -> Double {
        let p = a.x * b.x + a.y * b.y
        let n = ((a.x * a.x + a.y * a.y) * (b.x * b.x + b.y * b.y)).squareRoot()
        let sign: Double = a.x * b.y - a.y * b.x < 0 ? -1 : 1
        return sign * acos(clamp(p / n, -1, 1))
    }

    /// Rotate a vector about the origin.
    static func rot(_ a: Vec, _ radians: Double) -> Vec {
        let s = sin(radians), c = cos(radians)
        return Vec(a.x * c - a.y * s, a.x * s + a.y * c)
    }

    /// Rotate `a` about `center`.
    static func rotWith(_ a: Vec, _ center: Vec, _ radians: Double) -> Vec {
        if radians == 0 { return a }
        let s = sin(radians), c = cos(radians)
        let px = a.x - center.x
        let py = a.y - center.y
        return Vec(px * c - py * s + center.x, px * s + py * c + center.y)
    }

    /// Are the three points in clockwise order?
    static func clockwise(_ a: Vec, _ b: Vec, _ c: Vec) -> Bool {
        (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y) < 0
    }

    static func average(_ points: [Vec]) -> Vec {
        guard !points.isEmpty else { return Vec(0, 0) }
        var x = 0.0, y = 0.0
        for p in points { x += p.x; y += p.y }
        return Vec(x / Double(points.count), y / Double(points.count))
    }

    static func nearestPointOnLineSegment(_ a: Vec, _ b: Vec, _ p: Vec, _ shouldClamp: Bool = true) -> Vec {
        let dx = b.x - a.x, dy = b.y - a.y
        let d2 = dx * dx + dy * dy
        if d2 == 0 { return a }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / d2
        if shouldClamp {
            if t < 0 { t = 0 } else if t > 1 { t = 1 }
        }
        return Vec(a.x + t * dx, a.y + t * dy)
    }

    /// `n` points between `a` and `b`, optionally eased.
    static func pointsBetween(_ a: Vec, _ b: Vec, _ steps: Int, easing: (Double) -> Double = { $0 }) -> [Vec] {
        guard steps > 1 else { return [a, b] }
        return (0..<steps).map { i in
            let t = easing(Double(i) / Double(steps - 1))
            var v = lrp(a, b, t)
            v.z = a.z + (b.z - a.z) * t
            return v
        }
    }

    /// Compares with a tolerance rather than exactly. The arrow
    /// solvers depend on this: they re-derive a direction after clipping a terminal to a shape's
    /// edge and compare it against the original to detect that the terminals swapped order. An
    /// exact comparison reports a flip on every bound arrow, which inverts the arrowhead offset
    /// and pushes the tip inside the shape.
    static func equals(_ a: Vec, _ b: Vec) -> Bool {
        abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001
    }
}
