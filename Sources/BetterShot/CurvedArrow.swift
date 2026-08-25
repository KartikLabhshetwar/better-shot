import Foundation

/// Resolves a bent arrow. The user's three handles (start, middle, end) define a circle; the drawn
/// body is the piece of that circle left after clipping to the bound shapes and offsetting for
/// arrowheads.
enum CurvedArrow {
    static func info(_ document: AnnoDocument, _ shape: AnnoShape, _ bindings: ArrowBindings) -> ArrowInfo {
        guard let props = shape.arrowProps else {
            return StraightArrow.degenerate(bindings, Vec(0, 0), .none, .none)
        }
        let bend = props.bend

        if abs(bend) > abs(props.bend * ArrowConstants.wayTooBigArrowBendFactor) {
            return StraightArrow.info(document, shape, bindings)
        }

        let terminals = ArrowShared.terminalsInArrowSpace(document, shape, bindings)
        let med = Vec.med(terminals.start, terminals.end)
        let distance = Vec.sub(terminals.end, terminals.start)
        let u = distance.len != 0 ? distance.uni : distance
        let middle = Vec.add(med, Vec.mul(u.per, -bend))

        let arrowSW = props.strokeWidth

        let startShapeInfo = ArrowShared.boundShapeInfo(document, shape, .start)
        let endShapeInfo = ArrowShared.boundShapeInfo(document, shape, .end)

        // The body's positions, which differ from the handles once the arrow is bound.
        let a = terminals.start
        let b = terminals.end
        let c = middle

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

        let isClockwise = bend < 0
        let distFn: (Double, Double) -> Double = isClockwise
            ? { clockwiseAngleDist($0, $1) }
            : { counterClockwiseAngleDist($0, $1) }

        let handleArc = ArrowShared.arcInfo(a, b, c)
        let handleACA = Vec.angle(handleArc.center, a)
        let handleACB = Vec.angle(handleArc.center, b)
        let handleDAB = distFn(handleACA, handleACB)

        if handleArc.length == 0 || handleArc.size == 0
            || !isSafeFloat(handleArc.length) || !isSafeFloat(handleArc.size) {
            return StraightArrow.info(document, shape, bindings)
        }

        var tempA = a
        var tempB = b
        var tempC = c

        let arrowPageTransform = shape.pageTransform
        var offsetA = 0.0
        var offsetB = 0.0
        var minLength = ArrowConstants.minArrowLength

        // Clip the start against its bound shape, by intersecting the shape with the arrow's circle.
        if let startInfo = startShapeInfo, !startInfo.isExact {
            let point = clipTerminal(
                info: startInfo,
                arrowPageTransform: arrowPageTransform,
                thisEnd: tempA,
                otherEnd: tempB,
                arcCenter: handleArc.center,
                radius: handleArc.radius,
                distFn: distFn,
                // The start wants the first intersection along the arc.
                targetFraction: 0.25
            )
            if let point {
                tempA = document.pointInShapeSpace(shape, startInfo.transform.applyToPoint(point))
                startInfo.didIntersect = true
                if props.arrowheadStart != .none {
                    let strokeOffset = arrowSW / 2 + startInfo.shape.strokeWidth / 2
                    offsetA = ArrowConstants.boundArrowOffset + strokeOffset
                    minLength += strokeOffset
                }
            }
        }

        if let endInfo = endShapeInfo, !endInfo.isExact {
            let point = clipTerminal(
                info: endInfo,
                arrowPageTransform: arrowPageTransform,
                thisEnd: tempB,
                otherEnd: tempA,
                arcCenter: handleArc.center,
                radius: handleArc.radius,
                distFn: distFn,
                // The end wants the last intersection along the arc.
                targetFraction: 0.75,
                measureFromStart: true,
                startPoint: tempA
            )
            if let point {
                tempB = document.pointInShapeSpace(shape, endInfo.transform.applyToPoint(point))
                endInfo.didIntersect = true
                if props.arrowheadEnd != .none {
                    let strokeOffset = arrowSW / 2 + endInfo.shape.strokeWidth / 2
                    offsetB = ArrowConstants.boundArrowOffset + strokeOffset
                    minLength += strokeOffset
                }
            }
        }

        // Apply the arrowhead offsets, as rotations along the arc.
        var aCA = Vec.angle(handleArc.center, tempA)
        var aCB = Vec.angle(handleArc.center, tempB)
        var dAB = distFn(aCA, aCB)
        var lAB = dAB * handleArc.radius

        // Try the offsets on temporaries first, so that if the arrow ends up too short we can flip
        // and expand both in a balanced way.
        var tA = tempA
        var tB = tempB

        if offsetA != 0 {
            tA = Vec.add(handleArc.center, Vec.mul(
                Vec.fromAngle(aCA + dAB * ((offsetA / lAB) * (isClockwise ? 1 : -1))), handleArc.radius
            ))
        }
        if offsetB != 0 {
            tB = Vec.add(handleArc.center, Vec.mul(
                Vec.fromAngle(aCB + dAB * ((offsetB / lAB) * (isClockwise ? -1 : 1))), handleArc.radius
            ))
        }

        if Vec.distMin(tA, tB, minLength) {
            if offsetA != 0 && offsetB != 0 {
                offsetA *= -1.5
                offsetB *= -1.5
            } else if offsetA != 0 {
                offsetA *= -2
            } else if offsetB != 0 {
                offsetB *= -2
            }

            // With negative offsets, keep the body arc from growing larger than the handle arc.
            let minOffsetA = 0.1 - distFn(handleACA, aCA) * handleArc.radius
            let minOffsetB = 0.1 - distFn(aCB, handleACB) * handleArc.radius
            offsetA = Swift.max(offsetA, minOffsetA)
            offsetB = Swift.max(offsetB, minOffsetB)
        }

        if offsetA != 0 {
            tempA = Vec.add(handleArc.center, Vec.mul(
                Vec.fromAngle(aCA + dAB * ((offsetA / lAB) * (isClockwise ? 1 : -1))), handleArc.radius
            ))
        }
        if offsetB != 0 {
            tempB = Vec.add(handleArc.center, Vec.mul(
                Vec.fromAngle(aCB + dAB * ((offsetB / lAB) * (isClockwise ? -1 : 1))), handleArc.radius
            ))
        }

        // Did we miss intersections? That happens when the two shapes overlap.
        if let startInfo = startShapeInfo, let endInfo = endShapeInfo,
           !startInfo.isExact, !endInfo.isExact {
            aCA = Vec.angle(handleArc.center, tempA)
            aCB = Vec.angle(handleArc.center, tempB)
            dAB = distFn(aCA, aCB)
            lAB = dAB * handleArc.radius
            let relationship = ArrowShared.boundShapeRelationship(document, startInfo.shape.id, endInfo.shape.id)

            if relationship == .doubleBound && lAB < 30 {
                tempA = a
                tempB = b
                tempC = c
            } else if relationship == .safe {
                if !startInfo.didIntersect {
                    tempA = a
                }
                if !endInfo.didIntersect || distFn(handleACA, aCA) > distFn(handleACA, aCB) {
                    let t = Swift.min(0.9, ArrowConstants.minArrowLength / lAB) * (isClockwise ? 1 : -1)
                    tempB = Vec.add(handleArc.center, Vec.mul(
                        Vec.fromAngle(aCA + dAB * t), handleArc.radius
                    ))
                }
            }
        }

        placeCenterHandle(
            center: handleArc.center,
            radius: handleArc.radius,
            tempA: &tempA,
            tempB: &tempB,
            tempC: &tempC,
            originalArcLength: handleDAB,
            isClockwise: isClockwise
        )

        if Vec.equals(tempA, tempB) {
            tempA = Vec.addXY(tempC, 1, 1)
            tempB = Vec.subXY(tempC, 1, 1)
        }

        let bodyArc = ArrowShared.arcInfo(tempA, tempB, tempC)

        return ArrowInfo(
            bindings: bindings,
            start: ArrowPoint(handle: terminals.start, point: tempA, arrowhead: props.arrowheadStart),
            end: ArrowPoint(handle: terminals.end, point: tempB, arrowhead: props.arrowheadEnd),
            middle: tempC,
            body: .arc(bodyArc),
            handleArc: handleArc,
            isValid: bodyArc.length != 0 && bodyArc.center.isFinite
        )
    }

    /// Intersect the arrow's circle with a bound shape, and pick the crossing that best fits where
    /// this end of the arrow should stop.
    ///
    /// Returns the point in the bound shape's local space, or nil if the arc misses it entirely.
    private static func clipTerminal(
        info: ArrowShared.BoundShapeInfo,
        arrowPageTransform: Mat,
        thisEnd: Vec,
        otherEnd: Vec,
        arcCenter: Vec,
        radius: Double,
        distFn: (Double, Double) -> Double,
        targetFraction: Double,
        measureFromStart: Bool = false,
        startPoint: Vec? = nil
    ) -> Vec? {
        let inverse = info.transform.inverse
        // The arc, described in the bound shape's local space.
        let thisInLocal = inverse.applyToPoint(arrowPageTransform.applyToPoint(thisEnd))
        let otherInLocal = inverse.applyToPoint(arrowPageTransform.applyToPoint(otherEnd))
        let centerInLocal = inverse.applyToPoint(arrowPageTransform.applyToPoint(arcCenter))

        // Angles are always measured from the arrow's start, so the two ends order intersections
        // the same way along the arc.
        let localStart = measureFromStart
            ? inverse.applyToPoint(arrowPageTransform.applyToPoint(startPoint ?? otherEnd))
            : thisInLocal
        let localEnd = measureFromStart ? thisInLocal : otherInLocal

        var intersections = info.geometry.intersectCircle(centerInLocal, radius)
        var point: Vec?

        if !intersections.isEmpty {
            let angleToStart = centerInLocal.angle(localStart)
            let angleToEnd = centerInLocal.angle(localEnd)
            let dAB = distFn(angleToStart, angleToEnd)

            // Discard crossings that lie outside the drawn part of the arc.
            intersections = intersections.filter {
                distFn(angleToStart, centerInLocal.angle($0)) <= dAB
            }

            let targetDist = dAB * targetFraction
            if info.isClosed {
                // A closed shape: prefer the crossing nearest where this end belongs.
                intersections.sort {
                    abs(distFn(angleToStart, centerInLocal.angle($0)) - targetDist)
                        < abs(distFn(angleToStart, centerInLocal.angle($1)) - targetDist)
                }
            } else {
                // An open shape: just take them in order along the arc.
                intersections.sort {
                    distFn(angleToStart, centerInLocal.angle($0))
                        < distFn(angleToStart, centerInLocal.angle($1))
                }
            }
            point = intersections.first
        }

        if point == nil {
            if info.isClosed {
                let nearest = info.geometry.nearestPoint(thisInLocal)
                if Vec.distMin(nearest, thisInLocal, 1) { point = nearest }
            } else {
                point = thisInLocal
            }
        }
        return point
    }

    /// Put the middle handle halfway along the body arc. If the body arc has grown past the handle
    /// arc, the terminals have swapped - flip them back and put the handle on the other side.
    private static func placeCenterHandle(
        center: Vec,
        radius: Double,
        tempA: inout Vec,
        tempB: inout Vec,
        tempC: inout Vec,
        originalArcLength: Double,
        isClockwise: Bool
    ) {
        let aCA = Vec.angle(center, tempA)
        let aCB = Vec.angle(center, tempB)
        var dAB = clockwiseAngleDist(aCA, aCB)
        if !isClockwise { dAB = PI2 - dAB }

        tempC = Vec.add(center, Vec.mul(Vec.fromAngle(aCA + dAB * (0.5 * (isClockwise ? 1 : -1))), radius))

        if dAB > originalArcLength {
            tempC = Vec.rotWith(tempC, center, PI)
            let t = tempB
            tempB = tempA
            tempA = t
        }
    }
}

/// The entry point that picks a solver, mirroring `getArrowInfo`.
enum ArrowEngine {
    static func getArrowInfo(_ document: AnnoDocument, _ shape: AnnoShape) -> ArrowInfo? {
        guard let props = shape.arrowProps else { return nil }
        let bindings = document.arrowBindings(shape.id)
        if ArrowShared.isArrowStraight(props) {
            return StraightArrow.info(document, shape, bindings)
        }
        return CurvedArrow.info(document, shape, bindings)
    }
}
