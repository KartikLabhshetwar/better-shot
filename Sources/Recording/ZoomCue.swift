import CoreGraphics
import Foundation

nonisolated enum ZoomAnchorMode: String, Codable, CaseIterable, Sendable {
    case pointerAnchor
    case pinnedAnchor

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ZoomAnchorMode(rawValue: raw) ?? .pointerAnchor
    }
}

nonisolated struct ZoomCue: Identifiable, Codable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.5

    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var zoom: Double
    var anchorMode: ZoomAnchorMode
    var pinnedPoint: CGPoint
    var boundsBias: Double
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        zoom: Double = 1.6,
        anchorMode: ZoomAnchorMode = .pointerAnchor,
        pinnedPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        boundsBias: Double = 0.25,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.zoom = zoom
        self.anchorMode = anchorMode
        self.pinnedPoint = Self.normalized(pinnedPoint)
        self.boundsBias = Self.unit(boundsBias)
        self.isEnabled = isEnabled
    }

    var duration: TimeInterval { max(0, end - start) }

    static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: unit(point.x), y: unit(point.y))
    }

    static func unit<T: BinaryFloatingPoint>(_ value: T) -> T {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

nonisolated struct ViewportFrame: Sendable, Equatable {
    var magnification: Double
    var anchor: CGPoint

    static let identity = ViewportFrame(magnification: 1, anchor: CGPoint(x: 0.5, y: 0.5))
}

nonisolated enum ZoomCueSynthesizer {
    private static let preRoll: TimeInterval = 0.3
    private static let postRoll: TimeInterval = 2.5
    private static let joinTolerance: TimeInterval = 2.5
    private static let tailExclusion: TimeInterval = 1.0
    private static let trailingGuard: TimeInterval = 0.8
    private static let earliestStart: TimeInterval = 0.001
    private static let defaultMagnification = 1.6

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
