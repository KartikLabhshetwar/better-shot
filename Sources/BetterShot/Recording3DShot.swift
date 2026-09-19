import Foundation
import QuartzCore
import simd

/// An authored view of the content plane. Angles are degrees; pan is a canvas fraction.
/// Scale is independent of perspective so changing the lens does not resize a flat shot.
nonisolated struct Recording3DPose: Codable, Equatable, Sendable {
    var tiltX: Double = 0
    var tiltY: Double = 0
    var roll: Double = 0
    var scale: Double = 1
    var panX: Double = 0
    var panY: Double = 0
    var perspective: Double = 45
    // Optional to retain the exact appearance of projects authored with the original plane controls.
    var camera: Recording3DCamera?

    static let identity = Self()

    var sanitized: Self {
        func bound(_ x: Double, _ range: ClosedRange<Double>, _ fallback: Double = 0) -> Double {
            x.isFinite ? min(max(x, range.lowerBound), range.upperBound) : fallback
        }
        return Self(tiltX: bound(tiltX, -65...65), tiltY: bound(tiltY, -65...65),
                    roll: bound(roll, -45...45), scale: bound(scale, 0.3...2.5, 1),
                    panX: bound(panX, -0.5...0.5), panY: bound(panY, -0.5...0.5),
                    perspective: bound(perspective, 20...70, 45), camera: camera?.sanitized)
    }

    func interpolated(to end: Self, progress: Double) -> Self {
        let t = min(max(progress, 0), 1)
        if t == 0 { return self }
        if t == 1 { return end }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Self(tiltX: mix(tiltX, end.tiltX), tiltY: mix(tiltY, end.tiltY),
                    roll: mix(roll, end.roll), scale: mix(scale, end.scale),
                    panX: mix(panX, end.panX), panY: mix(panY, end.panY),
                    perspective: mix(perspective, end.perspective),
                    camera: Recording3DCamera.interpolate(camera, end.camera, t: t))
    }

    /// Perspective projection of a rotated plane, centered in top-left canvas coordinates.
    /// Both SwiftUI and Core Image consume this matrix; there is no preview-only geometry.
    func projection(in size: CGSize) -> CATransform3D {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CATransform3DIdentity
        }
        let p = sanitized
        let x = p.tiltX * .pi / 180, y = p.tiltY * .pi / 180, z = p.roll * .pi / 180
        // Rz * Ry * Rx, evaluated only for the plane's two basis vectors.
        let r00 = cos(z) * cos(y)
        let r01 = cos(z) * sin(y) * sin(x) - sin(z) * cos(x)
        let r10 = sin(z) * cos(y)
        let r11 = sin(z) * sin(y) * sin(x) + cos(z) * cos(x)
        let r20 = -sin(y), r21 = cos(y) * sin(x)
        let cx = size.width / 2, cy = size.height / 2
        // The lens limits keep every corner in front of the near plane, even at maximum tilt.
        let distance = max(size.width, size.height) / (2 * tan(p.perspective * .pi / 360))
        let g = -r20 / distance, h = -r21 / distance
        let i = 1 - g * cx - h * cy
        let tx = cx + p.panX * size.width, ty = cy + p.panY * size.height
        var m = CATransform3DIdentity
        m.m11 = p.scale * r00 + tx * g
        m.m21 = p.scale * r01 + tx * h
        m.m41 = -p.scale * (r00 * cx + r01 * cy) + tx * i
        m.m12 = p.scale * r10 + ty * g
        m.m22 = p.scale * r11 + ty * h
        m.m42 = -p.scale * (r10 * cx + r11 * cy) + ty * i
        m.m14 = g; m.m24 = h; m.m44 = i
        guard let camera = p.camera else { return m }
        let c = camera.projection(in: size)
        let t = camera.amount
        // Both homographies have unit depth at the canvas center. Blending is
        // continuous for optional flat transitions and preserves positive depth.
        m.m11 += (c.m11 - m.m11) * t; m.m21 += (c.m21 - m.m21) * t
        m.m41 += (c.m41 - m.m41) * t; m.m12 += (c.m12 - m.m12) * t
        m.m22 += (c.m22 - m.m22) * t; m.m42 += (c.m42 - m.m42) * t
        m.m14 += (c.m14 - m.m14) * t; m.m24 += (c.m24 - m.m24) * t
        m.m44 += (c.m44 - m.m44) * t
        return m
    }

    func project(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let m = projection(in: size)
        let w = m.m14 * point.x + m.m24 * point.y + m.m44
        return CGPoint(x: (m.m11 * point.x + m.m21 * point.y + m.m41) / w,
                       y: (m.m12 * point.x + m.m22 * point.y + m.m42) / w)
    }
}

/// Native pinhole camera: orbit and content-plane rotation are independent.
/// Distances use a plane whose longest edge is two world units; FOV is vertical.
nonisolated struct Recording3DCamera: Codable, Equatable, Sendable {
    var tiltX: Double = 0
    var tiltY: Double = 0
    var roll: Double = 0
    var rotateX: Double = 0
    var rotateY: Double = 0
    var distance: Double = 2
    var fieldOfView: Double = 45
    var panX: Double = 0
    var panY: Double = 0
    var amount: Double = 1

    var sanitized: Self {
        var result = self
        for (key, range, fallback) in Self.controls {
            let value = result[keyPath: key]
            result[keyPath: key] = value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        result.amount = amount.isFinite ? min(max(amount, 0), 1) : 1
        return result
    }

    static let controls: [(WritableKeyPath<Self, Double> & Sendable, ClosedRange<Double>, Double)] = [
        (\.tiltX, -70...70, 0), (\.tiltY, -60...60, 0), (\.roll, -180...180, 0),
        (\.rotateX, -90...90, 0), (\.rotateY, -50...50, 0), (\.distance, 0.5...10, 2),
        (\.fieldOfView, 10...100, 45), (\.panX, -3...3, 0), (\.panY, -3...3, 0)
    ]

    static func interpolate(_ a: Self?, _ b: Self?, t: Double) -> Self? {
        switch (a, b) {
        case (.none, .none): return nil
        case (.some(var a), .none): a.amount *= 1 - t; return a
        case (.none, .some(var b)): b.amount *= t; return b
        case (.some(let a), .some(let b)):
            var result = a
            for (key, _, _) in controls { result[keyPath: key] += (b[keyPath: key] - a[keyPath: key]) * t }
            result.amount += (b.amount - a.amount) * t
            return result
        }
    }

    func projection(in size: CGSize) -> CATransform3D {
        let p = sanitized
        func rotation(_ degrees: Double, _ axis: SIMD3<Double>) -> simd_quatd {
            simd_quatd(angle: degrees * .pi / 180, axis: axis)
        }
        let x = SIMD3<Double>(1, 0, 0), y = SIMD3<Double>(0, 1, 0), z = SIMD3<Double>(0, 0, 1)
        let orientation = rotation(p.tiltY, y) * rotation(p.tiltX, x) * rotation(p.roll, z)
            * rotation(p.rotateY, y) * rotation(p.rotateX, x)
        let u = orientation.act(x), v = orientation.act(y)
        let w = Double(size.width), h = Double(size.height), longest = max(w, h)
        // Pull back only if a custom pose would cross the near plane. Authored
        // presets stay untouched; arbitrary slider combinations remain finite.
        let distance = max(p.distance, abs(u.z) * w / longest + abs(v.z) * h / longest + 0.05)
        let focal = h / (2 * tan(p.fieldOfView * .pi / 360))
        func homogeneous(_ px: Double, _ py: Double) -> SIMD3<Double> {
            let world = u * ((px - w / 2) * 2 / longest) + v * ((h / 2 - py) * 2 / longest)
            let depth = (distance - world.z) / distance
            return SIMD3(w / 2 * depth + focal * (world.x + p.panX) / distance,
                         h / 2 * depth - focal * (world.y + p.panY) / distance, depth)
        }
        let origin = homogeneous(0, 0), dx = homogeneous(w, 0) - origin, dy = homogeneous(0, h) - origin
        var m = CATransform3DIdentity
        m.m11 = dx.x / w; m.m12 = dx.y / w; m.m14 = dx.z / w
        m.m21 = dy.x / h; m.m22 = dy.y / h; m.m24 = dy.z / h
        m.m41 = origin.x; m.m42 = origin.y; m.m44 = origin.z
        return m
    }
}

nonisolated enum Recording3DEasing: String, Codable, CaseIterable, Sendable {
    case smooth = "Smooth", linear = "Linear", easeIn = "Ease In", easeOut = "Ease Out"
    func value(at t: Double) -> Double {
        switch self {
        case .smooth: t * t * (3 - 2 * t)
        case .linear: t
        case .easeIn: t * t
        case .easeOut: 1 - (1 - t) * (1 - t)
        }
    }
}

nonisolated struct Recording3DShot: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var startPose = Recording3DPose.identity
    var endPose = Recording3DPose.identity
    var easing = Recording3DEasing.smooth
    var transition: Double = 0.25
    var isEnabled = true
    static let minimumDuration = 0.2

    var title: String {
        Recording3DPreset.allCases.first { $0.poses.0 == startPose && $0.poses.1 == endPose }?.rawValue
            ?? (startPose == endPose ? "Custom angle" : "Custom move")
    }

    func pose(at time: Double) -> Recording3DPose {
        guard isEnabled, time >= start, time < end, end > start else { return .identity }
        let progress = easing.value(at: min(max((time - start) / (end - start), 0), 1))
        let pose = startPose.interpolated(to: endPose, progress: progress)
        let ramp = min(max(transition, 0), (end - start) / 2)
        guard ramp > 0 else { return pose }
        let edge = min(1, min(time - start, end - time) / ramp)
        return Recording3DPose.identity.interpolated(to: pose, progress: edge * edge * (3 - 2 * edge))
    }

    mutating func apply(_ preset: Recording3DPreset) {
        (startPose, endPose) = preset.poses
        easing = .linear
        transition = 0
    }
}

/// Native camera implementation of the reference shot catalog. See docs/export-performance.md.
nonisolated enum Recording3DPreset: String, CaseIterable, Sendable {
    case spotlight = "Spotlight", perspective = "Perspective", center = "Center"
    case lowAngle = "Low angle", closeUp = "Close up"
    case glide = "Glide across", drift = "Drift down", rise = "Rising sweep"
    case pullBack = "Pull back", topDown = "Top down", tiltAway = "Tilt away"
    case unfold = "Unfold", slide = "Slide by"

    var isMove: Bool {
        switch self {
        case .spotlight, .perspective, .center, .lowAngle, .closeUp: false
        default: true
        }
    }
    var poses: (Recording3DPose, Recording3DPose) {
        var a = Recording3DCamera(), b = Recording3DCamera()
        switch self {
        case .spotlight:
            a = .init(distance: 1.35, panX: 0.39, panY: -0.4)
            b = a; b.distance = 1.22; b.panY = -0.34
        case .perspective:
            a = .init(tiltX: -28, tiltY: 26, roll: 5, distance: 1.59, panX: 0.37, panY: -0.15)
            b = a; b.tiltY = 18; b.distance = 1.53
        case .center:
            a = .init(distance: 2); b = a; b.distance = 2.25
        case .lowAngle:
            a = .init(tiltX: -50, tiltY: 1, distance: 1.5)
            b = a; b.tiltX = -44; b.panY = -0.12
        case .closeUp:
            a = .init(tiltX: 26, tiltY: -22, roll: 1, distance: 0.8, panX: -0.3, panY: -0.4)
            b = a; b.tiltY = -27; b.panX = -0.36
        case .glide:
            a = .init(tiltX: -46.65, tiltY: 42.49, rotateX: -1, rotateY: -20,
                      distance: 1.785, fieldOfView: 24, panX: 0.673, panY: -0.133)
            b = a; b.panX = 0.054; b.panY = -0.31
        case .drift:
            a = .init(distance: 0.8, panX: 0.536, panY: -0.452)
            b = a; b.panX = 0.544; b.panY = 0.5
        case .rise:
            a = .init(tiltX: -57.83, tiltY: -8.7, rotateY: -16,
                      distance: 1.51, fieldOfView: 29, panX: -0.634, panY: -0.082)
            b = a; b.tiltX = -46.65; b.tiltY = -7.94; b.fieldOfView = 25; b.panX = -0.613; b.panY = -0.268
        case .pullBack:
            a = .init(rotateX: -14, distance: 0.715); b = a; b.distance = 2.1
        case .topDown:
            a = .init(tiltX: 24.8, tiltY: 17.04, rotateX: -40, rotateY: 18,
                      distance: 0.5, fieldOfView: 60, panX: -0.065, panY: -0.195)
            b = a; b.tiltX = 34.19; b.tiltY = 15.28; b.rotateY = 9; b.panX = -0.217; b.panY = -0.476
        case .tiltAway:
            a = .init(rotateX: -5, distance: 0.5); b = a; b.rotateX = -21; b.distance = 0.6
        case .unfold:
            a = .init(rotateX: -42.96, distance: 2.05, fieldOfView: 31)
            b = a; b.rotateX = -12.01; b.distance = 2; b.panY = -0.179
        case .slide:
            a = .init(tiltX: -30.29, tiltY: 60, rotateX: -39, rotateY: -24,
                      distance: 1.99, fieldOfView: 13, panX: 0.238, panY: 0.135)
            b = a; b.panX = -0.204; b.panY = 0.039
        }
        return (.init(camera: a), .init(camera: b))
    }
}

nonisolated enum Recording3DScene: String, CaseIterable {
    case showcase = "Showcase", tour = "Product tour", punch = "Punch in"
    var weights: [Double] { self == .showcase ? [0.27, 0.25, 0.48] : [0.3, 0.3, 0.4] }
    var presets: [Recording3DPreset] {
        switch self {
        case .showcase: [.closeUp, .topDown, .pullBack]
        case .tour: [.unfold, .perspective, .center]
        case .punch: [.spotlight, .closeUp, .pullBack]
        }
    }
}

/// Sorted once per edit, binary searched per frame. Times belong to the edited movie,
/// like mask ranges; clip edits never destructively rewrite authored shots.
nonisolated struct Recording3DTimeline: Sendable {
    let shots: [Recording3DShot]
    static let empty = Self(shots: [], duration: 0)

    init(shots: [Recording3DShot], duration: Double) {
        guard duration.isFinite, duration > 0 else { self.shots = []; return }
        var normalized: [Recording3DShot] = []
        var ids = Set<UUID>()
        for var shot in shots.filter({ $0.start.isFinite && $0.end.isFinite }).sorted(by: { $0.start < $1.start }) {
            guard shot.start.isFinite, shot.end.isFinite, ids.insert(shot.id).inserted else { continue }
            shot.start = max(0, max(shot.start, normalized.last?.end ?? 0))
            shot.end = min(duration, shot.end)
            guard shot.end - shot.start >= Recording3DShot.minimumDuration - 0.000_001 else { continue }
            shot.startPose = shot.startPose.sanitized
            shot.endPose = shot.endPose.sanitized
            shot.transition = shot.transition.isFinite ? min(max(shot.transition, 0), 2) : 0.25
            normalized.append(shot)
        }
        self.shots = normalized
    }

    func pose(at time: Double) -> Recording3DPose {
        guard time.isFinite else { return .identity }
        var low = 0, high = shots.count
        while low < high {
            let mid = (low + high) / 2
            if shots[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? shots[low - 1].pose(at: time) : .identity
    }

    static func scene(_ presets: [Recording3DPreset], in range: ClosedRange<Double>,
                      weights: [Double]? = nil, showcaseFinish: Bool = false) -> [Recording3DShot] {
        guard !presets.isEmpty, range.lowerBound.isFinite, range.upperBound.isFinite else { return [] }
        let weights = weights ?? Array(repeating: 1, count: presets.count)
        guard weights.count == presets.count, weights.allSatisfy({ $0.isFinite && $0 > 0 }) else { return [] }
        let sum = weights.reduce(0, +), duration = range.upperBound - range.lowerBound
        guard sum.isFinite, duration.isFinite,
              weights.allSatisfy({ duration * $0 / sum >= Recording3DShot.minimumDuration - 0.000_001 }) else { return [] }
        var start = range.lowerBound
        return presets.enumerated().map { index, preset in
            let end = index == presets.count - 1 ? range.upperBound : start + duration * weights[index] / sum
            var shot = Recording3DShot(start: start, end: end)
            shot.apply(preset)
            if showcaseFinish && index == 2 { shot.endPose.camera?.distance = 1.6 }
            start = end
            return shot
        }
    }
}
