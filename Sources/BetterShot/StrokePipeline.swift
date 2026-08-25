import Foundation

/// One point of a freehand stroke after streamlining.
struct StrokePoint {
    var point: Vec
    var input: Vec
    var pressure: Double
    var distance: Double
    var runningLength: Double
    var radius: Double
}

/// Phase 1 and 2 of the freehand pipeline: ingest raw input into streamlined points, then
/// give each point a radius from its pressure, speed and position along the stroke.
///
/// Storage lives as instance state on a class that callers own, giving a "fill once, consume
/// once" shape without any global/module-level state.
final class StrokePipeline {
    private static let minPressure = 0.025
    /// The rate of change for simulated pressure.
    private static let rateOfPressureChange = 0.275

    var pointX: [Double] = []
    var pointY: [Double] = []
    var inputX: [Double] = []
    var inputY: [Double] = []
    var inputZ: [Double] = []
    var pressures: [Double] = []
    var distances: [Double] = []
    var runningLengths: [Double] = []
    var radii: [Double] = []
    var pointCount = 0

    private func reserve(_ n: Int) {
        if pointX.count >= n { return }
        let extra = n - pointX.count
        pointX.append(contentsOf: repeatElement(0, count: extra))
        pointY.append(contentsOf: repeatElement(0, count: extra))
        inputX.append(contentsOf: repeatElement(0, count: extra))
        inputY.append(contentsOf: repeatElement(0, count: extra))
        inputZ.append(contentsOf: repeatElement(0, count: extra))
        pressures.append(contentsOf: repeatElement(0, count: extra))
        distances.append(contentsOf: repeatElement(0, count: extra))
        runningLengths.append(contentsOf: repeatElement(0, count: extra))
        radii.append(contentsOf: repeatElement(0, count: extra))
    }

    /// The z of a raw input point after the pressure clamp.
    private static func zOf(_ p: Vec, _ clampZ: Bool) -> Double {
        let z = p.z
        // Some pens or OSes report z=0 even while the pen is touching, so clamp rather than strip.
        return clampZ && z < minPressure ? minPressure : z
    }

    /// Phase 1: ingest and streamline raw input points.
    ///
    /// Every order-sensitive step is kept: the pressure clamp, near-start and near-end
    /// stripping, the two-point simulated-pressure interpolation, the early-noise skip and the
    /// short-stroke pressure fixup.
    func ingest(_ rawInputPoints: [Vec], _ options: StrokeOptions) {
        pointCount = 0
        let rawLen = rawInputPoints.count
        guard rawLen > 0 else { return }

        let streamline = options.streamline
        let size = options.size
        let simulatePressure = options.simulatePressure

        // The interpolation level between points.
        let t = 0.15 + (1 - streamline) * 0.85

        reserve(rawLen + 8)
        var stageX = [Double](repeating: 0, count: rawLen + 8)
        var stageY = [Double](repeating: 0, count: rawLen + 8)
        var stageZ = [Double](repeating: 0, count: rawLen + 8)

        let minDist2 = (size / 3) * (size / 3)
        let clampZ = !simulatePressure

        // Strip points too close to the first point, keeping the maximum pressure among them.
        let first = rawInputPoints[0]
        var firstZ = Self.zOf(first, clampZ)
        var startIdx = 1
        while startIdx < rawLen {
            let pt = rawInputPoints[startIdx]
            let dx = pt.x - first.x
            let dy = pt.y - first.y
            if dx * dx + dy * dy > minDist2 { break }
            firstZ = Swift.max(firstZ, Self.zOf(pt, clampZ))
            startIdx += 1
        }

        stageX[0] = first.x
        stageY[0] = first.y
        stageZ[0] = firstZ
        var m = 1
        if startIdx < rawLen {
            for i in startIdx..<rawLen {
                let pt = rawInputPoints[i]
                stageX[m] = pt.x
                stageY[m] = pt.y
                stageZ[m] = Self.zOf(pt, clampZ)
                m += 1
            }
        }

        // Strip points too close to the last point. This can consume the whole sequence.
        var pointsRemovedFromNearEnd = 0
        if m > 1 {
            let lastX = stageX[m - 1]
            let lastY = stageY[m - 1]
            var j = m - 2
            while j >= 0 {
                let dx = stageX[j] - lastX
                let dy = stageY[j] - lastY
                if dx * dx + dy * dy > minDist2 { break }
                j -= 1
                pointsRemovedFromNearEnd += 1
            }
            if j < m - 2 {
                stageX[j + 1] = lastX
                stageY[j + 1] = lastY
                stageZ[j + 1] = stageZ[m - 1]
                m = j + 2
            }
        }

        let lastSegmentIsShort: Bool = {
            guard m > 1 else { return false }
            let dx = stageX[m - 1] - stageX[m - 2]
            let dy = stageY[m - 1] - stageY[m - 2]
            return dx * dx + dy * dy < size * size
        }()

        let isComplete = options.last
            || !options.simulatePressure
            || lastSegmentIsShort
            || pointsRemovedFromNearEnd > 0

        // Add extra points between the two, to avoid "dash" lines for tapered strokes.
        if m == 2 && options.simulatePressure {
            let x0 = stageX[0], y0 = stageY[0], z0 = stageZ[0]
            let x1 = stageX[1], y1 = stageY[1], z1 = stageZ[1]
            for i in 1..<5 {
                let u = Double(i) / 4
                stageX[i] = x0 + (x1 - x0) * u
                stageY[i] = y0 + (y1 - y0) * u
                stageZ[i] = ((z0 + (z1 - z0)) * Double(i)) / 4
            }
            m = 5
        }

        // The first point needs no adjustment.
        pointX[0] = stageX[0]
        pointY[0] = stageY[0]
        inputX[0] = stageX[0]
        inputY[0] = stageY[0]
        inputZ[0] = stageZ[0]
        pressures[0] = simulatePressure ? 0.5 : stageZ[0]
        distances[0] = 0
        runningLengths[0] = 0
        radii[0] = 1
        var count = 1

        if isComplete && streamline > 0 {
            stageX[m] = stageX[m - 1]
            stageY[m] = stageY[m - 1]
            stageZ[m] = stageZ[m - 1]
            m += 1
        }

        var totalLength = 0.0
        var prevX = stageX[0]
        var prevY = stageY[0]
        let u = 1 - t
        let isLast = options.last

        if m > 1 {
            for i in 1..<m {
                var x: Double
                var y: Double
                if t == 0 || (isLast && i == m - 1) {
                    x = stageX[i]
                    y = stageY[i]
                } else {
                    x = stageX[i] + (prevX - stageX[i]) * u
                    y = stageY[i] + (prevY - stageY[i]) * u
                }

                // If the new point is the same as the previous point, skip ahead.
                if abs(prevX - x) < 0.0001 && abs(prevY - y) < 0.0001 { continue }

                let distance = ((y - prevY) * (y - prevY) + (x - prevX) * (x - prevX)).squareRoot()
                totalLength += distance

                // At the start of the line, wait until the new point is far enough from the
                // original point to avoid noise.
                if i < 4 && totalLength < size { continue }

                pointX[count] = x
                pointY[count] = y
                inputX[count] = stageX[i]
                inputY[count] = stageY[i]
                inputZ[count] = stageZ[i]
                pressures[count] = simulatePressure ? 0.5 : stageZ[i]
                distances[count] = distance
                runningLengths[count] = totalLength
                radii[count] = 1
                count += 1
                prevX = x
                prevY = y
            }
        }

        if totalLength < 1 {
            var maxPressure = 0.5
            for i in 0..<count { maxPressure = Swift.max(maxPressure, pressures[i]) }
            for i in 0..<count { pressures[i] = maxPressure }
        }

        pointCount = count
    }

    /// Phase 2: compute each point's radius from its pressure, distance and running length.
    func computeRadii(_ options: StrokeOptions) {
        let size = options.size
        let thinning = options.thinning
        let simulatePressure = options.simulatePressure
        let easing = options.easing
        let taperStartEase = options.start.easing ?? Easings.easeOutQuad
        let taperEndEase = options.end.easing ?? Easings.easeOutCubic

        let n = pointCount
        guard n > 0 else { return }

        let totalLength = runningLengths[n - 1]

        if !simulatePressure && totalLength < size {
            var maxPressure = 0.5
            for i in 0..<n { maxPressure = Swift.max(maxPressure, pressures[i]) }
            for i in 0..<n {
                pressures[i] = maxPressure
                radii[i] = size * easing(0.5 - thinning * (0.5 - maxPressure))
            }
            return
        }

        // Seed the pressure from the average over the first stretch of the stroke. This prevents
        // "dots" at the start of the line - drawn lines almost always start slow.
        var prevPressure = pressures[0]
        for i in 0..<n {
            if runningLengths[i] > size * 5 { break }
            let sp = Swift.min(1, distances[i] / size)
            let p: Double
            if simulatePressure {
                let rp = Swift.min(1, 1 - sp)
                p = Swift.min(1, prevPressure + (rp - prevPressure) * (sp * Self.rateOfPressureChange))
            } else {
                p = Swift.min(1, prevPressure + (pressures[i] - prevPressure) * 0.5)
            }
            prevPressure = prevPressure + (p - prevPressure) * 0.5
        }

        let taperStart = resolveTaper(options.start.taper, size, totalLength)
        let taperEnd = resolveTaper(options.end.taper, size, totalLength)
        let hasTaper = taperStart != 0 || taperEnd != 0

        for i in 0..<n {
            var radius: Double
            if thinning != 0 {
                var pressure = pressures[i]
                let sp = Swift.min(1, distances[i] / size)
                if simulatePressure {
                    // Simulated pressure comes from the distance between this point and the last,
                    // relative to the size of the stroke.
                    let rp = Swift.min(1, 1 - sp)
                    pressure = Swift.min(1, prevPressure + (rp - prevPressure) * (sp * Self.rateOfPressureChange))
                } else {
                    // Otherwise use the input pressure, smoothed by that same distance.
                    pressure = Swift.min(1, prevPressure + (pressure - prevPressure) * (sp * Self.rateOfPressureChange))
                }
                radius = size * easing(0.5 - thinning * (0.5 - pressure))
                prevPressure = pressure
            } else {
                radius = size / 2
            }

            if hasTaper {
                let runningLength = runningLengths[i]
                let ts = taperStart != 0 && runningLength < taperStart
                    ? taperStartEase(runningLength / taperStart)
                    : 1
                let te = taperEnd != 0 && totalLength - runningLength < taperEnd
                    ? taperEndEase((totalLength - runningLength) / taperEnd)
                    : 1
                radius = Swift.max(0.01, radius * Swift.min(ts, te))
            }

            radii[i] = radius
        }
    }

    /// The streamlined points as `StrokePoint`s, for callers that want the centerline (geometry,
    /// hit testing) rather than an outline.
    func strokePoints() -> [StrokePoint] {
        (0..<pointCount).map { i in
            let input = Vec(inputX[i], inputY[i], inputZ[i])
            // The first point needs no adjustment, so its point and input are the same.
            let point = i == 0 ? input : Vec(pointX[i], pointY[i], inputZ[i])
            return StrokePoint(
                point: point,
                input: input,
                pressure: pressures[i],
                distance: distances[i],
                runningLength: runningLengths[i],
                radius: radii[i]
            )
        }
    }
}

/// The subsequence of stroke points that the outline tracks are built from: the whole stroke for a
/// plain outline, or one elbow partition at a time when rendering ink.
///
/// `isCap` marks points to treat as the first/last point when placing the outline, decided by
/// an identity check against the first and last point objects.
struct TrackSource {
    var x: [Double] = []
    var y: [Double] = []
    var z: [Double] = []
    var inputX: [Double] = []
    var inputY: [Double] = []
    var radius: [Double] = []
    var runningLength: [Double] = []
    var isCap: [Bool] = []
    var count = 0

    private mutating func reserve(_ n: Int) {
        guard x.count < n else { return }
        let extra = n - x.count
        x.append(contentsOf: repeatElement(0, count: extra))
        y.append(contentsOf: repeatElement(0, count: extra))
        z.append(contentsOf: repeatElement(0, count: extra))
        inputX.append(contentsOf: repeatElement(0, count: extra))
        inputY.append(contentsOf: repeatElement(0, count: extra))
        radius.append(contentsOf: repeatElement(0, count: extra))
        runningLength.append(contentsOf: repeatElement(0, count: extra))
        isCap.append(contentsOf: repeatElement(false, count: extra))
    }

    /// Load the whole pipeline as the track source.
    mutating func load(from p: StrokePipeline) {
        let n = p.pointCount
        reserve(n)
        for i in 0..<n {
            x[i] = p.pointX[i]
            y[i] = p.pointY[i]
            z[i] = p.inputZ[i]
            inputX[i] = p.inputX[i]
            inputY[i] = p.inputY[i]
            radius[i] = p.radii[i]
            runningLength[i] = p.runningLengths[i]
            isCap[i] = i == 0 || i == n - 1
        }
        count = n
    }

    mutating func load(from strokePoints: [StrokePoint]) {
        let n = strokePoints.count
        reserve(n)
        for i in 0..<n {
            let sp = strokePoints[i]
            x[i] = sp.point.x
            y[i] = sp.point.y
            z[i] = sp.point.z
            inputX[i] = sp.input.x
            inputY[i] = sp.input.y
            radius[i] = sp.radius
            runningLength[i] = sp.runningLength
            isCap[i] = i == 0 || i == n - 1
        }
        count = n
    }

    /// Load one elbow partition: boundary point `a`, the surviving inner points, and boundary
    /// point `b`. Elbow boundaries read the input coordinates instead of the streamlined ones.
    mutating func loadPartition(
        from p: StrokePipeline,
        a: Int,
        aElbow: Bool,
        innerStart: Int,
        innerEnd: Int,
        b: Int,
        bElbow: Bool,
        dupQuirk: Bool
    ) {
        reserve(innerEnd - innerStart + 3)
        x[0] = aElbow ? p.inputX[a] : p.pointX[a]
        y[0] = aElbow ? p.inputY[a] : p.pointY[a]
        z[0] = p.inputZ[a]
        inputX[0] = p.inputX[a]
        inputY[0] = p.inputY[a]
        radius[0] = p.radii[a]
        runningLength[0] = p.runningLengths[a]
        isCap[0] = true

        var w = 1
        if innerStart <= innerEnd {
            for i in innerStart...innerEnd {
                x[w] = p.pointX[i]
                y[w] = p.pointY[i]
                z[w] = p.inputZ[i]
                inputX[w] = p.inputX[i]
                inputY[w] = p.inputY[i]
                radius[w] = p.radii[i]
                runningLength[w] = p.runningLengths[i]
                isCap[w] = false
                w += 1
            }
        }
        // A hard elbow whose duplicated end point survived cleanup: both slots held the same
        // point object, so the inner copy is a cap point too.
        if dupQuirk && w > 1 { isCap[w - 1] = true }

        x[w] = bElbow ? p.inputX[b] : p.pointX[b]
        y[w] = bElbow ? p.inputY[b] : p.pointY[b]
        z[w] = p.inputZ[b]
        inputX[w] = p.inputX[b]
        inputY[w] = p.inputY[b]
        radius[w] = p.radii[b]
        runningLength[w] = p.runningLengths[b]
        isCap[w] = true
        count = w + 1
    }
}
