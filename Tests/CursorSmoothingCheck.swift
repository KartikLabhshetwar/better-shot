import AppKit
import CoreGraphics
import Foundation

@main
enum CursorSmoothingCheck {
    static let rate: TimeInterval = 1.0 / 30

    static func glide(from: CGPoint, to: CGPoint, seconds: TimeInterval, jitter: Double = 0) -> [PointerTravelSample] {
        let count = Int(seconds / rate)
        return (0...count).map { index in
            let progress = Double(index) / Double(count)
            let wobble = jitter * (index % 2 == 0 ? 1 : -1)
            return PointerTravelSample(
                time: Double(index) * rate,
                x: from.x + (to.x - from.x) * progress + wobble,
                y: from.y + (to.y - from.y) * progress - wobble
            )
        }
    }

    static func length(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    static func main() {
        let spring = CursorStyle.Motion.natural.spring
        precondition(spring.lead > 0, "a spring that trails its target has a lead to cancel it")

        precondition(SmoothedCursorPath.build(travel: [], presses: [], spring: spring).isEmpty, "no pointer capture draws no cursor")
        precondition(SmoothedCursorPath().position(at: 1) == nil, "an empty path has no position to draw")

        let straight = glide(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.9, y: 0.5), seconds: 2)
        let path = SmoothedCursorPath.build(travel: straight, presses: [], spring: spring)
        precondition(!path.isEmpty, "a recorded path smooths into a drawable one")

        guard let followed = path.position(at: 1.5) else { preconditionFailure("the path covers the recording") }
        let raw = CGPoint(x: 0.1 + 0.8 * 0.75, y: 0.1 + 0.4 * 0.75)
        precondition(hypot(followed.x - raw.x, followed.y - raw.y) < 0.01, "steady movement is followed without visibly lagging behind")

        guard let before = path.position(at: -1), let after = path.position(at: 30) else { preconditionFailure("the path clamps outside the recording") }
        precondition(before == path.points.first && after == path.points.last, "the cursor rests at both ends instead of vanishing")
        precondition(path.position(at: 2.2) != nil, "the spring is given time to settle after the last sample")

        let shaky = glide(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.8, y: 0.8), seconds: 2, jitter: 0.004)
        let steadied = SmoothedCursorPath.build(travel: shaky, presses: [], spring: spring)
        let rawLength = length(shaky.map { CGPoint(x: $0.x, y: $0.y) })
        let steadiedLength = length(steadied.points)
        precondition(steadiedLength < rawLength * 0.8, "a shaking hand travels less distance once it is smoothed")

        let clean = SmoothedCursorPath.build(travel: glide(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.8, y: 0.8), seconds: 2), presses: [], spring: spring)
        precondition(abs(steadiedLength - length(clean.points)) < rawLength * 0.1, "smoothing out shake keeps the move it was hiding")

        let click = PointerPressEvent(time: 1.5, x: 0.9, y: 0.5, phase: .down)
        let anticipated = SmoothedCursorPath.build(travel: straight, presses: [click], spring: spring)
        guard let landed = anticipated.position(at: 1.5) else { preconditionFailure("the click falls inside the recording") }
        precondition(hypot(landed.x - raw.x, landed.y - raw.y) < 0.006, "the cursor is on the spot when the click lands")

        let jump = [
            PointerTravelSample(time: 0, x: 0.1, y: 0.1),
            PointerTravelSample(time: 0.03, x: 0.1, y: 0.1),
            PointerTravelSample(time: 0.06, x: 0.9, y: 0.9),
            PointerTravelSample(time: 1, x: 0.9, y: 0.9),
        ]
        let eased = SmoothedCursorPath.build(travel: jump, presses: [], spring: spring)
        guard let midway = eased.position(at: 0.1), let settled = eased.position(at: 1) else { preconditionFailure("the jump is covered") }
        precondition(midway.x > 0.1 && midway.x < 0.85, "a teleport is glided through rather than snapped")
        precondition(hypot(settled.x - 0.9, settled.y - 0.9) < 0.01, "the glide still arrives where the pointer went")

        let trembling = (0...60).map { index in
            PointerTravelSample(time: Double(index) * rate, x: 0.5 + (index % 2 == 0 ? 0.004 : -0.004), y: 0.5)
        }
        let stilled = SmoothedCursorPath.build(travel: trembling, presses: [], spring: spring)
        precondition(length(stilled.points) < 0.02, "a hand trembling in place leaves the cursor where it is")

        let looseLength = length(SmoothedCursorPath.build(travel: shaky, presses: [], spring: CursorStyle.Motion.loose.spring).points)
        let snappyLength = length(SmoothedCursorPath.build(travel: shaky, presses: [], spring: CursorStyle.Motion.snappy.spring).points)
        precondition(looseLength < snappyLength, "looser motion smooths harder than snappy motion")

        var style = CursorStyle()
        precondition(!style.isEnabled, "a drawn cursor stays off until the recording is missing the real one")
        style.size = 2
        precondition(style.sourceHeight(in: CGSize(width: 1920, height: 1080)) == 1080 * CursorStyle.heightFraction * 2, "size scales the cursor against the source frame")

        print("PASS CursorSmoothingCheck: cursor smoothing: a spring follows the recorded path without lag, shake or a snapped teleport")
    }
}
