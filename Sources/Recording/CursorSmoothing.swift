import AppKit
import CoreGraphics
import Foundation

nonisolated struct CursorSpring: Equatable, Sendable {
    var tension: Double
    var mass: Double
    var friction: Double

    /// A spring chasing a moving target trails it by friction over tension seconds, so the target is read that far ahead to cancel the lag.
    var lead: TimeInterval { tension > 0 ? friction / tension : 0 }
}

/// How a drawn cursor moves and how big it is, for recordings made with the system pointer hidden.
nonisolated struct CursorStyle: Equatable, Sendable {
    enum Motion: String, CaseIterable, Identifiable, Sendable {
        case loose
        case natural
        case snappy

        var id: String { rawValue }
        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        var spring: CursorSpring {
            switch self {
            case .loose: CursorSpring(tension: 200, mass: 2.25, friction: 40)
            case .natural: CursorSpring(tension: 470, mass: 3, friction: 70)
            case .snappy: CursorSpring(tension: 380, mass: 1, friction: 30)
            }
        }
    }

    static let heightFraction: CGFloat = 0.045
    static let spriteOversample: CGFloat = 2

    var isEnabled = false
    var motion: Motion = .natural
    var size: CGFloat = 1

    /// The cursor is measured in source pixels so the frame transform scales it exactly like the rest of the picture.
    func sourceHeight(in sourceSize: CGSize) -> CGFloat {
        sourceSize.height * Self.heightFraction * size
    }
}

nonisolated struct CursorSprite: @unchecked Sendable {
    var image: CGImage
    var size: CGSize
    /// Where the pointer tip sits inside the image, normalized and top-down.
    var hotspot: CGPoint

    @MainActor
    static func arrow(pixelHeight: CGFloat) -> CursorSprite? {
        let cursor = NSCursor.arrow
        let source = cursor.image
        guard source.size.width > 0, source.size.height > 0, pixelHeight >= 1 else { return nil }

        let height = pixelHeight.rounded()
        let width = max(1, (source.size.width / source.size.height * height).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let image = rep.cgImage else { return nil }
        return CursorSprite(
            image: image,
            size: CGSize(width: width, height: height),
            hotspot: CGPoint(x: cursor.hotSpot.x / source.size.width, y: cursor.hotSpot.y / source.size.height)
        )
    }
}

nonisolated struct ResolvedCursor: Equatable, Sendable {
    /// Canvas pixels, y pointing up, at the pointer tip.
    var point: CGPoint
    var scale: CGFloat
}

/// Cap's smoothed cursor: a spring chases the recorded path, so a hand that jitters lands as one clean glide.
nonisolated struct SmoothedCursorPath: Equatable, Sendable {
    static let step: TimeInterval = 1.0 / 120
    static let settle: TimeInterval = 0.3
    static let clickLookahead: TimeInterval = 0.5
    static let idleGap: TimeInterval = 0.08
    static let shakeWindow: TimeInterval = 0.1
    static let shakeThreshold: Double = 0.015

    var points: [CGPoint] = []
    var start: TimeInterval = 0

    var isEmpty: Bool { points.isEmpty }

    func position(at time: TimeInterval) -> CGPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        let offset = (time - start) / Self.step
        guard offset > 0 else { return first }
        let index = Int(offset)
        guard index + 1 < points.count else { return last }
        let progress = CGFloat(offset - Double(index))
        let a = points[index]
        let b = points[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
    }

    static func build(travel: [PointerTravelSample], presses: [PointerPressEvent], spring: CursorSpring) -> SmoothedCursorPath {
        let moves = steadied(travel.sorted { $0.time < $1.time })
        guard let first = moves.first, let last = moves.last, spring.mass > 0 else { return SmoothedCursorPath() }

        let clicks = presses.map(\.time).sorted()
        var position = CGPoint(x: first.x, y: first.y)
        var velocity = CGVector.zero
        var points = [position]
        var moveHint = 0
        var clickHint = 0
        var time = first.time

        while time < last.time + settle {
            time += step
            let now = min(time, last.time)

            while clickHint < clicks.count, clicks[clickHint] <= now { clickHint += 1 }
            let anticipated = clickHint < clicks.count && clicks[clickHint] - now <= clickLookahead ? clicks[clickHint] : nil
            let target = raw(moves, at: min(anticipated ?? now + spring.lead, last.time), hint: &moveHint)

            let ax = (spring.tension * (target.x - position.x) - spring.friction * velocity.dx) / spring.mass
            let ay = (spring.tension * (target.y - position.y) - spring.friction * velocity.dy) / spring.mass
            velocity.dx += ax * step
            velocity.dy += ay * step
            position.x += velocity.dx * step
            position.y += velocity.dy * step
            points.append(position)
        }

        return SmoothedCursorPath(points: points, start: first.time)
    }

    /// A pointer that wobbles in place reverses direction over a few pixels, which is a hand shaking rather than a move worth following.
    private static func steadied(_ moves: [PointerTravelSample]) -> [PointerTravelSample] {
        guard moves.count >= 3 else { return moves }
        var kept = [moves[0]]
        var index = 1

        while index < moves.count - 1 {
            let previous = kept[kept.count - 1]
            let current = moves[index]
            let next = moves[index + 1]
            index += 1

            if next.time - previous.time > shakeWindow {
                kept.append(current)
                continue
            }

            let toCurrent = (x: current.x - previous.x, y: current.y - previous.y)
            let toNext = (x: next.x - current.x, y: next.y - current.y)
            let reverses = toCurrent.x * toNext.x + toCurrent.y * toNext.y < 0
            let isSmall = hypot(toCurrent.x, toCurrent.y) < shakeThreshold && hypot(toNext.x, toNext.y) < shakeThreshold
            if reverses, isSmall { continue }
            kept.append(current)
        }

        kept.append(moves[moves.count - 1])
        return kept
    }

    private static func raw(_ moves: [PointerTravelSample], at time: TimeInterval, hint: inout Int) -> CGPoint {
        while hint > 0, moves[hint].time > time { hint -= 1 }
        while hint + 1 < moves.count, moves[hint + 1].time <= time { hint += 1 }

        let sample = moves[hint]
        let resting = CGPoint(x: sample.x, y: sample.y)
        guard hint + 1 < moves.count else { return resting }

        let next = moves[hint + 1]
        let span = next.time - sample.time
        guard time > sample.time, span > 1e-9, span <= idleGap else { return resting }

        let progress = (time - sample.time) / span
        return CGPoint(x: sample.x + (next.x - sample.x) * progress, y: sample.y + (next.y - sample.y) * progress)
    }
}
