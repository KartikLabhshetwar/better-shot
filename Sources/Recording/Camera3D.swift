import CoreGraphics
import Foundation

/// Where a point on the card lands once the pose is applied, as row-vector homography coefficients.
nonisolated struct CardProjection: Equatable, Sendable {
    var m11: Double
    var m21: Double
    var m41: Double
    var m12: Double
    var m22: Double
    var m42: Double
    var m14: Double
    var m24: Double
    var m44: Double

    static let identity = CardProjection(m11: 1, m21: 0, m41: 0, m12: 0, m22: 1, m42: 0, m14: 0, m24: 0, m44: 1)

    func apply(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        let w = x * m14 + y * m24 + m44
        guard abs(w) > 0.000_001 else { return point }
        return CGPoint(x: (x * m11 + y * m21 + m41) / w, y: (x * m12 + y * m22 + m42) / w)
    }
}

/// Tips the composed card in space the way Cap's 3D camera does, using one pinhole projection so combined tilts stay square.
nonisolated struct Camera3D: Equatable, Sendable {
    static let maximumTilt: Double = 45
    static let maximumRoll: Double = 45
    static let neutral = Camera3D()

    var tiltX: Double = 0
    var tiltY: Double = 0
    var roll: Double = 0
    var perspective: Double = 0.4

    var isNeutral: Bool { tiltX == 0 && tiltY == 0 && roll == 0 }

    /// Close enough to bend the card hard, still far enough that no corner can cross behind the lens.
    private var distance: Double { 1.6 + (1 - min(max(perspective, 0), 1)) * 18.4 }

    func projection(in rect: CGRect, flipped: Bool = false) -> CardProjection {
        let pitch = (flipped ? -tiltX : tiltX) * .pi / 180
        let yaw = tiltY * .pi / 180
        let spin = (flipped ? -roll : roll) * .pi / 180

        let rotation = Self.multiply(
            Self.rotationZ(spin),
            Self.multiply(Self.rotationX(pitch), Self.rotationY(yaw))
        )
        let r11 = rotation[0][0], r12 = rotation[0][1]
        let r21 = rotation[1][0], r22 = rotation[1][1]
        let r31 = rotation[2][0], r32 = rotation[2][1]

        let half = max(rect.width, rect.height) / 2
        guard half > 0 else { return .identity }
        let scale = 1 / Double(half)
        let cx = Double(rect.midX)
        let cy = Double(rect.midY)
        let d = distance
        let shear = (r31 * cx + r32 * cy) * scale

        return CardProjection(
            m11: d * r11 - cx * r31 * scale,
            m21: d * r12 - cx * r32 * scale,
            m41: cx * d + cx * shear - d * (r11 * cx + r12 * cy),
            m12: d * r21 - cy * r31 * scale,
            m22: d * r22 - cy * r32 * scale,
            m42: cy * d + cy * shear - d * (r21 * cx + r22 * cy),
            m14: -r31 * scale,
            m24: -r32 * scale,
            m44: d + shear
        )
    }

    /// Bottom-left, bottom-right, top-right, top-left of the posed card, in the same orientation the rect was given in.
    func corners(in rect: CGRect, flipped: Bool = false) -> [CGPoint] {
        let projection = projection(in: rect, flipped: flipped)
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map(projection.apply)
    }

    private static func rotationX(_ angle: Double) -> [[Double]] {
        [[1, 0, 0], [0, cos(angle), -sin(angle)], [0, sin(angle), cos(angle)]]
    }

    private static func rotationY(_ angle: Double) -> [[Double]] {
        [[cos(angle), 0, sin(angle)], [0, 1, 0], [-sin(angle), 0, cos(angle)]]
    }

    private static func rotationZ(_ angle: Double) -> [[Double]] {
        [[cos(angle), -sin(angle), 0], [sin(angle), cos(angle), 0], [0, 0, 1]]
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { row in
            (0..<3).map { column in
                (0..<3).reduce(0.0) { $0 + a[row][$1] * b[$1][column] }
            }
        }
    }
}
