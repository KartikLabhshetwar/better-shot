import CoreGraphics
import Foundation

/// Collects the ink outline as a `CGPath`.
///
/// The outline is conceptually written with SVG's `t` smooth-quadratic shorthand; this sink
/// reproduces that shorthand's reflected control points so the curve is identical. Export
/// converts the finished path to SVG, rather than this building a string on every frame.
final class InkPathSink {
    let path = CGMutablePath()

    private var current = Vec()
    /// The control point of the previous quadratic, for `t`'s reflection rule. `nil` when the run
    /// was broken (the previous command wasn't a quadratic).
    private var lastControl: Vec?

    func move(to p: Vec) {
        path.move(to: p.cgPoint)
        current = p
        lastControl = nil
    }

    /// SVG's `T`: a quadratic whose control point is the reflection of the previous control point
    /// about the current point. With no previous control, the control point is the current point,
    /// which degenerates to a line.
    func smoothQuad(to p: Vec) {
        let control = lastControl.map { Vec(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
        path.addQuadCurve(to: p.cgPoint, control: control.cgPoint)
        lastControl = control
        current = p
    }

    /// Start a new smooth-quadratic run, so the next `smoothQuad` draws a line rather than
    /// reflecting a stale control point.
    func breakSmoothRun() {
        lastControl = nil
    }

    /// SVG's `a r,r 0 0 1 dx,dy` - a circular arc with largeArc=0, sweep=1.
    func arc(radius: Double, to p: Vec) {
        addSvgArc(from: current, to: p, rx: radius, ry: radius, xAxisRotation: 0, largeArc: false, sweep: true)
        current = p
        lastControl = nil
    }

    func close() {
        path.closeSubpath()
        lastControl = nil
    }

    func circle(center: Vec, radius: Double) {
        path.addEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))

        current = Vec(center.x - radius, center.y)
        lastControl = nil
    }

    /// Endpoint- to center-parameterization of an SVG elliptical arc, so we can hand it to
    /// `CGPath.addArc`. Same conversion PathBuilder uses when it approximates arcs.
    private func addSvgArc(from p1: Vec, to p2: Vec, rx: Double, ry: Double, xAxisRotation: Double, largeArc: Bool, sweep: Bool) {
        if p1.x == p2.x && p1.y == p2.y { return }
        if rx == 0 || ry == 0 {
            path.addLine(to: p2.cgPoint)
            return
        }

        let phi = xAxisRotation
        let sinPhi = sin(phi)
        let cosPhi = cos(phi)
        var rx1 = abs(rx)
        var ry1 = abs(ry)

        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx1 * rx1) + (y1p * y1p) / (ry1 * ry1)
        if lambda > 1 {
            let sqrtLambda = lambda.squareRoot()
            rx1 *= sqrtLambda
            ry1 *= sqrtLambda
        }

        let sign: Double = largeArc != sweep ? 1 : -1
        let term = rx1 * rx1 * ry1 * ry1 - rx1 * rx1 * y1p * y1p - ry1 * ry1 * x1p * x1p
        let numerator = rx1 * rx1 * y1p * y1p + ry1 * ry1 * x1p * x1p
        var radicand = numerator == 0 ? 0 : term / numerator
        if radicand < 0 { radicand = 0 }
        let coef = sign * radicand.squareRoot()

        let cxp = coef * ((rx1 * y1p) / ry1)
        let cyp = coef * (-(ry1 * x1p) / rx1)
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        let ux = (x1p - cxp) / rx1
        let uy = (y1p - cyp) / ry1
        let vx = (-x1p - cxp) / rx1
        let vy = (-y1p - cyp) / ry1

        let startAngle = atan2(uy, ux)
        var endAngle = atan2(vy, vx)
        if !sweep && endAngle > startAngle {
            endAngle -= PI2
        } else if sweep && endAngle < startAngle {
            endAngle += PI2
        }

        // `sweep` means the angle increases, which is `clockwise: false` in CGPath's parametric
        // sense (the visual direction depends on the y axis of the current transform).
        if rx1 == ry1 && phi == 0 {
            path.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: rx1,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: !sweep
            )
        } else {
            // A general ellipse: sweep the unit circle and let the transform stretch it.
            let transform = CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: phi)
                .scaledBy(x: rx1, y: ry1)
            path.addArc(
                center: .zero, radius: 1,
                startAngle: startAngle, endAngle: endAngle,
                clockwise: !sweep,
                transform: transform
            )
        }
    }
}

/// Render a freehand stroke as a filled outline with round caps, in a single pass from raw input
/// points. This is the path used when drawing with ink.
enum SvgInk {
    static func render(_ rawInputPoints: [Vec], _ options: StrokeOptions) -> InkPathSink {
        let sink = InkPathSink()
        let pipeline = StrokePipeline()
        pipeline.ingest(rawInputPoints, options)
        guard pipeline.pointCount > 0 else { return sink }
        pipeline.computeRadii(options)
        partitionAtElbows(pipeline, options, sink)
        return sink
    }

    /// Walk the stroke points, cutting the stroke into partitions at elbows, and render each one.
    ///
    /// An acute elbow uses the input point rather than the streamlined point at the boundary (for
    /// swooshiness in fast zaggy lines), in which case the next partition's second point keeps the
    /// vector it had in the uncut stroke via the vector anchor.
    private static func partitionAtElbows(_ p: StrokePipeline, _ options: StrokeOptions, _ sink: InkPathSink) {
        let n = p.pointCount
        guard n > 0 else { return }
        if n <= 2 {
            var src = TrackSource()
            src.load(from: p)
            renderPartition(src, options, anchor: nil, sink)
            return
        }

        // The start of the current partition, and whether it is an acute elbow.
        var a = 0
        var aElbow = false
        var anchor: Vec?

        var dx = p.pointX[1] - p.pointX[0]
        var dy = p.pointY[1] - p.pointY[0]
        var len = (dx * dx + dy * dy).squareRoot()
        var prevVx = dx / len
        var prevVy = dy / len

        for i in 1..<(n - 1) {
            dx = p.pointX[i + 1] - p.pointX[i]
            dy = p.pointY[i + 1] - p.pointY[i]
            len = (dx * dx + dy * dy).squareRoot()
            let nextVx = dx / len
            let nextVy = dy / len
            let dpr = prevVx * nextVx + prevVy * nextVy
            prevVx = nextVx
            prevVy = nextVy

            if dpr < -0.8 {
                // Always treat such acute angles as elbows, using the extended input point as the
                // elbow point for swooshiness in fast zaggy lines.
                finishPartition(p, a: a, aElbow: aElbow, b: i, bElbow: true, bDup: false, anchor: anchor, options, sink)
                a = i
                aElbow = true
                // The next partition's second point keeps the vector it had in the uncut stroke,
                // which pointed at this point's streamlined position rather than its input.
                anchor = Vec(p.pointX[i], p.pointY[i])
                continue
            }

            if dpr > 0.7 { continue } // not an elbow

            // A reasonably acute angle, but it might not be an elbow if it's far from its
            // neighbours. Normalize the neighbour distance by the radius to decide.
            let pdx = p.pointX[i] - p.pointX[i - 1]
            let pdy = p.pointY[i] - p.pointY[i - 1]
            let ndx = p.pointX[i + 1] - p.pointX[i]
            let ndy = p.pointY[i + 1] - p.pointY[i]
            let meanRadius = (p.radii[i - 1] + p.radii[i] + p.radii[i + 1]) / 3
            if (pdx * pdx + pdy * pdy + ndx * ndx + ndy * ndy) / (meanRadius * meanRadius) < 1.5 {
                // Close to its neighbours and reasonably acute: probably a hard elbow. The
                // boundary point ends its partition twice over.
                finishPartition(p, a: a, aElbow: aElbow, b: i, bElbow: false, bDup: true, anchor: anchor, options, sink)
                a = i
                aElbow = false
                anchor = nil
            }
        }
        finishPartition(p, a: a, aElbow: aElbow, b: n - 1, bElbow: false, bDup: false, anchor: anchor, options, sink)
    }

    /// Clean up a partition's ends (dropping inner points too close to the boundary points), then
    /// render it.
    private static func finishPartition(
        _ p: StrokePipeline,
        a: Int,
        aElbow: Bool,
        b: Int,
        bElbow: Bool,
        bDup: Bool,
        anchor: Vec?,
        _ options: StrokeOptions,
        _ sink: InkPathSink
    ) {
        var anchor = anchor
        // The partition: point a, points a+1..b-1, point b (twice when bDup). Cleanup only ever
        // removes points adjacent to the ends, so it reduces to two skip counters.
        let len = b - a + 1 + (bDup ? 1 : 0)
        var s = 0
        var e = 0

        let startX = aElbow ? p.inputX[a] : p.pointX[a]
        let startY = aElbow ? p.inputY[a] : p.pointY[a]
        let startRadius = p.radii[a]
        while len - s > 2 {
            let i = a + 1 + s
            let dx = startX - p.pointX[i]
            let dy = startY - p.pointY[i]
            if dx * dx + dy * dy < pow(((startRadius + p.radii[i]) / 2) * 0.5, 2) {
                // The surviving second point's vector keeps pointing at the spliced-out point.
                anchor = Vec(p.pointX[i], p.pointY[i])
                s += 1
            } else {
                break
            }
        }

        let endX = bElbow ? p.inputX[b] : p.pointX[b]
        let endY = bElbow ? p.inputY[b] : p.pointY[b]
        let endRadius = p.radii[b]
        while len - s - e > 2 {
            let i = bDup ? b - e : b - 1 - e
            let dx = endX - p.pointX[i]
            let dy = endY - p.pointY[i]
            if dx * dx + dy * dy < pow(((endRadius + p.radii[i]) / 2) * 0.5, 2) {
                e += 1
            } else {
                break
            }
        }

        let innerStart = a + 1 + s
        let innerEnd = bDup ? b - e : b - 1 - e
        var src = TrackSource()
        src.loadPartition(
            from: p,
            a: a, aElbow: aElbow,
            innerStart: innerStart, innerEnd: innerEnd,
            b: b, bElbow: bElbow,
            dupQuirk: bDup && e == 0
        )
        renderPartition(src, options, anchor: anchor, sink)
    }

    /// Render one partition: up the left track as quadratics through midpoints, around the end cap
    /// arc, back down the right track, then the start cap arc.
    private static func renderPartition(_ src: TrackSource, _ options: StrokeOptions, anchor: Vec?, _ sink: InkPathSink) {
        let n = src.count
        guard n > 0 else { return }
        if n == 1 {
            sink.circle(center: Vec(src.x[0], src.y[0]), radius: src.radius[0])
            return
        }

        let tracks = StrokeOutline.buildTracks(src, options, anchor: anchor)
        guard tracks.leftCount > 0, tracks.rightCount > 0 else { return }

        sink.move(to: Vec(tracks.leftX[0], tracks.leftY[0]))

        // The left track, as quadratics through the midpoints of consecutive points.
        var prev = Vec(tracks.leftX[0], tracks.leftY[0])
        if tracks.leftCount > 1 {
            for i in 1..<tracks.leftCount {
                let pt = Vec(tracks.leftX[i], tracks.leftY[i])
                sink.smoothQuad(to: Vec((prev.x + pt.x) / 2, (prev.y + pt.y) / 2))
                prev = pt
            }
        }

        // The end cap arc, whose endpoints sit one radius to each side of the last point,
        // perpendicular to the vector pointing back at its nearest neighbour.
        do {
            let point = Vec(src.x[n - 1], src.y[n - 1])
            let radius = src.radius[n - 1]
            let vdx = src.x[n - 2] - point.x
            let vdy = src.y[n - 2] - point.y
            let vlen = (vdx * vdx + vdy * vdy).squareRoot()
            let dx = (-vdy / vlen) * radius
            let dy = (vdx / vlen) * radius
            sink.smoothQuad(to: Vec(point.x + dx, point.y + dy))
            sink.arc(radius: radius, to: Vec(point.x - dx, point.y - dy))
            sink.breakSmoothRun()
        }

        // The right track in reverse.
        prev = Vec(tracks.rightX[tracks.rightCount - 1], tracks.rightY[tracks.rightCount - 1])
        if tracks.rightCount > 1 {
            for i in stride(from: tracks.rightCount - 2, through: 0, by: -1) {
                let pt = Vec(tracks.rightX[i], tracks.rightY[i])
                sink.smoothQuad(to: Vec((prev.x + pt.x) / 2, (prev.y + pt.y) / 2))
                prev = pt
            }
        }

        // The start cap arc.
        do {
            let point = Vec(src.x[0], src.y[0])
            let radius = src.radius[0]
            let vdx = point.x - src.x[1]
            let vdy = point.y - src.y[1]
            let vlen = (vdx * vdx + vdy * vdy).squareRoot()
            let dx = (vdy / vlen) * radius
            let dy = (-vdx / vlen) * radius
            sink.smoothQuad(to: Vec(point.x + dx, point.y + dy))
            sink.arc(radius: radius, to: Vec(point.x - dx, point.y - dy))
            sink.close()
        }
    }
}
