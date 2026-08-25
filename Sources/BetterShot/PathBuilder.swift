import CoreGraphics
import Foundation

/// Builds a path once and renders it either solid or in old-apps's "draw" style - two jittered
/// passes with rounded corners, which is what makes a rectangle look hand-drawn.
///
/// Ported from `packages/old-apps/src/lib/shapes/shared/PathBuilder.tsx`, keeping the parts that
/// matter for geo shapes and arrows (move / line / cubic / arc, solid and draw rendering).
final class PathBuilder {
    struct CommandOpts {
        /// How far from the original point a draw-style pass may wander.
        var offset: Double?
        /// How much roundness to apply to the corner at the end of this command.
        var roundness: Double?
    }

    enum Kind {
        case move
        case line
        case cubic(cp1: Vec, cp2: Vec)
    }

    struct Command {
        var kind: Kind
        var point: Vec
        var isClose: Bool = false
        var opts = CommandOpts()
    }

    private(set) var commands: [Command] = []
    private var lastMoveToIdx: Int?

    @discardableResult
    func move(to p: Vec, opts: CommandOpts = CommandOpts()) -> PathBuilder {
        commands.append(Command(kind: .move, point: p, opts: opts))
        lastMoveToIdx = commands.count - 1
        return self
    }

    @discardableResult
    func line(to p: Vec, opts: CommandOpts = CommandOpts()) -> PathBuilder {
        commands.append(Command(kind: .line, point: p, opts: opts))
        return self
    }

    @discardableResult
    func cubic(to p: Vec, cp1: Vec, cp2: Vec, opts: CommandOpts = CommandOpts()) -> PathBuilder {
        commands.append(Command(kind: .cubic(cp1: cp1, cp2: cp2), point: p, opts: opts))
        return self
    }

    @discardableResult
    func close() -> PathBuilder {
        guard let moveIdx = lastMoveToIdx, let last = commands.last else { return self }
        let movePoint = commands[moveIdx].point
        if approximately(movePoint.x, last.point.x) && approximately(movePoint.y, last.point.y) {
            commands[commands.count - 1].isClose = true
        } else {
            commands.append(Command(kind: .line, point: movePoint, isClose: true))
        }
        return self
    }

    @discardableResult
    func circularArc(radius: Double, largeArc: Bool, sweep: Bool, to p: Vec, opts: CommandOpts = CommandOpts()) -> PathBuilder {
        arc(rx: radius, ry: radius, largeArc: largeArc, sweep: sweep, xAxisRotation: 0, to: p, opts: opts)
    }

    /// Approximate an SVG elliptical arc with up to four cubic segments, one per quadrant.
    ///
    /// old-apps does this because arc flags make arcs very sensitive to the offsets applied in draw
    /// mode; cubics jitter predictably.
    @discardableResult
    func arc(rx: Double, ry: Double, largeArc: Bool, sweep: Bool, xAxisRotation: Double, to p2: Vec, opts: CommandOpts = CommandOpts()) -> PathBuilder {
        guard let last = commands.last else { return self }
        let p1 = last.point
        if p1.x == p2.x && p1.y == p2.y { return self }
        if rx == 0 || ry == 0 { return line(to: p2, opts: opts) }

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
        let sweepAngle = endAngle - startAngle

        func ellipsePoint(_ angle: Double) -> Vec {
            Vec(
                cx + rx1 * cos(angle) * cosPhi - ry1 * sin(angle) * sinPhi,
                cy + rx1 * cos(angle) * sinPhi + ry1 * sin(angle) * cosPhi
            )
        }
        func ellipseDerivative(_ angle: Double) -> Vec {
            Vec(
                -rx1 * sin(angle) * cosPhi - ry1 * cos(angle) * sinPhi,
                -rx1 * sin(angle) * sinPhi + ry1 * cos(angle) * cosPhi
            )
        }

        let numSegments = Swift.max(1, Swift.min(4, Int(ceil(abs(sweepAngle) / HALF_PI))))
        let anglePerSegment = sweepAngle / Double(numSegments)

        for i in 0..<numSegments {
            let theta1 = startAngle + Double(i) * anglePerSegment
            let theta2 = startAngle + Double(i + 1) * anglePerSegment
            let start = ellipsePoint(theta1)
            let end = ellipsePoint(theta2)
            let d1 = ellipseDerivative(theta1)
            let d2 = ellipseDerivative(theta2)
            // For a 90° arc the handle length is 4/3 * tan(π/8) * r; smaller arcs scale by angle.
            let handleScale = (4.0 / 3.0) * tan((theta2 - theta1) / 4)
            let cp1 = Vec(start.x + handleScale * d1.x, start.y + handleScale * d1.y)
            let cp2 = Vec(end.x - handleScale * d2.x, end.y - handleScale * d2.y)
            cubic(to: end, cp1: cp1, cp2: cp2, opts: i == 0 ? opts : CommandOpts())
        }
        return self
    }

    static func lineThroughPoints(_ points: [Vec]) -> PathBuilder {
        let path = PathBuilder()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        return path
    }

    // MARK: - Command info

    private struct CommandInfo {
        var tangentStart: Vec
        var tangentEnd: Vec
        var length: Double
    }

    /// The tangents and lengths that draw-style rendering needs to size its corners.
    private func commandInfo() -> [CommandInfo?] {
        var info = [CommandInfo?](repeating: nil, count: commands.count)
        guard commands.count > 1 else { return info }
        for i in 1..<commands.count {
            let previous = commands[i - 1].point
            let current = commands[i]
            if case .move = current.kind { continue }

            let tangentStart: Vec
            let tangentEnd: Vec
            let length: Double
            switch current.kind {
            case .move:
                continue
            case .line:
                let t = Vec.sub(previous, current.point).uni
                tangentStart = t
                tangentEnd = t
                length = Vec.dist(previous, current.point)
            case let .cubic(cp1, cp2):
                tangentStart = Vec.sub(cp1, previous).uni
                tangentEnd = Vec.sub(cp2, current.point).uni
                length = Self.cubicLength(previous, cp1, cp2, current.point)
            }
            info[i] = CommandInfo(tangentStart: tangentStart, tangentEnd: tangentEnd, length: length)
        }
        return info
    }

    private static func cubicLength(_ p0: Vec, _ p1: Vec, _ p2: Vec, _ p3: Vec, samples: Int = 16) -> Double {
        var length = 0.0
        var prev = p0
        for i in 1...samples {
            let t = Double(i) / Double(samples)
            let mt = 1 - t
            let a = mt * mt * mt
            let b = 3 * mt * mt * t
            let c = 3 * mt * t * t
            let d = t * t * t
            let point = Vec(
                a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                a * p0.y + b * p1.y + c * p2.y + d * p3.y
            )
            length += Vec.dist(prev, point)
            prev = point
        }
        return length
    }

    // MARK: - Rendering

    /// The path exactly as built.
    func solidPath() -> CGPath {
        let path = CGMutablePath()
        for command in commands {
            switch command.kind {
            case .move:
                path.move(to: command.point.cgPoint)
            case .line:
                path.addLine(to: command.point.cgPoint)
            case let .cubic(cp1, cp2):
                path.addCurve(to: command.point.cgPoint, control1: cp1.cgPoint, control2: cp2.cgPoint)
            }
            if command.isClose { path.closeSubpath() }
        }
        return path
    }

    /// The path flattened to a point list, with curves sampled. This is what the geo shapes use as
    /// their geometry, so hit-testing follows whatever the path actually draws.
    func vertices(curveResolution: Int = 12) -> [Vec] {
        var points: [Vec] = []
        var current = Vec(0, 0)
        for command in commands {
            switch command.kind {
            case .move:
                points.append(command.point)
            case .line:
                points.append(command.point)
            case let .cubic(cp1, cp2):
                for i in 1...curveResolution {
                    let t = Double(i) / Double(curveResolution)
                    let mt = 1 - t
                    let a = mt * mt * mt
                    let b = 3 * mt * mt * t
                    let c = 3 * mt * t * t
                    let d = t * t * t
                    points.append(Vec(
                        a * current.x + b * cp1.x + c * cp2.x + d * command.point.x,
                        a * current.y + b * cp1.y + c * cp2.y + d * command.point.y
                    ))
                }
            }
            current = command.point
        }
        return points
    }

    /// One subpath per segment, each with its own dash pattern.
    ///
    /// old-apps dashes every segment separately rather than dashing the path as a whole, which is
    /// what makes dashes meet cleanly at a rectangle's corners instead of wrapping around them.
    struct DashedSegment {
        var path: CGPath
        var dashes: [CGFloat]
        var phase: CGFloat
    }

    func dashedSegments(strokeWidth: Double, style: DashStyle) -> [DashedSegment] {
        var segments: [DashedSegment] = []
        var current: Vec?

        for command in commands {
            defer { current = command.point }
            guard let from = current else { continue }
            if case .move = command.kind { continue }

            let path = CGMutablePath()
            path.move(to: from.cgPoint)
            let length: Double
            switch command.kind {
            case .move:
                continue
            case .line:
                path.addLine(to: command.point.cgPoint)
                length = Vec.dist(from, command.point)
            case let .cubic(cp1, cp2):
                path.addCurve(to: command.point.cgPoint, control1: cp1.cgPoint, control2: cp2.cgPoint)
                length = Self.cubicLength(from, cp1, cp2, command.point)
            }

            guard length > 0 else { continue }
            let props = perfectDashProps(totalLength: length, strokeWidth: strokeWidth, style: style)
            segments.append(DashedSegment(path: path, dashes: props.dashes, phase: props.phase))
        }
        return segments
    }

    struct DrawOptions {
        var strokeWidth: Double
        var randomSeed: String
        var offset: Double?
        var roundness: Double?
        var passes: Int = 2
    }

    private struct DrawCommand {
        var command: Command
        var offsetAmount: Double
        var roundnessBefore: Double
        var roundnessAfter: Double
        var tangentToPrev: Vec?
        var tangentToNext: Vec?
    }

    /// Precompute, per command, how far a pass may jitter it and how round its corner may get.
    /// Roundness falls off as the corner angle approaches a straight line, and both are clamped so
    /// they can't overrun the shortest adjacent segment.
    private func drawCommands(_ opts: DrawOptions) -> [DrawCommand] {
        let defaultOffset = opts.offset ?? opts.strokeWidth / 3
        let defaultRoundness = opts.roundness ?? opts.strokeWidth * 2
        let info = commandInfo()

        var result: [DrawCommand] = []
        var lastMoveCommandIdx: Int?
        var closeRoundness: [Int: Double] = [:]

        for i in 0..<commands.count {
            let command = commands[i]
            let offset = command.opts.offset ?? defaultOffset
            let roundness = command.opts.roundness ?? defaultRoundness

            if case .move = command.kind { lastMoveCommandIdx = i }

            let nextIdx: Int?
            if command.isClose {
                nextIdx = lastMoveCommandIdx.map { $0 + 1 }
            } else if i + 1 < commands.count, !isMove(commands[i + 1]) {
                nextIdx = i + 1
            } else {
                nextIdx = nil
            }

            let nextInfo: CommandInfo? = {
                guard let nextIdx, nextIdx < commands.count, !isMove(commands[nextIdx]) else { return nil }
                return info[nextIdx]
            }()

            let currentSupportsRoundness = supportsRoundness(command)
            let nextSupportsRoundness = nextIdx.map { $0 < commands.count && supportsRoundness(commands[$0]) } ?? false

            let currentInfo = info[i]
            let tangentToPrev = currentInfo?.tangentEnd
            let tangentToNext = nextInfo?.tangentStart

            var roundnessClampedForAngle = 0.0
            if currentSupportsRoundness, nextSupportsRoundness,
               let tp = tangentToPrev, let tn = tangentToNext,
               tp.len2 > 0.01, tn.len2 > 0.01 {
                roundnessClampedForAngle = modulate(
                    abs(Vec.angleBetween(tp, tn)),
                    (HALF_PI, PI),
                    (roundness, 0),
                    true
                )
            }

            let shortestDistance = Swift.min(currentInfo?.length ?? .infinity, nextInfo?.length ?? .infinity)
            let offsetLimit = shortestDistance - roundnessClampedForAngle * 2
            let offsetAmount = clamp(offset, 0, Swift.max(0, offsetLimit / 4))

            let roundnessBefore = Swift.min(roundnessClampedForAngle, (currentInfo?.length ?? .infinity) / 4)
            let roundnessAfter = Swift.min(roundnessClampedForAngle, (nextInfo?.length ?? .infinity) / 4)

            result.append(DrawCommand(
                command: command,
                offsetAmount: offsetAmount,
                roundnessBefore: roundnessBefore,
                roundnessAfter: roundnessAfter,
                tangentToPrev: tangentToPrev,
                tangentToNext: tangentToNext
            ))

            // A closed path's corner at the move point is the corner the closing segment makes,
            // so hand the move command that corner's roundness.
            if command.isClose, let moveIdx = lastMoveCommandIdx {
                closeRoundness[moveIdx] = roundnessAfter
            }
        }

        for (idx, roundness) in closeRoundness where idx < result.count {
            result[idx].roundnessAfter = roundness
        }
        return result
    }

    private func isMove(_ command: Command) -> Bool {
        if case .move = command.kind { return true }
        return false
    }

    private func supportsRoundness(_ command: Command) -> Bool {
        switch command.kind {
        case .move, .line: return true
        case .cubic: return false
        }
    }

    /// The draw-style path: `passes` jittered traversals of the same commands, with corners cut
    /// into quadratics so the strokes look drawn rather than plotted.
    func drawPath(_ opts: DrawOptions) -> CGPath {
        let path = CGMutablePath()
        forEachDrawSegment(opts) { segment in
            switch segment {
            case let .move(p):
                path.move(to: p.cgPoint)
            case let .line(p):
                path.addLine(to: p.cgPoint)
            case let .quad(control, p):
                path.addQuadCurve(to: p.cgPoint, control: control.cgPoint)
            case let .cubic(cp1, cp2, p):
                path.addCurve(to: p.cgPoint, control1: cp1.cgPoint, control2: cp2.cgPoint)
            }
        }
        return path
    }

    private enum DrawSegment {
        case move(Vec)
        case line(Vec)
        case quad(Vec, Vec)
        case cubic(Vec, Vec, Vec)
    }

    private func forEachDrawSegment(_ opts: DrawOptions, _ emit: (DrawSegment) -> Void) {
        let draws = drawCommands(opts)
        guard !draws.isEmpty else { return }

        for pass in 0..<opts.passes {
            let random = makeRng(opts.randomSeed + String(pass))
            var lastMoveToOffset = Vec(0, 0)

            for draw in draws {
                let command = draw.command
                var offset: Vec
                if command.isClose {
                    // The closing point must land exactly where the move point did.
                    offset = lastMoveToOffset
                } else {
                    let direction = Vec(random(), random()).uni
                    let magnitude = abs(random()).squareRoot() * draw.offsetAmount
                    offset = Vec.mul(direction, magnitude)
                }

                if isMove(command) { lastMoveToOffset = offset }

                let offsetPoint = Vec.add(command.point, offset)

                // Pull the segment's ends back along their tangents to leave room for the corner.
                let endPoint = (draw.tangentToNext.map { $0 } != nil && draw.roundnessAfter > 0)
                    ? Vec.add(Vec.mul(draw.tangentToNext!, -draw.roundnessAfter), offsetPoint)
                    : offsetPoint
                let startPoint = (draw.tangentToPrev.map { $0 } != nil && draw.roundnessBefore > 0)
                    ? Vec.add(Vec.mul(draw.tangentToPrev!, draw.roundnessBefore), offsetPoint)
                    : offsetPoint

                let hasCorner = !Vec.equals(endPoint, offsetPoint) && !Vec.equals(startPoint, offsetPoint)

                switch command.kind {
                case .move:
                    emit(.move(endPoint))
                case .line:
                    if hasCorner {
                        // Straight to where the corner begins, then round through the true corner.
                        emit(.line(startPoint))
                        emit(.quad(offsetPoint, endPoint))
                    } else {
                        emit(.line(endPoint))
                    }
                case let .cubic(cp1, cp2):
                    let offsetCp1 = Vec.add(cp1, offset)
                    let offsetCp2 = Vec.add(cp2, offset)
                    if hasCorner {
                        emit(.cubic(offsetCp1, offsetCp2, offsetPoint))
                        emit(.quad(offsetPoint, endPoint))
                    } else {
                        emit(.cubic(offsetCp1, offsetCp2, endPoint))
                    }
                }
            }
        }
    }

}
