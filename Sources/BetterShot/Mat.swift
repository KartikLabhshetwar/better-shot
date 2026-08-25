import CoreGraphics
import Foundation

/// A 2d affine transform, `[a c e; b d f]`.
struct Mat: Equatable {
    var a: Double, b: Double, c: Double, d: Double, e: Double, f: Double

    init(_ a: Double = 1, _ b: Double = 0, _ c: Double = 0, _ d: Double = 1, _ e: Double = 0, _ f: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }

    static let identity = Mat()

    static func translate(_ x: Double, _ y: Double) -> Mat { Mat(1, 0, 0, 1, x, y) }

    static func rotate(_ r: Double) -> Mat {
        let cosr = cos(r), sinr = sin(r)
        return Mat(cosr, sinr, -sinr, cosr, 0, 0)
    }

    static func scale(_ x: Double, _ y: Double) -> Mat { Mat(x, 0, 0, y, 0, 0) }

    /// The transform for a shape at `(x, y)` rotated by `rotation` about its own origin.
    static func compose(x: Double, y: Double, rotation: Double) -> Mat {
        multiply(translate(x, y), rotate(rotation))
    }

    static func multiply(_ m1: Mat, _ m2: Mat) -> Mat {
        Mat(
            m1.a * m2.a + m1.c * m2.b,
            m1.b * m2.a + m1.d * m2.b,
            m1.a * m2.c + m1.c * m2.d,
            m1.b * m2.c + m1.d * m2.d,
            m1.a * m2.e + m1.c * m2.f + m1.e,
            m1.b * m2.e + m1.d * m2.f + m1.f
        )
    }

    var inverse: Mat {
        let denom = a * d - b * c
        return Mat(
            d / denom,
            b / -denom,
            c / -denom,
            a / denom,
            (d * e - c * f) / -denom,
            (b * e - a * f) / denom
        )
    }

    func applyToPoint(_ p: Vec) -> Vec {
        Vec(a * p.x + c * p.y + e, b * p.x + d * p.y + f, p.z)
    }

    func applyToPoints(_ points: [Vec]) -> [Vec] {
        points.map { applyToPoint($0) }
    }

    /// The point in this transform's local space corresponding to a point in the parent space.
    func applyInverseToPoint(_ p: Vec) -> Vec { inverse.applyToPoint(p) }

    struct Decomposed {
        var x: Double
        var y: Double
        var scaleX: Double
        var scaleY: Double
        var rotation: Double
    }

    var decomposed: Decomposed {
        // Assumes no skew, which holds for shape transforms (translate + rotate + scale).
        if a != 0 || b != 0 {
            let r = (a * a + b * b).squareRoot()
            return Decomposed(
                x: e, y: f,
                scaleX: r,
                scaleY: (a * d - b * c) / r,
                rotation: acos(a / r) * (b > 0 ? 1 : -1)
            )
        }
        if c != 0 || d != 0 {
            let s = (c * c + d * d).squareRoot()
            return Decomposed(
                x: e, y: f,
                scaleX: (a * d - b * c) / s,
                scaleY: s,
                rotation: HALF_PI + acos(c / s) * (d > 0 ? 1 : -1)
            )
        }
        return Decomposed(x: e, y: f, scaleX: 0, scaleY: 0, rotation: 0)
    }

    var rotation: Double { decomposed.rotation }

    var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
    }
}
