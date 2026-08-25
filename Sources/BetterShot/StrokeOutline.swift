import Foundation

/// Phase 3 of the freehand pipeline: turn stroke points into the left and right outline tracks,
/// then close them off with caps.
enum StrokeOutline {
    /// Browser strokes seem to be off if PI is regular; a tiny offset fixes it.
    static let fixedPI = PI + 0.0001

    /// How far the simplified tracks may deviate from the raw tracks, as a fraction of stroke size.
    private static let trackToleranceRatio = 0.05
    /// The maximum number of intermediate points the simplifier may drop per kept segment.
    private static let simplifyWindow = 8

    private static let minRoundedCornerSteps = 8
    private static let maxRoundedCornerSteps = 13
    private static let minCapSteps = 8
    private static let maxCapSteps = 29

    /// Dot product threshold for identifying a hard corner.
    private static let hardCornerDpr = -0.62

    struct Tracks {
        var leftX: [Double] = []
        var leftY: [Double] = []
        var rightX: [Double] = []
        var rightY: [Double] = []
        var leftCount = 0
        var rightCount = 0

        var left: [Vec] { (0..<leftCount).map { Vec(leftX[$0], leftY[$0]) } }
        var right: [Vec] { (0..<rightCount).map { Vec(rightX[$0], rightY[$0]) } }
    }

    /// Drop track points that lie within `tol` of the segment between their kept neighbours. The
    /// tracks are dense on gentle curves where the quadratic smoothing used for rendering needs far
    /// fewer points.
    private static func simplifyTrack(_ xs: inout [Double], _ ys: inout [Double], _ len: Int, _ tol: Double) -> Int {
        if len <= 2 || tol <= 0 { return len }
        let tol2 = tol * tol
        var out = 1
        var anchor = 0
        let lastIdx = len - 1
        while anchor < lastIdx {
            var best = anchor + 1
            let maxJ = Swift.min(anchor + simplifyWindow, lastIdx)
            let ax = xs[anchor]
            let ay = ys[anchor]
            if anchor + 2 <= maxJ {
                outer: for j in (anchor + 2)...maxJ {
                    let acx = xs[j] - ax
                    let acy = ys[j] - ay
                    let l2 = acx * acx + acy * acy
                    for k in (anchor + 1)..<j {
                        var t = l2 == 0 ? 0 : ((xs[k] - ax) * acx + (ys[k] - ay) * acy) / l2
                        t = t < 0 ? 0 : (t > 1 ? 1 : t)
                        let ex = xs[k] - (ax + acx * t)
                        let ey = ys[k] - (ay + acy * t)
                        if ex * ex + ey * ey > tol2 { break outer }
                    }
                    best = j
                }
            }
            // Compaction never overtakes the read cursor: the `out`th kept index is always >= out.
            xs[out] = xs[best]
            ys[out] = ys[best]
            out += 1
            anchor = best
        }
        return out
    }

    /// Build the left and right outline tracks for a track source.
    ///
    /// `anchor` carries the original predecessor of point 1 when the caller has cut the sequence in
    /// front of it (the ink renderer's elbow partitions): the second point's vector is then derived
    /// from the anchor rather than from point 0, preserving the direction it had in the uncut
    /// stroke. It only applies when there are more than two points.
    static func buildTracks(_ src: TrackSource, _ options: StrokeOptions, anchor: Vec? = nil) -> Tracks {
        var tracks = Tracks()
        let size = options.size
        let smoothing = options.smoothing

        let n = src.count
        guard n > 0, size > 0 else { return tracks }

        // Worst case, every point contributes a full rounded corner.
        let capacity = n * (maxRoundedCornerSteps + 1) + maxRoundedCornerSteps
        var lxs = [Double](repeating: 0, count: capacity)
        var lys = [Double](repeating: 0, count: capacity)
        var rxs = [Double](repeating: 0, count: capacity)
        var rys = [Double](repeating: 0, count: capacity)
        var lc = 0
        var rc = 0

        let totalLength = src.runningLength[n - 1]
        let minDistance = pow(size * smoothing, 2)

        // A point's vector is the unit vector pointing back at its predecessor. The first point
        // shares the second point's vector; a lone point keeps the legacy unnormalized (1, 1).
        var curVecX = 1.0
        var curVecY = 1.0
        if n > 1 {
            let dx = src.x[0] - src.x[1]
            let dy = src.y[0] - src.y[1]
            let l = (dx * dx + dy * dy).squareRoot()
            if l == 0 {
                curVecX = dx
                curVecY = dy
            } else {
                curVecX = dx / l
                curVecY = dy / l
            }
        }

        var prevVecX = curVecX
        var prevVecY = curVecY

        var plx = src.x[0]
        var ply = src.y[0]
        var prx = plx
        var pry = ply

        var tlx = plx
        var tly = ply
        var trx = prx
        var trY = pry

        // Track whether the previous point was a sharp corner, so the same corner isn't
        // detected twice.
        var isPrevPointSharpCorner = false

        for i in 0..<n {
            let pointX = src.x[i]
            let pointY = src.y[i]
            let radius = src.radius[i]
            let vecX = curVecX
            let vecY = curVecY

            // Derive the next point's vector (the last point reuses its own), and advance the
            // running vector so the next iteration picks it up regardless of the `continue`s below.
            var nextVecX = vecX
            var nextVecY = vecY
            if i < n - 1 {
                let useAnchor = i == 0 && n > 2 && anchor != nil
                let fromX = useAnchor ? anchor!.x : pointX
                let fromY = useAnchor ? anchor!.y : pointY
                let dx = fromX - src.x[i + 1]
                let dy = fromY - src.y[i + 1]
                let l = (dx * dx + dy * dy).squareRoot()
                if l == 0 {
                    nextVecX = dx
                    nextVecY = dy
                } else {
                    nextVecX = dx / l
                    nextVecY = dy / l
                }
            }
            curVecX = nextVecX
            curVecY = nextVecY

            // Handle sharp corners: if the next vector is at more than a right angle to the
            // current one, draw a cap at the current point and move on.
            let prevDpr = vecX * prevVecX + vecY * prevVecY
            let nextDpr = i < n - 1 ? nextVecX * vecX + nextVecY * vecY : 1

            let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
            let isNextPointSharpCorner = nextDpr < 0.2

            if isPointSharpCorner || isNextPointSharpCorner {
                if nextDpr > hardCornerDpr && totalLength - src.runningLength[i] > radius {
                    // A "soft" corner.
                    let offsetX = prevVecX * radius
                    let offsetY = prevVecY * radius
                    let cpr = prevVecX * nextVecY - prevVecY * nextVecX

                    if cpr < 0 {
                        tlx = pointX + offsetX
                        tly = pointY + offsetY
                        trx = pointX - offsetX
                        trY = pointY - offsetY
                    } else {
                        tlx = pointX - offsetX
                        tly = pointY - offsetY
                        trx = pointX + offsetX
                        trY = pointY + offsetY
                    }

                    lxs[lc] = tlx; lys[lc] = tly; lc += 1
                    rxs[rc] = trx; rys[rc] = trY; rc += 1
                } else {
                    // A "sharp" corner: rotate around the input point. The arm swept around the
                    // point starts perpendicular to the incoming direction, one radius long.
                    let inX = src.inputX[i]
                    let inY = src.inputY[i]
                    let dx = -prevVecY * radius
                    let dy = prevVecX * radius

                    let step = 1.0 / Double(maxRoundedCornerSteps)
                    var t = 0.0
                    while t < 1 {
                        var angle = fixedPI * t
                        var s = sin(angle)
                        var c = cos(angle)
                        tlx = inX + (dx * c - dy * s)
                        tly = inY + (dx * s + dy * c)
                        lxs[lc] = tlx; lys[lc] = tly; lc += 1

                        angle = fixedPI + fixedPI * -t
                        s = sin(angle)
                        c = cos(angle)
                        trx = inX + (dx * c - dy * s)
                        trY = inY + (dx * s + dy * c)
                        rxs[rc] = trx; rys[rc] = trY; rc += 1

                        t += step
                    }
                }

                plx = tlx
                ply = tly
                prx = trx
                pry = trY

                if isNextPointSharpCorner { isPrevPointSharpCorner = true }
                continue
            }

            isPrevPointSharpCorner = false

            if src.isCap[i] {
                // Project one radius to each side, perpendicular to the direction of travel.
                let offsetX = vecY * radius
                let offsetY = -vecX * radius
                lxs[lc] = pointX - offsetX; lys[lc] = pointY - offsetY; lc += 1
                rxs[rc] = pointX + offsetX; rys[rc] = pointY + offsetY; rc += 1
                continue
            }

            // Regular points: project to either side, blending the current and next vectors so the
            // offset leans into the next vector as the upcoming turn sharpens. Points closer to
            // their predecessor on that side than the minimum distance are dropped.
            let lerpedX = nextVecX + (vecX - nextVecX) * nextDpr
            let lerpedY = nextVecY + (vecY - nextVecY) * nextDpr
            let offsetX = lerpedY * radius
            let offsetY = -lerpedX * radius

            tlx = pointX - offsetX
            tly = pointY - offsetY

            if i <= 1 || pow(plx - tlx, 2) + pow(ply - tly, 2) > minDistance {
                lxs[lc] = tlx; lys[lc] = tly; lc += 1
                plx = tlx
                ply = tly
            }

            trx = pointX + offsetX
            trY = pointY + offsetY

            if i <= 1 || pow(prx - trx, 2) + pow(pry - trY, 2) > minDistance {
                rxs[rc] = trx; rys[rc] = trY; rc += 1
                prx = trx
                pry = trY
            }

            prevVecX = vecX
            prevVecY = vecY
        }

        let tolerance = size * trackToleranceRatio
        tracks.leftCount = simplifyTrack(&lxs, &lys, lc, tolerance)
        tracks.rightCount = simplifyTrack(&rxs, &rys, rc, tolerance)
        tracks.leftX = lxs
        tracks.leftY = lys
        tracks.rightX = rxs
        tracks.rightY = rys
        return tracks
    }

    /// Pick a step count for a polygonal arc so its chord error stays within `tol`.
    private static func arcSteps(_ radius: Double, _ sweep: Double, _ tol: Double, _ minSteps: Int, _ maxSteps: Int) -> Int {
        if radius <= tol { return minSteps }
        let maxAngle = 2 * acos(1 - tol / radius)
        let steps = Int(ceil(sweep / maxAngle))
        return Swift.min(Swift.max(steps, minSteps), maxSteps)
    }

    /// The full outline (tracks plus caps) for a track source, in winding order: up the left side,
    /// around the end cap, back down the right side, then the start cap.
    static func outline(_ src: TrackSource, _ options: StrokeOptions) -> [Vec] {
        let size = options.size
        let capStart = options.start.cap
        let capEnd = options.end.cap
        let isComplete = options.last

        let n = src.count
        guard n > 0, size > 0 else { return [] }

        let totalLength = src.runningLength[n - 1]
        let taperStart = resolveTaper(options.start.taper, size, totalLength)
        let taperEnd = resolveTaper(options.end.taper, size, totalLength)

        let tracks = buildTracks(src, options)

        // Caps don't need a fixed number of segments, just enough that the polygon is
        // indistinguishable from the arc.
        let capTolerance = Swift.max(0.05, size * 0.02)

        let firstRadius = src.radius[0]
        let firstPoint = Vec(src.x[0], src.y[0], src.z[0])
        let lastPoint = n > 1
            ? Vec(src.x[n - 1], src.y[n - 1], src.z[n - 1])
            : Vec.addXY(firstPoint, 1, 1)

        // Draw a dot for very short or completed strokes.
        if n == 1 {
            if (taperStart == 0 && taperEnd == 0) || isComplete {
                let start = Vec.add(
                    firstPoint,
                    Vec.mul(Vec.sub(firstPoint, lastPoint).uni.per, -firstRadius)
                )
                var dotPts: [Vec] = []
                let steps = arcSteps(firstRadius, fixedPI * 2, capTolerance, minRoundedCornerSteps, maxRoundedCornerSteps)
                let step = 1.0 / Double(steps)
                var t = step
                while t <= 1 {
                    dotPts.append(Vec.rotWith(start, firstPoint, fixedPI * 2 * t))
                    t += step
                }
                return dotPts
            }
        }

        guard tracks.leftCount > 0, tracks.rightCount > 0 else { return [] }

        // The start cap. Unless the line has a tapered start (or a tapered end and is very short),
        // rotate the first right point around the start point to the first left point.
        var startCap: [Vec] = []
        if taperStart != 0 || (taperEnd != 0 && n == 1) {
            // Tapered start: no cap.
        } else if capStart {
            let firstRight = Vec(tracks.rightX[0], tracks.rightY[0])
            let steps = arcSteps(firstRadius, fixedPI, capTolerance, 4, 8)
            let step = 1.0 / Double(steps)
            var t = step
            while t <= 1 {
                startCap.append(Vec.rotWith(firstRight, firstPoint, fixedPI * t))
                t += step
            }
        } else {
            // A flat cap: a point to the left and right of the start point.
            let cornersVector = Vec(
                tracks.leftX[0] - tracks.rightX[0],
                tracks.leftY[0] - tracks.rightY[0]
            )
            let offsetA = Vec.mul(cornersVector, 0.5)
            let offsetB = Vec.mul(cornersVector, 0.51)
            startCap.append(contentsOf: [
                Vec.sub(firstPoint, offsetA),
                Vec.sub(firstPoint, offsetB),
                Vec.add(firstPoint, offsetB),
                Vec.add(firstPoint, offsetA),
            ])
        }

        // The end cap. This is a full turn and a half, which prevents incorrect caps on sharp
        // end turns.
        var endCap: [Vec] = []
        let lastRadius = src.radius[n - 1]

        // The exit vector at the last point points back at its predecessor; the cap starts
        // perpendicular to it.
        var lastVecX = 1.0
        var lastVecY = 1.0
        if n > 1 {
            let dx = src.x[n - 2] - src.x[n - 1]
            let dy = src.y[n - 2] - src.y[n - 1]
            let l = (dx * dx + dy * dy).squareRoot()
            if l == 0 {
                lastVecX = dx
                lastVecY = dy
            } else {
                lastVecX = dx / l
                lastVecY = dy / l
            }
        }
        let direction = Vec(-lastVecY, lastVecX)

        if taperEnd != 0 || (taperStart != 0 && n == 1) {
            endCap.append(lastPoint)
        } else if capEnd {
            let start = Vec.add(lastPoint, Vec.mul(direction, lastRadius))
            let steps = arcSteps(lastRadius, fixedPI * 3, capTolerance, minCapSteps, maxCapSteps)
            let step = 1.0 / Double(steps)
            var t = step
            while t < 1 {
                endCap.append(Vec.rotWith(start, lastPoint, fixedPI * 3 * t))
                t += step
            }
        } else {
            endCap.append(contentsOf: [
                Vec.add(lastPoint, Vec.mul(direction, lastRadius)),
                Vec.add(lastPoint, Vec.mul(direction, lastRadius * 0.99)),
                Vec.sub(lastPoint, Vec.mul(direction, lastRadius * 0.99)),
                Vec.sub(lastPoint, Vec.mul(direction, lastRadius)),
            ])
        }

        var result = tracks.left
        result.append(contentsOf: endCap)
        result.append(contentsOf: (0..<tracks.rightCount).reversed().map {
            Vec(tracks.rightX[$0], tracks.rightY[$0])
        })
        result.append(contentsOf: startCap)
        return result
    }

    /// The complete pipeline: raw points in, outline polygon out.
    static func getStroke(_ points: [Vec], _ options: StrokeOptions) -> [Vec] {
        let pipeline = StrokePipeline()
        pipeline.ingest(points, options)
        guard pipeline.pointCount > 0 else { return [] }
        pipeline.computeRadii(options)
        var src = TrackSource()
        src.load(from: pipeline)
        return outline(src, options)
    }

    /// The streamlined centerline for raw points, used for geometry.
    static func getStrokePoints(_ points: [Vec], _ options: StrokeOptions) -> [StrokePoint] {
        let pipeline = StrokePipeline()
        pipeline.ingest(points, options)
        return pipeline.strokePoints()
    }
}
