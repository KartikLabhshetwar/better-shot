import Foundation

/// Bound-shape lookup and terminal resolution, shared by the straight and curved arrow solvers.
enum ArrowShared {
    /// What a terminal is bound to, and everything the solvers need to intersect against it.
    final class BoundShapeInfo {
        let shape: AnnoShape
        let transform: Mat
        let geometry: Geometry2d
        let isClosed: Bool
        let isExact: Bool
        var didIntersect = false

        init(shape: AnnoShape, transform: Mat, geometry: Geometry2d, isExact: Bool) {
            self.shape = shape
            self.transform = transform
            self.geometry = geometry
            self.isClosed = geometry.isClosed
            self.isExact = isExact
        }
    }

    enum Relationship {
        case safe
        case doubleBound
        case startContainsEnd
        case endContainsStart
    }

    static func isArrowStraight(_ props: ArrowProps) -> Bool {
        abs(props.bend) < ArrowConstants.minArrowBend
    }

    static func boundShapeInfo(_ document: AnnoDocument, _ arrow: AnnoShape, _ terminal: ArrowTerminal) -> BoundShapeInfo? {
        let bindings = document.arrowBindings(arrow.id)
        guard let binding = terminal == .start ? bindings.start : bindings.end else { return nil }
        guard let boundShape = document.shape(binding.toId) else { return nil }
        return BoundShapeInfo(
            shape: boundShape,
            transform: boundShape.pageTransform,
            geometry: document.geometry(boundShape),
            isExact: binding.isExact
        )
    }

    private static func clampNormalizedAnchor(_ anchor: Vec) -> Vec {
        let e = ArrowConstants.normalizedAnchorEpsilon
        return Vec(clamp(anchor.x, e, 1 - e), clamp(anchor.y, e, 1 - e))
    }

    /// Where a bound terminal sits, expressed in the arrow's own local space.
    static func terminalInArrowSpace(
        _ document: AnnoDocument,
        _ arrowPageTransform: Mat,
        _ binding: ArrowBinding,
        forcePrecise: Bool
    ) -> Vec {
        guard let boundShape = document.shape(binding.toId) else { return Vec(0, 0) }
        let bounds = document.geometry(boundShape).bounds
        // An imprecise binding aims at the shape's center. Shapes that contain each other, or an
        // arrow bound to the same shape twice, force the precise anchor instead - a center-to-center
        // arrow would be degenerate in those cases.
        let shouldUsePreciseAnchor = binding.isPrecise || forcePrecise
        let normalizedAnchor = shouldUsePreciseAnchor
            ? clampNormalizedAnchor(binding.normalizedAnchor)
            : Vec(0.5, 0.5)

        let shapePoint = Vec.add(bounds.point, Vec.mulV(normalizedAnchor, Vec(bounds.w, bounds.h)))
        let pagePoint = boundShape.pageTransform.applyToPoint(shapePoint)
        return arrowPageTransform.inverse.applyToPoint(pagePoint)
    }

    /// Both terminals in the arrow's local space, falling back to the arrow's own props when a
    /// terminal isn't bound.
    static func terminalsInArrowSpace(_ document: AnnoDocument, _ arrow: AnnoShape, _ bindings: ArrowBindings) -> (start: Vec, end: Vec) {
        guard let props = arrow.arrowProps else { return (Vec(0, 0), Vec(0, 0)) }
        let arrowPageTransform = arrow.pageTransform
        let relationship = boundShapeRelationship(document, bindings.start?.toId, bindings.end?.toId)

        let start: Vec
        if let binding = bindings.start {
            start = terminalInArrowSpace(
                document, arrowPageTransform, binding,
                forcePrecise: relationship == .doubleBound || relationship == .startContainsEnd
            )
        } else {
            start = props.start
        }

        let end: Vec
        if let binding = bindings.end {
            end = terminalInArrowSpace(
                document, arrowPageTransform, binding,
                forcePrecise: relationship == .doubleBound || relationship == .endContainsStart
            )
        } else {
            end = props.end
        }

        return (start, end)
    }

    /// How the two bound shapes relate. Offsets and precise anchors only apply when it's "safe" -
    /// when the shapes aren't the same shape, and neither contains the other.
    static func boundShapeRelationship(_ document: AnnoDocument, _ startShapeId: AnnoShapeID?, _ endShapeId: AnnoShapeID?) -> Relationship {
        guard let startShapeId, let endShapeId else { return .safe }
        if startShapeId == endShapeId { return .doubleBound }
        guard let startBounds = document.pageBounds(startShapeId),
              let endBounds = document.pageBounds(endShapeId) else { return .safe }
        if startBounds.contains(endBounds) { return .startContainsEnd }
        if endBounds.contains(startBounds) { return .endContainsStart }
        return .safe
    }

    /// Info about the arc through three points: the two ends and a point on it.
    static func arcInfo(_ a: Vec, _ b: Vec, _ c: Vec) -> ArcInfo {
        let center = centerOfCircleFromThreePoints(a, b, c) ?? Vec.med(a, b)
        let radius = Vec.dist(center, a)

        // Whether to draw the arc clockwise or counter-clockwise.
        let sweepFlag = Vec.clockwise(a, c, b) ? 1 : 0

        let ab = ((a.y - b.y) * (a.y - b.y) + (a.x - b.x) * (a.x - b.x)).squareRoot()
        let bc = ((b.y - c.y) * (b.y - c.y) + (b.x - c.x) * (b.x - c.x)).squareRoot()
        let ca = ((c.y - a.y) * (c.y - a.y) + (c.x - a.x) * (c.x - a.x)).squareRoot()

        let theta = acos((bc * bc + ca * ca - ab * ab) / (2 * bc * ca)) * 2

        let largeArcFlag = PI > theta ? 1 : 0
        let size = (PI2 - theta) * (sweepFlag != 0 ? 1 : -1)
        let length = size * radius

        return ArcInfo(
            center: center,
            radius: radius,
            size: size,
            length: length,
            largeArcFlag: largeArcFlag,
            sweepFlag: sweepFlag
        )
    }
}
