import AppKit
import CoreGraphics
import Foundation

/// A single drawable piece of a shape, in the shape's own local space.
///
/// Everything the canvas and the exporter draw comes through this list, which `AnnoDocument` caches
/// per shape. Rebuilding it per frame meant panning re-ran the whole freehand pipeline for strokes
/// whose pixels hadn't moved.
///
/// BetterShot's non-vector tools ride the same list: a redaction, a spotlight hole and a numbered
/// callout are `Content` cases rather than paths, so one draw loop covers every tool and they all
/// inherit the same transform, z-order and caching.
struct RenderElement {
    enum Content {
        /// A vector path: filled, stroked, or both.
        case path(CGPath)
        /// A rectangle of the underlying screenshot, blurred or pixelated in place.
        case redaction(RedactionProps)
        /// A hole punched in the spotlight dimming layer.
        case spotlight(CGSize)
        /// A numbered callout: filled disc, outline, and centred digits.
        case numbered(NumberedProps)
        /// Glyph outlines, already positioned in the shape's local space.
        case glyphs(CGPath)
    }

    var content: Content
    var fill: NSColor?
    var stroke: NSColor?
    var strokeWidth: Double = 1
    /// Fill rule for self-overlapping ink outlines and glyph counters.
    var usesEvenOddFill = false
    /// Dash pattern and phase for the stroke, empty for a solid line.
    var dashes: [CGFloat] = []
    var dashPhase: CGFloat = 0

    var cgPath: CGPath? {
        switch content {
        case let .path(path), let .glyphs(path): path
        case .redaction, .spotlight, .numbered: nil
        }
    }

    /// Whether this element transforms the screenshot underneath it rather than painting over it.
    /// Those are drawn in a first pass, below the spotlight.
    var isRedaction: Bool {
        if case .redaction = content { return true }
        return false
    }

    var isSpotlight: Bool {
        if case .spotlight = content { return true }
        return false
    }
}

/// Turns shapes into render elements, in the shape's own local space.
enum AnnoShapeRenderer {
    static func elements(for shape: AnnoShape, in document: AnnoDocument) -> [RenderElement] {
        switch shape.kind {
        case let .geo(props):
            geoElements(props)
        case let .draw(props):
            drawElements(props)
        case .arrow:
            arrowElements(shape, in: document)
        case let .text(props):
            textElements(props)
        case let .redaction(props):
            [RenderElement(content: .redaction(props))]
        case let .highlight(props):
            [RenderElement(content: .spotlight(CGSize(width: props.w, height: props.h)))]
        case let .numbered(props):
            [RenderElement(content: .numbered(props))]
        }
    }

    // MARK: - Text

    private static func textElements(_ props: TextProps) -> [RenderElement] {
        guard !props.text.isEmpty else { return [] }
        return [RenderElement(
            content: .glyphs(TextMeasure.glyphPath(props)),
            fill: props.swatch.nsColor,
            stroke: nil,
            // Non-zero, not even-odd. OpenType contours are wound so that counters (the hole in an
            // "o") come out hollow under non-zero anyway, and even-odd additionally punches a hole
            // wherever two glyphs overlap - which at bold weights is most of a sentence.
            usesEvenOddFill: false
        )]
    }

    // MARK: - Draw

    private static func drawElements(_ props: DrawProps) -> [RenderElement] {
        guard !props.points.isEmpty else { return [] }

        let options = FreehandSettings.forDrawShape(
            isPen: props.isPen,
            isComplete: props.isComplete,
            strokeWidth: props.strokeWidth,
            forceComplete: false,
            forceSolid: false
        )
        let ink = SvgInk.render(props.points, options)
        return [RenderElement(
            content: .path(ink.path),
            fill: props.swatch.nsColor,
            stroke: nil,
            // The outline can double back on itself at tight corners; non-zero winding keeps those
            // overlaps solid instead of punching holes in the stroke.
            usesEvenOddFill: false
        )]
    }

    // MARK: - Geo

    private static func geoElements(_ props: GeoProps) -> [RenderElement] {
        let path = GeoPaths.path(for: props)

        if props.fill != .none {
            return [RenderElement(
                content: .path(path.solidPath()),
                fill: props.swatch.nsColor,
                stroke: nil
            )]
        }
        return [strokeElement(
            path: path,
            dash: props.dash,
            strokeWidth: props.strokeWidth,
            color: props.swatch.nsColor,
            seed: ""
        )]
    }

    /// Stroke a path in whichever dash style is asked for.
    private static func strokeElement(
        path: PathBuilder,
        dash: DashStyle,
        strokeWidth: Double,
        color: NSColor,
        seed: String
    ) -> RenderElement {
        switch dash {
        case .draw:
            let opts = PathBuilder.DrawOptions(strokeWidth: strokeWidth, randomSeed: seed)
            return RenderElement(
                content: .path(path.drawPath(opts)),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth
            )
        case .solid:
            return RenderElement(
                content: .path(path.solidPath()),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth
            )
        case .dashed, .dotted:
            // Each segment carries its own pattern, so dashes meet cleanly at a rectangle's corners
            // instead of wrapping around them.
            let segments = path.dashedSegments(strokeWidth: strokeWidth, style: dash)
            let combined = CGMutablePath()
            for segment in segments { combined.addPath(segment.path) }
            let first = segments.first
            return RenderElement(
                content: .path(combined),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth,
                dashes: first?.dashes ?? [],
                dashPhase: first?.phase ?? 0
            )
        }
    }

    // MARK: - Arrow

    private static func arrowElements(_ shape: AnnoShape, in document: AnnoDocument) -> [RenderElement] {
        guard let props = shape.arrowProps,
              let info = document.arrowInfo(shape.id),
              info.isValid else { return [] }

        var elements: [RenderElement] = []
        elements.append(strokeElement(
            path: ArrowPath.body(info),
            dash: props.dash,
            strokeWidth: props.strokeWidth,
            color: props.swatch.nsColor,
            seed: shape.id.raw
        ))

        for side in [ArrowTerminal.start, ArrowTerminal.end] {
            guard let head = Arrowheads.path(info, side, props.strokeWidth) else { continue }
            elements.append(RenderElement(
                content: .path(head.path.solidPath()),
                fill: head.isFilled ? props.swatch.nsColor : nil,
                stroke: props.swatch.nsColor,
                strokeWidth: props.strokeWidth
            ))
        }

        return elements
    }
}
