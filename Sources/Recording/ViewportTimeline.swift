import CoreGraphics
import Foundation

nonisolated struct SpringConstant: Sendable {
    var tension: Double
    var friction: Double
    var inertia: Double
}

nonisolated struct DampedSpring: Sendable {
    var position: Double
    var velocity: Double = 0

    mutating func snap(to value: Double) {
        position = value
        velocity = 0
    }

    mutating func step(toward target: Double, using constant: SpringConstant, dt: Double) {
        guard constant.inertia > 0 else {
            position = target
            velocity = 0
            return
        }
        let acceleration = (
            constant.tension * (target - position) - constant.friction * velocity
        ) / constant.inertia
        velocity += acceleration * dt
        position += velocity * dt
    }
}

nonisolated struct ViewportTimeline: Sendable {
    static let stepRate: Double = 120

    private static let motionProfile = SpringConstant(tension: 200, friction: 40, inertia: 2.25)
    private static let travelComfortWidth: Double = 1.4
    private static let settleGuardWindow: TimeInterval = 0.15
    private static let interiorMargin: Double = 0.9

    private let frames: [ViewportFrame]
    private let duration: TimeInterval

    static let identity = ViewportTimeline(frames: [.identity], duration: 0)

    private init(frames: [ViewportFrame], duration: TimeInterval) {
        self.frames = frames
        self.duration = duration
    }

    func frame(at time: TimeInterval) -> ViewportFrame {
        guard frames.count > 1, duration > 0 else { return frames.first ?? .identity }
        let position = min(max(time, 0), duration) * Self.stepRate
        let index = Int(position)
        guard index < frames.count - 1 else { return frames[frames.count - 1] }
        let fraction = position - Double(index)
        let a = frames[index]
        let b = frames[index + 1]
        return ViewportFrame(
            magnification: a.magnification + (b.magnification - a.magnification) * fraction,
            anchor: CGPoint(
                x: a.anchor.x + (b.anchor.x - a.anchor.x) * fraction,
                y: a.anchor.y + (b.anchor.y - a.anchor.y) * fraction
            )
        )
    }

    static func build(cues: [ZoomCue], capture: PointerCaptureFile, duration: TimeInterval) -> ViewportTimeline {
        guard duration.isFinite, duration > 0 else { return .identity }
        let activeCues = cues.filter(\.isEnabled)
        guard !activeCues.isEmpty else { return .identity }

        let pointerSamples = mergedPointerSamples(from: capture)
        let pressEvents = pointerSamples.filter { $0.kind == .press }
        let frameCount = max(2, Int((duration * stepRate).rounded(.up)) + 1)
        let dt = 1.0 / stepRate

        var halfExtentSpring = DampedSpring(position: 0.5)
        var anchorXSpring = DampedSpring(position: 0.5)
        var anchorYSpring = DampedSpring(position: 0.5)
        var latestPressIndex = -1

        var frames: [ViewportFrame] = []
        frames.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let time = min(Double(frameIndex) * dt, duration)
            while latestPressIndex + 1 < pressEvents.count, pressEvents[latestPressIndex + 1].time <= time {
                latestPressIndex += 1
            }

            let active = activeCue(at: time, cues: activeCues)
            let targetMagnification = max(1, active?.zoom ?? 1)
            let rawTarget = active.map { cue in
                anchorPoint(for: cue, at: time, samples: pointerSamples)
            } ?? CGPoint(x: 0.5, y: 0.5)
            let targetAnchor = boundedAnchor(
                rawTarget,
                magnification: targetMagnification,
                anchorMode: active?.anchorMode ?? .pinnedAnchor,
                boundsBias: active?.boundsBias ?? 0
            )

            let remainingTravel = hypot(
                targetAnchor.x - anchorXSpring.position,
                targetAnchor.y - anchorYSpring.position
            )
            let pursuitMagnification = remainingTravel > 0.0001
                ? min(targetMagnification, max(1, travelComfortWidth / remainingTravel))
                : targetMagnification
            let targetHalfExtent = 1 / (2 * pursuitMagnification)

            if frameIndex > 0 {
                halfExtentSpring.step(toward: targetHalfExtent, using: motionProfile, dt: dt)
                anchorXSpring.step(toward: targetAnchor.x, using: motionProfile, dt: dt)
                anchorYSpring.step(toward: targetAnchor.y, using: motionProfile, dt: dt)
            } else {
                halfExtentSpring.snap(to: targetHalfExtent)
                anchorXSpring.snap(to: targetAnchor.x)
                anchorYSpring.snap(to: targetAnchor.y)
            }

            let safeHalfExtent = min(max(halfExtentSpring.position, 0.000_001), 0.5)
            let magnification = max(1, 1 / (2 * safeHalfExtent))
            var anchor = clampToFrame(
                CGPoint(x: anchorXSpring.position, y: anchorYSpring.position),
                magnification: magnification
            )

            if let active, active.anchorMode != .pinnedAnchor, latestPressIndex >= 0 {
                let press = pressEvents[latestPressIndex]
                let elapsed = time - press.time
                if elapsed >= 0, elapsed <= settleGuardWindow {
                    anchor = settleWithinMargin(
                        press.point,
                        from: anchor,
                        magnification: magnification,
                        interiorMargin: interiorMargin
                    )
                    anchorXSpring.position = anchor.x
                    anchorYSpring.position = anchor.y
                }
            }

            frames.append(ViewportFrame(magnification: magnification, anchor: anchor))
        }

        return ViewportTimeline(frames: frames, duration: duration)
    }

    private static func activeCue(at time: TimeInterval, cues: [ZoomCue]) -> ZoomCue? {
        let candidates = cues.filter { $0.start <= time && time < $0.end }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { lhs, rhs in
            let lhsPriority = cuePriority(lhs.anchorMode)
            let rhsPriority = cuePriority(rhs.anchorMode)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.start < rhs.start
        }
    }

    private static func cuePriority(_ mode: ZoomAnchorMode) -> Int {
        switch mode {
        case .pointerAnchor: return 0
        case .pinnedAnchor: return 1
        }
    }

    private static func anchorPoint(for cue: ZoomCue, at time: TimeInterval, samples: [PointerSample]) -> CGPoint {
        switch cue.anchorMode {
        case .pinnedAnchor:
            return cue.pinnedPoint
        case .pointerAnchor:
            return trackedPointerPosition(at: time, samples: samples) ?? cue.pinnedPoint
        }
    }

    private static func trackedPointerPosition(at time: TimeInterval, samples: [PointerSample]) -> CGPoint? {
        guard !samples.isEmpty else { return nil }
        if time <= samples[0].time { return samples[0].point }
        if time >= samples[samples.count - 1].time { return samples[samples.count - 1].point }

        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if samples[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }

        let a = samples[low]
        guard low + 1 < samples.count else { return a.point }
        let b = samples[low + 1]
        let span = b.time - a.time
        guard span > 0 else { return a.point }
        let fraction = (time - a.time) / span
        return CGPoint(
            x: a.point.x + (b.point.x - a.point.x) * fraction,
            y: a.point.y + (b.point.y - a.point.y) * fraction
        )
    }

    private static func boundedAnchor(
        _ point: CGPoint,
        magnification: Double,
        anchorMode: ZoomAnchorMode,
        boundsBias: Double
    ) -> CGPoint {
        let clamped = clampToFrame(point, magnification: magnification)
        guard anchorMode == .pointerAnchor, boundsBias > 0 else { return clamped }
        let preserving = CGPoint(
            x: 0.5 + (point.x - 0.5) / max(magnification, 1),
            y: 0.5 + (point.y - 0.5) / max(magnification, 1)
        )
        let blended = CGPoint(
            x: clamped.x + (preserving.x - clamped.x) * boundsBias,
            y: clamped.y + (preserving.y - clamped.y) * boundsBias
        )
        return clampToFrame(blended, magnification: magnification)
    }

    private static func clampToFrame(_ point: CGPoint, magnification: Double) -> CGPoint {
        let halfExtent = 1 / (2 * max(magnification, 1))
        return CGPoint(
            x: min(max(point.x, halfExtent), 1 - halfExtent),
            y: min(max(point.y, halfExtent), 1 - halfExtent)
        )
    }

    private static func settleWithinMargin(
        _ point: CGPoint,
        from anchor: CGPoint,
        magnification: Double,
        interiorMargin: Double
    ) -> CGPoint {
        let halfExtent = 1 / (2 * max(magnification, 1)) * interiorMargin
        let minX = point.x - halfExtent
        let maxX = point.x + halfExtent
        let minY = point.y - halfExtent
        let maxY = point.y + halfExtent
        let x = min(max(anchor.x, minX), maxX)
        let y = min(max(anchor.y, minY), maxY)
        return clampToFrame(CGPoint(x: x, y: y), magnification: magnification)
    }

    private struct PointerSample: Sendable {
        enum Kind: Sendable {
            case travel
            case press
        }

        var time: TimeInterval
        var point: CGPoint
        var kind: Kind
    }

    private static func mergedPointerSamples(from capture: PointerCaptureFile) -> [PointerSample] {
        var indexed: [(sample: PointerSample, order: Int)] = []
        indexed.reserveCapacity(capture.travel.count + capture.presses.count)

        for (i, t) in capture.travel.enumerated()
            where t.time.isFinite && (0...1).contains(t.x) && (0...1).contains(t.y) {
            indexed.append((PointerSample(time: t.time, point: CGPoint(x: t.x, y: t.y), kind: .travel), i))
        }

        let offset = capture.travel.count
        for (i, p) in capture.presses.enumerated()
            where p.time.isFinite && (0...1).contains(p.x) && (0...1).contains(p.y) {
            indexed.append((PointerSample(time: p.time, point: CGPoint(x: p.x, y: p.y), kind: .press), offset + i))
        }

        return indexed
            .sorted {
                $0.sample.time != $1.sample.time ? $0.sample.time < $1.sample.time : $0.order < $1.order
            }
            .map(\.sample)
    }
}
