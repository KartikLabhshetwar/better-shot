//
//  RecordingViewportTimeline.swift
//  BetterShot
//
//  Deterministic virtual-camera planning for screen recordings. Zoom cues
//  are editable project data; this file resolves those cues against the
//  separately recorded pointer capture, constrains the viewport to the
//  source, and integrates one damped spring at a fixed rate along the
//  *edited* (clip) timeline, so cuts never interrupt a zoom and per-clip
//  speed never changes how fast the camera itself moves. Preview and export
//  then interpolate the same immutable viewport timeline at editor time.
//

import CoreGraphics
import Foundation

nonisolated enum ZoomAnchorMode: String, Codable, CaseIterable, Sendable {
    /// Track the latest recorded pointer sample directly.
    case pointerAnchor
    /// Hold on stable regions of pointer activity instead of chasing every
    /// recorded sample. This remains available as an explicit editing choice.
    case smartAnchor
    /// Frame an explicit normalized point selected by the user.
    case pinnedAnchor

    /// Unknown and legacy experimental modes preserve the current project's
    /// pointer-follow behavior instead of silently changing saved edits.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ZoomAnchorMode(rawValue: raw) ?? .pointerAnchor
    }
}

nonisolated struct ZoomCue: Identifiable, Codable, Equatable, Sendable {
    /// Shortest cue the timeline will create or leave behind after a resize.
    static let minimumDuration: TimeInterval = 0.5

    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    /// Magnification while the cue is fully active (1 = no zoom).
    var zoom: Double
    var anchorMode: ZoomAnchorMode
    /// Normalized source coordinate, with a top-left origin.
    var pinnedPoint: CGPoint
    /// How strongly automatic targets retain their unzoomed screen position.
    var boundsBias: Double
    var isEnabled: Bool
    var isImplicit: Bool
    var skipsEasing: Bool

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        zoom: Double = 1.5,
        anchorMode: ZoomAnchorMode = .pointerAnchor,
        pinnedPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        boundsBias: Double = 0.25,
        isEnabled: Bool = true,
        isImplicit: Bool = false,
        skipsEasing: Bool = false
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.zoom = zoom
        self.anchorMode = anchorMode
        self.pinnedPoint = Self.normalized(pinnedPoint)
        self.boundsBias = Self.unit(boundsBias)
        self.isEnabled = isEnabled
        self.isImplicit = isImplicit
        self.skipsEasing = skipsEasing
    }

    var duration: TimeInterval {
        max(0, end - start)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case zoom
        case anchorMode
        case pinnedPoint
        case boundsBias
        case isEnabled
        case isImplicit
        case skipsEasing
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 2
        anchorMode = try container.decodeIfPresent(ZoomAnchorMode.self, forKey: .anchorMode) ?? .pointerAnchor
        let decodedPoint = try container.decodeIfPresent(CGPoint.self, forKey: .pinnedPoint)
            ?? CGPoint(x: 0.5, y: 0.5)
        pinnedPoint = Self.normalized(decodedPoint)
        boundsBias = Self.unit(try container.decodeIfPresent(Double.self, forKey: .boundsBias) ?? 0.25)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isImplicit = try container.decodeIfPresent(Bool.self, forKey: .isImplicit) ?? false
        skipsEasing = try container.decodeIfPresent(Bool.self, forKey: .skipsEasing) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(zoom, forKey: .zoom)
        try container.encode(anchorMode, forKey: .anchorMode)
        try container.encode(Self.normalized(pinnedPoint), forKey: .pinnedPoint)
        try container.encode(Self.unit(boundsBias), forKey: .boundsBias)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isImplicit, forKey: .isImplicit)
        try container.encode(skipsEasing, forKey: .skipsEasing)
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: unit(point.x), y: unit(point.y))
    }

    private static func unit<T: BinaryFloatingPoint>(_ value: T) -> T {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

/// One sampled state of the virtual camera.
nonisolated struct ViewportFrame: Sendable, Equatable {
    var magnification: Double
    /// Normalized (0...1, top-left origin) content point at the viewport center.
    var anchor: CGPoint

    static let identity = ViewportFrame(magnification: 1, anchor: CGPoint(x: 0.5, y: 0.5))
}

// MARK: - Auto-generation from recorded input

nonisolated enum ZoomCueSynthesizer {
    private static let preRoll: TimeInterval = 0.3
    private static let postRoll: TimeInterval = 2.5
    private static let joinTolerance: TimeInterval = 2.5
    private static let tailExclusion: TimeInterval = 1.0
    private static let trailingGuard: TimeInterval = 0.8
    private static let earliestStart: TimeInterval = 0.001
    private static let defaultMagnification = 1.5

    /// Builds editable Pointer cues around press events. A sorted one-pass merge
    /// is transitive, so cues connected by the allowed gap naturally become
    /// one continuous zoom.
    static func cues(from capture: PointerCaptureFile, duration: TimeInterval) -> [ZoomCue] {
        guard duration.isFinite, duration > 0 else { return [] }

        let latestEligiblePress = duration - tailExclusion
        let candidates = capture.presses
            .filter {
                $0.phase == .down
                    && $0.time.isFinite
                    && $0.time < latestEligiblePress
                    && (0...1).contains($0.x)
                    && (0...1).contains($0.y)
            }
            .sorted { $0.time < $1.time }
            .compactMap { press -> ZoomCue? in
                let start = max(press.time - preRoll, earliestStart)
                let end = min(press.time + postRoll, duration - trailingGuard)
                guard end > start else { return nil }
                return ZoomCue(
                    start: start,
                    end: end,
                    zoom: defaultMagnification,
                    anchorMode: .pointerAnchor,
                    pinnedPoint: CGPoint(x: press.x, y: press.y),
                    boundsBias: 0.25
                )
            }

        var merged: [ZoomCue] = []
        merged.reserveCapacity(candidates.count)
        for candidate in candidates {
            if var previous = merged.last, candidate.start <= previous.end + joinTolerance {
                previous.end = max(previous.end, candidate.end)
                merged[merged.count - 1] = previous
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }
}

// MARK: - Precomputed viewport timeline

nonisolated struct ViewportTimeline: Sendable {
    /// Fixed integration cadence. Playback display cadence never advances the
    /// springs; it only interpolates this immutable source-time timeline.
    static let stepRate: Double = 120

    private static let motionProfile = SpringConstant(tension: 200, friction: 40, inertia: 2.25)
    /// Longest comfortable pan, measured in visible viewport widths. When the
    /// remaining travel is longer, the pursuit zoom widens just enough to keep
    /// the sweep under this and re-tightens on approach (after van Wijk–Nuij,
    /// "Smooth and efficient zooming and panning"). Landing framing and snap
    /// targets always use the cue's own magnification.
    private static let travelComfortWidths = 1.4
    private static let settleGuardWindow: TimeInterval = 0.15
    private static let interiorMargin = 0.9

    private let frames: [ViewportFrame]
    private let duration: TimeInterval

    static let identity = ViewportTimeline(frames: [.identity], duration: 0)

    private init(frames: [ViewportFrame], duration: TimeInterval) {
        self.frames = frames
        self.duration = duration
    }

    /// - Parameter time: Editor (edited-timeline) time, not raw source time.
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

    /// Builds the camera's motion along the *edited* (clip) timeline rather
    /// than raw source time. Two things follow from that:
    ///
    /// - A cut never interrupts a zoom. The spring is only ever asked to
    ///   step across contiguous editor time, so when editor time crosses a
    ///   clip boundary it just keeps easing smoothly toward whatever target
    ///   applies after the cut, instead of jumping to wherever the
    ///   uncut-timeline curve would have been at that source instant.
    /// - Zoom motion is speed-independent. The spring's own step cadence is
    ///   fixed editor-time `dt`; only the *lookup* of which cue/pointer
    ///   target is active is resolved through the clip's speed (via
    ///   `clipTimeline.sourceTime(at:)`), so a sped-up clip plays its video
    ///   faster without the pan/zoom itself moving any faster.
    static func build(
        cues: [ZoomCue],
        capture: PointerCaptureFile,
        clipTimeline: RecordingClipTimeline
    ) -> ViewportTimeline {
        let duration = clipTimeline.duration
        guard duration.isFinite, duration > 0 else { return .identity }

        let pointerSamples = mergedPointerSamples(from: capture)
        let activitySamples = pointerSamples.filter {
            isRetainedSourceEvent($0.time, in: clipTimeline)
        }
        var activityTargetsByCueID: [UUID: [ActivityTarget]] = [:]
        for cue in cues where cue.anchorMode == .smartAnchor
            && activityTargetsByCueID[cue.id] == nil {
            activityTargetsByCueID[cue.id] = activityTargets(
                for: cue,
                samples: activitySamples
            )
        }
        let pressEvents = activitySamples.filter { $0.kind == .press }
        let frameCount = max(2, Int((duration * stepRate).rounded(.up)) + 1)
        let dt = 1.0 / stepRate

        // Magnification and translation share one physical response by
        // integrating the viewport's half-extent alongside its anchor on
        // each axis.
        var halfExtentSpring = DampedSpring(position: 0.5)
        var anchorXSpring = DampedSpring(position: 0.5)
        var anchorYSpring = DampedSpring(position: 0.5)
        var previousActive: ZoomCue?
        var latestPressIndex = -1

        var frames: [ViewportFrame] = []
        frames.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let editorTime = min(Double(frameIndex) * dt, duration)
            let time = clipTimeline.sourceTime(at: editorTime)
            while latestPressIndex + 1 < pressEvents.count,
                  pressEvents[latestPressIndex + 1].time <= time {
                latestPressIndex += 1
            }
            let active = activeCue(at: time, cues: cues)
            let targetMagnification = max(1, active?.zoom ?? 1)
            let rawTarget = active.map { cue in
                anchorPoint(
                    for: cue,
                    at: time,
                    samples: pointerSamples,
                    activityTargets: activityTargetsByCueID[cue.id] ?? []
                )
            } ?? CGPoint(x: 0.5, y: 0.5)
            let targetAnchor = boundedAnchor(
                rawTarget,
                magnification: targetMagnification,
                anchorMode: active?.anchorMode ?? .pinnedAnchor,
                boundsBias: active?.boundsBias ?? 0
            )
            let targetHalfExtent = 1 / (2 * targetMagnification)
            // Comfort widening only reshapes the spring's pursuit target:
            // a long remaining travel caps the chased magnification so the
            // sweep stays under travelComfortWidths viewport widths, and the
            // cap releases continuously as the anchor closes in.
            let remainingTravel = hypot(
                targetAnchor.x - anchorXSpring.position,
                targetAnchor.y - anchorYSpring.position
            )
            let pursuitMagnification = remainingTravel > 0.000_1
                ? min(targetMagnification, max(1, travelComfortWidths / remainingTravel))
                : targetMagnification
            let pursuitHalfExtent = 1 / (2 * pursuitMagnification)

            let activeChanged = active?.id != previousActive?.id
            let shouldSnap = activeChanged
                && (active?.skipsEasing == true
                    || previousActive?.skipsEasing == true)

            if shouldSnap {
                halfExtentSpring.snap(to: targetHalfExtent)
                anchorXSpring.snap(to: targetAnchor.x)
                anchorYSpring.snap(to: targetAnchor.y)
            } else if frameIndex > 0 {
                halfExtentSpring.step(toward: pursuitHalfExtent, using: motionProfile, dt: dt)
                anchorXSpring.step(toward: targetAnchor.x, using: motionProfile, dt: dt)
                anchorYSpring.step(toward: targetAnchor.y, using: motionProfile, dt: dt)
            }

            let safeHalfExtent = min(max(halfExtentSpring.position, 0.000_001), 0.5)
            let magnification = max(1, 1 / (2 * safeHalfExtent))
            var anchor = clampToFrame(
                CGPoint(x: anchorXSpring.position, y: anchorYSpring.position),
                magnification: magnification
            )

            // Pointer tracking normally gives the spring enough time to
            // arrive. This final guard handles very fast/far successive
            // presses: during the 150 ms press feedback, the pressed source
            // point is never allowed to sit outside the rendered viewport.
            // Pinned framing remains authoritative and bypasses this pull.
            if let active,
               active.anchorMode != .pinnedAnchor,
               latestPressIndex >= 0 {
                let press = pressEvents[latestPressIndex]
                let elapsed = time - press.time
                if elapsed >= 0, elapsed <= settleGuardWindow {
                    anchor = settleWithinMargin(
                        press.point,
                        from: anchor,
                        magnification: magnification,
                        interiorMargin: interiorMargin
                    )
                    // Keep the spring and rendered state coherent so releasing
                    // the safety constraint cannot create a snap-back frame.
                    anchorXSpring.position = anchor.x
                    anchorYSpring.position = anchor.y
                }
            }
            frames.append(ViewportFrame(magnification: magnification, anchor: anchor))
            previousActive = active
        }

        return ViewportTimeline(frames: frames, duration: duration)
    }

    // MARK: Cue selection

    /// User-authored intent wins over generic behavior. Within the same class,
    /// the most recently started active cue wins deterministically.
    private static func activeCue(
        at time: TimeInterval,
        cues: [ZoomCue]
    ) -> ZoomCue? {
        var selected: ZoomCue?
        var selectedPrecedence = Int.min

        for cue in cues where cue.isEnabled
            && time >= cue.start
            && time <= cue.end {
            let precedence = cuePriority(cue)
            if selected == nil
                || precedence > selectedPrecedence
                || (precedence == selectedPrecedence && cue.start >= selected!.start) {
                selected = cue
                selectedPrecedence = precedence
            }
        }
        return selected
    }

    private static func cuePriority(_ cue: ZoomCue) -> Int {
        if cue.isImplicit { return 0 }
        switch cue.anchorMode {
        case .pointerAnchor: return 1
        case .smartAnchor: return 2
        case .pinnedAnchor: return 3
        }
    }

    // MARK: Target resolution

    private static func anchorPoint(
        for cue: ZoomCue,
        at time: TimeInterval,
        samples: [PointerSample],
        activityTargets: [ActivityTarget]
    ) -> CGPoint {
        switch cue.anchorMode {
        case .pinnedAnchor:
            return normalized(cue.pinnedPoint)
        case .pointerAnchor:
            return trackedPointerPosition(at: time, samples: samples) ?? normalized(cue.pinnedPoint)
        case .smartAnchor:
            return activityTarget(at: time, targets: activityTargets) ?? normalized(cue.pinnedPoint)
        }
    }

    /// Groups a cue's surviving input into viewport-sized activity regions.
    /// Each region has one immutable bounding-box center, so tiny pointer
    /// movement cannot make the camera continually revise its destination.
    private static func activityTargets(
        for cue: ZoomCue,
        samples: [PointerSample]
    ) -> [ActivityTarget] {
        var cueSamples = samples.filter { $0.time >= cue.start && $0.time <= cue.end }
        if cueSamples.isEmpty {
            if let preceding = samples.last(where: { $0.time < cue.start }) {
                cueSamples = [preceding]
            } else if let following = samples.first(where: { $0.time > cue.start }) {
                cueSamples = [following]
            }
        }
        guard let first = cueSamples.first else { return [] }

        let magnification = max(cue.zoom, 1)
        let horizontalLimit = 0.5 / magnification
        let verticalLimit = 0.7 / magnification
        var group = ActivityGroup(sample: first)
        var groups: [ActivityGroup] = []

        for sample in cueSamples.dropFirst() {
            if group.canInclude(
                sample,
                horizontalLimit: horizontalLimit,
                verticalLimit: verticalLimit
            ) {
                group.include(sample)
            } else {
                groups.append(group)
                group = ActivityGroup(sample: sample)
            }
        }
        groups.append(group)

        // When this cue contains clicks, movement-only groups are just transit
        // between interaction targets. Ignoring them prevents the camera from
        // following the travel path it was introduced to smooth out. A Smart
        // cue without clicks still uses its movement regions.
        let focusedGroups = groups.contains { $0.firstPressTime != nil }
            ? groups.filter { $0.firstPressTime != nil }
            : groups
        return focusedGroups.map { group in
            // When a region contains a click, begin the handoff during the
            // same 300 ms lead-in used by automatic zoom generation. This is
            // precomputed, so seeking and export remain deterministic.
            let activationTime = group.firstPressTime.map {
                max(cue.start, $0 - 0.3)
            } ?? group.firstTime
            return ActivityTarget(
                activationTime: activationTime,
                point: group.center
            )
        }
    }

    private static func activityTarget(
        at time: TimeInterval,
        targets: [ActivityTarget]
    ) -> CGPoint? {
        guard let first = targets.first else { return nil }
        // A manually extended Smart cue can begin long before its first click.
        // Hold its captured fallback point until the planned handoff instead
        // of revealing a future target early.
        guard time >= first.activationTime else { return nil }

        var low = 0
        var high = targets.count
        while low < high {
            let middle = (low + high) / 2
            if targets[middle].activationTime <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return targets[max(0, low - 1)].point
    }

    private static func trackedPointerPosition(
        at time: TimeInterval,
        samples: [PointerSample]
    ) -> CGPoint? {
        guard let first = samples.first else { return nil }
        guard time >= first.time else { return first.point }

        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return samples[max(0, low - 1)].point
    }

    /// Match the pointer timeline's half-open event-boundary contract so an
    /// outgoing clip-end click cannot become a Smart target in the next clip.
    private static func isRetainedSourceEvent(
        _ time: TimeInterval,
        in clipTimeline: RecordingClipTimeline
    ) -> Bool {
        clipTimeline.segments.contains {
            time >= $0.sourceStart && time < $0.sourceEnd
        }
    }

    private static func mergedPointerSamples(from capture: PointerCaptureFile) -> [PointerSample] {
        var merged: [(sample: PointerSample, sourceOrder: Int, originalIndex: Int)] = []
        merged.reserveCapacity(capture.travel.count + capture.presses.count)

        for (index, travel) in capture.travel.enumerated()
            where travel.time.isFinite
                && travel.x.isFinite
                && travel.y.isFinite
                && (0...1).contains(travel.x)
                && (0...1).contains(travel.y) {
            merged.append((
                PointerSample(
                    time: travel.time,
                    point: normalized(CGPoint(x: travel.x, y: travel.y)),
                    kind: .travel
                ),
                0,
                index
            ))
        }
        for (index, press) in capture.presses.enumerated()
            where press.time.isFinite
                && press.x.isFinite
                && press.y.isFinite
                && (0...1).contains(press.x)
                && (0...1).contains(press.y) {
            merged.append((
                PointerSample(
                    time: press.time,
                    point: normalized(CGPoint(x: press.x, y: press.y)),
                    kind: press.phase == .down ? .press : .release
                ),
                1,
                index
            ))
        }

        return merged.sorted { lhs, rhs in
            if lhs.sample.time != rhs.sample.time { return lhs.sample.time < rhs.sample.time }
            if lhs.sourceOrder != rhs.sourceOrder { return lhs.sourceOrder < rhs.sourceOrder }
            return lhs.originalIndex < rhs.originalIndex
        }.map(\.sample)
    }

    // MARK: Viewport constraints

    private static func boundedAnchor(
        _ point: CGPoint,
        magnification: Double,
        anchorMode: ZoomAnchorMode,
        boundsBias: Double
    ) -> CGPoint {
        let rawCenteredTarget = normalized(point)
        guard anchorMode != .pinnedAnchor else {
            return clampToFrame(rawCenteredTarget, magnification: magnification)
        }

        let halfExtent = 1 / (2 * max(magnification, 1))
        // This anchor keeps the subject at its original unzoomed screen
        // position: screen = 0.5 + magnification * (subject - viewportAnchor).
        let screenPositionPreservingTarget = CGPoint(
            x: halfExtent + rawCenteredTarget.x * (1 - 2 * halfExtent),
            y: halfExtent + rawCenteredTarget.y * (1 - 2 * halfExtent)
        )
        let bias = unit(boundsBias)
        let blended = CGPoint(
            x: rawCenteredTarget.x
                + (screenPositionPreservingTarget.x - rawCenteredTarget.x) * bias,
            y: rawCenteredTarget.y
                + (screenPositionPreservingTarget.y - rawCenteredTarget.y) * bias
        )
        return clampToFrame(blended, magnification: magnification)
    }

    /// Final safety invariant: the viewport never exposes space beyond source.
    private static func clampToFrame(_ point: CGPoint, magnification: Double) -> CGPoint {
        let halfExtent = 1 / (2 * max(magnification, 1))
        return CGPoint(
            x: min(max(point.x, halfExtent), 1 - halfExtent),
            y: min(max(point.y, halfExtent), 1 - halfExtent)
        )
    }

    /// Minimally moves a viewport anchor so `point` remains in a safe interior
    /// portion of the viewport. Near source edges, where an interior margin is
    /// geometrically impossible, it falls back to simple full-viewport
    /// containment while still respecting the source bounds.
    private static func settleWithinMargin(
        _ point: CGPoint,
        from anchor: CGPoint,
        magnification: Double,
        interiorMargin: Double
    ) -> CGPoint {
        let halfExtent = 1 / (2 * max(magnification, 1))
        let safeHalfExtent = halfExtent * unit(interiorMargin)

        func constrainedAxis(point: Double, anchor: Double) -> Double {
            let sourceMinimum = halfExtent
            let sourceMaximum = 1 - halfExtent
            let safeMinimum = max(sourceMinimum, point - safeHalfExtent)
            let safeMaximum = min(sourceMaximum, point + safeHalfExtent)
            if safeMinimum <= safeMaximum {
                return min(max(anchor, safeMinimum), safeMaximum)
            }

            let visibleMinimum = max(sourceMinimum, point - halfExtent)
            let visibleMaximum = min(sourceMaximum, point + halfExtent)
            guard visibleMinimum <= visibleMaximum else {
                return min(max(anchor, sourceMinimum), sourceMaximum)
            }
            return min(max(anchor, visibleMinimum), visibleMaximum)
        }

        return CGPoint(
            x: constrainedAxis(point: point.x, anchor: anchor.x),
            y: constrainedAxis(point: point.y, anchor: anchor.y)
        )
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: unit(point.x), y: unit(point.y))
    }

    private static func unit<T: BinaryFloatingPoint>(_ value: T) -> T {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Helpers

nonisolated private struct PointerSample: Sendable {
    var time: TimeInterval
    var point: CGPoint
    var kind: PointerSampleKind
}

nonisolated private enum PointerSampleKind: Sendable {
    case travel
    case press
    case release
}

nonisolated private struct ActivityTarget: Sendable {
    var activationTime: TimeInterval
    var point: CGPoint
}

nonisolated private struct ActivityGroup: Sendable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    var firstTime: TimeInterval
    var firstPressTime: TimeInterval?

    init(sample: PointerSample) {
        minX = sample.point.x
        maxX = sample.point.x
        minY = sample.point.y
        maxY = sample.point.y
        firstTime = sample.time
        if case .press = sample.kind {
            firstPressTime = sample.time
        } else {
            firstPressTime = nil
        }
    }

    var center: CGPoint {
        CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    func canInclude(
        _ sample: PointerSample,
        horizontalLimit: Double,
        verticalLimit: Double
    ) -> Bool {
        let candidateMinX = min(minX, sample.point.x)
        let candidateMaxX = max(maxX, sample.point.x)
        let candidateMinY = min(minY, sample.point.y)
        let candidateMaxY = max(maxY, sample.point.y)
        return candidateMaxX - candidateMinX <= horizontalLimit
            && candidateMaxY - candidateMinY <= verticalLimit
    }

    mutating func include(_ sample: PointerSample) {
        minX = min(minX, sample.point.x)
        maxX = max(maxX, sample.point.x)
        minY = min(minY, sample.point.y)
        maxY = max(maxY, sample.point.y)
        if firstPressTime == nil, case .press = sample.kind {
            firstPressTime = sample.time
        }
    }
}
