import Foundation
import CoreGraphics

// MARK: - Annotation Tool

enum AnnotationTool: String, Codable, CaseIterable {
    case select
    case rectangle
    case filledRect
    case ellipse
    case line
    case arrow
    case freehand
    case numberedBadge
    case pixelate
    case blur
    case text
}

// MARK: - Color Swatch

struct ColorSwatch: Codable, Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let presets: [ColorSwatch] = [
        ColorSwatch(red: 0.05, green: 0.05, blue: 0.05),
        ColorSwatch(red: 0.92, green: 0.22, blue: 0.24),
        ColorSwatch(red: 0.96, green: 0.52, blue: 0.14),
        ColorSwatch(red: 0.95, green: 0.72, blue: 0.20),
        ColorSwatch(red: 0.22, green: 0.60, blue: 0.34),
        ColorSwatch(red: 0.30, green: 0.72, blue: 0.68),
        ColorSwatch(red: 0.20, green: 0.48, blue: 0.86),
        ColorSwatch(red: 0.46, green: 0.24, blue: 0.88),
        ColorSwatch(red: 0.92, green: 0.36, blue: 0.58),
        ColorSwatch(red: 0.95, green: 0.95, blue: 0.93),
    ]
}

// MARK: - Stroke Width

enum StrokePreset: CGFloat, CaseIterable {
    case thin = 2
    case light = 4
    case medium = 6
    case heavy = 8
    case bold = 12
}

// MARK: - Annotation Item

/// All geometry is normalized (0…1) relative to the image dimensions.
struct AnnotationItem: Identifiable, Equatable, Codable {
    let id: UUID
    var tool: AnnotationTool
    var rect: CGRect
    var points: [CGPoint]
    var swatch: ColorSwatch
    var strokeWidth: CGFloat
    var redactionDensity: CGFloat

    // Text properties
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool

    // Numbered badge
    var badgeNumber: Int

    init(
        tool: AnnotationTool,
        rect: CGRect = .zero,
        points: [CGPoint] = [],
        swatch: ColorSwatch = .presets[0],
        strokeWidth: CGFloat = 4,
        redactionDensity: CGFloat = 0.5,
        text: String = "",
        fontName: String = ".AppleSystemUIFont",
        fontSize: CGFloat = 16,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        badgeNumber: Int = 1
    ) {
        self.id = UUID()
        self.tool = tool
        self.rect = rect
        self.points = points
        self.swatch = swatch
        self.strokeWidth = strokeWidth
        self.redactionDensity = redactionDensity
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.badgeNumber = badgeNumber
    }
}
