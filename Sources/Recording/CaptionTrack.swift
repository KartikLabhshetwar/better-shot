import CoreGraphics
import Foundation

/// One spoken line with the window it was said in, in source time, the clock the preview and the exporter already share.
nonisolated struct CaptionCue: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    static let minimumDuration: TimeInterval = 0.2
    static let maximumWords = 8
    static let maximumDuration: TimeInterval = 3.2
    static let breakingGap: TimeInterval = 0.55

    /// A timeline drag can push a cue past either edge, so it comes back inside the recording with its floor intact.
    func clamped(to duration: TimeInterval) -> CaptionCue {
        var cue = self
        cue.start = min(max(0, start), max(0, duration - Self.minimumDuration))
        cue.end = min(max(cue.start + Self.minimumDuration, end), max(duration, cue.start + Self.minimumDuration))
        return cue
    }

    /// Speech hands back one word at a time, so cues break on a pause, on a full stop, or when a line grows too long to read.
    static func grouped(_ words: [SpokenWord]) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        var pending: [SpokenWord] = []

        func flush() {
            guard let first = pending.first, let last = pending.last else { return }
            cues.append(CaptionCue(
                start: first.start,
                end: max(last.end, first.start + 0.2),
                text: pending.map(\.text).joined(separator: " ")
            ))
            pending = []
        }

        for word in words {
            if let last = pending.last, word.start - last.end > breakingGap || word.end - (pending.first?.start ?? word.start) > maximumDuration {
                flush()
            }
            pending.append(word)
            if pending.count >= maximumWords || word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!") {
                flush()
            }
        }
        flush()
        return cues
    }
}

nonisolated struct SpokenWord: Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// How the spoken track is drawn: one look for every cue, the way a subtitle track works.
nonisolated struct CaptionStyle: Equatable, Sendable {
    enum Position: String, CaseIterable, Identifiable, Sendable {
        case bottom
        case top

        var id: String { rawValue }
        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        var icon: String { self == .bottom ? "text.append" : "text.insert" }
        var center: CGFloat { self == .bottom ? 0.88 : 0.12 }
    }

    var isEnabled = true
    var position: Position = .bottom
    var fontSize: CGFloat = 44
    var weight: TextOverlay.Weight = .bold
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var backgroundOpacity: CGFloat = 0.55
    var isUppercase = false
    var fadeDuration: TimeInterval = 0.12
    var maxWidth: CGFloat = 0.76

    func resolved(_ cues: [CaptionCue], atSourceTime time: TimeInterval, canvasSize: CGSize) -> ResolvedText? {
        guard isEnabled, canvasSize.height > 0 else { return nil }
        guard let cue = cues.first(where: { time >= $0.start && time <= $0.end }), !cue.text.isEmpty else { return nil }

        let fade = fadeDuration > 0
            ? min(min(time - cue.start, cue.end - time) / fadeDuration, 1)
            : 1
        guard fade > 0.001 else { return nil }

        let scale = canvasSize.height / TextOverlay.referenceHeight
        return ResolvedText(
            content: isUppercase ? cue.text.uppercased() : cue.text,
            center: CGPoint(x: canvasSize.width / 2, y: position.center * canvasSize.height),
            offset: .zero,
            scale: 1,
            opacity: CGFloat(fade),
            fontSize: min(max(fontSize, CGFloat(TextOverlay.fontSizeRange.lowerBound)), CGFloat(TextOverlay.fontSizeRange.upperBound)) * scale,
            maxWidth: min(max(maxWidth, 0.2), 1) * canvasSize.width,
            weight: weight,
            align: .center,
            red: red,
            green: green,
            blue: blue,
            shadow: backgroundOpacity > 0 ? 0 : 0.6,
            lineHeight: 1.15,
            backgroundOpacity: min(max(backgroundOpacity, 0), 1)
        )
    }
}
