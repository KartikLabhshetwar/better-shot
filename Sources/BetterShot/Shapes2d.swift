import Foundation

/// The concrete geometries shapes are built from.

/// A single line segment.
final class Edge2d: Geometry2d {
    let start: Vec
    let end: Vec
    private let dx: Double
    private let dy: Double
    private let len2: Double

    init(start: Vec, end: Vec) {
        self.start = start
        self.end = end
        self.dx = end.x - start.x
        self.dy = end.y - start.y
        self.len2 = dx * dx + dy * dy
        super.init(isFilled: false, isClosed: false)
    }

    override func computeVertices() -> [Vec] { [start, end] }
    override func computeLength() -> Double { len2.squareRoot() }

    override func nearestPoint(_ point: Vec) -> Vec {
        if len2 == 0 { return start }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / len2
        if t <= 0 { return start }
        if t >= 1 { return end }
        return Vec(start.x + dx * t, start.y + dy * t)
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        Vec.dist(point, nearestPoint(point))
    }
}

/// An open run of line segments.
class Polyline2d: Geometry2d {
    let points: [Vec]

    init(points: [Vec], isClosed: Bool = false, isFilled: Bool = false) {
        self.points = points
        super.init(isFilled: isFilled, isClosed: isClosed)
    }

    override func computeVertices() -> [Vec] { points }

    private var _segments: [Edge2d]?
    var segments: [Edge2d] {
        if let s = _segments { return s }
        var result: [Edge2d] = []
        let verts = vertices
        if verts.count > 1 {
            for i in 0..<(verts.count - 1) {
                result.append(Edge2d(start: verts[i], end: verts[i + 1]))
            }
            if isClosed {
                result.append(Edge2d(start: verts[verts.count - 1], end: verts[0]))
            }
        }
        _segments = result
        return result
    }

    override func computeLength() -> Double {
        segments.reduce(0) { $0 + $1.length }
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        var minDist = Double.infinity
        for segment in segments {
            minDist = Swift.min(minDist, segment.distanceToPoint(point))
        }
        if isClosed && (isFilled || hitInside) && pointInPolygon(point, vertices) { return -minDist }
        return minDist
    }

    override func hitTestPoint(_ point: Vec, margin: Double = 0, hitInside: Bool = false) -> Bool {
        distanceToPoint(point, hitInside: hitInside) <= margin
    }
}

/// A closed run of line segments.
class Polygon2d: Polyline2d {
    init(points: [Vec], isFilled: Bool) {
        super.init(points: points, isClosed: true, isFilled: isFilled)
    }
}

/// An axis-aligned rectangle in the shape's own space.
final class Rectangle2d: Polygon2d {
    let x: Double, y: Double, w: Double, h: Double

    init(x: Double = 0, y: Double = 0, width: Double, height: Double, isFilled: Bool) {
        self.x = x; self.y = y; self.w = width; self.h = height
        super.init(
            points: [
                Vec(x, y),
                Vec(x + width, y),
                Vec(x + width, y + height),
                Vec(x, y + height),
            ],
            isFilled: isFilled
        )
    }

    override func computeBounds() -> Box { Box(x, y, w, h) }
}

/// An ellipse, approximated by a polygon whose resolution follows its perimeter, so hit tests
/// and arrow intersections agree with what's drawn.
final class Ellipse2d: Geometry2d {
    let w: Double
    let h: Double

    init(width: Double, height: Double, isFilled: Bool) {
        self.w = width
        self.h = height
        super.init(isFilled: isFilled, isClosed: true)
    }

    override func computeVertices() -> [Vec] {
        let w = Swift.max(1, self.w)
        let h = Swift.max(1, self.h)
        let cx = w / 2
        let cy = h / 2
        let q = pow(cx - cy, 2) / pow(cx + cy, 2)
        let p = PI * (cx + cy) * (1 + (3 * q) / (10 + (4 - 3 * q).squareRoot()))
        let len = getVerticesCountForArcLength(p)
        let step = PI2 / Double(len)

        let a = cos(step)
        let b = sin(step)
        var sinv = 0.0
        var cosv = 1.0

        var vertices: [Vec] = []
        vertices.reserveCapacity(len)
        for _ in 0..<len {
            vertices.append(Vec(clamp(cx + cx * cosv, 0, w), clamp(cy + cy * sinv, 0, h)))
            let ts = b * cosv + a * sinv
            let tc = a * cosv - b * sinv
            sinv = ts
            cosv = tc
        }
        return vertices
    }

    private var _edges: [Edge2d]?
    private var edges: [Edge2d] {
        if let e = _edges { return e }
        let verts = vertices
        var result: [Edge2d] = []
        for i in 0..<verts.count {
            result.append(Edge2d(start: verts[i], end: verts[(i + 1) % verts.count]))
        }
        _edges = result
        return result
    }

    override func nearestPoint(_ point: Vec) -> Vec {
        var nearest = point
        var dist = Double.infinity
        for edge in edges {
            let p = edge.nearestPoint(point)
            let d = Vec.dist2(p, point)
            if d < dist {
                nearest = p
                dist = d
            }
        }
        return nearest
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        var minDist = Double.infinity
        for edge in edges { minDist = Swift.min(minDist, edge.distanceToPoint(point)) }
        if (isFilled || hitInside) && pointInPolygon(point, vertices) { return -minDist }
        return minDist
    }

    override func computeBounds() -> Box { Box(0, 0, w, h) }

    override func computeLength() -> Double {
        perimeterOfEllipse(Swift.max(0, w / 2), Swift.max(0, h / 2))
    }
}

/// A circle, used for the dot case of the draw shape.
final class Circle2d: Geometry2d {
    let circleCenter: Vec
    let radius: Double
    private let x: Double
    private let y: Double

    init(x: Double = 0, y: Double = 0, radius: Double, isFilled: Bool) {
        self.x = x
        self.y = y
        self.radius = radius
        self.circleCenter = Vec(radius + x, radius + y)
        super.init(isFilled: isFilled, isClosed: true)
    }

    override func computeBounds() -> Box { Box(x, y, radius * 2, radius * 2) }

    override func computeVertices() -> [Vec] {
        let n = getVerticesCountForArcLength(PI2 * radius)
        return (0..<n).map { i in
            getPointOnCircle(circleCenter, radius, (Double(i) / Double(n)) * PI2)
        }
    }

    override func nearestPoint(_ point: Vec) -> Vec {
        let dx = point.x - circleCenter.x
        let dy = point.y - circleCenter.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len == 0 { return Vec(circleCenter.x + radius, circleCenter.y) }
        let scale = radius / len
        return Vec(circleCenter.x + dx * scale, circleCenter.y + dy * scale)
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        let distToEdge = Vec.dist(point, circleCenter) - radius
        if distToEdge < 0 && (isFilled || hitInside) { return distToEdge }
        return abs(distToEdge)
    }

    override func hitTestPoint(_ point: Vec, margin: Double = 0, hitInside: Bool = false) -> Bool {
        let dist2 = Vec.dist2(point, circleCenter)
        if (isFilled || hitInside) && dist2 <= radius * radius { return true }
        let outer = radius + margin
        if dist2 > outer * outer { return false }
        let inner = radius - margin
        if inner <= 0 { return true }
        return dist2 >= inner * inner
    }
}

/// A circular arc, used as the body geometry of a bent arrow.
final class Arc2d: Geometry2d {
    let arcCenter: Vec
    let radius: Double
    let start: Vec
    let end: Vec
    let measure: Double
    let angleStart: Double
    let angleEnd: Double

    init(center: Vec, start: Vec, end: Vec, sweepFlag: Int, largeArcFlag: Int) {
        self.arcCenter = center
        self.start = start
        self.end = end
        self.angleStart = Vec.angle(center, start)
        self.angleEnd = Vec.angle(center, end)
        self.radius = Vec.dist(center, start)
        self.measure = getArcMeasure(angleStart, angleEnd, sweepFlag, largeArcFlag)
        super.init(isFilled: false, isClosed: false)
    }

    override func computeVertices() -> [Vec] {
        let n = getVerticesCountForArcLength(abs(measure * radius))
        return (0...n).map { i in
            let t = (Double(i) / Double(n)) * measure
            return getPointOnCircle(arcCenter, radius, angleStart + t)
        }
    }

    override func nearestPoint(_ point: Vec) -> Vec {
        let t = getPointInArcT(measure, angleStart, angleEnd, arcCenter.angle(point))
        if t <= 0 { return start }
        if t >= 1 { return end }
        let dx = point.x - arcCenter.x
        let dy = point.y - arcCenter.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len == 0 { return start }
        let scale = radius / len
        return Vec(arcCenter.x + dx * scale, arcCenter.y + dy * scale)
    }

    override func computeLength() -> Double { abs(measure * radius) }
}

/// Several geometries treated as one, for shapes made of multiple parts (an arrow's body plus
/// its arrowheads).
final class Group2d: Geometry2d {
    let children: [Geometry2d]

    init(children: [Geometry2d]) {
        self.children = children
        super.init(isFilled: false, isClosed: false)
    }

    override func computeVertices() -> [Vec] {
        children.flatMap { $0.vertices }
    }

    override func nearestPoint(_ point: Vec) -> Vec {
        var nearest = point
        var dist = Double.infinity
        for child in children {
            let p = child.nearestPoint(point)
            let d = Vec.dist2(p, point)
            if d < dist {
                nearest = p
                dist = d
            }
        }
        return nearest
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        children.reduce(Double.infinity) {
            Swift.min($0, $1.distanceToPoint(point, hitInside: hitInside))
        }
    }

    override func hitTestPoint(_ point: Vec, margin: Double = 0, hitInside: Bool = false) -> Bool {
        children.contains { $0.hitTestPoint(point, margin: margin, hitInside: hitInside) }
    }

    override func computeBounds() -> Box {
        Box.common(children.map { $0.bounds })
    }

    override func intersectLineSegment(_ a: Vec, _ b: Vec) -> [Vec] {
        children.flatMap { $0.intersectLineSegment(a, b) }
    }

    override func intersectCircle(_ center: Vec, _ radius: Double) -> [Vec] {
        children.flatMap { $0.intersectCircle(center, radius) }
    }

    override func overlapsPolygon(_ polygon: [Vec]) -> Bool {
        children.contains { $0.overlapsPolygon(polygon) }
    }
}
