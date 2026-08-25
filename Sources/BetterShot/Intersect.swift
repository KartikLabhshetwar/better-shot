import Foundation

func intersectLineSegmentLineSegment(_ a1: Vec, _ a2: Vec, _ b1: Vec, _ b2: Vec, precision: Double = 1e-10) -> Vec? {
    let abx = a1.x - b1.x
    let aby = a1.y - b1.y
    let bvx = b2.x - b1.x
    let bvy = b2.y - b1.y
    let avx = a2.x - a1.x
    let avy = a2.y - a1.y
    let uaT = bvx * aby - bvy * abx
    let ubT = avx * aby - avy * abx
    let uB = bvy * avx - bvx * avy

    if abs(uaT) <= precision || abs(ubT) <= precision { return nil } // coincident
    if abs(uB) <= precision { return nil } // parallel

    let ua = uaT / uB
    let ub = ubT / uB
    if ua >= -precision && ua <= 1 + precision && ub >= -precision && ub <= 1 + precision {
        return Vec(a1.x + ua * avx, a1.y + ua * avy)
    }
    return nil
}

func intersectLineSegmentCircle(_ a1: Vec, _ a2: Vec, _ c: Vec, _ r: Double) -> [Vec]? {
    let dx = a2.x - a1.x
    let dy = a2.y - a1.y
    let ocx = a1.x - c.x
    let ocy = a1.y - c.y

    let a = dx * dx + dy * dy
    let b = 2 * (dx * ocx + dy * ocy)
    let cc = ocx * ocx + ocy * ocy - r * r
    let deter = b * b - 4 * a * cc

    if deter <= 0 { return nil } // outside or tangent

    let e = deter.squareRoot()
    let u1 = (-b + e) / (2 * a)
    let u2 = (-b - e) / (2 * a)

    if (u1 < 0 || u1 > 1) && (u2 < 0 || u2 > 1) { return nil }

    var result: [Vec] = []
    if u1 >= 0 && u1 <= 1 { result.append(Vec(a1.x + dx * u1, a1.y + dy * u1)) }
    if u2 >= 0 && u2 <= 1 { result.append(Vec(a1.x + dx * u2, a1.y + dy * u2)) }
    return result.isEmpty ? nil : result
}

func intersectLineSegmentPolyline(_ a1: Vec, _ a2: Vec, _ points: [Vec]) -> [Vec]? {
    guard points.count > 1 else { return nil }
    var result: [Vec] = []
    for i in 0..<(points.count - 1) {
        if let p = intersectLineSegmentLineSegment(a1, a2, points[i], points[i + 1]) {
            result.append(p)
        }
    }
    return result.isEmpty ? nil : result
}

func intersectLineSegmentPolygon(_ a1: Vec, _ a2: Vec, _ points: [Vec]) -> [Vec]? {
    guard !points.isEmpty else { return nil }
    var result: [Vec] = []
    for i in 0..<points.count {
        if let p = intersectLineSegmentLineSegment(a1, a2, points[i], points[(i + 1) % points.count]) {
            result.append(p)
        }
    }
    return result.isEmpty ? nil : result
}

func intersectCircleCircle(_ c1: Vec, _ r1: Double, _ c2: Vec, _ r2: Double) -> [Vec] {
    var dx = c2.x - c1.x
    var dy = c2.y - c1.y
    let d = (dx * dx + dy * dy).squareRoot()
    let x = (d * d - r2 * r2 + r1 * r1) / (2 * d)
    let y = (r1 * r1 - x * x).squareRoot()
    dx /= d
    dy /= d
    return [
        Vec(c1.x + dx * x - dy * y, c1.y + dy * x + dx * y),
        Vec(c1.x + dx * x + dy * y, c1.y + dy * x - dx * y),
    ]
}

func intersectCirclePolygon(_ c: Vec, _ r: Double, _ points: [Vec]) -> [Vec]? {
    guard !points.isEmpty else { return nil }
    var result: [Vec] = []
    for i in 0..<points.count {
        if let ints = intersectLineSegmentCircle(points[i], points[(i + 1) % points.count], c, r) {
            result.append(contentsOf: ints)
        }
    }
    return result.isEmpty ? nil : result
}

func intersectCirclePolyline(_ c: Vec, _ r: Double, _ points: [Vec]) -> [Vec]? {
    guard points.count > 1 else { return nil }
    var result: [Vec] = []
    for i in 1..<points.count {
        if let ints = intersectLineSegmentCircle(points[i - 1], points[i], c, r) {
            result.append(contentsOf: ints)
        }
    }
    return result.isEmpty ? nil : result
}

private func ccw(_ a: Vec, _ b: Vec, _ c: Vec) -> Bool {
    (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
}

func linesIntersect(_ a: Vec, _ b: Vec, _ c: Vec, _ d: Vec) -> Bool {
    ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d)
}

func polygonsIntersect(_ a: [Vec], _ b: [Vec]) -> Bool {
    guard !a.isEmpty, !b.isEmpty else { return false }
    for i in 0..<a.count {
        let a0 = a[i], a1 = a[(i + 1) % a.count]
        for j in 0..<b.count {
            if linesIntersect(a0, a1, b[j], b[(j + 1) % b.count]) { return true }
        }
    }
    return false
}

func polygonIntersectsPolyline(_ polygon: [Vec], _ polyline: [Vec]) -> Bool {
    guard !polygon.isEmpty, polyline.count > 1 else { return false }
    for i in 0..<polygon.count {
        let a = polygon[i], b = polygon[(i + 1) % polygon.count]
        for j in 1..<polyline.count {
            if linesIntersect(a, b, polyline[j - 1], polyline[j]) { return true }
        }
    }
    return false
}
