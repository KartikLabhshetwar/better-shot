import AppKit
import Foundation

/// The engine's chrome colours.
///
/// Only the selection chrome and the hatch ground are used here: annotation colours come from
/// BetterShot's own `AnnotationSwatch` palette.
enum AnnoTheme {
    /// A colour that picks its value from the appearance it's resolved against.
    static func dynamic(light: String, dark: String) -> NSColor {
        let lightColor = NSColor(annoHex: light)
        let darkColor = NSColor(annoHex: dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    /// The ground the hatch tile is drawn over.
    static let neutralSolid = dynamic(light: "#fcfffe", dark: "#010403")

    /// `--tl-color-selection-stroke`, `hsl(214, 84%, 56%)` in both themes.
    static let selectionStroke = dynamic(light: "#3182ed", dark: "#3182ed")

    /// `--tl-color-selection-fill`, at the alpha each theme uses.
    static var selectionFill: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(annoHex: "#1f91ff").withAlphaComponent(0.20)
                : NSColor(annoHex: "#1f8fff").withAlphaComponent(0.24)
        }
    }

    /// What a selection handle is filled with, so handles read as holes punched in the frame.
    static let handleFill = dynamic(light: "#ffffff", dark: "#2a2a2c")
}

extension NSColor {
    convenience init(annoHex hex: String) {
        var hexString = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if hexString.count == 3 {
            hexString = hexString.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// How much the spotlight tool dims everything outside its holes. Lived in the old highlight
/// overlay view, which the engine's spotlight pass replaced.
enum AnnotationHighlightMetrics {
    static let overlayOpacity: CGFloat = 0.55
}
