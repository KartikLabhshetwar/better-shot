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

// MARK: - Gradient Presets (16 three-stop linear gradients)

struct GradientPreset: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let stops: [GradientStop]
    let startPoint: UnitPoint2D
    let endPoint: UnitPoint2D

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
    var swiftUIGradient: LinearGradient {
        LinearGradient(
            colors: stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
            startPoint: startPoint.unitPoint,
            endPoint: endPoint.unitPoint
        )
    }

    func cgGradient(in colorSpace: CGColorSpace) -> CGGradient? {
        var components: [CGFloat] = []
        for stop in stops {
            components.append(contentsOf: [CGFloat(stop.red), CGFloat(stop.green), CGFloat(stop.blue), 1.0])
        }
        return CGGradient(
            colorSpace: colorSpace,
            colorComponents: components,
            locations: nil,
            count: stops.count
        )
    }

    static let presets: [GradientPreset] = {
        let tl = UnitPoint2D(x: 0, y: 0)
        let t  = UnitPoint2D(x: 0.5, y: 0)
        let tr = UnitPoint2D(x: 1, y: 0)
        let bl = UnitPoint2D(x: 0, y: 1)
        let br = UnitPoint2D(x: 1, y: 1)

        func s(_ r: Double, _ g: Double, _ b: Double) -> GradientStop {
            GradientStop(red: r, green: g, blue: b)
        }

        return [
            GradientPreset(id: "dawn-fire", name: "Dawn Fire",
                stops: [s(0.98, 0.31, 0.58), s(0.40, 0.32, 0.95), s(0.29, 0.84, 0.80)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "deep-ocean", name: "Deep Ocean",
                stops: [s(0.04, 0.05, 0.50), s(0.26, 0.19, 0.93), s(0.42, 0.67, 0.98)],
                startPoint: t, endPoint: br),
            GradientPreset(id: "coral-bloom", name: "Coral Bloom",
                stops: [s(0.98, 0.38, 0.36), s(0.99, 0.71, 0.36), s(0.90, 0.33, 0.65)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "arctic-lens", name: "Arctic Lens",
                stops: [s(0.87, 0.95, 0.94), s(0.46, 0.77, 0.86), s(0.25, 0.53, 0.93)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "neon-pulse", name: "Neon Pulse",
                stops: [s(0.08, 0.02, 0.22), s(0.35, 0.12, 0.84), s(0.95, 0.26, 0.42)],
                startPoint: tr, endPoint: bl),
            GradientPreset(id: "ripe-mango", name: "Ripe Mango",
                stops: [s(0.99, 0.75, 0.20), s(0.96, 0.33, 0.21), s(0.67, 0.19, 0.89)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "soft-linen", name: "Soft Linen",
                stops: [s(0.94, 0.94, 0.92), s(0.80, 0.88, 0.94), s(0.95, 0.76, 0.70)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "tidal-pool", name: "Tidal Pool",
                stops: [s(0.08, 0.30, 0.54), s(0.25, 0.64, 0.72), s(0.70, 0.92, 0.78)],
                startPoint: bl, endPoint: tr),
            GradientPreset(id: "forge", name: "Forge",
                stops: [s(0.18, 0.03, 0.08), s(0.86, 0.17, 0.18), s(1.00, 0.67, 0.25)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "twilight", name: "Twilight",
                stops: [s(0.24, 0.08, 0.51), s(0.59, 0.22, 0.94), s(0.96, 0.42, 0.74)],
                startPoint: t, endPoint: br),
            GradientPreset(id: "lagoon", name: "Lagoon",
                stops: [s(0.43, 0.86, 0.75), s(0.25, 0.62, 0.80), s(0.22, 0.35, 0.75)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "orchard", name: "Orchard",
                stops: [s(0.99, 0.91, 0.30), s(0.44, 0.78, 0.29), s(0.12, 0.58, 0.42)],
                startPoint: tr, endPoint: bl),
            GradientPreset(id: "gemstone", name: "Gemstone",
                stops: [s(0.10, 0.08, 0.28), s(0.35, 0.15, 0.65), s(0.76, 0.39, 0.95)],
                startPoint: bl, endPoint: tr),
            GradientPreset(id: "sherbet", name: "Sherbet",
                stops: [s(1.00, 0.49, 0.51), s(1.00, 0.74, 0.48), s(0.56, 0.78, 0.98)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "granite", name: "Granite",
                stops: [s(0.93, 0.96, 0.95), s(0.64, 0.72, 0.82), s(0.33, 0.42, 0.55)],
                startPoint: tl, endPoint: br),
            GradientPreset(id: "sunrise", name: "Sunrise",
                stops: [s(0.98, 0.62, 0.77), s(0.98, 0.82, 0.47), s(0.42, 0.71, 0.96)],
                startPoint: bl, endPoint: tr),
        ]
    }()
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
