//
//  AnnotationBackground.swift
//  BetterShot
//
//  Created by Codex on 28/04/26.
//

import AppKit
import CoreGraphics
import SwiftUI

struct AnnotationBackgroundSettings: Equatable {
    var style: AnnotationBackgroundStyle = .none
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.018
    var shadow: CGFloat = 0.36
    var shadowStyle: AnnotationShadowStyle = .soft
    var border = AnnotationScreenshotBorderSettings()
    var aspectRatio: AnnotationBackgroundAspectRatio = .auto
    var alignment: AnnotationBackgroundAlignment = .center
    var customWallpaper: AnnotationCustomWallpaper?
    var camera = AnnotationCameraSettings()
    var progressiveBlur = AnnotationProgressiveBlurSettings()
    var watermark = AnnotationWatermarkSettings()

    var isEnabled: Bool {
        style != .none
    }

    /// Camera transforms and scene blur need a stage even without an explicit
    /// background so their pixels have transparent breathing room instead of
    /// being cropped to the original screenshot bounds.
    var usesCanvasLayout: Bool {
        isEnabled
            || camera.hasEffect
            || (progressiveBlur.isActive && progressiveBlur.edgeMode == .bleed)
    }

    /// An outer screenshot border needs a canvas large enough to preserve the
    /// ring even when no fill, camera transform, or scene blur is active.
    var requiresCanvasLayout: Bool {
        usesCanvasLayout || border.isVisible
    }

    /// Once the card leaves the flat plane, "stuck" edges no longer describe
    /// the projected geometry. Camera pan replaces alignment for that mode.
    var effectiveCanvasAlignment: AnnotationBackgroundAlignment {
        camera.hasEffect || !usesCanvasLayout ? .center : alignment
    }

    var hasRenderableContent: Bool {
        isEnabled
            || camera.hasEffect
            || progressiveBlur.isActive
            || border.isVisible
            || watermark.isVisible
    }
}

struct AnnotationScreenshotBorderSettings: Equatable {
    var isEnabled = false
    var color: AnnotationSwatch = .white
    /// Thickness as a fraction of the screenshot's shortest edge so saved
    /// presets keep the same visual weight across different capture sizes.
    var thickness: CGFloat = 0.012
    var opacity: CGFloat = 1

    var isVisible: Bool {
        isEnabled && thickness > 0.0001 && opacity > 0.0001
    }

    func pixelThickness(for imageSize: CGSize) -> CGFloat {
        guard isVisible, imageSize.width > 0, imageSize.height > 0 else { return 0 }
        return max(0, thickness) * min(imageSize.width, imageSize.height)
    }
}

struct AnnotationCameraSettings: Equatable {
    /// Translation as a fraction of the final canvas dimensions.
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    /// Horizontal/vertical camera orbit around the card center, in degrees.
    var tiltXDegrees: CGFloat = 0
    var tiltYDegrees: CGFloat = 0
    /// Local card rotation around its horizontal and vertical axes.
    var rotationXDegrees: CGFloat = 0
    var rotationYDegrees: CGFloat = 0
    /// Rotation around the viewing axis.
    var rollDegrees: CGFloat = 0
    /// Lens angle controlling the strength of perspective.
    var fieldOfViewDegrees: CGFloat = 24
    /// Explicit final scale around the card center. Rotation never changes it.
    var zoom: CGFloat = 1
    /// Version 1 used shear-based Tilt and hidden angle-dependent auto-fit.
    /// Version 2 uses center-origin camera orbit and explicit-only Zoom.
    var projectionVersion: Int = 2

    var isDefault: Bool {
        let defaultFieldOfView: CGFloat = projectionVersion < 2 ? 45 : 24
        return isApproximatelyZero(panX)
            && isApproximatelyZero(panY)
            && isApproximatelyZero(tiltXDegrees)
            && isApproximatelyZero(tiltYDegrees)
            && isApproximatelyZero(rotationXDegrees)
            && isApproximatelyZero(rotationYDegrees)
            && isApproximatelyZero(rollDegrees)
            && abs(fieldOfViewDegrees - defaultFieldOfView) <= 0.0001
            && abs(zoom - 1) <= 0.0001
    }

    var hasEffect: Bool {
        !isApproximatelyZero(panX)
            || !isApproximatelyZero(panY)
            || !isApproximatelyZero(tiltXDegrees)
            || !isApproximatelyZero(tiltYDegrees)
            || !isApproximatelyZero(rotationXDegrees)
            || !isApproximatelyZero(rotationYDegrees)
            || !isApproximatelyZero(rollDegrees)
            || abs(zoom - 1) > 0.0001
    }

    private func isApproximatelyZero(_ value: CGFloat) -> Bool {
        abs(value) <= 0.0001
    }

    mutating func upgradeProjectionIfNeeded() {
        guard projectionVersion < 2 else { return }
        projectionVersion = 2
        if abs(fieldOfViewDegrees - 45) <= 0.0001 {
            fieldOfViewDegrees = 24
        }
    }
}

enum AnnotationProgressiveBlurMode: String, CaseIterable, Identifiable, Sendable {
    case radial
    case directional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radial: "Radial"
        case .directional: "Directional"
        }
    }
}

enum AnnotationProgressiveBlurEdgeMode: String, CaseIterable, Identifiable, Sendable {
    case clipped
    case bleed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipped: "Screenshot"
        case .bleed: "Scene"
        }
    }
}

struct AnnotationProgressiveBlurSettings: Equatable, Sendable {
    var isEnabled = false
    var edgeMode: AnnotationProgressiveBlurEdgeMode = .bleed
    var mode: AnnotationProgressiveBlurMode = .radial
    /// Maximum blur radius, normalized by the preview/export scale at render time.
    var strength: CGFloat = 18
    /// Width of the transition from sharp to blurred, normalized to 0...1.
    var falloff: CGFloat = 0.55
    /// Size of the sharp focal area, normalized from a small detail to the
    /// farthest image edge. A larger default keeps the screenshot as the hero.
    var focusSize: CGFloat = 0.45
    /// Top-left-origin normalized focal point within the active blur layer.
    var focusPosition = CGPoint(x: 0.5, y: 0.5)
    /// Direction of the in-focus band. Zero degrees is horizontal.
    var directionDegrees: CGFloat = 0

    var isActive: Bool {
        isEnabled && strength > 0.01
    }
}

enum AnnotationBackgroundStyle: Equatable {
    case none
    case solid(AnnotationBackgroundColor)
    case gradient(AnnotationBackgroundGradient)
    case customWallpaper(AnnotationCustomWallpaper)
}

struct AnnotationBackgroundColor: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ id: String, title: String, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.id = id
        self.title = title
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let black = AnnotationBackgroundColor("black", title: "Black", red: 0.02, green: 0.02, blue: 0.024)
    static let white = AnnotationBackgroundColor("white", title: "White", red: 0.96, green: 0.96, blue: 0.94)
    static let graphite = AnnotationBackgroundColor("graphite", title: "Graphite", red: 0.17, green: 0.18, blue: 0.21)
    static let red = AnnotationBackgroundColor("red", title: "Red", red: 0.94, green: 0.23, blue: 0.28)
    static let orange = AnnotationBackgroundColor("orange", title: "Orange", red: 0.97, green: 0.52, blue: 0.16)
    static let yellow = AnnotationBackgroundColor("yellow", title: "Yellow", red: 0.96, green: 0.73, blue: 0.23)
    static let green = AnnotationBackgroundColor("green", title: "Green", red: 0.23, green: 0.61, blue: 0.36)
    static let blue = AnnotationBackgroundColor("blue", title: "Blue", red: 0.16, green: 0.50, blue: 0.88)
    static let purple = AnnotationBackgroundColor("purple", title: "Purple", red: 0.48, green: 0.26, blue: 0.91)
    static let blush = AnnotationBackgroundColor("blush", title: "Blush", red: 0.93, green: 0.66, blue: 0.62)
    static let mint = AnnotationBackgroundColor("mint", title: "Mint", red: 0.66, green: 0.90, blue: 0.73)
    static let sky = AnnotationBackgroundColor("sky", title: "Sky", red: 0.63, green: 0.79, blue: 0.94)
    static let lavender = AnnotationBackgroundColor("lavender", title: "Lavender", red: 0.80, green: 0.76, blue: 0.92)
    static let peach = AnnotationBackgroundColor("peach", title: "Peach", red: 0.98, green: 0.80, blue: 0.69)
    static let sage = AnnotationBackgroundColor("sage", title: "Sage", red: 0.74, green: 0.82, blue: 0.70)
    static let sand = AnnotationBackgroundColor("sand", title: "Sand", red: 0.91, green: 0.87, blue: 0.76)

    static let plainPresets: [AnnotationBackgroundColor] = [
        .black, .white, .graphite, .red, .orange, .yellow,
        .green, .blue, .purple, .blush, .mint, .sky,
        .lavender, .peach, .sage, .sand
    ]
}

struct AnnotationBackgroundGradient: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let colors: [AnnotationBackgroundColor]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    static let presets: [AnnotationBackgroundGradient] = [
        AnnotationBackgroundGradient(
            id: "aurora",
            title: "Aurora",
            colors: [
                AnnotationBackgroundColor("aurora-a", title: "Aurora A", red: 0.98, green: 0.31, blue: 0.58),
                AnnotationBackgroundColor("aurora-b", title: "Aurora B", red: 0.40, green: 0.32, blue: 0.95),
                AnnotationBackgroundColor("aurora-c", title: "Aurora C", red: 0.29, green: 0.84, blue: 0.80)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "cobalt",
            title: "Cobalt",
            colors: [
                AnnotationBackgroundColor("cobalt-a", title: "Cobalt A", red: 0.04, green: 0.05, blue: 0.50),
                AnnotationBackgroundColor("cobalt-b", title: "Cobalt B", red: 0.26, green: 0.19, blue: 0.93),
                AnnotationBackgroundColor("cobalt-c", title: "Cobalt C", red: 0.42, green: 0.67, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "peach",
            title: "Peach",
            colors: [
                AnnotationBackgroundColor("peach-a", title: "Peach A", red: 0.98, green: 0.38, blue: 0.36),
                AnnotationBackgroundColor("peach-b", title: "Peach B", red: 0.99, green: 0.71, blue: 0.36),
                AnnotationBackgroundColor("peach-c", title: "Peach C", red: 0.90, green: 0.33, blue: 0.65)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "glass",
            title: "Glass",
            colors: [
                AnnotationBackgroundColor("glass-a", title: "Glass A", red: 0.87, green: 0.95, blue: 0.94),
                AnnotationBackgroundColor("glass-b", title: "Glass B", red: 0.46, green: 0.77, blue: 0.86),
                AnnotationBackgroundColor("glass-c", title: "Glass C", red: 0.25, green: 0.53, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "plasma",
            title: "Plasma",
            colors: [
                AnnotationBackgroundColor("plasma-a", title: "Plasma A", red: 0.08, green: 0.02, blue: 0.22),
                AnnotationBackgroundColor("plasma-b", title: "Plasma B", red: 0.35, green: 0.12, blue: 0.84),
                AnnotationBackgroundColor("plasma-c", title: "Plasma C", red: 0.95, green: 0.26, blue: 0.42)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        ),
        AnnotationBackgroundGradient(
            id: "mango",
            title: "Mango",
            colors: [
                AnnotationBackgroundColor("mango-a", title: "Mango A", red: 0.99, green: 0.75, blue: 0.20),
                AnnotationBackgroundColor("mango-b", title: "Mango B", red: 0.96, green: 0.33, blue: 0.21),
                AnnotationBackgroundColor("mango-c", title: "Mango C", red: 0.67, green: 0.19, blue: 0.89)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "mist",
            title: "Mist",
            colors: [
                AnnotationBackgroundColor("mist-a", title: "Mist A", red: 0.94, green: 0.94, blue: 0.92),
                AnnotationBackgroundColor("mist-b", title: "Mist B", red: 0.80, green: 0.88, blue: 0.94),
                AnnotationBackgroundColor("mist-c", title: "Mist C", red: 0.95, green: 0.76, blue: 0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "lagoon",
            title: "Lagoon",
            colors: [
                AnnotationBackgroundColor("lagoon-a", title: "Lagoon A", red: 0.08, green: 0.30, blue: 0.54),
                AnnotationBackgroundColor("lagoon-b", title: "Lagoon B", red: 0.25, green: 0.64, blue: 0.72),
                AnnotationBackgroundColor("lagoon-c", title: "Lagoon C", red: 0.70, green: 0.92, blue: 0.78)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        ),
        AnnotationBackgroundGradient(
            id: "ember",
            title: "Ember",
            colors: [
                AnnotationBackgroundColor("ember-a", title: "Ember A", red: 0.18, green: 0.03, blue: 0.08),
                AnnotationBackgroundColor("ember-b", title: "Ember B", red: 0.86, green: 0.17, blue: 0.18),
                AnnotationBackgroundColor("ember-c", title: "Ember C", red: 1.00, green: 0.67, blue: 0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "violet",
            title: "Violet",
            colors: [
                AnnotationBackgroundColor("violet-a", title: "Violet A", red: 0.24, green: 0.08, blue: 0.51),
                AnnotationBackgroundColor("violet-b", title: "Violet B", red: 0.59, green: 0.22, blue: 0.94),
                AnnotationBackgroundColor("violet-c", title: "Violet C", red: 0.96, green: 0.42, blue: 0.74)
            ],
            startPoint: .top,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "seaglass",
            title: "Sea Glass",
            colors: [
                AnnotationBackgroundColor("seaglass-a", title: "Sea Glass A", red: 0.43, green: 0.86, blue: 0.75),
                AnnotationBackgroundColor("seaglass-b", title: "Sea Glass B", red: 0.25, green: 0.62, blue: 0.80),
                AnnotationBackgroundColor("seaglass-c", title: "Sea Glass C", red: 0.22, green: 0.35, blue: 0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "citrus",
            title: "Citrus",
            colors: [
                AnnotationBackgroundColor("citrus-a", title: "Citrus A", red: 0.99, green: 0.91, blue: 0.30),
                AnnotationBackgroundColor("citrus-b", title: "Citrus B", red: 0.44, green: 0.78, blue: 0.29),
                AnnotationBackgroundColor("citrus-c", title: "Citrus C", red: 0.12, green: 0.58, blue: 0.42)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        ),
        AnnotationBackgroundGradient(
            id: "amethyst",
            title: "Amethyst",
            colors: [
                AnnotationBackgroundColor("amethyst-a", title: "Amethyst A", red: 0.10, green: 0.08, blue: 0.28),
                AnnotationBackgroundColor("amethyst-b", title: "Amethyst B", red: 0.35, green: 0.15, blue: 0.65),
                AnnotationBackgroundColor("amethyst-c", title: "Amethyst C", red: 0.76, green: 0.39, blue: 0.95)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        ),
        AnnotationBackgroundGradient(
            id: "sorbet",
            title: "Sorbet",
            colors: [
                AnnotationBackgroundColor("sorbet-a", title: "Sorbet A", red: 1.00, green: 0.49, blue: 0.51),
                AnnotationBackgroundColor("sorbet-b", title: "Sorbet B", red: 1.00, green: 0.74, blue: 0.48),
                AnnotationBackgroundColor("sorbet-c", title: "Sorbet C", red: 0.56, green: 0.78, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "mineral",
            title: "Mineral",
            colors: [
                AnnotationBackgroundColor("mineral-a", title: "Mineral A", red: 0.93, green: 0.96, blue: 0.95),
                AnnotationBackgroundColor("mineral-b", title: "Mineral B", red: 0.64, green: 0.72, blue: 0.82),
                AnnotationBackgroundColor("mineral-c", title: "Mineral C", red: 0.33, green: 0.42, blue: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        AnnotationBackgroundGradient(
            id: "dawn",
            title: "Dawn",
            colors: [
                AnnotationBackgroundColor("dawn-a", title: "Dawn A", red: 0.98, green: 0.62, blue: 0.77),
                AnnotationBackgroundColor("dawn-b", title: "Dawn B", red: 0.98, green: 0.82, blue: 0.47),
                AnnotationBackgroundColor("dawn-c", title: "Dawn C", red: 0.42, green: 0.71, blue: 0.96)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    ]
}

struct AnnotationCustomWallpaper: Identifiable, Equatable, Hashable {
    let url: URL

    var id: String {
        url.path
    }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct AnnotationWatermarkSettings: Equatable {
    var isEnabled = false
    var text = ""
    var density: CGFloat = 4
    var fontSize: CGFloat = 72
    var rotationDegrees: CGFloat = 45
    var opacity: CGFloat = 0.18
    var color: AnnotationWatermarkColor = .mercury

    var isVisible: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && opacity > 0
    }
}

enum AnnotationWatermarkTypography {
    private static let compactFontNames = [
        "SFCompact-Semibold",
        "SFCompactDisplay-Semibold",
        "SFCompactText-Semibold"
    ]

    private static let compactFontName = compactFontNames.first {
        NSFont(name: $0, size: 12) != nil
    }

    static func font(size: CGFloat) -> Font {
        let clampedSize = max(1, size)
        guard let compactFontName else {
            return .system(size: clampedSize, weight: .semibold)
        }

        return .custom(compactFontName, size: clampedSize)
    }

    static func nsFont(size: CGFloat) -> NSFont {
        let clampedSize = max(1, size)
        guard let compactFontName,
              let font = NSFont(name: compactFontName, size: clampedSize) else {
            return NSFont.systemFont(ofSize: clampedSize, weight: .semibold)
        }

        return font
    }
}

struct AnnotationWatermarkColor: Equatable, Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let mercury = AnnotationWatermarkColor(red: 0.90, green: 0.90, blue: 0.90)
    static let white = AnnotationWatermarkColor(red: 0.96, green: 0.96, blue: 0.96)

    static func custom(from color: Color) -> AnnotationWatermarkColor {
        custom(from: NSColor(color))
    }

    static func custom(from nsColor: NSColor) -> AnnotationWatermarkColor {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return AnnotationWatermarkColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }
}

enum AnnotationBackgroundAspectRatio: String, CaseIterable, Identifiable {
    case auto
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    var value: CGFloat? {
        switch self {
        case .auto: nil
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        }
    }
}

enum AnnotationBackgroundAlignment: String, CaseIterable, Identifiable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .top: "Top"
        case .topTrailing: "Top right"
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        case .bottomLeading: "Bottom left"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom right"
        }
    }

    var xFactor: CGFloat {
        switch self {
        case .topLeading, .leading, .bottomLeading:
            0
        case .top, .center, .bottom:
            0.5
        case .topTrailing, .trailing, .bottomTrailing:
            1
        }
    }

    var yFactor: CGFloat {
        switch self {
        case .topLeading, .top, .topTrailing:
            0
        case .leading, .center, .trailing:
            0.5
        case .bottomLeading, .bottom, .bottomTrailing:
            1
        }
    }

    /// Whether the image sticks to the top edge (zero top padding).
    var sticksToTop: Bool {
        switch self {
        case .topLeading, .top, .topTrailing: true
        default: false
        }
    }

    /// Whether the image sticks to the bottom edge (zero bottom padding).
    var sticksToBottom: Bool {
        switch self {
        case .bottomLeading, .bottom, .bottomTrailing: true
        default: false
        }
    }

    /// Whether the image sticks to the leading (left) edge (zero left padding).
    var sticksToLeading: Bool {
        switch self {
        case .topLeading, .leading, .bottomLeading: true
        default: false
        }
    }

    /// Whether the image sticks to the trailing (right) edge (zero right padding).
    var sticksToTrailing: Bool {
        switch self {
        case .topTrailing, .trailing, .bottomTrailing: true
        default: false
        }
    }

    /// Per-corner radius multipliers. A corner that touches a stuck edge gets 0.
    /// Returns (topLeft, topRight, bottomLeft, bottomRight) multipliers (0 or 1).
    var cornerRadiusMultipliers: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        switch self {
        case .center:
            (1, 1, 1, 1)
        case .top:
            (0, 0, 1, 1)
        case .bottom:
            (1, 1, 0, 0)
        case .leading:
            (0, 1, 0, 1)
        case .trailing:
            (1, 0, 1, 0)
        case .topLeading:
            (0, 0, 0, 1)
        case .topTrailing:
            (0, 0, 1, 0)
        case .bottomLeading:
            (0, 1, 0, 0)
        case .bottomTrailing:
            (1, 0, 0, 0)
        }
    }
}

extension BeautifierConfig {
    var annotationStyle: AnnotationBackgroundStyle {
        switch style {
        case .none:
            return .none
        case .solid(let color):
            return .solid(AnnotationBackgroundColor(
                color.id,
                title: color.name,
                red: color.red,
                green: color.green,
                blue: color.blue
            ))
        case .gradient(let preset):
            let colors = preset.stops.enumerated().map { index, stop in
                AnnotationBackgroundColor(
                    "\(preset.id)-\(index)",
                    title: preset.name,
                    red: stop.red,
                    green: stop.green,
                    blue: stop.blue
                )
            }
            return .gradient(AnnotationBackgroundGradient(
                id: preset.id,
                title: preset.name,
                colors: colors,
                startPoint: preset.startPoint.unitPoint,
                endPoint: preset.endPoint.unitPoint
            ))
        case .wallpaper(let source):
            return .customWallpaper(AnnotationCustomWallpaper(url: URL(fileURLWithPath: source.path)))
        case .bundledImage(let assetID):
            guard let url = BundledBackgrounds.asset(byID: assetID)?.url else { return .none }
            return .customWallpaper(AnnotationCustomWallpaper(url: url))
        }
    }

    var annotationBackgroundSettings: AnnotationBackgroundSettings {
        var settings = AnnotationBackgroundSettings()
        settings.style = annotationStyle
        settings.padding = padding
        settings.cornerRadius = cornerRadius
        settings.shadow = shadowStrength
        settings.alignment = AnnotationBackgroundAlignment(rawValue: alignment.rawValue) ?? .center
        settings.aspectRatio = switch aspectRatio {
        case .auto, .nineSixteen: .auto
        case .square: .square
        case .fourThree: .fourThree
        case .threeTwo: .threeTwo
        case .sixteenNine: .sixteenNine
        }
        if case .customWallpaper(let wallpaper) = settings.style {
            settings.customWallpaper = wallpaper
        }
        return settings
    }
}
