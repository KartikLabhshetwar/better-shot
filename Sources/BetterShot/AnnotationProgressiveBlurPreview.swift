//
//  AnnotationProgressiveBlurPreview.swift
//  BetterShot
//

import AppKit
import CoreGraphics
import os
import SwiftUI

struct AnnotationProgressiveBlurBlendMask: View {
    let settings: AnnotationProgressiveBlurSettings
    let level: Int
    let levelCount: Int

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let geometry = AnnotationProgressiveBlurGeometry(
                extent: CGRect(origin: .zero, size: size),
                settings: settings,
                coordinateOrigin: .topLeft
            )

            switch settings.mode {
            case .radial:
                radialMask(geometry: geometry, size: size)
            case .directional:
                directionalMask(geometry: geometry, size: size)
            }
        }
    }

    private func radialMask(
        geometry: AnnotationProgressiveBlurGeometry,
        size: CGSize
    ) -> some View {
        let transitionStart = geometry.radialFocusRadius
            + geometry.transitionWidth * levelStart
        let transitionEnd = geometry.radialFocusRadius
            + geometry.transitionWidth * levelEnd

        return RadialGradient(
            colors: [.clear, .white],
            center: UnitPoint(
                x: geometry.focus.x / max(size.width, 1),
                y: geometry.focus.y / max(size.height, 1)
            ),
            startRadius: transitionStart,
            endRadius: transitionEnd
        )
    }

    private func directionalMask(
        geometry: AnnotationProgressiveBlurGeometry,
        size: CGSize
    ) -> some View {
        let minimumDistance = geometry.directionalDistances.min() ?? -1
        let maximumDistance = geometry.directionalDistances.max() ?? 1
        let distanceRange = max(maximumDistance - minimumDistance, 1)
        let transitionStart = geometry.transitionWidth * levelStart
        let transitionEnd = geometry.transitionWidth * levelEnd

        func location(for distance: CGFloat) -> CGFloat {
            min(max((distance - minimumDistance) / distanceRange, 0), 1)
        }

        let start = CGPoint(
            x: geometry.focus.x + geometry.directionNormal.dx * minimumDistance,
            y: geometry.focus.y + geometry.directionNormal.dy * minimumDistance
        )
        let end = CGPoint(
            x: geometry.focus.x + geometry.directionNormal.dx * maximumDistance,
            y: geometry.focus.y + geometry.directionNormal.dy * maximumDistance
        )
        let stops = [
            Gradient.Stop(color: .white, location: 0),
            Gradient.Stop(
                color: .white,
                location: location(
                    for: -geometry.directionalFocusHalfWidth - transitionEnd
                )
            ),
            Gradient.Stop(
                color: .clear,
                location: location(
                    for: -geometry.directionalFocusHalfWidth - transitionStart
                )
            ),
            Gradient.Stop(
                color: .clear,
                location: location(
                    for: geometry.directionalFocusHalfWidth + transitionStart
                )
            ),
            Gradient.Stop(
                color: .white,
                location: location(
                    for: geometry.directionalFocusHalfWidth + transitionEnd
                )
            ),
            Gradient.Stop(color: .white, location: 1)
        ]

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: UnitPoint(
                x: start.x / max(size.width, 1),
                y: start.y / max(size.height, 1)
            ),
            endPoint: UnitPoint(
                x: end.x / max(size.width, 1),
                y: end.y / max(size.height, 1)
            )
        )
    }

    private var levelStart: CGFloat {
        CGFloat(min(max(level, 0), max(levelCount - 1, 0))) / CGFloat(max(levelCount, 1))
    }

    private var levelEnd: CGFloat {
        CGFloat(min(max(level + 1, 1), max(levelCount, 1))) / CGFloat(max(levelCount, 1))
    }

}

struct AnnotationProgressiveBlurPreviewKey: Hashable {
    let sourceID: ObjectIdentifier
    let isEnabled: Bool
    let edgeMode: AnnotationProgressiveBlurEdgeMode
    let mode: AnnotationProgressiveBlurMode
    let strength: CGFloat
    let falloff: CGFloat
    let focusSize: CGFloat
    let focusX: CGFloat
    let focusY: CGFloat
    let directionDegrees: CGFloat
    let contentPixelWidth: CGFloat

    init(
        image: NSImage,
        settings: AnnotationProgressiveBlurSettings,
        contentPixelWidth: CGFloat
    ) {
        sourceID = ObjectIdentifier(image)
        isEnabled = settings.isEnabled
        edgeMode = settings.edgeMode
        mode = settings.mode
        strength = settings.strength
        falloff = settings.falloff
        focusSize = settings.focusSize
        focusX = settings.focusPosition.x
        focusY = settings.focusPosition.y
        directionDegrees = settings.directionDegrees
        self.contentPixelWidth = contentPixelWidth
    }
}

actor AnnotationProgressiveBlurPreviewWorker {
    static let shared = AnnotationProgressiveBlurPreviewWorker()

    private let signposter = OSSignposter(
        subsystem: "com.bettershot",
        category: "SceneBlurPreview"
    )

    func render(
        source: CGImage,
        settings: AnnotationProgressiveBlurSettings,
        contentPixelWidth: CGFloat,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }

        // Blur at the resolution the image occupies on screen, not full
        // source resolution: the geometry is proportional, so the result is
        // visually identical while the per-tick cost drops several-fold on
        // large screenshots.
        let scale = min(1, contentPixelWidth / CGFloat(source.width))
        let input: CGImage
        if scale < 1,
           let downscaled = try? AnnotationScenePreviewRenderer.downscaled(
            source,
            scale: scale,
            colorSpace: colorSpace
           ) {
            input = downscaled
        } else {
            input = source
        }

        return try? AnnotationMockupEffectsRenderer.progressiveBlur(
            input,
            settings: settings,
            colorSpace: colorSpace
        )
    }

    func renderScene(
        source: CGImage,
        shapes: [AnnoShape],
        settings: AnnotationBackgroundSettings,
        contentPixelWidth: CGFloat,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let state = signposter.beginInterval("settleRender")
        defer { signposter.endInterval("settleRender", state) }
        return try? AnnotationScenePreviewRenderer.render(
            source: source,
            shapes: shapes,
            settings: settings,
            contentPixelWidth: contentPixelWidth,
            colorSpace: colorSpace
        )
    }
}

/// Identity of one settled scene render. The canvas shows a settled frame only
/// while the key it was rendered for still matches the live editing state, so
/// any change hides the frame instantly instead of showing stale output.
struct AnnotationSceneSettleKey: Equatable {
    let sourceID: ObjectIdentifier
    let shapes: [AnnoShape]
    let settings: AnnotationBackgroundSettings
    let contentPixelWidth: CGFloat
    let isEligible: Bool
}

struct AnnotationSceneSettleResult {
    let key: AnnotationSceneSettleKey
    let image: NSImage
}

/// Renders the exact export composition at display resolution for the settled
/// scene preview. The background layout and blur geometry are proportional to
/// their extent, so this matches the full-resolution export apart from scale.
nonisolated enum AnnotationScenePreviewRenderer {
    static func render(
        source: CGImage,
        shapes: [AnnoShape],
        settings: AnnotationBackgroundSettings,
        contentPixelWidth: CGFloat,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let scale = min(1, contentPixelWidth / CGFloat(source.width))
        let contentImage = scale < 1
            ? try downscaled(source, scale: scale, colorSpace: colorSpace)
            : source

        return try AnnotationBackgroundRenderer.compose(
            contentImage: contentImage,
            settings: settings,
            colorSpace: colorSpace,
            foregroundOverlay: { context, layout, imageRect, imageClipPath in
                AnnotationRenderer.drawAnnotations(
                    shapes,
                    in: imageRect,
                    // Shapes are in the *source* image's pixels; this render may be downscaled.
                    pageSize: CGSize(width: source.width, height: source.height),
                    canvasSize: layout.canvasSize,
                    context: context,
                    colorSpace: colorSpace,
                    highlightClipPath: imageClipPath
                )
            }
        )
    }

    static func downscaled(
        _ source: CGImage,
        scale: CGFloat,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return image
    }
}
