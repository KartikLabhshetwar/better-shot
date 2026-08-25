import AppKit
import Foundation

/// The shape model, ported from the drawing-app's `Model/Shape.swift` and widened to cover the
/// tools BetterShot has that a whiteboard doesn't (redactions, the spotlight highlight, numbered
/// callouts).
///
/// Page space is the screenshot's own pixel space: y-down, origin at the image's top-left, one
/// unit per image pixel. That makes export a 1:1 draw and lets the canvas be a pure camera on top,
/// which is what gives every tool the same rotate/resize behaviour for free.
struct AnnoShapeID: Hashable, Codable {
    let raw: String
    init(_ raw: String = UUID().uuidString) { self.raw = raw }
}

// MARK: - Styles

/// Dash styles. BetterShot draws clean strokes, so `solid` is the default; the engine keeps the
/// others because arrows and geo share one stroke path.
enum DashStyle: String, CaseIterable, Codable {
    case draw
    case solid
    case dashed
    case dotted

    var label: String { rawValue.capitalized }
}

/// How a geo shape's interior is painted.
enum AnnoFillStyle: String, CaseIterable, Codable {
    case none
    case solid

    var label: String { self == .none ? "Outline" : "Solid" }
}

enum GeoKind: String, CaseIterable, Codable {
    case rectangle
    case ellipse

    var label: String { rawValue.capitalized }
}

// MARK: - Props

struct GeoProps: Codable, Equatable {
    var geo: GeoKind = .rectangle
    var w: Double = 100
    var h: Double = 100
    var swatch: AnnotationSwatch = .red
    /// Stroke width in page (image pixel) units, so resizing never changes it.
    var strokeWidth: Double = 8
    var fill: AnnoFillStyle = .none
    var dash: DashStyle = .solid
    /// Corner rounding for rectangles, in page units. Ellipses ignore it.
    var cornerRadius: Double = 0
}

struct DrawProps: Codable, Equatable {
    /// Points in the shape's local space; `z` carries pressure.
    var points: [Vec] = []
    var isComplete = false
    var isPen = false
    var isClosed = false
    var swatch: AnnotationSwatch = .red
    var strokeWidth: Double = 8
}

enum Arrowhead: String, CaseIterable, Codable {
    case none
    case arrow
    case triangle
    case square
    case dot
    case diamond
    case inverted
    case bar
}

struct ArrowProps: Codable, Equatable {
    /// Terminals in the shape's local space. When a terminal is bound to another shape, the bound
    /// position wins and this is only a fallback.
    var start = Vec(0, 0)
    var end = Vec(100, 0)
    /// How far the arrow bows out from the straight line between its terminals.
    var bend: Double = 0
    var arrowheadStart: Arrowhead = .none
    var arrowheadEnd: Arrowhead = .arrow
    var swatch: AnnotationSwatch = .red
    var strokeWidth: Double = 8
    var dash: DashStyle = .solid
}

enum TextAlign: String, CaseIterable, Codable {
    case start
    case middle
    case end

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .start: .left
        case .middle: .center
        case .end: .right
        }
    }

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center: self = .middle
        case .right: self = .end
        default: self = .start
        }
    }
}

struct TextProps: Codable, Equatable, Hashable {
    var text: String = ""
    var swatch: AnnotationSwatch = .red
    /// Point size in page (image pixel) units.
    var fontSize: Double = 48
    var fontFamily: AnnoFontFamily = .pro
    var isBold = true
    var isItalic = false
    var isUnderline = false
    var align: TextAlign = .start
    /// The box's width. Meaningful only when `autoSize` is false, where text wraps into it.
    var w: Double = 16
    /// While true the box is exactly as wide as its text. Dragging a side handle turns it off,
    /// which is how text switches from growing to wrapping.
    var autoSize = true
}

enum RedactionKind: String, CaseIterable, Codable {
    case blur
    case pixelate
}

struct RedactionProps: Codable, Equatable {
    var kind: RedactionKind = .blur
    var w: Double = 100
    var h: Double = 100
    /// 0...1; drives blur radius and pixel block size.
    var density: Double = 0.55
}

struct HighlightProps: Codable, Equatable {
    var w: Double = 100
    var h: Double = 100
}

struct NumberedProps: Codable, Equatable {
    var value: Int = 1
    var diameter: Double = 64
    var swatch: AnnotationSwatch = .red
}

// MARK: - Shape

enum AnnoShapeKind: Codable, Equatable {
    case geo(GeoProps)
    case draw(DrawProps)
    case arrow(ArrowProps)
    case text(TextProps)
    case redaction(RedactionProps)
    case highlight(HighlightProps)
    case numbered(NumberedProps)
}

struct AnnoShape: Codable, Equatable, Identifiable {
    var id: AnnoShapeID
    /// Position of the shape's local origin, in page space.
    var x: Double
    var y: Double
    var rotation: Double = 0
    /// 0...1, applied to the whole shape when drawn.
    var opacity: Double = 1
    var kind: AnnoShapeKind

    init(
        id: AnnoShapeID = AnnoShapeID(),
        x: Double,
        y: Double,
        rotation: Double = 0,
        opacity: Double = 1,
        kind: AnnoShapeKind
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.rotation = rotation
        self.opacity = opacity
        self.kind = kind
    }

    var pageTransform: Mat {
        Mat.compose(x: x, y: y, rotation: rotation)
    }

    var strokeWidth: Double {
        switch kind {
        case let .geo(p): p.strokeWidth
        case let .draw(p): p.strokeWidth
        case let .arrow(p): p.strokeWidth
        case .text, .redaction, .highlight, .numbered: 0
        }
    }

    /// The tool this shape belongs to, for the inspector and the style presets.
    var tool: AnnotationTool {
        switch kind {
        case let .geo(p):
            switch (p.geo, p.fill) {
            case (.rectangle, .none): .rectangle
            case (.rectangle, .solid): .filledRectangle
            case (.ellipse, _): .ellipse
            }
        case .draw: .freehand
        case let .arrow(p):
            p.arrowheadStart == .none && p.arrowheadEnd == .none ? .line : .arrow
        case .text: .text
        case let .redaction(p): p.kind == .blur ? .blur : .pixelate
        case .highlight: .highlight
        case .numbered: .numberedCircle
        }
    }

    var swatch: AnnotationSwatch? {
        switch kind {
        case let .geo(p): p.swatch
        case let .draw(p): p.swatch
        case let .arrow(p): p.swatch
        case let .text(p): p.swatch
        case let .numbered(p): p.swatch
        case .redaction, .highlight: nil
        }
    }

    /// Whether a click anywhere inside the shape grabs it, as opposed to only its outline.
    var isFilled: Bool {
        switch kind {
        case let .geo(p): p.fill != .none
        case let .draw(p): p.isClosed
        case .arrow: false
        // Text, redactions, the highlight and numbered callouts are solid objects.
        case .text, .redaction, .highlight, .numbered: true
        }
    }

    var isArrow: Bool {
        if case .arrow = kind { return true }
        return false
    }

    var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    var isRedaction: Bool {
        if case .redaction = kind { return true }
        return false
    }

    var isHighlight: Bool {
        if case .highlight = kind { return true }
        return false
    }

    var geoProps: GeoProps? {
        if case let .geo(p) = kind { return p }
        return nil
    }

    var drawProps: DrawProps? {
        if case let .draw(p) = kind { return p }
        return nil
    }

    var arrowProps: ArrowProps? {
        if case let .arrow(p) = kind { return p }
        return nil
    }

    var textProps: TextProps? {
        if case let .text(p) = kind { return p }
        return nil
    }

    var redactionProps: RedactionProps? {
        if case let .redaction(p) = kind { return p }
        return nil
    }

    var numberedProps: NumberedProps? {
        if case let .numbered(p) = kind { return p }
        return nil
    }
}

// MARK: - Bindings

enum ArrowTerminal: String, Codable {
    case start
    case end
}

/// A binding between an arrow terminal and a shape.
struct ArrowBinding: Codable, Equatable {
    var arrowId: AnnoShapeID
    var toId: AnnoShapeID
    var terminal: ArrowTerminal
    /// Where on the bound shape's bounds the terminal points, in 0...1 of its width and height.
    var normalizedAnchor: Vec
    /// When false the terminal snaps to the shape's center rather than the anchor.
    var isPrecise: Bool
    /// When true the arrow stops exactly at the terminal rather than at the shape's edge.
    var isExact: Bool
}

// MARK: - Codable support

extension AnnotationSwatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, red, green, blue, alpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            red: try container.decode(CGFloat.self, forKey: .red),
            green: try container.decode(CGFloat.self, forKey: .green),
            blue: try container.decode(CGFloat.self, forKey: .blue),
            alpha: try container.decodeIfPresent(CGFloat.self, forKey: .alpha) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }
}
