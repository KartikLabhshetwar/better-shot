//
//  AnnotationCameraGeometry.swift
//  BetterShot
//

import CoreGraphics
import QuartzCore
import SwiftUI

nonisolated struct AnnotationCameraQuad {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }
}

nonisolated struct AnnotationCameraProjection {
    let quad: AnnotationCameraQuad

    private let forward: AnnotationHomography
    private let inverse: AnnotationHomography

    fileprivate init(
        sourceRect: CGRect,
        quad: AnnotationCameraQuad
    ) {
        if let transform = AnnotationHomography.mapping(sourceRect, to: quad),
           let inverted = transform.inverted() {
            self.quad = quad
            forward = transform
            inverse = inverted
        } else {
            // Preview hit-testing and export must fail as one unit. Keeping a
            // transformed quad with identity homographies would make them render
            // and interact with different geometry.
            self.quad = AnnotationCameraQuad(
                topLeft: CGPoint(x: sourceRect.minX, y: sourceRect.minY),
                topRight: CGPoint(x: sourceRect.maxX, y: sourceRect.minY),
                bottomRight: CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
                bottomLeft: CGPoint(x: sourceRect.minX, y: sourceRect.maxY)
            )
            forward = .identity
            inverse = .identity
        }
    }

    var swiftUITransform: ProjectionTransform {
        forward.projectionTransform
    }

    func project(_ point: CGPoint) -> CGPoint {
        forward.applying(to: point)
    }

    func unproject(_ point: CGPoint) -> CGPoint {
        inverse.applying(to: point)
    }
}

nonisolated enum AnnotationCameraGeometry {
    static func projection(
        sourceRect: CGRect,
        imageRect: CGRect,
        canvasSize: CGSize,
        settings: AnnotationCameraSettings
    ) -> AnnotationCameraProjection {
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              imageRect.width > 0,
              imageRect.height > 0 else {
            return AnnotationCameraProjection(
                sourceRect: sourceRect,
                quad: quad(for: sourceRect)
            )
        }

        let pivot = CGPoint(x: imageRect.midX, y: imageRect.midY)
        let scale: CGFloat
        if settings.projectionVersion < 2 {
            let rawImageCorners = corners(of: imageRect).map {
                legacyProjectedPoint($0, pivot: pivot, imageRect: imageRect, settings: settings)
            }
            let rawBounds = boundingRect(rawImageCorners)
            let fitScale = min(
                1,
                imageRect.width / max(rawBounds.width, 1),
                imageRect.height / max(rawBounds.height, 1)
            )
            scale = fitScale * min(max(settings.zoom, 0.4), 2.5)
        } else {
            // Zoom is the only framing scale in the current model. Do not
            // silently shrink the card as its angle changes.
            scale = min(max(settings.zoom, 0.4), 2.5)
        }
        let pan = CGSize(
            width: settings.panX * canvasSize.width,
            height: settings.panY * canvasSize.height
        )

        func projected(_ point: CGPoint) -> CGPoint {
            let rawPoint = if settings.projectionVersion < 2 {
                legacyProjectedPoint(
                    point,
                    pivot: pivot,
                    imageRect: imageRect,
                    settings: settings
                )
            } else {
                currentProjectedPoint(
                    point,
                    pivot: pivot,
                    imageRect: imageRect,
                    settings: settings
                )
            }
            return CGPoint(
                x: pivot.x + (rawPoint.x - pivot.x) * scale + pan.width,
                y: pivot.y + (rawPoint.y - pivot.y) * scale + pan.height
            )
        }

        let sourceCorners = corners(of: sourceRect)
        let destinationQuad = AnnotationCameraQuad(
            topLeft: projected(sourceCorners[0]),
            topRight: projected(sourceCorners[1]),
            bottomRight: projected(sourceCorners[2]),
            bottomLeft: projected(sourceCorners[3])
        )
        return AnnotationCameraProjection(sourceRect: sourceRect, quad: destinationQuad)
    }

    private static func currentProjectedPoint(
        _ point: CGPoint,
        pivot: CGPoint,
        imageRect: CGRect,
        settings: AnnotationCameraSettings
    ) -> CGPoint {
        var vector = Vector3(
            x: point.x - pivot.x,
            y: point.y - pivot.y,
            z: 0
        )

        // Rotate turns the card around its local center axes.
        vector = rotatedAroundX(vector, by: radians(settings.rotationXDegrees))
        vector = rotatedAroundY(vector, by: radians(settings.rotationYDegrees))

        // Tilt orbits the camera horizontally/vertically around the same
        // center. Applying the inverse world rotations to the card plane gives
        // the exact pinhole-camera view while remaining one invertible plane.
        vector = rotatedAroundY(vector, by: -radians(settings.tiltXDegrees))
        vector = rotatedAroundX(vector, by: -radians(settings.tiltYDegrees))

        return perspectivePoint(
            vector,
            pivot: pivot,
            imageRect: imageRect,
            fieldOfViewDegrees: settings.fieldOfViewDegrees,
            rollDegrees: settings.rollDegrees
        )
    }

    /// Version 1 compatibility for saved development presets/documents.
    private static func legacyProjectedPoint(
        _ point: CGPoint,
        pivot: CGPoint,
        imageRect: CGRect,
        settings: AnnotationCameraSettings
    ) -> CGPoint {
        var vector = Vector3(
            x: point.x - pivot.x,
            y: point.y - pivot.y,
            z: 0
        )

        vector = rotatedAroundX(vector, by: radians(settings.rotationXDegrees))
        vector = rotatedAroundY(vector, by: radians(settings.rotationYDegrees))

        let tiltX = tan(radians(settings.tiltXDegrees)) * 0.42
        let tiltY = tan(radians(settings.tiltYDegrees)) * 0.42
        let tiltedX = vector.x + vector.y * tiltY
        let tiltedY = vector.y + vector.x * tiltX
        vector.x = tiltedX
        vector.y = tiltedY

        return perspectivePoint(
            vector,
            pivot: pivot,
            imageRect: imageRect,
            fieldOfViewDegrees: settings.fieldOfViewDegrees,
            rollDegrees: settings.rollDegrees
        )
    }

    private static func perspectivePoint(
        _ vector: Vector3,
        pivot: CGPoint,
        imageRect: CGRect,
        fieldOfViewDegrees: CGFloat,
        rollDegrees: CGFloat
    ) -> CGPoint {
        let fov = min(max(fieldOfViewDegrees, 18), 80)
        let longestEdge = max(imageRect.width, imageRect.height)
        let focalDistance = longestEdge * (
            0.35 + 0.5 / max(tan(radians(fov) / 2), 0.01)
        )
        let denominator = max(focalDistance - vector.z, focalDistance * 0.12)
        let perspectiveScale = focalDistance / denominator
        let x = vector.x * perspectiveScale
        let y = vector.y * perspectiveScale

        let roll = radians(rollDegrees)
        let rolledX = x * cos(roll) - y * sin(roll)
        let rolledY = x * sin(roll) + y * cos(roll)
        return CGPoint(x: pivot.x + rolledX, y: pivot.y + rolledY)
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    private static func rotatedAroundX(_ vector: Vector3, by angle: CGFloat) -> Vector3 {
        Vector3(
            x: vector.x,
            y: vector.y * cos(angle) - vector.z * sin(angle),
            z: vector.y * sin(angle) + vector.z * cos(angle)
        )
    }

    private static func rotatedAroundY(_ vector: Vector3, by angle: CGFloat) -> Vector3 {
        Vector3(
            x: vector.x * cos(angle) + vector.z * sin(angle),
            y: vector.y,
            z: -vector.x * sin(angle) + vector.z * cos(angle)
        )
    }

    private static func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    private static func quad(for rect: CGRect) -> AnnotationCameraQuad {
        let points = corners(of: rect)
        return AnnotationCameraQuad(
            topLeft: points[0],
            topRight: points[1],
            bottomRight: points[2],
            bottomLeft: points[3]
        )
    }

    private static func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(
            CGRect(origin: first, size: .zero)
        ) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }
    }

    private struct Vector3 {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat
    }
}

nonisolated private struct AnnotationHomography {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    let e: CGFloat
    let f: CGFloat
    let g: CGFloat
    let h: CGFloat
    let i: CGFloat

    static let identity = AnnotationHomography(
        a: 1, b: 0, c: 0,
        d: 0, e: 1, f: 0,
        g: 0, h: 0, i: 1
    )

    static func mapping(
        _ sourceRect: CGRect,
        to quad: AnnotationCameraQuad
    ) -> AnnotationHomography? {
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }

        let p0 = quad.topLeft
        let p1 = quad.topRight
        let p2 = quad.bottomRight
        let p3 = quad.bottomLeft

        let dx1 = p1.x - p2.x
        let dx2 = p3.x - p2.x
        let dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y
        let dy2 = p3.y - p2.y
        let dy3 = p0.y - p1.y + p2.y - p3.y

        let unit: AnnotationHomography
        let denominator = dx1 * dy2 - dx2 * dy1
        if abs(dx3) < 0.000001 && abs(dy3) < 0.000001 {
            unit = AnnotationHomography(
                a: p1.x - p0.x,
                b: p3.x - p0.x,
                c: p0.x,
                d: p1.y - p0.y,
                e: p3.y - p0.y,
                f: p0.y,
                g: 0,
                h: 0,
                i: 1
            )
        } else {
            guard abs(denominator) > 0.000001 else { return nil }
            let projectiveX = (dx3 * dy2 - dx2 * dy3) / denominator
            let projectiveY = (dx1 * dy3 - dx3 * dy1) / denominator
            unit = AnnotationHomography(
                a: p1.x - p0.x + projectiveX * p1.x,
                b: p3.x - p0.x + projectiveY * p3.x,
                c: p0.x,
                d: p1.y - p0.y + projectiveX * p1.y,
                e: p3.y - p0.y + projectiveY * p3.y,
                f: p0.y,
                g: projectiveX,
                h: projectiveY,
                i: 1
            )
        }

        let inverseWidth = 1 / sourceRect.width
        let inverseHeight = 1 / sourceRect.height
        return AnnotationHomography(
            a: unit.a * inverseWidth,
            b: unit.b * inverseHeight,
            c: unit.c - unit.a * sourceRect.minX * inverseWidth - unit.b * sourceRect.minY * inverseHeight,
            d: unit.d * inverseWidth,
            e: unit.e * inverseHeight,
            f: unit.f - unit.d * sourceRect.minX * inverseWidth - unit.e * sourceRect.minY * inverseHeight,
            g: unit.g * inverseWidth,
            h: unit.h * inverseHeight,
            i: unit.i - unit.g * sourceRect.minX * inverseWidth - unit.h * sourceRect.minY * inverseHeight
        )
    }

    func applying(to point: CGPoint) -> CGPoint {
        let denominator = g * point.x + h * point.y + i
        guard abs(denominator) > 0.000001 else { return point }
        return CGPoint(
            x: (a * point.x + b * point.y + c) / denominator,
            y: (d * point.x + e * point.y + f) / denominator
        )
    }

    func inverted() -> AnnotationHomography? {
        let determinant = a * (e * i - f * h)
            - b * (d * i - f * g)
            + c * (d * h - e * g)
        guard abs(determinant) > 0.000001 else { return nil }
        let reciprocal = 1 / determinant
        return AnnotationHomography(
            a: (e * i - f * h) * reciprocal,
            b: (c * h - b * i) * reciprocal,
            c: (b * f - c * e) * reciprocal,
            d: (f * g - d * i) * reciprocal,
            e: (a * i - c * g) * reciprocal,
            f: (c * d - a * f) * reciprocal,
            g: (d * h - e * g) * reciprocal,
            h: (b * g - a * h) * reciprocal,
            i: (a * e - b * d) * reciprocal
        )
    }

    var projectionTransform: ProjectionTransform {
        ProjectionTransform(CATransform3D(
            m11: a, m12: d, m13: 0, m14: g,
            m21: b, m22: e, m23: 0, m24: h,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: c, m42: f, m43: 0, m44: i
        ))
    }
}
