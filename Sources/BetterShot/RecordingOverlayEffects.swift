//
//  RecordingOverlayEffects.swift
//  BetterShot
//
//  Post-record input feedback drawn by Studio: the click pulse and the
//  keystroke caption. Both are reconstructed from the input.json sidecar on
//  the source timeline, so they can be toggled and styled in the editor and
//  render pixel-identically in the live preview and the offline exporter.
//

import CoreGraphics
import Foundation

// MARK: - Click feedback

nonisolated struct PointerPressEffectGeometry: Sendable {
    var impactRadius: CGFloat
    var impactOpacity: Double
    var rippleRadius: CGFloat
    var rippleOpacity: Double
    var rippleLineWidth: CGFloat
}

/// Shared preview/export math for a crisp impact followed by a quieter ripple.
/// The effect stays anchored to the recorded press coordinate rather than the
/// cursor spring, so the marked target is exact even during a fast movement.
nonisolated enum PointerPressEffectStyle {
    /// macOS system blue.
    static let color: (red: Double, green: Double, blue: Double) = (0, 122.0 / 255.0, 1)
    static let duration: TimeInterval = 0.4
    private static let impactDuration: TimeInterval = 0.12
    private static let rippleDelay: TimeInterval = 0.06

    /// `referenceHeight` is the unzoomed content height. Camera transforms move
    /// the effect but never inflate its on-screen size.
    static func geometry(
        progress: Double,
        referenceHeight: CGFloat,
        cursorScale: CGFloat
    ) -> PointerPressEffectGeometry {
        let age = min(max(progress, 0), 1) * duration
        let base = referenceHeight * CGFloat(21.0 / 1_080.0) * cursorScale
        let impactProgress = min(max(age / impactDuration, 0), 1)
        let impactEase = easeOutCubic(impactProgress)
        let rippleProgress = min(max(
            (age - rippleDelay) / (duration - rippleDelay),
            0
        ), 1)
        let rippleEase = easeOutCubic(rippleProgress)
        return PointerPressEffectGeometry(
            impactRadius: base * CGFloat(0.38 + 0.34 * impactEase),
            impactOpacity: age <= impactDuration ? 0.38 * (1 - impactEase) : 0,
            rippleRadius: base * CGFloat(0.62 + 0.93 * rippleEase),
            rippleOpacity: age >= rippleDelay ? 0.44 * (1 - rippleEase) : 0,
            rippleLineWidth: max(1, base * CGFloat(0.14 - 0.07 * rippleEase))
        )
    }

    private static func easeOutCubic(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}

// MARK: - Keystroke caption placement

enum RecordingKeystrokePlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var isTop: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight: true
        case .bottomLeft, .bottomCenter, .bottomRight: false
        }
    }

    var title: String {
        switch self {
        case .topLeft, .bottomLeft: "Left"
        case .topCenter, .bottomCenter: "Center"
        case .topRight, .bottomRight: "Right"
        }
    }
}

// MARK: - Keystroke caption timeline

/// What the caption shows at a single point in time.
nonisolated struct KeystrokeCaptionFrame: Sendable, Equatable {
    var modifiers: [String]
    var key: String
    var opacity: Double
    var scale: Double
}

/// Deterministic caption playback built once from the recorded keystrokes.
/// Consecutive chords replace the caption content in place; a chord with
/// nothing after it fades out on its own.
nonisolated struct KeystrokeCaptionTimeline: Sendable {
    private static let popInDuration: TimeInterval = 0.16
    private static let holdDuration: TimeInterval = 1.1
    private static let popOutDuration: TimeInterval = 0.3

    private let events: [RecordingKeystrokeEvent]

    static let empty = KeystrokeCaptionTimeline(events: [])

    init(events: [RecordingKeystrokeEvent]) {
        self.events = events
            .filter { $0.time.isFinite && !$0.key.isEmpty }
            .sorted { $0.time < $1.time }
    }

    var isEmpty: Bool {
        events.isEmpty
    }

    func frame(at time: TimeInterval) -> KeystrokeCaptionFrame? {
        guard !events.isEmpty, time.isFinite else { return nil }

        // Last event that has already started.
        var low = 0
        var high = events.count
        while low < high {
            let middle = (low + high) / 2
            if events[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0 else { return nil }

        let event = events[index]
        let naturalEnd = event.time + Self.popInDuration + Self.holdDuration + Self.popOutDuration
        let nextStart = index + 1 < events.count ? events[index + 1].time : nil
        let end = min(naturalEnd, nextStart ?? .greatestFiniteMagnitude)
        guard time < end else { return nil }

        // Pop-in is skipped when the previous chord was still on screen -
        // the caption just swaps its content in place.
        let previousEnd: TimeInterval? = index > 0
            ? events[index - 1].time + Self.popInDuration + Self.holdDuration + Self.popOutDuration
            : nil
        let continuesPreviousCaption = previousEnd.map { $0 > event.time } ?? false

        var opacity = 1.0
        var scale = 1.0

        if !continuesPreviousCaption, time - event.time < Self.popInDuration {
            let progress = min(max((time - event.time) / Self.popInDuration, 0), 1)
            let eased = 1 - pow(1 - progress, 3)
            opacity = eased
            scale = 0.92 + 0.08 * eased
        }

        // Fade out only applies at the natural end; a chord cut short by the
        // next one hands over at full opacity.
        if naturalEnd <= (nextStart ?? .greatestFiniteMagnitude), time > naturalEnd - Self.popOutDuration {
            let progress = min(max((naturalEnd - time) / Self.popOutDuration, 0), 1)
            let eased = 1 - pow(1 - progress, 3)
            opacity = min(opacity, eased)
            scale = min(scale, 0.97 + 0.03 * eased)
        }

        guard opacity > 0.005 else { return nil }
        return KeystrokeCaptionFrame(
            modifiers: event.modifiers,
            key: event.key,
            opacity: opacity,
            scale: scale
        )
    }
}

// MARK: - Keystroke caption metrics

/// Geometry shared verbatim by the SwiftUI preview and the CoreGraphics
/// exporter. Everything derives from the recording card's height so the
/// caption is stable under zoom and identical at any render resolution.
nonisolated struct KeystrokeCaptionMetrics: Sendable {
    let fontSize: CGFloat
    let paddingHorizontal: CGFloat
    let paddingVertical: CGFloat
    let cornerRadius: CGFloat
    let margin: CGFloat

    static let backgroundAlpha: Double = 0.62
    static let modifierAlpha: Double = 0.7

    /// The caption text drawn for a frame: modifiers, a space, then the key.
    static func text(for frame: KeystrokeCaptionFrame) -> (modifiers: String, key: String) {
        let modifiers = frame.modifiers.joined(separator: " ")
        return (modifiers.isEmpty ? "" : modifiers + " ", frame.key)
    }

    init(cardHeight: CGFloat) {
        fontSize = max(11, cardHeight * 0.033)
        paddingHorizontal = fontSize * 0.72
        paddingVertical = fontSize * 0.46
        // One rounded container; radius stays proportional to the pill so it
        // reads as a soft capsule-ish rectangle at any resolution.
        cornerRadius = fontSize * 0.55
        margin = cardHeight * 0.045
    }

    /// Top-left origin of the caption pill inside `cardRect` (both in the
    /// same top-left-origin coordinate space).
    func pillOrigin(
        pillSize: CGSize,
        cardRect: CGRect,
        placement: RecordingKeystrokePlacement
    ) -> CGPoint {
        let x: CGFloat
        switch placement {
        case .topLeft, .bottomLeft:
            x = cardRect.minX + margin
        case .topCenter, .bottomCenter:
            x = cardRect.midX - pillSize.width / 2
        case .topRight, .bottomRight:
            x = cardRect.maxX - margin - pillSize.width
        }
        let y = placement.isTop
            ? cardRect.minY + margin
            : cardRect.maxY - margin - pillSize.height
        return CGPoint(x: x, y: y)
    }
}
