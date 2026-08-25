import Foundation

/// The base of the geometry hierarchy: everything a shape needs for hit testing, snapping,
/// arrow intersection and bounds.
///
/// Subclasses supply `computeVertices()`; everything else (nearest point, hit testing,
/// intersections, bounds, length, area) falls out of the vertex polyline. Subclasses override
/// the pieces they can do analytically.
class Geometry2d {
    var isFilled: Bool
    var isClosed: Bool

    init(isFilled: Bool, isClosed: Bool) {
        self.isFilled = isFilled
        self.isClosed = isClosed
    }

    // MARK: - To be overridden

    func computeVertices() -> [Vec] { [] }

    private var _vertices: [Vec]?
    var vertices: [Vec] {
        if let v = _vertices { return v }
        let v = computeVertices()
        _vertices = v
        return v
    }

    func nearestPoint(_ point: Vec) -> Vec {
        let verts = vertices
        guard !verts.isEmpty else { return point }
        var best = verts[0]
        var bestDist = Vec.dist2(point, best)
        let limit = isClosed ? verts.count : verts.count - 1
        guard limit > 0 else { return best }
        for i in 0..<limit {
            let p = Vec.nearestPointOnLineSegment(verts[i], verts[(i + 1) % verts.count], point)
            let d = Vec.dist2(point, p)
            if d < bestDist {
                best = p
                bestDist = d
            }
        }
        return best
    }

    // MARK: - Derived

    private var _bounds: Box?
    var bounds: Box {
        if let b = _bounds { return b }
        let b = computeBounds()
        _bounds = b
        return b
    }

    func computeBounds() -> Box { Box.fromPoints(vertices) }

    var center: Vec { bounds.center }

    private var _length: Double?
    var length: Double {
        if let l = _length { return l }
        let l = computeLength()
        _length = l
        return l
    }

    func computeLength() -> Double {
        let verts = vertices
        guard verts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<verts.count { total += Vec.dist(verts[i - 1], verts[i]) }
        if isClosed { total += Vec.dist(verts[verts.count - 1], verts[0]) }
        return total
    }

    // MARK: - Hit testing

    func hitTestPoint(_ point: Vec, margin: Double = 0, hitInside: Bool = false) -> Bool {
        if isClosed && (isFilled || hitInside) && pointInPolygon(point, vertices) { return true }
        return Vec.dist2(point, nearestPoint(point)) <= margin * margin
    }

    func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        let d = Vec.dist(point, nearestPoint(point))
        if isClosed && (isFilled || hitInside) && pointInPolygon(point, vertices) { return -d }
        return d
    }

    // MARK: - Intersections

    func intersectLineSegment(_ a: Vec, _ b: Vec) -> [Vec] {
        let ints = isClosed
            ? intersectLineSegmentPolygon(a, b, vertices)
            : intersectLineSegmentPolyline(a, b, vertices)
        return ints ?? []
    }

    func intersectCircle(_ center: Vec, _ radius: Double) -> [Vec] {
        let ints = isClosed
            ? intersectCirclePolygon(center, radius, vertices)
            : intersectCirclePolyline(center, radius, vertices)
        return ints ?? []
    }

    /// Whether this geometry overlaps a selection polygon (the brush).
    func overlapsPolygon(_ polygon: [Vec]) -> Bool {
        let verts = vertices
        if verts.contains(where: { pointInPolygon($0, polygon) }) { return true }

        if isClosed {
            if isFilled {
                if pointInPolygon(center, polygon) { return true }
                if polygon.allSatisfy({ pointInPolygon($0, verts) }) { return true }
            }
            if polygonsIntersect(polygon, verts) { return true }
        } else {
            if polygonIntersectsPolyline(polygon, verts) { return true }
        }
        return false
    }

    /// A copy of this geometry with `transform` applied to its vertices.
    func transformed(_ transform: Mat) -> Geometry2d {
        TransformedGeometry2d(self, transform)
    }
}

/// Wraps a geometry in a transform, mapping points in and out of its local space. Only used
/// for uniform scales (shape page transforms).
final class TransformedGeometry2d: Geometry2d {
    private let geometry: Geometry2d
    private let matrix: Mat
    private let inverseMatrix: Mat
    private let scale: Double

    init(_ geometry: Geometry2d, _ matrix: Mat) {
        self.geometry = geometry
        self.matrix = matrix
        self.inverseMatrix = matrix.inverse
        self.scale = matrix.decomposed.scaleX
        super.init(isFilled: geometry.isFilled, isClosed: geometry.isClosed)
    }

    override func computeVertices() -> [Vec] {
        matrix.applyToPoints(geometry.vertices)
    }

    override func nearestPoint(_ point: Vec) -> Vec {
        matrix.applyToPoint(geometry.nearestPoint(inverseMatrix.applyToPoint(point)))
    }

    override func hitTestPoint(_ point: Vec, margin: Double = 0, hitInside: Bool = false) -> Bool {
        geometry.hitTestPoint(inverseMatrix.applyToPoint(point), margin: margin / scale, hitInside: hitInside)
    }

    override func distanceToPoint(_ point: Vec, hitInside: Bool = false) -> Double {
        geometry.distanceToPoint(inverseMatrix.applyToPoint(point), hitInside: hitInside) * scale
    }

    override func intersectLineSegment(_ a: Vec, _ b: Vec) -> [Vec] {
        matrix.applyToPoints(
            geometry.intersectLineSegment(inverseMatrix.applyToPoint(a), inverseMatrix.applyToPoint(b))
        )
    }

    override func intersectCircle(_ center: Vec, _ radius: Double) -> [Vec] {
        matrix.applyToPoints(
            geometry.intersectCircle(inverseMatrix.applyToPoint(center), radius / scale)
        )
    }

    override func transformed(_ transform: Mat) -> Geometry2d {
        TransformedGeometry2d(geometry, Mat.multiply(transform, matrix))
    }
}
