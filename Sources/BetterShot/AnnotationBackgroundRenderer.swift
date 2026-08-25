//
//  AnnotationBackgroundRenderer.swift
//  BetterShot
//

import AppKit
import CoreGraphics
import ImageIO
import SwiftUI

nonisolated enum AnnotationBackgroundRenderer {
    /// Decoded wallpapers are reused across settled previews and exports so
    /// compose doesn't pay a disk read + full decode per render. NSCache is
    /// thread-safe and evicts under memory pressure.
    nonisolated(unsafe) private static let wallpaperCache: NSCache<NSString, WallpaperCacheBox> = {
        let cache = NSCache<NSString, WallpaperCacheBox>()
        cache.countLimit = 4
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    typealias ForegroundOverlay = (
        _ context: CGContext,
        _ layout: AnnotationBackgroundLayout,
        _ imageRect: CGRect,
        _ imageClipPath: CGPath
    ) -> Void
    typealias CanvasOverlay = (_ context: CGContext, _ layout: AnnotationBackgroundLayout, _ imageRect: CGRect) -> Void

    static func compose(
        annotatedImage: CGImage,
        settings: AnnotationBackgroundSettings,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        try compose(
            contentImage: annotatedImage,
            settings: settings,
            colorSpace: colorSpace
        )
    }

    static func compose(
        contentImage: CGImage,
        settings: AnnotationBackgroundSettings,
        colorSpace: CGColorSpace,
        foregroundOverlay: ForegroundOverlay? = nil,
        canvasOverlay: CanvasOverlay? = nil
    ) throws -> CGImage {
        let contentSize = CGSize(width: contentImage.width, height: contentImage.height)
        let layout = AnnotationBackgroundLayout.make(contentSize: contentSize, settings: settings)
        let width = max(1, Int(ceil(layout.canvasSize.width)))
        let height = max(1, Int(ceil(layout.canvasSize.height)))

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

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        drawBackground(settings.style, in: canvasRect, context: context)

        let borderWidth = settings.border.pixelThickness(for: contentSize)
        let imageRect = pixelAlignedImageRect(
            flipped(layout.imageRect, canvasHeight: CGFloat(height)),
            contentSize: contentSize,
            canvasSize: canvasRect.size,
            minimumInset: borderWidth
        )
        let frameGeometry = AnnotationScreenshotFrameGeometry(
            imageRect: imageRect,
            cardRect: imageRect.insetBy(dx: -borderWidth, dy: -borderWidth),
            settings: settings
        )
        let clipPath = frameGeometry.imagePath
        let usesSceneBlur = settings.progressiveBlur.isActive
            && settings.progressiveBlur.edgeMode == .bleed
        let displayedImage = if settings.progressiveBlur.edgeMode == .clipped {
            try AnnotationMockupEffectsRenderer.progressiveBlur(
                contentImage,
                settings: settings.progressiveBlur,
                colorSpace: colorSpace
            )
        } else {
            contentImage
        }

        if settings.camera.hasEffect {
            guard let foregroundContext = CGContext(
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

            drawScreenshotFrameBacking(
                settings,
                geometry: frameGeometry,
                castsShadow: true,
                context: foregroundContext
            )
            drawImage(displayedImage, in: imageRect, clippedTo: clipPath, context: foregroundContext)
            foregroundOverlay?(foregroundContext, layout, imageRect, clipPath)

            guard let foregroundImage = foregroundContext.makeImage() else {
                throw CocoaError(.fileWriteUnknown)
            }

            let topLeftImageRect = flipped(imageRect, canvasHeight: CGFloat(height))
            let projection = AnnotationCameraGeometry.projection(
                sourceRect: canvasRect,
                imageRect: topLeftImageRect,
                canvasSize: canvasRect.size,
                settings: settings.camera
            )
            try AnnotationMockupEffectsRenderer.drawProjectedForeground(
                foregroundImage,
                projection: projection,
                canvasSize: canvasRect.size,
                colorSpace: colorSpace,
                into: context
            )
        } else {
            drawScreenshotFrameBacking(
                settings,
                geometry: frameGeometry,
                castsShadow: settings.isEnabled,
                context: context
            )
            drawImage(displayedImage, in: imageRect, clippedTo: clipPath, context: context)
            foregroundOverlay?(context, layout, imageRect, clipPath)
        }

        if usesSceneBlur {
            guard let sceneImage = context.makeImage() else {
                throw CocoaError(.fileWriteUnknown)
            }
            context.clear(canvasRect)
            try AnnotationMockupEffectsRenderer.drawProgressivelyBlurredScene(
                sceneImage,
                canvasSize: canvasRect.size,
                colorSpace: colorSpace,
                progressiveBlurSettings: settings.progressiveBlur,
                into: context
            )
        }

        canvasOverlay?(context, layout, imageRect)

        guard let renderedImage = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return renderedImage
    }

    private static func drawImage(
        _ image: CGImage,
        in rect: CGRect,
        clippedTo path: CGPath,
        context: CGContext
    ) {
        context.saveGState()
        context.interpolationQuality = .none
        context.addPath(path)
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func drawScreenshotFrameBacking(
        _ settings: AnnotationBackgroundSettings,
        geometry: AnnotationScreenshotFrameGeometry,
        castsShadow: Bool,
        context: CGContext
    ) {
        if settings.border.isVisible, geometry.borderWidth > 0 {
            let opacity = min(max(settings.border.opacity, 0), 1)
                * min(max(settings.border.color.alpha, 0), 1)

            if castsShadow {
                drawShadow(
                    path: geometry.cardPath,
                    knockoutPath: geometry.cardShadowKnockoutPath,
                    strength: settings.shadow,
                    style: settings.shadowStyle,
                    context: context
                )
            }
            context.saveGState()
            context.setFillColor(
                settings.border.color.nsColor.withAlphaComponent(opacity).cgColor
            )
            context.addPath(geometry.cardPath)
            context.fillPath()
            context.restoreGState()
        } else if castsShadow {
            drawShadow(
                path: geometry.imagePath,
                knockoutPath: geometry.imageShadowKnockoutPath,
                strength: settings.shadow,
                style: settings.shadowStyle,
                context: context
            )
        }
    }

    static func drawWatermark(
        _ settings: AnnotationWatermarkSettings,
        in rect: CGRect,
        context: CGContext
    ) {
        let text = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.isVisible,
              !text.isEmpty,
              rect.width > 1,
              rect.height > 1 else {
            return
        }

        let rows = max(2, Int(round(settings.density)))
        let spacingY = rect.height / CGFloat(rows)
        let spacingX = max(1, spacingY * 2.2)
        let diagonal = hypot(rect.width, rect.height)
        let columnCount = max(2, Int(ceil(diagonal / spacingX)))
        let rowCount = max(2, Int(ceil(diagonal / spacingY)))
        let originX = rect.midX - CGFloat(columnCount) * spacingX / 2
        let originY = rect.midY - CGFloat(rowCount) * spacingY / 2

        let font = AnnotationWatermarkTypography.nsFont(size: settings.fontSize)
        let color = settings.color.nsColor.withAlphaComponent(min(0.75, max(0, settings.opacity)))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let measuredSize = attributedText.size()
        guard measuredSize.width > 0, measuredSize.height > 0 else { return }

        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -settings.rotationDegrees * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for row in 0...rowCount {
            for column in 0...columnCount {
                let center = CGPoint(
                    x: originX + CGFloat(column) * spacingX,
                    y: originY + CGFloat(row) * spacingY
                )
                attributedText.draw(
                    with: CGRect(
                        x: center.x - measuredSize.width / 2,
                        y: center.y - measuredSize.height / 2,
                        width: measuredSize.width,
                        height: measuredSize.height
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func drawBackground(
        _ style: AnnotationBackgroundStyle,
        in rect: CGRect,
        context: CGContext
    ) {
        switch style {
        case .none:
            context.clear(rect)

        case .solid(let color):
            context.setFillColor(color.nsColor.cgColor)
            context.fill(rect)

        case .gradient(let gradient):
            let nsColors = gradient.colors.map(\.nsColor)
            let cgColors = nsColors.map(\.cgColor) as CFArray
            guard let cgGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: nil
            ) else {
                context.setFillColor(nsColors.first?.cgColor ?? NSColor.black.cgColor)
                context.fill(rect)
                return
            }

            context.drawLinearGradient(
                cgGradient,
                start: cgPoint(for: gradient.startPoint, in: rect),
                end: cgPoint(for: gradient.endPoint, in: rect),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )

        case .customWallpaper(let wallpaper):
            drawCustomWallpaper(
                wallpaper,
                in: rect,
                context: context
            )
        }
    }

    private static func drawCustomWallpaper(
        _ wallpaper: AnnotationCustomWallpaper,
        in rect: CGRect,
        context: CGContext
    ) {
        guard let image = loadCGImageForAspectFill(at: wallpaper.url, fillSize: rect.size) else {
            drawMissingWallpaperFallback(in: rect, context: context)
            return
        }

        context.interpolationQuality = .high
        context.draw(image, in: aspectFillRect(
            imageSize: CGSize(width: image.width, height: image.height),
            fillRect: rect
        ))
    }

    private static func loadCGImageForAspectFill(at url: URL, fillSize: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        guard let sourceSize = imageSize(from: source),
              sourceSize.width > 0,
              sourceSize.height > 0,
              fillSize.width > 0,
              fillSize.height > 0 else {
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary)
        }

        let drawScale = max(fillSize.width / sourceSize.width, fillSize.height / sourceSize.height)
        let requiredMaxPixelSize = max(sourceSize.width, sourceSize.height) * drawScale
        // Bucket the decode size so settled previews and exports of similar
        // sizes share one cache entry instead of decoding near-duplicates.
        let bucketedMaxPixelSize = (requiredMaxPixelSize / 512).rounded(.up) * 512
        let cacheKey = AnnotationWallpaperPreviewCache.cacheID(
            for: url,
            maxPixelSize: bucketedMaxPixelSize
        ) as NSString
        if let cached = wallpaperCache.object(forKey: cacheKey) {
            return cached.image
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(bucketedMaxPixelSize))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        wallpaperCache.setObject(
            WallpaperCacheBox(image),
            forKey: cacheKey,
            cost: image.width * image.height * 4
        )
        return image
    }

    private static func imageSize(from source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private static func aspectFillRect(imageSize: CGSize, fillRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, fillRect.width > 0, fillRect.height > 0 else {
            return fillRect
        }

        let scale = max(fillRect.width / imageSize.width, fillRect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: fillRect.midX - size.width / 2,
            y: fillRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func drawMissingWallpaperFallback(in rect: CGRect, context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: 8, dy: 8))
    }

    /// Paints the shadow without laying any ink inside the card: the fill is
    /// clipped away so only the spill survives. That keeps translucent borders
    /// and screenshots with alpha from being backed by black.
    private static func drawShadow(
        path: CGPath,
        knockoutPath: CGPath,
        strength: CGFloat,
        style: AnnotationShadowStyle,
        context: CGContext
    ) {
        let rect = path.boundingBoxOfPath
        guard let layer = style.layer(
            strength: strength,
            referenceEdge: min(rect.width, rect.height)
        ) else {
            return
        }

        context.saveGState()

        let exterior = CGMutablePath()
        exterior.addRect(context.boundingBoxOfClipPath)
        exterior.addPath(knockoutPath)
        context.addPath(exterior)
        context.clip(using: .evenOdd)

        context.setShadow(
            offset: CGSize(width: 0, height: -layer.yOffset),
            blur: layer.coreGraphicsBlur,
            color: NSColor.black.withAlphaComponent(layer.alpha).cgColor
        )
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(path)
        context.fillPath()

        context.restoreGState()
    }

    private static func flipped(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func pixelAlignedImageRect(
        _ rect: CGRect,
        contentSize: CGSize,
        canvasSize: CGSize,
        minimumInset: CGFloat
    ) -> CGRect {
        let width = min(contentSize.width, canvasSize.width)
        let height = min(contentSize.height, canvasSize.height)
        let inset = max(0, minimumInset)
        let minX = min(inset, max(0, canvasSize.width - width))
        let minY = min(inset, max(0, canvasSize.height - height))
        let maxX = max(minX, canvasSize.width - width - inset)
        let maxY = max(minY, canvasSize.height - height - inset)
        let x = min(max(minX, rect.minX.rounded()), maxX)
        let y = min(max(minY, rect.minY.rounded()), maxY)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func cgPoint(for unitPoint: UnitPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + unitPoint.x * rect.width,
            y: rect.minY + (1 - unitPoint.y) * rect.height
        )
    }
}

nonisolated private final class WallpaperCacheBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
