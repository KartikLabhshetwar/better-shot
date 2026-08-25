//
//  RecordingPointerTimeline.swift
//  BetterShot
//
//  Deterministic reconstruction of the pointer that was deliberately omitted
//  from the screen master. Raw pointer samples select an intentional target;
//  fixed-step, interaction-specific springs produce the displayed motion.
//  Source events are remapped through the clip edit before integration, so
//  preview and export interpolate the same immutable edited-time timeline.
//

import CoreGraphics
import Foundation

nonisolated struct PointerPressFrame: Sendable, Equatable {
    /// Exact recorded press coordinate. The smoothed cursor may still be
    /// settling when the click lands, but feedback must mark the real target.
    var location: CGPoint
    var progress: Double
}

nonisolated struct PointerFrame: Sendable, Equatable {
    /// Normalized recording coordinate, with a top-left origin.
    var location: CGPoint
    var artworkID: String?
    /// Interaction and visibility magnification, anchored at the pointer artwork's anchor point.
    var magnification: Double
    var tiltDegrees: Double
    var opacity: Double
    var blurRadius: Double
    var press: PointerPressFrame?
}

nonisolated struct PointerTimeline: Sendable {
    static let stepRate: Double = 120

    private static let anticipationWindow: TimeInterval = 0.5
    private static let interceptWindow: TimeInterval = 0.175
    private static let pressAnticipation: TimeInterval = 0.13
    private static let orphanPressHold: TimeInterval = 0.15
    private static let pulseDuration = PointerPressEffectStyle.duration
    private static let tiltSampleWindow: TimeInterval = 0.4
    private static let tiltGain = 0.03
    private static let tiltWeight = 0.5
    private static let revealLeadWindow: TimeInterval = 0.25

    private let frames: [PointerFrame]
    private let duration: TimeInterval
    private let artworkByID: [String: PointerArtwork]
    private let fallbackArtwork: PointerArtwork?

    static let empty = PointerTimeline(
        frames: [],
        duration: 0,
        artworkByID: [:],
        fallbackArtwork: nil
    )

    private init(
        frames: [PointerFrame],
        duration: TimeInterval,
        artworkByID: [String: PointerArtwork],
        fallbackArtwork: PointerArtwork?
    ) {
        self.frames = frames
        self.duration = duration
        self.artworkByID = artworkByID
        self.fallbackArtwork = fallbackArtwork
    }

    func frame(at time: TimeInterval) -> PointerFrame? {
        guard !frames.isEmpty else { return nil }
        guard frames.count > 1, duration > 0 else { return frames.first }

        let position = min(max(time, 0), duration) * Self.stepRate
        let index = Int(position)
        guard index < frames.count - 1 else { return frames[frames.count - 1] }

        let fraction = position - Double(index)
        let a = frames[index]
        let b = frames[index + 1]
        return PointerFrame(
            location: CGPoint(
                x: a.location.x + (b.location.x - a.location.x) * fraction,
                y: a.location.y + (b.location.y - a.location.y) * fraction
            ),
            artworkID: fraction < 0.5 ? a.artworkID : b.artworkID,
            magnification: a.magnification + (b.magnification - a.magnification) * fraction,
            tiltDegrees: a.tiltDegrees
                + (b.tiltDegrees - a.tiltDegrees) * fraction,
            opacity: a.opacity + (b.opacity - a.opacity) * fraction,
            blurRadius: a.blurRadius + (b.blurRadius - a.blurRadius) * fraction,
            press: fraction < 0.5 ? a.press : b.press
        )
    }

    /// Compatibility helper retained for existing camera and preview callers.
    func location(at time: TimeInterval) -> CGPoint? {
        frame(at: time)?.location
    }

    func artwork(id: String?) -> PointerArtwork? {
        guard let id else { return fallbackArtwork }
        return artworkByID[id] ?? fallbackArtwork
    }

    static func build(
        capture: PointerCaptureFile,
        duration: TimeInterval,
        recordingSizeInPoints: CGSize = CGSize(width: 1_000, height: 1_000),
        fallbackArtwork: PointerArtwork? = nil,
        hideAfterInactivity: TimeInterval? = nil,
        clipTimeline: RecordingClipTimeline? = nil
    ) -> PointerTimeline {
        guard duration.isFinite, duration > 0 else { return .empty }
        let timelineDuration = clipTimeline?.duration ?? duration
        guard timelineDuration.isFinite, timelineDuration > 0 else { return .empty }

        let safeSize = CGSize(
            width: recordingSizeInPoints.width > 0 ? recordingSizeInPoints.width : 1_000,
            height: recordingSizeInPoints.height > 0 ? recordingSizeInPoints.height : 1_000
        )
        let stream = PointerStreamSanitizer.sanitize(
            capture,
            options: PointerSanitizeOptions(
                recordingSizeInPoints: safeSize
            )
        )
        let sourceSamples = stream.samples.filter {
            $0.time.isFinite && $0.x.isFinite && $0.y.isFinite
        }
        let samples = timelineSamples(
            from: sourceSamples,
            clipTimeline: clipTimeline
        )
        guard let firstSample = samples.first else { return .empty }

        let pressSamples = samples.filter { $0.kind == .press }
        let travelSamples = samples.filter {
            $0.kind == .travel || $0.kind == .drag
        }
        let intervals = pressIntervals(
            from: samples,
            duration: timelineDuration
        )

        var artworkByID: [String: PointerArtwork] = [:]
        for artwork in stream.artwork where artworkByID[artwork.artworkID] == nil {
            artworkByID[artwork.artworkID] = artwork
        }

        let frameCount = max(2, Int((timelineDuration * stepRate).rounded(.up)) + 1)
        let dt = 1 / stepRate
        var xSpring = DampedSpring(position: firstSample.x)
        var ySpring = DampedSpring(position: firstSample.y)
        var magnificationSpring = DampedSpring(position: 1)
        var opacitySpring = DampedSpring(position: 1)
        var blurSpring = DampedSpring(position: 0)

        var sampleIndex = -1
        var travelIndex = -1
        var latestPressIndex = -1
        var pressIntervalIndex = 0
        var currentArtworkID = firstSample.artworkID
        var frames: [PointerFrame] = []
        frames.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let time = min(Double(frameIndex) * dt, timelineDuration)

            while sampleIndex + 1 < samples.count,
                  samples[sampleIndex + 1].time <= time {
                sampleIndex += 1
                let sample = samples[sampleIndex]
                currentArtworkID = sample.artworkID
            }

            while travelIndex + 1 < travelSamples.count,
                  travelSamples[travelIndex + 1].time <= time {
                travelIndex += 1
            }
            while latestPressIndex + 1 < pressSamples.count,
                  pressSamples[latestPressIndex + 1].time <= time {
                latestPressIndex += 1
            }
            while pressIntervalIndex < intervals.count,
                  intervals[pressIntervalIndex].end < time {
                pressIntervalIndex += 1
            }

            let latest = sampleIndex >= 0 ? samples[sampleIndex] : firstSample
            var target = latest.location
            var approachingPress = false
            let upcomingPressIndex = latestPressIndex + 1
            if upcomingPressIndex < pressSamples.count {
                let press = pressSamples[upcomingPressIndex]
                let remaining = press.time - time
                if remaining >= 0, remaining <= anticipationWindow {
                    target = press.location
                    approachingPress = remaining <= interceptWindow
                }
            }

            let isPressed = pressIntervalIndex < intervals.count
                && intervals[pressIntervalIndex].contains(time)
            // A drag sample is authoritative even if a press sample was lost
            // to permissions or an interrupted capture. Release immediately
            // becomes the latest sample and returns to the ordinary spring.
            let isDragging = latest.kind == .drag
            let motion = isDragging
                ? PointerSpring.track
                : (approachingPress ? PointerSpring.intercept : PointerSpring.glide)
            xSpring.step(toward: target.x, using: motion, dt: dt)
            ySpring.step(toward: target.y, using: motion, dt: dt)

            var isHidden = false
            if let hideAfterInactivity,
               hideAfterInactivity > 0,
               travelIndex >= 0 {
                let previousTravel = travelSamples[travelIndex]
                let nextTravel = travelIndex + 1 < travelSamples.count
                    ? travelSamples[travelIndex + 1]
                    : nil
                let willMoveSoon = nextTravel.map {
                    $0.time - time <= revealLeadWindow
                } ?? false
                isHidden = time - previousTravel.time > hideAfterInactivity && !willMoveSoon
            }

            let targetMagnification = (isPressed ? 0.8 : 1) * (isHidden ? 0.8 : 1)
            magnificationSpring.step(toward: targetMagnification, using: PointerSpring.settle, dt: dt)
            opacitySpring.step(toward: isHidden ? 0 : 1, using: PointerSpring.settle, dt: dt)
            blurSpring.step(toward: isHidden ? 5 : 0, using: PointerSpring.settle, dt: dt)

            let press: PointerPressFrame?
            if latestPressIndex >= 0 {
                let event = pressSamples[latestPressIndex]
                let elapsed = time - event.time
                press = elapsed <= pulseDuration
                    ? PointerPressFrame(
                        location: event.location,
                        progress: min(max(elapsed / pulseDuration, 0), 1)
                    )
                    : nil
            } else {
                press = nil
            }

            frames.append(PointerFrame(
                location: CGPoint(x: xSpring.position, y: ySpring.position),
                artworkID: currentArtworkID,
                magnification: magnificationSpring.position,
                tiltDegrees: 0,
                opacity: min(max(opacitySpring.position, 0), 1),
                blurRadius: max(0, blurSpring.position),
                press: press
            ))
        }

        let tiltOffset = max(1, Int((tiltSampleWindow * stepRate).rounded()))
        let recordingWidth = max(Double(safeSize.width), 1)
        for index in frames.indices {
            let previous = frames[max(0, index - tiltOffset)].location
            let current = frames[index].location
            let deltaInPoints = (current.x - previous.x) * recordingWidth
            frames[index].tiltDegrees = min(max(
                deltaInPoints * tiltGain * tiltWeight,
                -20
            ), 20)
        }

        return PointerTimeline(
            frames: frames,
            duration: timelineDuration,
            artworkByID: artworkByID,
            fallbackArtwork: fallbackArtwork
        )
    }

    /// Maps retained source events onto edited time before spring integration.
    /// Removed clicks can no longer attract the cursor through look-ahead, and
    /// a seed at every clip boundary lets the spring bridge cuts smoothly.
    private static func timelineSamples(
        from sourceSamples: [PointerStreamEvent],
        clipTimeline: RecordingClipTimeline?
    ) -> [PointerStreamEvent] {
        guard let clipTimeline else { return sourceSamples }
        guard !sourceSamples.isEmpty, !clipTimeline.segments.isEmpty else { return [] }

        var ranked: [EditedPointerEvent] = []
        ranked.reserveCapacity(sourceSamples.count + clipTimeline.segments.count)
        for (index, sample) in sourceSamples.enumerated() {
            guard let editorTime = editorTime(
                forSourceEventTime: sample.time,
                in: clipTimeline
            ) else {
                continue
            }
            var mapped = sample
            mapped.time = editorTime
            ranked.append(EditedPointerEvent(
                event: mapped,
                boundarySeed: false,
                order: index
            ))
        }

        var editorStart: TimeInterval = 0
        for (index, segment) in clipTimeline.segments.enumerated() {
            if var seed = sourceSample(at: segment.sourceStart, samples: sourceSamples) {
                seed.time = editorStart
                seed.kind = .travel
                seed.button = nil
                ranked.append(EditedPointerEvent(
                    event: seed,
                    boundarySeed: true,
                    order: index
                ))
            }
            editorStart += segment.editorDuration
        }

        ranked.sort { lhs, rhs in
            if lhs.event.time != rhs.event.time { return lhs.event.time < rhs.event.time }
            if lhs.boundarySeed != rhs.boundarySeed { return lhs.boundarySeed }
            return lhs.order < rhs.order
        }
        return ranked.map(\.event)
    }

    /// Events use half-open source ranges so an event at an outgoing clip's
    /// exact end cannot leak onto the first frame of the next clip. The public
    /// clip lookup is inclusive because it also serves playhead placement,
    /// which is a different boundary contract.
    private static func editorTime(
        forSourceEventTime sourceTime: TimeInterval,
        in clipTimeline: RecordingClipTimeline
    ) -> TimeInterval? {
        var editorStart: TimeInterval = 0
        for segment in clipTimeline.segments {
            if sourceTime >= segment.sourceStart,
               sourceTime < segment.sourceEnd {
                return editorStart
                    + (sourceTime - segment.sourceStart) / max(segment.speed, 1)
            }
            editorStart += segment.editorDuration
        }
        return nil
    }

    private static func sourceSample(
        at time: TimeInterval,
        samples: [PointerStreamEvent]
    ) -> PointerStreamEvent? {
        guard let first = samples.first else { return nil }
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
        return low > 0 ? samples[low - 1] : first
    }

    private static func pressIntervals(
        from samples: [PointerStreamEvent],
        duration: TimeInterval
    ) -> [PressInterval] {
        let presses = samples.filter { $0.kind == .press || $0.kind == .release }
        var result: [PressInterval] = []
        var unmatchedPresses: [Int: [PointerStreamEvent]] = [:]

        for sample in presses {
            let button = sample.button ?? 0
            if sample.kind == .press {
                unmatchedPresses[button, default: []].append(sample)
            } else if var pending = unmatchedPresses[button], !pending.isEmpty {
                let press = pending.removeFirst()
                unmatchedPresses[button] = pending
                result.append(PressInterval(
                    start: max(0, press.time - pressAnticipation),
                    end: min(max(sample.time, press.time), duration)
                ))
            }
        }

        for pending in unmatchedPresses.values {
            for press in pending {
                result.append(PressInterval(
                    start: max(0, press.time - pressAnticipation),
                    end: min(press.time + orphanPressHold, duration)
                ))
            }
        }
        let sorted = result.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        var merged: [PressInterval] = []
        for interval in sorted {
            if let lastIndex = merged.indices.last,
               interval.start <= merged[lastIndex].end {
                merged[lastIndex].end = max(merged[lastIndex].end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

// MARK: - Pointer artwork metrics

extension PointerArtwork {
    var normalizedAnchor: CGPoint {
        let width = max(referenceSize.width, 1)
        let height = max(referenceSize.height, 1)
        return CGPoint(
            x: min(max(anchorPoint.x / width, 0), 1),
            y: min(max(anchorPoint.y / height, 0), 1)
        )
    }

    var aspectRatio: CGFloat {
        guard referenceSize.width > 0, referenceSize.height > 0 else {
            return 1
        }
        return CGFloat(referenceSize.width / referenceSize.height)
    }

    /// Preserve relative system-cursor sizes without allowing drag artwork or
    /// malformed metadata to dominate the composition.
    var intrinsicScale: CGFloat {
        guard referenceSize.height > 0 else { return 1 }
        return min(max(CGFloat(referenceSize.height / 16), 0.75), 2.5)
    }
}

/// Shared sizing for pointer artwork embedded in the recording sidecar.
nonisolated enum PointerArtworkMetrics {
    static let heightRatio: CGFloat = 0.032
}

// MARK: - Motion helpers

nonisolated private struct PressInterval {
    var start: TimeInterval
    var end: TimeInterval

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

nonisolated private struct EditedPointerEvent {
    var event: PointerStreamEvent
    var boundarySeed: Bool
    var order: Int
}

nonisolated private enum PointerSpring {
    static let glide = SpringConstant(tension: 470, friction: 70, inertia: 3)
    static let intercept = SpringConstant(tension: 538, friction: 40, inertia: 1)
    static let track = SpringConstant(tension: 1_000, friction: 40, inertia: 1)
    static let settle = SpringConstant(tension: 300, friction: 30, inertia: 0.3)
}
