import AppKit
import SwiftUI

enum AnnotationResizeHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case start
    case control
    case end

    static var boxCases: [AnnotationResizeHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    static var endpointCases: [AnnotationResizeHandle] {
        [.start, .end]
    }

    static var arrowCases: [AnnotationResizeHandle] {
        [.control, .start, .end]
    }

    static func handles(for tool: AnnotationTool) -> [AnnotationResizeHandle] {
        tool == .arrow ? arrowCases : endpointCases
    }

    func corner(in rect: CGRect) -> CGPoint? {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .start, .control, .end:
            nil
        }
    }

    func oppositeCorner(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight:
            CGPoint(x: rect.minX, y: rect.minY)
        case .start, .control, .end:
            .zero
        }
    }

    func constrainedPoint(_ point: CGPoint, from anchor: CGPoint, minimumSize: CGFloat) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: min(point.x, anchor.x - minimumSize), y: min(point.y, anchor.y - minimumSize))
        case .topRight:
            CGPoint(x: max(point.x, anchor.x + minimumSize), y: min(point.y, anchor.y - minimumSize))
        case .bottomLeft:
            CGPoint(x: min(point.x, anchor.x - minimumSize), y: max(point.y, anchor.y + minimumSize))
        case .bottomRight:
            CGPoint(x: max(point.x, anchor.x + minimumSize), y: max(point.y, anchor.y + minimumSize))
        case .start, .control, .end:
            point
        }
    }

    func point(in item: AnnotationItem) -> CGPoint? {
        switch self {
        case .start:
            item.points.first
        case .control:
            item.arrowCurveHandle
        case .end:
            item.points.last
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            nil
        }
    }
}


enum AnnotationTextMetrics {
    static let minimumFontSize: CGFloat = 9
    static let defaultNormalizedLineHeight: CGFloat = 0.06
    static let defaultFontName: String = "SF Pro"
    static let fontScale: CGFloat = 0.72

    static var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 1.4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    static func viewFontSize(lineHeight: CGFloat, imageFrameHeight: CGFloat) -> CGFloat {
        max(lineHeight * imageFrameHeight * fontScale, minimumFontSize)
    }

    static func renderedFontSize(lineHeight: CGFloat, imagePixelHeight: CGFloat) -> CGFloat {
        max(lineHeight * imagePixelHeight * fontScale, minimumFontSize)
    }

    static func lineCount(for text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        return max(lines.count, 1)
    }

    static func minimumNormalizedWidth(lineHeight: CGFloat, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0.02 }
        let fontSize = renderedFontSize(lineHeight: lineHeight, imagePixelHeight: imageSize.height)
        return max(0.02, (fontSize * 0.5 + 4) / imageSize.width)
    }

    static func resolvedFont(name: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var descriptor: NSFontDescriptor
        if let family = NSFontManager.shared.availableMembers(ofFontFamily: name), !family.isEmpty {
            descriptor = NSFontDescriptor(fontAttributes: [.family: name]).withSize(size)
        } else {
            descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits)
        }

        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

enum AnnotationNumberedCircleMetrics {
    static let normalizedDiameter: CGFloat = 0.039

    static func defaultRect(
        centeredAt point: CGPoint,
        imageSize: CGSize,
        within allowedBounds: CGRect
    ) -> CGRect {
        let height = normalizedDiameter
        let width = imageSize.width > 0
            ? height * max(imageSize.height, 1) / imageSize.width
            : height
        let maxX = max(allowedBounds.minX, allowedBounds.maxX - width)
        let maxY = max(allowedBounds.minY, allowedBounds.maxY - height)

        return CGRect(
            x: min(max(point.x - width / 2, allowedBounds.minX), maxX),
            y: min(max(point.y - height / 2, allowedBounds.minY), maxY),
            width: width,
            height: height
        )
    }

    static func fontSize(for diameter: CGFloat, text: String) -> CGFloat {
        let digitCount = max(text.count, 1)
        let scale: CGFloat
        if digitCount <= 2 {
            scale = 0.54
        } else if digitCount == 3 {
            scale = 0.44
        } else {
            scale = 0.34
        }

        return max(8, diameter * scale)
    }

    static func outlineWidth(for diameter: CGFloat) -> CGFloat {
        max(1, diameter * 0.055)
    }
}

enum AnnotationFilledRectangleMetrics {
    static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(12, max(3, min(rect.width, rect.height) * 0.08))
    }
}


struct AnnotationArrowGeometry {
    let tip: CGPoint
    let shaftControl: CGPoint
    let firstWing: CGPoint
    let secondWing: CGPoint

    init?(start: CGPoint, control: CGPoint, end: CGPoint, lineWidth: CGFloat) {
        let curveLength = Self.approximateCurveLength(start: start, control: control, end: end)
        guard curveLength > 0.5 else { return nil }

        let tangent = Self.tangent(start: start, control: control, end: end)
        let tangentLength = hypot(tangent.x, tangent.y)
        guard tangentLength > 0.5 else { return nil }

        let direction = CGPoint(x: tangent.x / tangentLength, y: tangent.y / tangentLength)
        let backwardDirection = CGPoint(x: -direction.x, y: -direction.y)
        let headLength = min(max(13, lineWidth * 4.4), curveLength * 0.34)
        let headAngle = CGFloat.pi * 0.2
        let firstDirection = Self.rotate(backwardDirection, by: headAngle)
        let secondDirection = Self.rotate(backwardDirection, by: -headAngle)

        tip = end
        shaftControl = control
        firstWing = CGPoint(
            x: end.x + firstDirection.x * headLength,
            y: end.y + firstDirection.y * headLength
        )
        secondWing = CGPoint(
            x: end.x + secondDirection.x * headLength,
            y: end.y + secondDirection.y * headLength
        )
    }

    private static func approximateCurveLength(start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
        var length: CGFloat = 0
        var previous = start

        for step in 1...24 {
            let point = quadraticPoint(start: start, control: control, end: end, t: CGFloat(step) / 24)
            length += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
        }

        return length
    }

    private static func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let first = lerp(start, control, t)
        let second = lerp(control, end, t)
        return lerp(first, second, t)
    }

    private static func tangent(start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let tangent = CGPoint(
            x: 2 * (end.x - control.x),
            y: 2 * (end.y - control.y)
        )

        if hypot(tangent.x, tangent.y) > 0.5 {
            return tangent
        }

        return CGPoint(
            x: end.x - start.x,
            y: end.y - start.y
        )
    }

    private static func rotate(_ point: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x * cos(angle) - point.y * sin(angle),
            y: point.x * sin(angle) + point.y * cos(angle)
        )
    }

    private static func lerp(_ lhs: CGPoint, _ rhs: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(
            x: lhs.x + (rhs.x - lhs.x) * t,
            y: lhs.y + (rhs.y - lhs.y) * t
        )
    }
}


struct AnnotationItem: Identifiable, Equatable {
    let id: UUID
    var tool: AnnotationTool
    var rect: CGRect
    var points: [CGPoint]
    var swatch: AnnotationSwatch
    var strokeWidth: CGFloat
    var redactionDensity: CGFloat
    var text: String
    var textLineHeight: CGFloat
    var fontName: String
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    var textAlignment: NSTextAlignment

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        rect: CGRect,
        points: [CGPoint] = [],
        swatch: AnnotationSwatch,
        strokeWidth: CGFloat,
        redactionDensity: CGFloat = 0.55,
        text: String = "",
        textLineHeight: CGFloat = AnnotationTextMetrics.defaultNormalizedLineHeight,
        fontName: String = AnnotationTextMetrics.defaultFontName,
        isBold: Bool = true,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        textAlignment: NSTextAlignment = .left
    ) {
        self.id = id
        self.tool = tool
        self.rect = rect
        self.points = points
        self.swatch = swatch
        self.strokeWidth = strokeWidth
        self.redactionDensity = redactionDensity
        self.text = text
        self.textLineHeight = textLineHeight
        self.fontName = fontName
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.textAlignment = textAlignment
    }

    func resolvedFont(size: CGFloat) -> NSFont {
        AnnotationTextMetrics.resolvedFont(
            name: fontName, size: size, bold: isBold, italic: isItalic
        )
    }

    var bounds: CGRect {
        switch tool {
        case .select:
            return rect.standardized

        case .line, .arrow, .freehand:
            let boundsPoints = tool == .arrow ? arrowPoints : points
            guard let first = boundsPoints.first else { return rect.standardized }
            let bounds = boundsPoints.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }
            return bounds.standardized
        case .rectangle, .filledRectangle, .ellipse, .numberedCircle, .pixelate, .blur, .spotlight, .text:
            return rect.standardized
        }
    }

    var controlPoint: CGPoint? {
        guard tool == .arrow,
              let start = points.first,
              let end = points.last else {
            return nil
        }

        if points.count >= 3 {
            return points[1]
        }

        return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    var arrowCurveHandle: CGPoint? {
        guard tool == .arrow,
              let start = points.first,
              let end = points.last,
              let control = controlPoint else {
            return nil
        }

        return CGPoint(
            x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
            y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
        )
    }

    static func arrowControlPoint(forApex apex: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        return CGPoint(x: 2 * apex.x - mid.x, y: 2 * apex.y - mid.y)
    }

    func isRenderable(minimumSize: CGFloat, allowEmptyText: Bool = false) -> Bool {
        switch tool {
        case .select:
            return false

        case .line:
            guard points.count == 2 else { return false }
            return hypot(points[0].x - points[1].x, points[0].y - points[1].y) >= minimumSize
        case .arrow:
            guard let start = points.first,
                  let end = points.last else {
                return false
            }

            return hypot(start.x - end.x, start.y - end.y) >= minimumSize
        case .freehand:
            guard points.count >= 2 else { return false }
            return pathLength(points) >= minimumSize
        case .rectangle, .filledRectangle, .ellipse, .numberedCircle, .pixelate, .blur, .spotlight:
            return bounds.width >= minimumSize && bounds.height >= minimumSize
        case .text:
            return bounds.width >= minimumSize
                && bounds.height >= minimumSize
                && (allowEmptyText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch tool {
        case .select:
            return false

        case .line:
            guard let start = points.first,
                  let end = points.last else {
                return false
            }

            return distance(from: point, toSegmentFrom: start, to: end) <= tolerance

        case .freehand:
            guard points.count >= 2 else { return false }
            for index in 1..<points.count {
                if distance(from: point, toSegmentFrom: points[index - 1], to: points[index]) <= tolerance {
                    return true
                }
            }
            return false

        case .arrow:
            guard let start = points.first,
                  let controlPoint,
                  let end = points.last else {
                return false
            }

            return distance(from: point, toQuadraticFrom: start, control: controlPoint, to: end) <= tolerance

        case .rectangle, .filledRectangle, .pixelate, .blur, .spotlight, .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)

        case .ellipse, .numberedCircle:
            let expandedBounds = bounds.insetBy(dx: -tolerance, dy: -tolerance)
            guard expandedBounds.width > 0, expandedBounds.height > 0 else { return false }

            let center = CGPoint(x: expandedBounds.midX, y: expandedBounds.midY)
            let normalizedX = (point.x - center.x) / (expandedBounds.width / 2)
            let normalizedY = (point.y - center.y) / (expandedBounds.height / 2)
            return normalizedX * normalizedX + normalizedY * normalizedY <= 1
        }
    }

    func offsetBy(_ delta: CGPoint) -> AnnotationItem {
        var item = self
        item.rect = rect.offsetBy(dx: delta.x, dy: delta.y)
        item.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return item
    }

    func withEndpoint(_ handle: AnnotationResizeHandle, movedTo point: CGPoint) -> AnnotationItem {
        guard tool.usesEndpoints else { return self }

        var item = self
        if item.points.count < 2 {
            let fallback = item.points.first ?? point
            item.points = [fallback, fallback]
        }

        switch handle {
        case .start:
            item.ensureArrowPointStorage()
            item.points[0] = point
        case .control:
            guard item.tool == .arrow else { return self }
            item.ensureArrowPointStorage()
            item.points[1] = point
        case .end:
            item.ensureArrowPointStorage()
            item.points[item.points.count - 1] = point
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return self
        }

        item.rect = item.bounds
        return item
    }

    func resized(to newBounds: CGRect) -> AnnotationItem {
        let oldBounds = bounds.standardized
        guard oldBounds.width > 0, oldBounds.height > 0 else {
            var item = self
            item.rect = newBounds
            return item
        }

        var item = self
        item.rect = newBounds
        item.points = points.map { point in
            CGPoint(
                x: newBounds.minX + ((point.x - oldBounds.minX) / oldBounds.width) * newBounds.width,
                y: newBounds.minY + ((point.y - oldBounds.minY) / oldBounds.height) * newBounds.height
            )
        }
        return item
    }

    private var arrowPoints: [CGPoint] {
        guard tool == .arrow,
              let start = points.first,
              let controlPoint,
              let end = points.last else {
            return points
        }

        return [start, controlPoint, end]
    }

    private mutating func ensureArrowPointStorage() {
        guard tool == .arrow,
              points.count == 2,
              let start = points.first,
              let end = points.last else {
            return
        }

        points = [start, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), end]
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }

        var length: CGFloat = 0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            length += hypot(current.x - previous.x, current.y - previous.y)
        }
        return length
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closest = CGPoint(
            x: start.x + clampedProjection * dx,
            y: start.y + clampedProjection * dy
        )

        return hypot(point.x - closest.x, point.y - closest.y)
    }

    private func distance(from point: CGPoint, toQuadraticFrom start: CGPoint, control: CGPoint, to end: CGPoint) -> CGFloat {
        var shortestDistance = CGFloat.greatestFiniteMagnitude
        var previous = start

        for step in 1...16 {
            let t = CGFloat(step) / 16
            let current = quadraticPoint(start: start, control: control, end: end, t: t)
            shortestDistance = min(shortestDistance, distance(from: point, toSegmentFrom: previous, to: current))
            previous = current
        }

        return shortestDistance
    }

    private func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let first = CGPoint(
            x: start.x + (control.x - start.x) * t,
            y: start.y + (control.y - start.y) * t
        )
        let second = CGPoint(
            x: control.x + (end.x - control.x) * t,
            y: control.y + (end.y - control.y) * t
        )

        return CGPoint(
            x: first.x + (second.x - first.x) * t,
            y: first.y + (second.y - first.y) * t
        )
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    case select
    case rectangle
    case filledRectangle
    case ellipse
    case line
    case arrow
    case freehand
    case numberedCircle
    case pixelate
    case blur
    case spotlight
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .rectangle: "Rectangle"
        case .filledRectangle: "Solid rectangle"
        case .ellipse: "Circle"
        case .line: "Straight line"
        case .arrow: "Arrow"
        case .freehand: "Freehand"
        case .numberedCircle: "Numbered circle"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .spotlight: "Spotlight"
        case .text: "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .rectangle: "rectangle"
        case .filledRectangle: "square.fill"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .freehand: "scribble"
        case .numberedCircle: "1.circle.fill"
        case .pixelate: "app.background.dotted"
        case .blur: "drop.fill"
        case .spotlight: "light.max"
        case .text: "textformat"
        }
    }

    var isFilledShape: Bool {
        self == .filledRectangle
    }

    var usesEndpoints: Bool {
        self == .line || self == .arrow
    }

    var isRedactionTool: Bool {
        self == .pixelate || self == .blur
    }

    var isSpotlightTool: Bool {
        self == .spotlight
    }

    var supportsAspectLock: Bool {
        switch self {
        case .rectangle, .filledRectangle, .ellipse, .spotlight:
            true
        case .select, .line, .arrow, .freehand, .numberedCircle, .pixelate, .blur, .text:
            false
        }
    }

    var createsAnnotation: Bool {
        self != .select
    }
}

struct AnnotationSwatch: Identifiable, Equatable, Hashable {
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

    var numberedCircleTextColor: Color {
        isLight ? .black : .white
    }

    var numberedCircleTextNSColor: NSColor {
        isLight ? .black : .white
    }

    var numberedCircleOutlineColor: Color {
        isLight ? Color.black.opacity(0.22) : Color.white.opacity(0.42)
    }

    var numberedCircleOutlineNSColor: NSColor {
        isLight ? NSColor.black.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.42)
    }

    private var isLight: Bool {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.68
    }

    static let black = AnnotationSwatch("black", title: "Black", red: 0.02, green: 0.02, blue: 0.024)
    static let red = AnnotationSwatch("red", title: "Red", red: 0.97, green: 0.22, blue: 0.2)
    static let orange = AnnotationSwatch("orange", title: "Orange", red: 1.0, green: 0.53, blue: 0.08)
    static let yellow = AnnotationSwatch("yellow", title: "Yellow", red: 1, green: 0.82, blue: 0.18)
    static let green = AnnotationSwatch("green", title: "Green", red: 0.18, green: 0.72, blue: 0.36)
    static let turquoise = AnnotationSwatch("turquoise", title: "Turquoise", red: 0.20, green: 0.77, blue: 0.72)
    static let blue = AnnotationSwatch("blue", title: "Blue", red: 0.18, green: 0.48, blue: 1)
    static let purple = AnnotationSwatch("purple", title: "Purple", red: 0.55, green: 0.30, blue: 0.95)
    static let pink = AnnotationSwatch("pink", title: "Pink", red: 1.0, green: 0.18, blue: 0.43)
    static let white = AnnotationSwatch("white", title: "White", red: 0.96, green: 0.96, blue: 0.96)

    static let allCases: [AnnotationSwatch] = [
        .black, .red, .orange, .yellow, .green, .turquoise, .blue, .purple, .pink, .white
    ]

    static func custom(from color: Color) -> AnnotationSwatch {
        custom(from: NSColor(color))
    }

    static func custom(from nsColor: NSColor) -> AnnotationSwatch {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let red = converted.redComponent
        let green = converted.greenComponent
        let blue = converted.blueComponent
        let alpha = converted.alphaComponent
        return AnnotationSwatch(
            "custom-\(Int(red * 255))-\(Int(green * 255))-\(Int(blue * 255))-\(Int(alpha * 255))",
            title: "Custom",
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}
