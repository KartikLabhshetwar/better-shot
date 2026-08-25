//
//  AnnotationProgressiveBlurGeometry.swift
//  BetterShot
//

import CoreGraphics

/// Shared, pure geometry for the inspector, SwiftUI preview, and Core Image
/// renderer. Keeping these values in one place prevents preview/export drift.
nonisolated struct AnnotationProgressiveBlurGeometry {
    enum CoordinateOrigin {
        case topLeft
        case bottomLeft
    }

    let extent: CGRect
    let focus: CGPoint
    let corners: [CGPoint]
    let directionNormal: CGVector
    let directionalDistances: [CGFloat]
    let shortestEdge: CGFloat
    let transitionWidth: CGFloat
    let radialFocusRadius: CGFloat
    let directionalFocusHalfWidth: CGFloat
    let renderRadius: CGFloat

    init(
        extent: CGRect,
        focusPosition: CGPoint,
        focusSize: CGFloat,
        falloff: CGFloat,
        directionDegrees: CGFloat,
        strength: CGFloat,
        coordinateOrigin: CoordinateOrigin
    ) {
        self.extent = extent
        let normalizedFocus = CGPoint(
            x: min(max(focusPosition.x, 0), 1),
            y: min(max(focusPosition.y, 0), 1)
        )
        let resolvedFocus = CGPoint(
            x: extent.minX + normalizedFocus.x * extent.width,
            y: extent.minY + (
                coordinateOrigin == .topLeft
                    ? normalizedFocus.y
                    : 1 - normalizedFocus.y
            ) * extent.height
        )
        let resolvedCorners = [
            CGPoint(x: extent.minX, y: extent.minY),
            CGPoint(x: extent.maxX, y: extent.minY),
            CGPoint(x: extent.maxX, y: extent.maxY),
            CGPoint(x: extent.minX, y: extent.maxY)
        ]

        let angle = directionDegrees * .pi / 180
        let resolvedDirectionNormal = switch coordinateOrigin {
        case .topLeft:
            CGVector(dx: -sin(angle), dy: cos(angle))
        case .bottomLeft:
            CGVector(dx: sin(angle), dy: cos(angle))
        }
        let resolvedDirectionalDistances = resolvedCorners.map { corner in
            (corner.x - resolvedFocus.x) * resolvedDirectionNormal.dx
                + (corner.y - resolvedFocus.y) * resolvedDirectionNormal.dy
        }

        let resolvedShortestEdge = min(extent.width, extent.height)
        let normalizedFocusSize = min(max(focusSize, 0), 1)
        let normalizedFalloff = min(max(falloff, 0), 1)
        let resolvedTransitionWidth = resolvedShortestEdge * (0.10 + normalizedFalloff * 0.48)

        let minimumRadius = resolvedShortestEdge * 0.04
        let maximumRadius = resolvedCorners.map { corner in
            hypot(corner.x - resolvedFocus.x, corner.y - resolvedFocus.y)
        }.max() ?? minimumRadius
        let resolvedRadialFocusRadius = minimumRadius
            + normalizedFocusSize * max(0, maximumRadius - minimumRadius)

        let minimumHalfWidth = resolvedShortestEdge * 0.025
        let maximumHalfWidth = resolvedDirectionalDistances.map(abs).max() ?? minimumHalfWidth
        let resolvedDirectionalFocusHalfWidth = minimumHalfWidth
            + normalizedFocusSize * max(0, maximumHalfWidth - minimumHalfWidth)

        focus = resolvedFocus
        corners = resolvedCorners
        directionNormal = resolvedDirectionNormal
        directionalDistances = resolvedDirectionalDistances
        shortestEdge = resolvedShortestEdge
        transitionWidth = resolvedTransitionWidth
        radialFocusRadius = resolvedRadialFocusRadius
        directionalFocusHalfWidth = resolvedDirectionalFocusHalfWidth
        renderRadius = max(0.5, strength * resolvedShortestEdge / 1000)
    }

    init(
        extent: CGRect,
        settings: AnnotationProgressiveBlurSettings,
        coordinateOrigin: CoordinateOrigin
    ) {
        self.init(
            extent: extent,
            focusPosition: settings.focusPosition,
            focusSize: settings.focusSize,
            falloff: settings.falloff,
            directionDegrees: settings.directionDegrees,
            strength: settings.strength,
            coordinateOrigin: coordinateOrigin
        )
    }
}
