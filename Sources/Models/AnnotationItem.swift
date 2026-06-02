import Foundation
import CoreGraphics

enum AnnotationTool: String, Codable, CaseIterable {
    case select
    case rectangle
    case filledRect
    case ellipse
    case line
    case arrow
    case freehand
    case numberedBadge
    case text
    case pixelate
    case blur
}

extension AnnotationTool {
    var usesEndpoints: Bool {
        switch self {
        case .line, .arrow, .freehand: return true
        default: return false
        }
    }

    var isRedactionTool: Bool {
        self == .pixelate || self == .blur
    }

    var createsAnnotation: Bool {
        self != .select
    }
}

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
        ColorSwatch(red: 0.94, green: 0.22, blue: 0.24),
        ColorSwatch(red: 0.96, green: 0.52, blue: 0.14),
        ColorSwatch(red: 0.95, green: 0.72, blue: 0.20),
        ColorSwatch(red: 0.22, green: 0.60, blue: 0.34),
        ColorSwatch(red: 0.20, green: 0.48, blue: 0.86),
        ColorSwatch(red: 0.46, green: 0.24, blue: 0.88),
        ColorSwatch(red: 0.92, green: 0.36, blue: 0.58),
        ColorSwatch(red: 0.05, green: 0.05, blue: 0.05),
        ColorSwatch(red: 0.95, green: 0.95, blue: 0.93),
    ]
}

enum StrokeWidth: CGFloat, CaseIterable, Codable {
    case thin = 2
    case light = 4
    case medium = 6
    case heavy = 8
    case bold = 12

    var label: String { "\(Int(rawValue))" }
}

struct AnnotationItem: Identifiable, Equatable, Codable {
    let id: UUID
    var tool: AnnotationTool
    var rect: CGRect
    var points: [CGPoint]
    var swatch: ColorSwatch
    var strokeWidth: CGFloat

    var text: String
    var fontSize: CGFloat
    var isBold: Bool

    var badgeNumber: Int
    var redactionDensity: CGFloat

    init(
        tool: AnnotationTool,
        rect: CGRect = .zero,
        points: [CGPoint] = [],
        swatch: ColorSwatch = .presets[0],
        strokeWidth: CGFloat = 4,
        text: String = "",
        fontSize: CGFloat = 16,
        isBold: Bool = false,
        badgeNumber: Int = 1,
        redactionDensity: CGFloat = 10
    ) {
        self.id = UUID()
        self.tool = tool
        self.rect = rect
        self.points = points
        self.swatch = swatch
        self.strokeWidth = strokeWidth
        self.text = text
        self.fontSize = fontSize
        self.isBold = isBold
        self.badgeNumber = badgeNumber
        self.redactionDensity = redactionDensity
    }
}
