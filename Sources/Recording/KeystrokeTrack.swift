import CoreGraphics
import Foundation

nonisolated struct KeyModifiers: OptionSet, Codable, Sendable {
    let rawValue: Int

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let shift = KeyModifiers(rawValue: 1 << 3)

    /// A shortcut is worth showing on its own; shift alone is just how you typed the character.
    var isShortcut: Bool { contains(.command) || contains(.control) }

    var symbols: String {
        var out = ""
        if contains(.command) { out += "\u{2318}" }
        if contains(.control) { out += "\u{2303}" }
        if contains(.option) { out += "\u{2325}" }
        if contains(.shift) { out += "\u{21E7}" }
        return out
    }
}

nonisolated struct KeyPress: Codable, Sendable, Equatable {
    var time: TimeInterval
    var key: String
    var modifiers: KeyModifiers = []
}

nonisolated struct KeystrokeCaptureFile: Codable, Sendable {
    var presses: [KeyPress] = []
}

/// One line of typing that earned its own moment on screen, in source time.
nonisolated struct KeystrokeSegment: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    static let groupingThreshold: TimeInterval = 0.5
    static let lingerDuration: TimeInterval = 0.8

    static let symbols: [String: String] = [
        "Return": "\u{23CE}",
        "Tab": "\u{21E5}",
        "Backspace": "\u{232B}",
        "Delete": "\u{2326}",
        "Escape": "\u{238B}",
        "Space": "\u{2423}",
        "Up": "\u{2191}",
        "Down": "\u{2193}",
        "Left": "\u{2190}",
        "Right": "\u{2192}",
        "Home": "\u{21F1}",
        "End": "\u{21F2}",
        "PageUp": "\u{21DE}",
        "PageDown": "\u{21DF}",
    ]

    static func display(_ key: String) -> String? {
        if let symbol = symbols[key] { return symbol }
        return key.count == 1 ? key : nil
    }

    /// Typing reads as words, not as a stutter of single keys, so runs of keys collapse into one line and shortcuts get their own.
    static func grouped(
        _ presses: [KeyPress],
        threshold: TimeInterval = groupingThreshold,
        linger: TimeInterval = lingerDuration
    ) -> [KeystrokeSegment] {
        var segments: [KeystrokeSegment] = []
        var text = ""
        var start: TimeInterval?
        var lastTime: TimeInterval = -.greatestFiniteMagnitude

        func flush() {
            if let began = start, !text.isEmpty {
                segments.append(KeystrokeSegment(start: began, end: lastTime + linger, text: text))
            }
            text = ""
            start = nil
        }

        for press in presses.sorted(by: { $0.time < $1.time }) {
            if press.modifiers.isShortcut {
                flush()
                let key = display(press.key) ?? press.key
                segments.append(KeystrokeSegment(
                    start: press.time,
                    end: press.time + linger,
                    text: press.modifiers.symbols + key.uppercased()
                ))
                lastTime = press.time
                continue
            }

            if press.key == "Space" {
                let typing = start != nil && !text.isEmpty && press.time - lastTime <= threshold
                let gap = press.time - lastTime > threshold
                flush()
                if !typing && gap {
                    segments.append(KeystrokeSegment(start: press.time, end: press.time + linger, text: symbols["Space"]!))
                }
                lastTime = press.time
                continue
            }

            if press.key == "Backspace", !text.isEmpty {
                text.removeLast()
                lastTime = press.time
                if text.isEmpty { start = nil }
                continue
            }

            if start != nil, press.time - lastTime > threshold { flush() }
            guard let character = display(press.key) else { continue }

            if start == nil { start = press.time }
            text += character
            lastTime = press.time
        }

        flush()
        return segments
    }
}

/// How typing is drawn, and where it sits so it clears the caption lane.
nonisolated struct KeystrokeStyle: Equatable, Sendable {
    enum Position: String, CaseIterable, Identifiable, Sendable {
        case bottom
        case top

        var id: String { rawValue }
        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        var icon: String { self == .bottom ? "text.append" : "text.insert" }
        var center: CGFloat { self == .bottom ? 0.76 : 0.08 }
    }

    var isEnabled = true
    var position: Position = .bottom
    var fontSize: CGFloat = 46
    var weight: TextOverlay.Weight = .medium
    var red: CGFloat = 1
    var green: CGFloat = 1
    var blue: CGFloat = 1
    var backgroundOpacity: CGFloat = 0.85
    var fadeDuration: TimeInterval = 0.15
    var isUppercase = false

    /// Keystrokes are text on the canvas, so they borrow the overlay resolve rather than growing a second painter.
    func overlays(_ segments: [KeystrokeSegment]) -> [TextOverlay] {
        guard isEnabled else { return [] }
        return segments.map { segment in
            var overlay = TextOverlay(start: segment.start, end: segment.end)
            overlay.id = segment.id
            overlay.content = isUppercase ? segment.text.uppercased() : segment.text
            overlay.center = CGPoint(x: 0.5, y: position.center)
            overlay.maxWidth = 0.8
            overlay.fontSize = fontSize
            overlay.weight = weight
            overlay.align = .center
            overlay.red = red
            overlay.green = green
            overlay.blue = blue
            overlay.shadow = backgroundOpacity > 0 ? 0 : 0.6
            overlay.backgroundOpacity = backgroundOpacity
            overlay.animationIn = .fade
            overlay.animationOut = .fade
            overlay.animationInDuration = fadeDuration
            overlay.animationOutDuration = fadeDuration
            return overlay
        }
    }
}
