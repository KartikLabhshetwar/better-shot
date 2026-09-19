import Foundation
import QuartzCore

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

    static let identity = Self()

    var sanitized: Self {
        func bound(_ x: Double, _ range: ClosedRange<Double>, _ fallback: Double = 0) -> Double {
            x.isFinite ? min(max(x, range.lowerBound), range.upperBound) : fallback
        }
        return Self(tiltX: bound(tiltX, -65...65), tiltY: bound(tiltY, -65...65),
                    roll: bound(roll, -45...45), scale: bound(scale, 0.3...2.5, 1),
                    panX: bound(panX, -0.5...0.5), panY: bound(panY, -0.5...0.5),
                    perspective: bound(perspective, 20...70, 45))
    }

    func interpolated(to end: Self, progress: Double) -> Self {
        let t = min(max(progress, 0), 1)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Self(tiltX: mix(tiltX, end.tiltX), tiltY: mix(tiltY, end.tiltY),
                    roll: mix(roll, end.roll), scale: mix(scale, end.scale),
                    panX: mix(panX, end.panX), panY: mix(panY, end.panY),
                    perspective: mix(perspective, end.perspective))
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
        return m
    }

    func project(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let m = projection(in: size)
        let w = m.m14 * point.x + m.m24 * point.y + m.m44
        return CGPoint(x: (m.m11 * point.x + m.m21 * point.y + m.m41) / w,
                       y: (m.m12 * point.x + m.m22 * point.y + m.m42) / w)
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
    }
}

/// Original native presets; no Cap source, shader, or artwork is included.
nonisolated enum Recording3DPreset: String, CaseIterable, Sendable {
    case spotlight = "Spotlight", perspective = "Perspective", center = "Center"
    case lowAngle = "Low angle", closeUp = "Close up"
    case glide = "Glide across", drift = "Drift down", rise = "Rising sweep"
    case pullBack = "Pull back", topDown = "Top down", tiltAway = "Tilt away"
    case unfold = "Unfold", slide = "Slide by"

    var isMove: Bool { Self.allCases.firstIndex(of: self)! >= 5 }
    var poses: (Recording3DPose, Recording3DPose) {
        let a: Recording3DPose, b: Recording3DPose
        switch self {
        case .spotlight: a = .init(tiltX: 12, tiltY: -18, roll: -4, scale: 0.85)
            b = a
        case .perspective: a = .init(tiltX: 15, tiltY: 28, scale: 0.8)
            b = a
        case .center: a = .init(scale: 0.82); b = a
        case .lowAngle: a = .init(tiltX: 40, scale: 0.85, panY: 0.05); b = a
        case .closeUp: a = .init(tiltX: 18, tiltY: -10, scale: 1.35, panY: 0.12); b = a
        case .glide: a = .init(tiltX: 12, tiltY: -24, scale: 0.8, panX: -0.08)
            b = .init(tiltX: 12, tiltY: 24, scale: 0.8, panX: 0.08)
        case .drift: a = .init(tiltX: -20, scale: 0.85, panY: -0.1)
            b = .init(tiltX: 20, scale: 0.85, panY: 0.1)
        case .rise: a = .init(tiltX: 35, tiltY: -12, scale: 0.75, panY: 0.12)
            b = .init(tiltX: 5, tiltY: 12, scale: 0.95, panY: -0.04)
        case .pullBack: a = .init(tiltX: 8, tiltY: -8, scale: 1.3)
            b = .init(tiltX: 20, tiltY: 18, scale: 0.7)
        case .topDown: a = .init(tiltX: -45, scale: 0.85, panY: -0.05)
            b = .init(tiltX: -25, scale: 0.9, panY: 0.05)
        case .tiltAway: a = .init(scale: 0.95)
            b = .init(tiltX: 35, tiltY: 30, scale: 0.7)
        case .unfold: a = .init(tiltX: 15, tiltY: -55, scale: 0.75)
            b = .init(scale: 0.95)
        case .slide: a = .init(tiltY: -20, scale: 1.05, panX: -0.15)
            b = .init(tiltY: 20, scale: 1.05, panX: 0.15)
        }
        return (a, b)
    }
}

nonisolated enum Recording3DScene: String, CaseIterable {
    case showcase = "Showcase", tour = "Product tour", punch = "Punch in"
    var presets: [Recording3DPreset] {
        switch self {
        case .showcase: [.glide, .unfold, .center]
        case .tour: [.topDown, .slide, .pullBack]
        case .punch: [.center, .closeUp, .perspective]
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

    static func scene(_ presets: [Recording3DPreset], in range: ClosedRange<Double>) -> [Recording3DShot] {
        guard !presets.isEmpty, range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound - range.lowerBound >= Double(presets.count) * Recording3DShot.minimumDuration else { return [] }
        let length = (range.upperBound - range.lowerBound) / Double(presets.count)
        return presets.enumerated().map { index, preset in
            var shot = Recording3DShot(start: range.lowerBound + Double(index) * length,
                                       end: range.lowerBound + Double(index + 1) * length)
            shot.apply(preset)
            return shot
        }
    }
}
