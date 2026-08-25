import Foundation

/// The seven arrowhead shapes, built from the arrow's tip and a point back along its body.
enum Arrowheads {
    struct Points {
        /// The tip.
        var point: Vec
        /// A point back along the body, one arrowhead's length away.
        var int: Vec
    }

    /// Where the arrowhead sits, and how big it is: a fifth of the arrow's length, clamped to
    /// between one and three stroke widths.
    static func arrowPoints(_ info: ArrowInfo, _ side: ArrowTerminal, _ strokeWidth: Double) -> Points {
        let point = side == .end ? info.end.point : info.start.point
        var int: Vec

        switch info.body {
        case .straight:
            let opposite = side == .end ? info.start.point : info.end.point
            let compareLength = Vec.dist(opposite, point)
            let length = clamp(compareLength / 5, strokeWidth, strokeWidth * 3)
            int = Vec.nudge(point, opposite, length)

        case let .arc(bodyArc):
            let compareLength = abs(bodyArc.length)
            let length = clamp(compareLength / 5, strokeWidth, strokeWidth * 3)
            guard let handleArc = info.handleArc else { return Points(point: point, int: point) }
            let intersections = intersectCircleCircle(point, length, handleArc.center, handleArc.radius)
            // Which of the two circle crossings lies *behind* the tip depends on both which end
            // this is and which way the arc sweeps.
            let takeFirst = side == .end ? handleArc.sweepFlag != 0 : handleArc.sweepFlag == 0
            int = takeFirst ? intersections[0] : intersections[1]
        }

        if int.isNaN { int = point }
        return Points(point: point, int: int)
    }

    /// The arrowhead's path, and whether it should be filled.
    static func path(_ info: ArrowInfo, _ side: ArrowTerminal, _ strokeWidth: Double) -> (path: PathBuilder, isFilled: Bool)? {
        let type = side == .end ? info.end.arrowhead : info.start.arrowhead
        if type == .none { return nil }
        let points = arrowPoints(info, side, strokeWidth)

        switch type {
        case .none:
            return nil
        case .arrow:
            return (openArrow(points), false)
        case .triangle:
            return (triangle(points), true)
        case .inverted:
            return (invertedTriangle(points), true)
        case .dot:
            return (dot(points), true)
        case .diamond:
            return (diamond(points), true)
        case .square:
            return (square(points), true)
        case .bar:
            return (bar(points), false)
        }
    }

    private static func openArrow(_ p: Points) -> PathBuilder {
        let pl = Vec.rotWith(p.int, p.point, PI / 6)
        let pr = Vec.rotWith(p.int, p.point, -PI / 6)
        return PathBuilder().move(to: pl).line(to: p.point).line(to: pr)
    }

    private static func triangle(_ p: Points) -> PathBuilder {
        let pl = Vec.rotWith(p.int, p.point, PI / 6)
        let pr = Vec.rotWith(p.int, p.point, -PI / 6)
        return PathBuilder().move(to: pl).line(to: pr).line(to: p.point).close()
    }

    private static func invertedTriangle(_ p: Points) -> PathBuilder {
        let d = Vec.div(Vec.sub(p.int, p.point), 2)
        let pl = Vec.add(p.point, Vec.rot(d, HALF_PI))
        let pr = Vec.sub(p.point, Vec.rot(d, HALF_PI))
        return PathBuilder().move(to: pl).line(to: p.int).line(to: pr).close()
    }

    private static func dot(_ p: Points) -> PathBuilder {
        let a = Vec.lrp(p.point, p.int, 0.45)
        let r = Vec.dist(a, p.point)
        let path = PathBuilder()
        path.move(to: Vec(a.x - r, a.y))
        path.circularArc(radius: r, largeArc: true, sweep: false, to: Vec(a.x + r, a.y))
        path.circularArc(radius: r, largeArc: true, sweep: false, to: Vec(a.x - r, a.y))
        return path
    }

    private static func diamond(_ p: Points) -> PathBuilder {
        let pb = Vec.lrp(p.point, p.int, 0.75)
        let pl = Vec.rotWith(pb, p.point, PI / 4)
        let pr = Vec.rotWith(pb, p.point, -PI / 4)
        var pq = Vec.lrp(pl, pr, 0.5)
        pq = Vec.add(pq, Vec.sub(pq, p.point))
        return PathBuilder().move(to: pq).line(to: pr).line(to: p.point).line(to: pl).close()
    }

    private static func square(_ p: Points) -> PathBuilder {
        let pb = Vec.lrp(p.point, p.int, 0.85)
        let d = Vec.div(Vec.sub(pb, p.point), 2)
        let pl1 = Vec.add(p.point, Vec.rot(d, HALF_PI))
        let pr1 = Vec.sub(p.point, Vec.rot(d, HALF_PI))
        let pl2 = Vec.add(pb, Vec.rot(d, HALF_PI))
        let pr2 = Vec.sub(pb, Vec.rot(d, HALF_PI))
        return PathBuilder().move(to: pl1).line(to: pl2).line(to: pr2).line(to: pr1).close()
    }

    private static func bar(_ p: Points) -> PathBuilder {
        let d = Vec.div(Vec.sub(p.int, p.point), 2)
        let pl = Vec.add(p.point, Vec.rot(d, HALF_PI))
        let pr = Vec.sub(p.point, Vec.rot(d, HALF_PI))
        return PathBuilder().move(to: pl).line(to: pr)
    }
}

/// The arrow's body as a path, mirroring `ArrowPath.tsx`.
enum ArrowPath {
    static func body(_ info: ArrowInfo) -> PathBuilder {
        let path = PathBuilder()
        switch info.body {
        case let .straight(start, end):
            // The arrow's own ends get no jitter offset, so its arrowheads stay attached.
            path.move(to: start, opts: .init(offset: 0, roundness: 0))
            path.line(to: end, opts: .init(offset: 0, roundness: 0))
        case let .arc(arc):
            path.move(to: info.start.point, opts: .init(offset: 0, roundness: 0))
            path.circularArc(
                radius: arc.radius,
                largeArc: arc.largeArcFlag != 0,
                sweep: arc.sweepFlag != 0,
                to: info.end.point,
                opts: .init(offset: 0, roundness: 0)
            )
        }
        return path
    }

    /// The path through the *handles*, which is what the user is really dragging when they bend an
    /// arrow. Used to draw the handle guide line while an arrow is selected.
    static func handles(_ info: ArrowInfo) -> PathBuilder {
        let path = PathBuilder()
        path.move(to: info.start.handle)
        if let handleArc = info.handleArc, !info.isStraight {
            path.circularArc(
                radius: handleArc.radius,
                largeArc: handleArc.largeArcFlag != 0,
                sweep: handleArc.sweepFlag != 0,
                to: info.end.handle
            )
        } else {
            path.line(to: info.end.handle)
        }
        return path
    }
}
