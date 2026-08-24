import CoreGraphics

/// Where the face cam sits on the recorded video, normalized to the video card so the same numbers drive the editor preview and the export.
struct CameraOverlayLayout: Equatable {
    static let minDiameter: CGFloat = 0.08
    static let maxDiameter: CGFloat = 0.55

    /// Normalized inside the card with y pointing down, matching SwiftUI.
    var center = CGPoint(x: 0.16, y: 0.8)
    /// Fraction of the card's short edge, so the bubble stays a circle at any aspect ratio.
    var diameter: CGFloat = 0.22
    var isVisible = true

    func side(in card: CGRect) -> CGFloat {
        min(card.width, card.height) * Self.clampedDiameter(diameter)
    }

    func rect(in card: CGRect) -> CGRect {
        let side = side(in: card)
        let center = clamping(center, in: card)
        return CGRect(
            x: card.minX + center.x * card.width - side / 2,
            y: card.minY + center.y * card.height - side / 2,
            width: side,
            height: side
        )
    }

    /// The same rect with y pointing up, for the CoreGraphics and CoreImage compositing that produces the exported frames.
    func flippedRect(in card: CGRect) -> CGRect {
        let rect = rect(in: card)
        return CGRect(x: rect.minX, y: card.minY + card.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Keeps the whole bubble on the card, so a drag to the edge stops flush instead of hanging off.
    func clamping(_ proposed: CGPoint, in card: CGRect) -> CGPoint {
        guard card.width > 0, card.height > 0 else { return proposed }
        let half = side(in: card) / 2
        let halfX = min(0.5, half / card.width)
        let halfY = min(0.5, half / card.height)
        return CGPoint(
            x: min(max(proposed.x, halfX), 1 - halfX),
            y: min(max(proposed.y, halfY), 1 - halfY)
        )
    }

    static func clampedDiameter(_ value: CGFloat) -> CGFloat {
        min(max(value, minDiameter), maxDiameter)
    }
}
