import Foundation

let PI = Double.pi
let HALF_PI = Double.pi / 2
let PI2 = Double.pi * 2

func clamp(_ n: Double, _ min: Double, _ max: Double) -> Double {
    Swift.max(min, Swift.min(n, max))
}

func clamp(_ n: Double, _ min: Double) -> Double {
    Swift.max(min, n)
}

func modulate(_ value: Double, _ rangeA: (Double, Double), _ rangeB: (Double, Double), _ shouldClamp: Bool = false) -> Double {
    let (fromLow, fromHigh) = rangeA
    let (v0, v1) = rangeB
    let result = v0 + ((value - fromLow) / (fromHigh - fromLow)) * (v1 - v0)
    guard shouldClamp else { return result }
    return v0 < v1 ? Swift.max(Swift.min(result, v1), v0) : Swift.max(Swift.min(result, v0), v1)
}

func approximately(_ a: Double, _ b: Double, _ precision: Double = 0.000001) -> Bool {
    abs(a - b) <= precision
}

func isSafeFloat(_ n: Double) -> Bool {
    n.isFinite && abs(n) < 9007199254740991
}

func perimeterOfEllipse(_ rx: Double, _ ry: Double) -> Double {
    let h = pow(rx - ry, 2) / pow(rx + ry, 2)
    return PI * (rx + ry) * (1 + (3 * h) / (10 + (4 - 3 * h).squareRoot()))
}

/// A number between 0 and 2π.
func canonicalizeRotation(_ a: Double) -> Double {
    var a = a.truncatingRemainder(dividingBy: PI2)
    if a < 0 { a += PI2 } else if a == 0 { a = 0 }
    return a
}

func clockwiseAngleDist(_ a0: Double, _ a1: Double) -> Double {
    let a0 = canonicalizeRotation(a0)
    var a1 = canonicalizeRotation(a1)
    if a0 > a1 { a1 += PI2 }
    return a1 - a0
}

func counterClockwiseAngleDist(_ a0: Double, _ a1: Double) -> Double {
    PI2 - clockwiseAngleDist(a0, a1)
}

func shortAngleDist(_ a0: Double, _ a1: Double) -> Double {
    let da = (a1 - a0).truncatingRemainder(dividingBy: PI2)
    return (2 * da).truncatingRemainder(dividingBy: PI2) - da
}

func snapAngle(_ r: Double, _ segments: Int) -> Double {
    let seg = PI2 / Double(segments)
    var ang = (floor((canonicalizeRotation(r) + seg / 2) / seg) * seg).truncatingRemainder(dividingBy: PI2)
    if ang < PI { ang += PI2 }
    if ang > PI { ang -= PI2 }
    return ang
}

func getPointOnCircle(_ center: Vec, _ r: Double, _ a: Double) -> Vec {
    Vec.add(center, Vec.fromAngle(a, r))
}

/// Winding-number point-in-polygon test.
func pointInPolygon(_ point: Vec, _ points: [Vec]) -> Bool {
    var windingNumber = 0
    let n = points.count
    guard n > 0 else { return false }
    for i in 0..<n {
        let a = points[i]
        if a.x == point.x && a.y == point.y { return true }
        let b = points[(i + 1) % n]
        let cross = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
        if a.y <= point.y {
            if b.y > point.y && cross > 0 { windingNumber += 1 }
        } else if b.y <= point.y && cross < 0 {
            windingNumber -= 1
        }
    }
    return windingNumber != 0
}

/// The center of the circle passing through three points, or nil if they're collinear.
func centerOfCircleFromThreePoints(_ a: Vec, _ b: Vec, _ c: Vec) -> Vec? {
    let u: Double = -2 * (a.x * (b.y - c.y) - a.y * (b.x - c.x) + b.x * c.y - c.x * b.y)
    let sa: Double = a.x * a.x + a.y * a.y
    let sb: Double = b.x * b.x + b.y * b.y
    let sc: Double = c.x * c.x + c.y * c.y
    let x: Double = (sa * (c.y - b.y) + sb * (a.y - c.y) + sc * (b.y - a.y)) / u
    let y: Double = (sa * (b.x - c.x) + sb * (c.x - a.x) + sc * (a.x - b.x)) / u
    guard x.isFinite, y.isFinite else { return nil }
    return Vec(x, y)
}

/// The measure of an arc, negative when counter-clockwise.
func getArcMeasure(_ a: Double, _ b: Double, _ sweepFlag: Int, _ largeArcFlag: Int) -> Double {
    let diff = (b - a).truncatingRemainder(dividingBy: PI2)
    let m = (2 * diff).truncatingRemainder(dividingBy: PI2) - diff
    if largeArcFlag == 0 { return m }
    return (PI2 - abs(m)) * (sweepFlag != 0 ? 1 : -1)
}

/// Where along an arc a given angle falls, with 0 the start and 1 the end.
func getPointInArcT(_ mAB: Double, _ a: Double, _ b: Double, _ p: Double) -> Double {
    if abs(mAB) > PI {
        let mAP = shortAngleDist(a, p)
        let mPB = shortAngleDist(p, b)
        if abs(mAP) < abs(mPB) { return mAP / mAB }
        return (mAB - mPB) / mAB
    }
    let mAP = shortAngleDist(a, p)
    let t = mAP / mAB
    // If the arc runs from, say, -2.8 to 2.2, the measure to the center is negative while
    // measures near the ends are positive; snap to whichever end is closer.
    if (mAP < 0) != (mAB < 0) {
        return abs(t) > 0.5 ? 1 : 0
    }
    return t
}

/// Number of vertices to approximate an arc of the given length with.
func getVerticesCountForArcLength(_ length: Double, spacing: Double = 20) -> Int {
    Swift.max(8, Int(ceil(length / spacing)))
}

/// A seeded xorshift PRNG driven by the seed string's UTF-16 code units, using 32-bit integer
/// semantics throughout. Returns values in roughly [-1, 1].
func makeRng(_ seed: String) -> () -> Double {
    var x: Int32 = 0
    var y: Int32 = 0
    var z: Int32 = 0
    var w: Int32 = 0

    func next() -> Double {
        let t = x ^ (x << 11)
        x = y
        y = z
        z = w
        let shiftedW = Int32(bitPattern: UInt32(bitPattern: w) >> 19)
        let shiftedT = Int32(bitPattern: UInt32(bitPattern: t) >> 8)
        // `w ^= ((w >>> 19) ^ t ^ (t >>> 8)) >>> 0` - the result of `^` in JS is signed 32-bit,
        // so the division below can go negative, giving a range of roughly [-1, 1).
        w ^= shiftedW ^ t ^ shiftedT
        return (Double(w) / 0x1_0000_0000) * 2
    }

    let units = Array(seed.utf16)
    for k in 0..<(units.count + 64) {
        // JS `seed.charCodeAt(k) | 0` yields 0 past the end of the string (NaN | 0 === 0).
        let code: Int32 = k < units.count ? Int32(units[k]) : 0
        x ^= code
        _ = next()
    }
    return next
}

enum Easings {
    static let linear: (Double) -> Double = { $0 }
    static let easeOutQuad: (Double) -> Double = { $0 * (2 - $0) }
    static let easeOutCubic: (Double) -> Double = { t in
        let u = t - 1
        return u * u * u + 1
    }
    static let easeInOutCubic: (Double) -> Double = { t in
        t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
    }
    static let easeOutSine: (Double) -> Double = { sin(($0 * PI) / 2) }
}
