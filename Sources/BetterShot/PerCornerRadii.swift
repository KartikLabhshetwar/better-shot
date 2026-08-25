//
//  PerCornerRadii.swift
//  BetterShot
//

import CoreGraphics

/// Holds per-corner radius values for a rounded rectangle.
nonisolated struct PerCornerRadii: Equatable {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    var isUniform: Bool {
        topLeft == topRight && topRight == bottomLeft && bottomLeft == bottomRight
    }

    func outset(by amount: CGFloat) -> PerCornerRadii {
        PerCornerRadii(
            topLeft: topLeft > 0 ? topLeft + amount : 0,
            topRight: topRight > 0 ? topRight + amount : 0,
            bottomLeft: bottomLeft > 0 ? bottomLeft + amount : 0,
            bottomRight: bottomRight > 0 ? bottomRight + amount : 0
        )
    }

    /// Creates a `CGPath` rounded rectangle with individual corner radii.
    static func path(in rect: CGRect, radii: PerCornerRadii) -> CGPath {
        let tl = min(radii.topLeft, min(rect.width, rect.height) / 2)
        let tr = min(radii.topRight, min(rect.width, rect.height) / 2)
        let bl = min(radii.bottomLeft, min(rect.width, rect.height) / 2)
        let br = min(radii.bottomRight, min(rect.width, rect.height) / 2)

        let path = CGMutablePath()

        // Start at top-left, after the top-left corner arc
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.maxY))

        // Top edge -> top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.maxY - tr),
                radius: tr,
                startAngle: .pi / 2,
                endAngle: 0,
                clockwise: true
            )
        }

        // Right edge -> bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.minY + br),
                radius: br,
                startAngle: 0,
                endAngle: -.pi / 2,
                clockwise: true
            )
        }

        // Bottom edge -> bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.minY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.minY + bl),
                radius: bl,
                startAngle: -.pi / 2,
                endAngle: .pi,
                clockwise: true
            )
        }

        // Left edge -> top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.maxY - tl),
                radius: tl,
                startAngle: .pi,
                endAngle: .pi / 2,
                clockwise: true
            )
        }

        path.closeSubpath()
        return path
    }
}
