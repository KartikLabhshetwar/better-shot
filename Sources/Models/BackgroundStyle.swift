import SwiftUI

// MARK: - Background Style

enum BackgroundStyle: Codable, Equatable, Hashable {
    case none
    case solid(SolidColor)
    case gradient(GradientPreset)
    case wallpaper(WallpaperSource)
    case bundledImage(String)
}

// MARK: - Solid Colors (12 presets matching a rich palette)

struct SolidColor: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension SolidColor {
    static let presets: [SolidColor] = [
        SolidColor(id: "obsidian", name: "Obsidian", red: 0.02, green: 0.02, blue: 0.03),
        SolidColor(id: "chalk", name: "Chalk", red: 0.96, green: 0.96, blue: 0.94),
        SolidColor(id: "slate", name: "Slate", red: 0.17, green: 0.18, blue: 0.22),
        SolidColor(id: "ember", name: "Ember", red: 0.94, green: 0.24, blue: 0.28),
        SolidColor(id: "tangerine", name: "Tangerine", red: 0.97, green: 0.53, blue: 0.16),
        SolidColor(id: "saffron", name: "Saffron", red: 0.96, green: 0.74, blue: 0.23),
        SolidColor(id: "fern", name: "Fern", red: 0.23, green: 0.62, blue: 0.36),
        SolidColor(id: "cobalt", name: "Cobalt", red: 0.16, green: 0.50, blue: 0.88),
        SolidColor(id: "iris", name: "Iris", red: 0.48, green: 0.27, blue: 0.91),
        SolidColor(id: "rose", name: "Rose", red: 0.93, green: 0.67, blue: 0.63),
        SolidColor(id: "seafoam", name: "Seafoam", red: 0.66, green: 0.90, blue: 0.74),
        SolidColor(id: "cloud", name: "Cloud", red: 0.63, green: 0.80, blue: 0.94),
    ]
}

// MARK: - Shared gradient presets

struct GradientPreset: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let stops: [GradientStop]
    let startPoint: UnitPoint2D
    let endPoint: UnitPoint2D
    var locations: [CGFloat]? = nil
    var highlights: [Highlight]? = nil

    struct Highlight: Codable, Equatable, Hashable {
        let x: CGFloat
        let y: CGFloat
        let opacity: CGFloat
        let extent: CGFloat
    }

    struct GradientStop: Codable, Equatable, Hashable {
        let red: Double
        let green: Double
        let blue: Double
    }

    struct UnitPoint2D: Codable, Equatable, Hashable {
        let x: Double
        let y: Double

        var unitPoint: UnitPoint {
            UnitPoint(x: x, y: y)
        }
    }
}

extension GradientPreset {
    /// The same vector drawing is used by swatches, the canvas, and exports.
    func draw(in context: CGContext, rect: CGRect, topLeftOrigin: Bool = false) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } as CFArray,
            locations: locations) else { return }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width,
                    y: rect.minY + (topLeftOrigin ? y : 1 - y) * rect.height)
        }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: point(startPoint.x, startPoint.y),
                                   end: point(endPoint.x, endPoint.y),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // CSS paints the first radial layer on top of the second.
        for highlight in (highlights ?? []).reversed() {
            let center = point(highlight.x, highlight.y)
            let rx = max(highlight.x, 1 - highlight.x) * rect.width * sqrt(2)
            let ry = max(highlight.y, 1 - highlight.y) * rect.height * sqrt(2)
            guard rx > 0, ry > 0,
                  let radial = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [CGColor(gray: 1, alpha: highlight.opacity), CGColor(gray: 1, alpha: 0)] as CFArray,
                    locations: [0, 1]) else { continue }
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: rx, y: ry)
            context.drawRadialGradient(radial, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: highlight.extent, options: [])
            context.restoreGState()
        }
        context.restoreGState()
    }

    static let presets: [GradientPreset] = {
        func color(_ hex: UInt32) -> GradientStop {
            GradientStop(red: Double((hex >> 16) & 255) / 255,
                         green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }
        return [
            GradientPreset(id: "soft-blush", name: "Blush / Lavender",
                stops: [color(0xFAFAFA), color(0xF9E8F3), color(0xE7C8F1)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.48, 1], highlights: [
                    Highlight(x: 0.18, y: 0.08, opacity: 0.32, extent: 0.35),
                    Highlight(x: 0.86, y: 0.9, opacity: 0.16, extent: 0.34),
                ]),
            GradientPreset(id: "soft-peach", name: "Peach / Apricot",
                stops: [color(0xFCFAF7), color(0xFBE6D8), color(0xFFB98D)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.5, 1], highlights: [
                    Highlight(x: 0.82, y: 0.08, opacity: 0.3, extent: 0.34),
                    Highlight(x: 0.14, y: 0.88, opacity: 0.18, extent: 0.32),
                ]),
            GradientPreset(id: "soft-mint", name: "Mint",
                stops: [color(0xFBFCFA), color(0xE8F8F0), color(0xAEEACD)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.48, 1], highlights: [
                    Highlight(x: 0.18, y: 0.1, opacity: 0.34, extent: 0.36),
                    Highlight(x: 0.88, y: 0.86, opacity: 0.2, extent: 0.34),
                ]),
            GradientPreset(id: "soft-blue", name: "Powder Blue",
                stops: [color(0xFBFCFD), color(0xE5F2FD), color(0xA8D7FF)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.5, 1], highlights: [
                    Highlight(x: 0.16, y: 0.08, opacity: 0.34, extent: 0.35),
                    Highlight(x: 0.88, y: 0.88, opacity: 0.22, extent: 0.33),
                ]),
            GradientPreset(id: "soft-butter", name: "Butter Yellow",
                stops: [color(0xFDFCF7), color(0xFFF8D6), color(0xFFE677)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.48, 1], highlights: [
                    Highlight(x: 0.16, y: 0.08, opacity: 0.36, extent: 0.36),
                    Highlight(x: 0.88, y: 0.86, opacity: 0.22, extent: 0.32),
                ]),
            GradientPreset(id: "soft-lilac", name: "Lilac / Periwinkle",
                stops: [color(0xFCFBFD), color(0xEEEAFE), color(0xAFAEFF)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.44, 1], highlights: [
                    Highlight(x: 0.18, y: 0.07, opacity: 0.34, extent: 0.36),
                    Highlight(x: 0.86, y: 0.84, opacity: 0.16, extent: 0.34),
                ]),
            GradientPreset(id: "soft-sage", name: "Sage Green",
                stops: [color(0xFCFBF7), color(0xE8EDE1), color(0x91AD8A)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.42, 1], highlights: [
                    Highlight(x: 0.16, y: 0.08, opacity: 0.3, extent: 0.36),
                    Highlight(x: 0.88, y: 0.42, opacity: 0.2, extent: 0.31),
                ]),
            GradientPreset(id: "soft-coral", name: "Coral / Rose",
                stops: [color(0xFCF9F7), color(0xF9D3CD), color(0xFF6F73)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.46, 1], highlights: [
                    Highlight(x: 0.18, y: 0.07, opacity: 0.3, extent: 0.36),
                    Highlight(x: 0.82, y: 0.7, opacity: 0.2, extent: 0.31),
                ]),
            GradientPreset(id: "soft-aqua", name: "Aqua / Cyan",
                stops: [color(0xFBFDFD), color(0xDFF9FC), color(0x6FE2ED)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.48, 1], highlights: [
                    Highlight(x: 0.15, y: 0.08, opacity: 0.34, extent: 0.36),
                    Highlight(x: 0.88, y: 0.87, opacity: 0.24, extent: 0.34),
                ]),
            GradientPreset(id: "soft-mauve", name: "Dusty Mauve",
                stops: [color(0xFBF8F6), color(0xE8DADB), color(0xB7949F)],
                startPoint: .init(x: 0.5, y: 0), endPoint: .init(x: 0.5, y: 1),
                locations: [0, 0.42, 1], highlights: [
                    Highlight(x: 0.17, y: 0.07, opacity: 0.3, extent: 0.36),
                    Highlight(x: 0.86, y: 0.38, opacity: 0.18, extent: 0.32),
                ]),
        ]
    }()
}

struct GradientBackgroundView: View {
    let preset: GradientPreset
    var body: some View {
        Canvas { context, size in
            context.withCGContext { preset.draw(in: $0, rect: CGRect(origin: .zero, size: size), topLeftOrigin: true) }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Wallpaper Source

struct WallpaperSource: Codable, Equatable, Hashable {
    let path: String
}

// MARK: - Image Alignment (9-point grid)

enum ImageAlignment: String, Codable, CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var title: String {
        switch self {
        case .topLeading: return "Top Left"
        case .top: return "Top"
        case .topTrailing: return "Top Right"
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        case .bottomLeading: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomTrailing: return "Bottom Right"
        }
    }

    var xFactor: CGFloat {
        switch self {
        case .topLeading, .leading, .bottomLeading: return 0
        case .top, .center, .bottom: return 0.5
        case .topTrailing, .trailing, .bottomTrailing: return 1
        }
    }

    var yFactor: CGFloat {
        switch self {
        case .topLeading, .top, .topTrailing: return 0
        case .leading, .center, .trailing: return 0.5
        case .bottomLeading, .bottom, .bottomTrailing: return 1
        }
    }

    /// Returns per-corner radius multipliers. Corners touching a stuck edge get 0.
    var cornerMultipliers: (tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) {
        let stuckTop = self == .topLeading || self == .top || self == .topTrailing
        let stuckBottom = self == .bottomLeading || self == .bottom || self == .bottomTrailing
        let stuckLeft = self == .topLeading || self == .leading || self == .bottomLeading
        let stuckRight = self == .topTrailing || self == .trailing || self == .bottomTrailing

        return (
            tl: (stuckTop || stuckLeft) ? 0 : 1,
            tr: (stuckTop || stuckRight) ? 0 : 1,
            br: (stuckBottom || stuckRight) ? 0 : 1,
            bl: (stuckBottom || stuckLeft) ? 0 : 1
        )
    }
}

// MARK: - Aspect Ratio

enum CanvasAspectRatio: String, Codable, CaseIterable {
    case auto = "Auto"
    case square = "1:1"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var numericValue: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}
