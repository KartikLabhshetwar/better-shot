//
//  AnnotationScreenshotFrameGeometry.swift
//  BetterShot
//

import CoreGraphics

/// Shared preview/export geometry for the rounded screenshot and its optional
/// outer border. Keeping both paths together prevents the border from drifting
/// away from the screenshot's per-corner alignment treatment.
nonisolated struct AnnotationScreenshotFrameGeometry {
    let imageRect: CGRect
    let cardRect: CGRect
    let imageCornerRadii: PerCornerRadii
    let cardCornerRadii: PerCornerRadii
    let borderWidth: CGFloat

    init(
        imageRect: CGRect,
        cardRect: CGRect,
        settings: AnnotationBackgroundSettings
    ) {
        self.imageRect = imageRect
        self.cardRect = cardRect

        let horizontalInset = max(0, (cardRect.width - imageRect.width) / 2)
        let verticalInset = max(0, (cardRect.height - imageRect.height) / 2)
        borderWidth = settings.border.isVisible
            ? min(horizontalInset, verticalInset)
            : 0

        let baseImageRadius = settings.requiresCanvasLayout
            ? max(0, settings.cornerRadius) * min(imageRect.width, imageRect.height)
            : 0
        let multipliers = settings.effectiveCanvasAlignment.cornerRadiusMultipliers
        imageCornerRadii = PerCornerRadii(
            topLeft: baseImageRadius * multipliers.topLeft,
            topRight: baseImageRadius * multipliers.topRight,
            bottomLeft: baseImageRadius * multipliers.bottomLeft,
            bottomRight: baseImageRadius * multipliers.bottomRight
        )

        // A rounded outer border stays concentric with the clipped screenshot:
        // add the ring width to rounded corners, while intentionally square
        // corners (including stuck canvas edges) remain square.
        let baseCardRadius = baseImageRadius > 0 ? baseImageRadius + borderWidth : 0
        cardCornerRadii = PerCornerRadii(
            topLeft: baseCardRadius * multipliers.topLeft,
            topRight: baseCardRadius * multipliers.topRight,
            bottomLeft: baseCardRadius * multipliers.bottomLeft,
            bottomRight: baseCardRadius * multipliers.bottomRight
        )
    }

    var imagePath: CGPath {
        PerCornerRadii.path(in: imageRect, radii: imageCornerRadii)
    }

    var cardPath: CGPath {
        PerCornerRadii.path(in: cardRect, radii: cardCornerRadii)
    }

    /// The exporter's shadow caster is clipped outside this slightly expanded
    /// path. The one-pixel outset removes antialiased caster residue without
    /// visibly separating the soft shadow from the card.
    var imageShadowKnockoutPath: CGPath {
        shadowKnockoutPath(rect: imageRect, radii: imageCornerRadii)
    }

    var cardShadowKnockoutPath: CGPath {
        shadowKnockoutPath(rect: cardRect, radii: cardCornerRadii)
    }

    private func shadowKnockoutPath(rect: CGRect, radii: PerCornerRadii) -> CGPath {
        let outset: CGFloat = 1
        return PerCornerRadii.path(
            in: rect.insetBy(dx: -outset, dy: -outset),
            radii: radii.outset(by: outset)
        )
    }
}
