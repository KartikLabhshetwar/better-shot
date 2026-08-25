import Foundation

/// Resolves a straight arrow: where its body starts and ends once it has been clipped to any bound
/// shapes and pushed off them to make room for arrowheads.
enum StraightArrow {
    static func info(_ document: AnnoDocument, _ shape: AnnoShape, _ bindings: ArrowBindings) -> ArrowInfo {
        guard let props = shape.arrowProps else {
            return degenerate(bindings, Vec(0, 0), .none, .none)
        }

        let terminals = ArrowShared.terminalsInArrowSpace(document, shape, bindings)
        var a = terminals.start
        var b = terminals.end
        var c = Vec.med(a, b)

        if Vec.equals(a, b) {
            return ArrowInfo(
                bindings: bindings,
                start: ArrowPoint(handle: a, point: a, arrowhead: props.arrowheadStart),
                end: ArrowPoint(handle: b, point: b, arrowhead: props.arrowheadEnd),
                middle: c,
                body: .straight(start: a, end: b),
                handleArc: nil,
                isValid: false
            )
        }

        let uAB = Vec.sub(b, a).uni

        let startShapeInfo = ArrowShared.boundShapeInfo(document, shape, .start)
        let endShapeInfo = ArrowShared.boundShapeInfo(document, shape, .end)
        let arrowPageTransform = shape.pageTransform

        // Pull each end back to where the line crosses the shape it's bound to.
        updateArrowheadPointWithBoundShape(&b, terminals.start, arrowPageTransform, endShapeInfo)
        updateArrowheadPointWithBoundShape(&a, terminals.end, arrowPageTransform, startShapeInfo)

        var offsetA = 0.0
        var offsetB = 0.0
        var minLength = ArrowConstants.minArrowLength

        let arrowSW = props.strokeWidth
        let isSelfIntersection = startShapeInfo != nil && endShapeInfo != nil
            && startShapeInfo!.shape.id == endShapeInfo!.shape.id

        let relationship = (startShapeInfo != nil && endShapeInfo != nil)
            ? ArrowShared.boundShapeRelationship(document, startShapeInfo!.shape.id, endShapeInfo!.shape.id)
            : .safe

        if relationship == .safe,
           let startInfo = startShapeInfo, let endInfo = endShapeInfo,
           !isSelfIntersection, !startInfo.isExact, !endInfo.isExact {
            if endInfo.didIntersect && !startInfo.didIntersect {
                // Only the end shape was hit: make it a short arrow ending at that intersection.
                if startInfo.isClosed {
                    a = Vec.add(b, Vec.mul(uAB, ArrowConstants.minArrowLength))
                }
            } else if !endInfo.didIntersect {
                // Neither was hit (or only the start): make it a short arrow starting at the
                // start shape's intersection.
                if endInfo.isClosed {
                    b = Vec.sub(a, Vec.mul(uAB, ArrowConstants.minArrowLength))
                }
            }
        }

        let distance = Vec.sub(b, a)
        let u = distance.len != 0 ? distance.uni : distance
        let didFlip = !Vec.equals(u, uAB)

        // A terminal that's bound and has an arrowhead gets pushed off the shape's edge, far
        // enough to clear both strokes.
        if !isSelfIntersection {
            if relationship != .startContainsEnd, let startInfo = startShapeInfo,
               props.arrowheadStart != .none, !startInfo.isExact {
                let strokeOffsetA = arrowSW / 2 + startInfo.shape.strokeWidth / 2
                offsetA = ArrowConstants.boundArrowOffset + strokeOffsetA
                minLength += strokeOffsetA
            }
            if relationship != .endContainsStart, let endInfo = endShapeInfo,
               props.arrowheadEnd != .none, !endInfo.isExact {
                let strokeOffsetB = arrowSW / 2 + endInfo.shape.strokeWidth / 2
                offsetB = ArrowConstants.boundArrowOffset + strokeOffsetB
                minLength += strokeOffsetB
            }
        }

        // Try the offsets; if they'd leave the arrow too short, flip and expand them instead.
        let tA = Vec.add(a, Vec.mul(u, offsetA * (didFlip ? -1 : 1)))
        let tB = Vec.sub(b, Vec.mul(u, offsetB * (didFlip ? -1 : 1)))

        if Vec.distMin(tA, tB, minLength) {
            if offsetA != 0 && offsetB != 0 {
                offsetA *= -1.5
                offsetB *= -1.5
            } else if offsetA != 0 {
                offsetA *= -1
            } else if offsetB != 0 {
                offsetB *= -1
            }
        }

        a = Vec.add(a, Vec.mul(u, offsetA * (didFlip ? -1 : 1)))
        b = Vec.sub(b, Vec.mul(u, offsetB * (didFlip ? -1 : 1)))

        if didFlip {
            // If the handles swapped order, keep the center handle between the terminals rather
            // than between the body's ends, where it might not sit "between" them at all.
            if startShapeInfo != nil && endShapeInfo != nil {
                b = Vec.add(a, Vec.mul(u, -ArrowConstants.minArrowLength))
            }
            c = Vec.med(terminals.start, terminals.end)
        } else {
            c = Vec.med(a, b)
        }

        let length = Vec.dist(a, b)

        return ArrowInfo(
            bindings: bindings,
            start: ArrowPoint(handle: terminals.start, point: a, arrowhead: props.arrowheadStart),
            end: ArrowPoint(handle: terminals.end, point: b, arrowhead: props.arrowheadEnd),
            middle: c,
            body: .straight(start: a, end: b),
            handleArc: nil,
            isValid: length > 0
        )
    }

    static func degenerate(_ bindings: ArrowBindings, _ point: Vec, _ startHead: Arrowhead, _ endHead: Arrowhead) -> ArrowInfo {
        ArrowInfo(
            bindings: bindings,
            start: ArrowPoint(handle: point, point: point, arrowhead: startHead),
            end: ArrowPoint(handle: point, point: point, arrowhead: endHead),
            middle: point,
            body: .straight(start: point, end: point),
            handleArc: nil,
            isValid: false
        )
    }

    /// Move `point` back to where the segment from `opposite` crosses the bound shape.
    private static func updateArrowheadPointWithBoundShape(
        _ point: inout Vec,
        _ opposite: Vec,
        _ arrowPageTransform: Mat,
        _ targetShapeInfo: ArrowShared.BoundShapeInfo?
    ) {
        guard let target = targetShapeInfo else { return }
        // An exact binding stops at the terminal itself.
        if target.isExact { return }

        let pageFrom = arrowPageTransform.applyToPoint(opposite)
        let pageTo = arrowPageTransform.applyToPoint(point)

        let inverse = target.transform.inverse
        let targetFrom = inverse.applyToPoint(pageFrom)
        let targetTo = inverse.applyToPoint(pageTo)

        var targetInt: Vec?
        let intersections = target.geometry.intersectLineSegment(targetFrom, targetTo)
        if !intersections.isEmpty {
            targetInt = intersections.min { Vec.dist2($0, targetFrom) < Vec.dist2($1, targetFrom) }
        }

        if targetInt == nil {
            // No intersection: if we _almost_ hit the target, put the arrowhead on its edge anyway.
            let nearest = target.geometry.nearestPoint(targetTo)
            if !Vec.distMin(nearest, targetTo, 1) { return }
            targetInt = nearest
        }

        guard let resolved = targetInt else { return }
        let pageInt = target.transform.applyToPoint(resolved)
        point = arrowPageTransform.inverse.applyToPoint(pageInt)
        target.didIntersect = true
    }
}
