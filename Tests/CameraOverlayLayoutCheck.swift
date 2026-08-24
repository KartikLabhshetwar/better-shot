import CoreGraphics
import Foundation

@main
enum CameraOverlayLayoutCheck {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            failures += 1
        }
    }

    @MainActor static func main() {
        let card = CGRect(x: 40, y: 90, width: 1600, height: 900)
        var layout = CameraOverlayLayout()

        let rect = layout.rect(in: card)
        check(abs(rect.width - rect.height) < 0.001, "the bubble must stay a circle, got \(rect.size)")
        check(abs(rect.width - 900 * 0.22) < 0.001, "the diameter must track the card's short edge, got \(rect.width)")
        check(card.contains(rect), "the default bubble must sit inside the card, got \(rect)")

        layout.center = CGPoint(x: 0.5, y: 0.5)
        let centered = layout.rect(in: card)
        check(abs(centered.midX - card.midX) < 0.001 && abs(centered.midY - card.midY) < 0.001, "a centred bubble must land on the card centre, got \(centered)")

        layout.center = CGPoint(x: -3, y: 4)
        let escaped = layout.rect(in: card)
        check(card.contains(escaped), "a centre dragged off the card must clamp back inside, got \(escaped)")
        check(abs(escaped.minX - card.minX) < 0.001, "clamping left must sit flush against the edge, got \(escaped.minX)")
        check(abs(escaped.maxY - card.maxY) < 0.001, "clamping down must sit flush against the edge, got \(escaped.maxY)")

        layout.center = CGPoint(x: 0.16, y: 0.8)
        let flipped = layout.flippedRect(in: card)
        let down = layout.rect(in: card)
        check(abs(flipped.minX - down.minX) < 0.001, "flipping must not move the bubble horizontally")
        check(abs(flipped.size.width - down.size.width) < 0.001, "flipping must not resize the bubble")
        check(card.contains(flipped), "the flipped bubble must stay inside the card, got \(flipped)")
        check(abs((flipped.midY - card.minY) - (card.maxY - down.midY)) < 0.001, "flipping must mirror the bubble about the card's centre line")

        layout.center = CGPoint(x: 0.5, y: 0.5)
        let flippedCentre = layout.flippedRect(in: card)
        check(abs(flippedCentre.midY - card.midY) < 0.001, "a centred bubble must be its own mirror, got \(flippedCentre.midY)")

        check(CameraOverlayLayout.clampedDiameter(0) == CameraOverlayLayout.minDiameter, "a zero diameter must clamp up to the minimum")
        check(CameraOverlayLayout.clampedDiameter(9) == CameraOverlayLayout.maxDiameter, "an oversized diameter must clamp down to the maximum")

        layout.diameter = 5
        let huge = layout.rect(in: card)
        check(card.contains(huge), "an oversized bubble must still fit the card, got \(huge)")

        let degenerate = CameraOverlayLayout().rect(in: CGRect(x: 0, y: 0, width: 0, height: 0))
        check(degenerate.width == 0, "a zero-sized card must not produce a bubble, got \(degenerate)")

        if failures > 0 { exit(1) }
        print("CameraOverlayLayoutCheck: all assertions passed")
    }
}
