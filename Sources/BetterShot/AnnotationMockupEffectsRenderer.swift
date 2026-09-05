//
//  AnnotationMockupEffectsRenderer.swift
//  BetterShot
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationMockupEffectsError: Error {
    case progressiveBlurFailed
    case cameraProjectionFailed
}

nonisolated enum AnnotationMockupEffectsRenderer {
    /// `CIContext` is immutable after creation and documented for reuse across
    /// render calls. Access is serialized for previews by the worker below;
    /// exports run on the editor's actor.
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    nonisolated static func progressiveBlur(
        _ image: CGImage,
        settings: AnnotationProgressiveBlurSettings,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        guard settings.isActive else { return image }

        let input = CIImage(cgImage: image)
        let extent = input.extent
        let output = try progressiveBlurCIImage(input, settings: settings)
        guard let renderedImage = context.createCGImage(
            output,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw AnnotationMockupEffectsError.progressiveBlurFailed
        }
        return renderedImage
    }

    static func drawProjectedForeground(
        _ image: CGImage,
        projection: AnnotationCameraProjection,
        canvasSize: CGSize,
        colorSpace: CGColorSpace,
        into destinationContext: CGContext
    ) throws {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let output = try projectedForegroundCIImage(
            image,
            projection: projection,
            canvasSize: canvasSize
        )

        try draw(
            output,
            in: canvasRect,
            colorSpace: colorSpace,
            into: destinationContext
        )
    }

    static func drawProgressivelyBlurredScene(
        _ image: CGImage,
        canvasSize: CGSize,
        colorSpace: CGColorSpace,
        progressiveBlurSettings: AnnotationProgressiveBlurSettings,
        into destinationContext: CGContext
    ) throws {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let output = try progressiveBlurCIImage(
            CIImage(cgImage: image),
            settings: progressiveBlurSettings
        )
        try draw(
            output,
            in: canvasRect,
            colorSpace: colorSpace,
            into: destinationContext
        )
    }

    private static func draw(
        _ image: CIImage,
        in canvasRect: CGRect,
        colorSpace: CGColorSpace,
        into destinationContext: CGContext
    ) throws {
        // Reuse the GPU context; a CGContext-backed CIContext is recreated
        // for every effect and cannot reuse its compiled filter pipeline.
        guard let rendered = context.createCGImage(
            image, from: canvasRect, format: .RGBA8, colorSpace: colorSpace
        ) else {
            throw AnnotationMockupEffectsError.cameraProjectionFailed
        }
        destinationContext.draw(rendered, in: canvasRect)
    }

    nonisolated private static func blurMask(
        geometry: AnnotationProgressiveBlurGeometry,
        settings: AnnotationProgressiveBlurSettings
    ) -> CIImage? {
        let baseMask: CIImage?

        switch settings.mode {
        case .radial:
            let gradient = CIFilter.radialGradient()
            gradient.center = geometry.focus
            gradient.radius0 = Float(geometry.radialFocusRadius)
            gradient.radius1 = Float(geometry.radialFocusRadius + geometry.transitionWidth)
            gradient.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            baseMask = gradient.outputImage

        case .directional:
            let positiveFocusEdge = CGPoint(
                x: geometry.focus.x
                    + geometry.directionNormal.dx * geometry.directionalFocusHalfWidth,
                y: geometry.focus.y
                    + geometry.directionNormal.dy * geometry.directionalFocusHalfWidth
            )
            let negativeFocusEdge = CGPoint(
                x: geometry.focus.x
                    - geometry.directionNormal.dx * geometry.directionalFocusHalfWidth,
                y: geometry.focus.y
                    - geometry.directionNormal.dy * geometry.directionalFocusHalfWidth
            )
            let positive = directionalGradient(
                from: positiveFocusEdge,
                to: CGPoint(
                    x: positiveFocusEdge.x
                        + geometry.directionNormal.dx * geometry.transitionWidth,
                    y: positiveFocusEdge.y
                        + geometry.directionNormal.dy * geometry.transitionWidth
                )
            )
            let negative = directionalGradient(
                from: negativeFocusEdge,
                to: CGPoint(
                    x: negativeFocusEdge.x
                        - geometry.directionNormal.dx * geometry.transitionWidth,
                    y: negativeFocusEdge.y
                        - geometry.directionNormal.dy * geometry.transitionWidth
                )
            )

            let maximum = CIFilter.maximumCompositing()
            maximum.inputImage = positive
            maximum.backgroundImage = negative
            baseMask = maximum.outputImage
        }

        return baseMask?.cropped(to: geometry.extent)
    }

    nonisolated private static func directionalGradient(from start: CGPoint, to end: CGPoint) -> CIImage? {
        let gradient = CIFilter.smoothLinearGradient()
        gradient.point0 = start
        gradient.point1 = end
        gradient.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        return gradient.outputImage
    }

    private static func coreImagePoint(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    private static func projectedForegroundCIImage(
        _ image: CGImage,
        projection: AnnotationCameraProjection,
        canvasSize: CGSize
    ) throws -> CIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw AnnotationMockupEffectsError.cameraProjectionFailed
        }

        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = coreImagePoint(projection.quad.topLeft, canvasHeight: canvasSize.height)
        filter.topRight = coreImagePoint(projection.quad.topRight, canvasHeight: canvasSize.height)
        filter.bottomRight = coreImagePoint(projection.quad.bottomRight, canvasHeight: canvasSize.height)
        filter.bottomLeft = coreImagePoint(projection.quad.bottomLeft, canvasHeight: canvasSize.height)

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        guard let output = filter.outputImage?.cropped(to: canvasRect) else {
            throw AnnotationMockupEffectsError.cameraProjectionFailed
        }
        return output
    }

    nonisolated private static func progressiveBlurCIImage(
        _ input: CIImage,
        settings: AnnotationProgressiveBlurSettings
    ) throws -> CIImage {
        guard settings.isActive else { return input }

        let extent = input.extent
        let geometry = AnnotationProgressiveBlurGeometry(
            extent: extent,
            settings: settings,
            coordinateOrigin: .bottomLeft
        )
        guard extent.width > 0, extent.height > 0,
              let mask = blurMask(geometry: geometry, settings: settings) else {
            throw AnnotationMockupEffectsError.progressiveBlurFailed
        }

        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = input.clampedToExtent()
        blur.mask = mask
        blur.radius = Float(geometry.renderRadius)
        guard let output = blur.outputImage?.cropped(to: extent) else {
            throw AnnotationMockupEffectsError.progressiveBlurFailed
        }
        return output
    }
}
