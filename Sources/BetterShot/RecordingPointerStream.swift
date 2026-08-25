//
//  RecordingPointerStream.swift
//  BetterShot
//
//  Cleans the pointer capture sidecar once, then exposes one ordered stream
//  shared by viewport planning and pointer reconstruction.
//

import CoreGraphics
import Foundation

nonisolated struct PointerSanitizeOptions: Sendable {
    var recordingSizeInPoints: CGSize
    var minimumTravel: Double = 1
    var maxSampleGap: TimeInterval = 0.25
}

nonisolated struct PointerStreamEvent: Sendable, Equatable {
    enum Kind: Sendable {
        case travel
        case drag
        case press
        case release
    }

    var time: TimeInterval
    var x: Double
    var y: Double
    var kind: Kind
    var button: Int?
    var artworkID: String?

    var location: CGPoint {
        CGPoint(x: x, y: y)
    }
}

nonisolated struct PointerStream: Sendable {
    var sanitizedCapture: PointerCaptureFile
    var samples: [PointerStreamEvent]
    var artwork: [PointerArtwork]
}

nonisolated enum PointerStreamSanitizer {
    static func sanitize(
        _ capture: PointerCaptureFile,
        options: PointerSanitizeOptions
    ) -> PointerStream {
        if capture.isSanitized {
            return buildStream(from: capture)
        }

        let artwork = validArtwork(in: capture.artwork)
        let validArtworkIDs = Set(artwork.map(\.artworkID))
        let recordingSize = sanitizedRecordingSize(options.recordingSizeInPoints)

        let orderedTravel: [PointerTravelSample] = capture.travel.enumerated().compactMap {
            (element: (offset: Int, element: PointerTravelSample)) -> RankedTravelSample? in
            let index = element.offset
            let sample = element.element
            guard sample.time.isFinite,
                  let point = clampedUnitPoint(x: sample.x, y: sample.y) else {
                return nil
            }
            return RankedTravelSample(
                index: index,
                sample: PointerTravelSample(
                    time: max(0, sample.time),
                    x: point.x,
                    y: point.y,
                    kind: sample.kind,
                    artworkID: validArtworkID(sample.artworkID, in: validArtworkIDs)
                )
            )
        }.sorted { lhs, rhs in
            if lhs.sample.time == rhs.sample.time { return lhs.index < rhs.index }
            return lhs.sample.time < rhs.sample.time
        }.map { $0.sample }

        let stableTravel = dropIsolatedSpikes(
            from: orderedTravel,
            recordingSize: recordingSize
        )
        let sanitizedTravel = thinTravelSamples(
            stableTravel,
            recordingSize: recordingSize,
            minimumTravel: max(options.minimumTravel, 0),
            maxSampleGap: max(options.maxSampleGap, 1.0 / 120.0)
        )

        let sanitizedPresses: [PointerPressEvent] = capture.presses.enumerated().compactMap {
            (element: (offset: Int, element: PointerPressEvent)) -> RankedPressSample? in
            let index = element.offset
            let press = element.element
            guard press.time.isFinite,
                  let point = clampedUnitPoint(x: press.x, y: press.y) else {
                return nil
            }
            return RankedPressSample(
                index: index,
                press: PointerPressEvent(
                    time: max(0, press.time),
                    x: point.x,
                    y: point.y,
                    button: max(0, press.button),
                    phase: press.phase,
                    artworkID: validArtworkID(press.artworkID, in: validArtworkIDs)
                )
            )
        }.sorted { lhs, rhs in
            if lhs.press.time == rhs.press.time { return lhs.index < rhs.index }
            return lhs.press.time < rhs.press.time
        }.map { $0.press }

        var sanitized = PointerCaptureFile()
        sanitized.formatVersion = PointerCaptureFile.currentFormatVersion
        sanitized.travel = sanitizedTravel
        sanitized.presses = sanitizedPresses
        sanitized.keystrokes = sanitizedKeystrokes(capture.keystrokes)
        sanitized.artwork = artwork
        sanitized.isSanitized = true
        return buildStream(from: sanitized)
    }

    private static func buildStream(from capture: PointerCaptureFile) -> PointerStream {
        var ordered: [OrderedStreamEvent] = []
        ordered.reserveCapacity(capture.travel.count + capture.presses.count)

        for (index, sample) in capture.travel.enumerated() {
            guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite else { continue }
            ordered.append(OrderedStreamEvent(
                event: PointerStreamEvent(
                    time: sample.time,
                    x: sample.x,
                    y: sample.y,
                    kind: sample.kind == .drag ? .drag : .travel,
                    button: nil,
                    artworkID: sample.artworkID
                ),
                order: index * 2
            ))
        }

        let travelOrderOffset = capture.travel.count * 2
        for (index, press) in capture.presses.enumerated() {
            guard press.time.isFinite, press.x.isFinite, press.y.isFinite else { continue }
            ordered.append(OrderedStreamEvent(
                event: PointerStreamEvent(
                    time: press.time,
                    x: press.x,
                    y: press.y,
                    kind: press.phase == .down ? .press : .release,
                    button: press.button,
                    artworkID: press.artworkID
                ),
                order: travelOrderOffset + index * 2 + 1
            ))
        }

        ordered.sort {
            if $0.event.time == $1.event.time {
                if streamPriority($0.event.kind) == streamPriority($1.event.kind) {
                    return $0.order < $1.order
                }
                return streamPriority($0.event.kind) < streamPriority($1.event.kind)
            }
            return $0.event.time < $1.event.time
        }

        return PointerStream(
            sanitizedCapture: capture,
            samples: ordered.map(\.event),
            artwork: capture.artwork
        )
    }

    private static func thinTravelSamples(
        _ samples: [PointerTravelSample],
        recordingSize: CGSize,
        minimumTravel: Double,
        maxSampleGap: TimeInterval
    ) -> [PointerTravelSample] {
        guard samples.count > 2 else { return samples }

        var result = [samples[0]]
        result.reserveCapacity(samples.count)
        for sample in samples.dropFirst().dropLast() {
            guard let previous = result.last else { continue }
            let elapsed = sample.time - previous.time
            let preservesState = sample.kind != previous.kind
                || sample.artworkID != previous.artworkID
            let moved = distanceInPoints(previous, sample, recordingSize: recordingSize)
            if preservesState
                || elapsed >= maxSampleGap
                || (elapsed >= 1.0 / 120.0 && moved >= minimumTravel) {
                result.append(sample)
            }
        }

        if let last = samples.last, result.last != last {
            result.append(last)
        }
        return result
    }

    private static func dropIsolatedSpikes(
        from samples: [PointerTravelSample],
        recordingSize: CGSize
    ) -> [PointerTravelSample] {
        guard samples.count > 2 else { return samples }

        let diagonal = hypot(recordingSize.width, recordingSize.height)
        let spikeDistanceFloor = max(160, diagonal * 0.24)
        let spikeNeighborCeiling = max(16, diagonal * 0.025)

        return samples.enumerated().filter { index, sample in
            guard index > 0, index < samples.count - 1 else { return true }
            let previous = samples[index - 1]
            let next = samples[index + 1]
            guard sample.kind == previous.kind,
                  sample.kind == next.kind,
                  sample.artworkID == previous.artworkID,
                  sample.artworkID == next.artworkID else {
                return true
            }

            let fromPrevious = distanceInPoints(previous, sample, recordingSize: recordingSize)
            let toNext = distanceInPoints(sample, next, recordingSize: recordingSize)
            let neighbors = distanceInPoints(previous, next, recordingSize: recordingSize)
            return !(fromPrevious > spikeDistanceFloor
                && toNext > spikeDistanceFloor
                && neighbors < spikeNeighborCeiling)
        }.map(\.element)
    }

    private static func sanitizedKeystrokes(
        _ keystrokes: [RecordingKeystrokeEvent]
    ) -> [RecordingKeystrokeEvent] {
        keystrokes.compactMap { event -> RecordingKeystrokeEvent? in
            guard event.time.isFinite, !event.key.isEmpty else { return nil }
            return RecordingKeystrokeEvent(
                time: max(0, event.time),
                modifiers: event.modifiers.filter { !$0.isEmpty },
                key: event.key
            )
        }.sorted { $0.time < $1.time }
    }

    private static func validArtwork(
        in items: [PointerArtwork]
    ) -> [PointerArtwork] {
        var seen = Set<String>()
        return items.filter { artwork in
            guard !artwork.artworkID.isEmpty,
                  seen.insert(artwork.artworkID).inserted,
                  !artwork.imageData.isEmpty,
                  artwork.anchorPoint.x.isFinite,
                  artwork.anchorPoint.y.isFinite,
                  artwork.referenceSize.width.isFinite,
                  artwork.referenceSize.height.isFinite,
                  artwork.referenceSize.width > 0,
                  artwork.referenceSize.height > 0 else {
                return false
            }
            return true
        }
    }

    private static func validArtworkID(_ id: String?, in validIDs: Set<String>) -> String? {
        guard let id, validIDs.contains(id) else { return nil }
        return id
    }

    /// A tiny tolerance absorbs floating-point conversion at the capture
    /// boundary. Real out-of-frame input is discarded instead of being
    /// pinned to an edge and rendered as a misleading press.
    private static func clampedUnitPoint(x: Double, y: Double) -> (x: Double, y: Double)? {
        guard x.isFinite, y.isFinite,
              x >= -0.001, x <= 1.001,
              y >= -0.001, y <= 1.001 else {
            return nil
        }
        return (min(max(x, 0), 1), min(max(y, 0), 1))
    }

    private static func sanitizedRecordingSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite && size.width > 0 ? size.width : 1_000,
            height: size.height.isFinite && size.height > 0 ? size.height : 1_000
        )
    }

    private static func distanceInPoints(
        _ lhs: PointerTravelSample,
        _ rhs: PointerTravelSample,
        recordingSize: CGSize
    ) -> Double {
        hypot(
            (rhs.x - lhs.x) * recordingSize.width,
            (rhs.y - lhs.y) * recordingSize.height
        )
    }

    private static func streamPriority(_ kind: PointerStreamEvent.Kind) -> Int {
        switch kind {
        case .travel, .drag: 0
        case .press: 1
        case .release: 2
        }
    }
}

nonisolated private struct RankedTravelSample {
    var index: Int
    var sample: PointerTravelSample
}

nonisolated private struct RankedPressSample {
    var index: Int
    var press: PointerPressEvent
}

nonisolated private struct OrderedStreamEvent {
    var event: PointerStreamEvent
    var order: Int
}
