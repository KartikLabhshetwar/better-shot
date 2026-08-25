//
//  AnnotationBackgroundLayout.swift
//  BetterShot
//

import CoreGraphics

nonisolated struct AnnotationBackgroundLayout {
    let canvasSize: CGSize
    let cardRect: CGRect
    let imageRect: CGRect
    let padding: CGFloat

    static func make(contentSize: CGSize, settings: AnnotationBackgroundSettings) -> AnnotationBackgroundLayout {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return AnnotationBackgroundLayout(
                canvasSize: .zero,
                cardRect: .zero,
                imageRect: .zero,
                padding: 0
            )
        }

        guard settings.requiresCanvasLayout else {
            let contentRect = CGRect(origin: .zero, size: contentSize)
            return AnnotationBackgroundLayout(
                canvasSize: contentSize,
                cardRect: contentRect,
                imageRect: contentRect,
                padding: 0
            )
        }

        let alignment = settings.effectiveCanvasAlignment
        let shortestEdge = min(contentSize.width, contentSize.height)
        let borderThickness = settings.border.pixelThickness(for: contentSize)
        let cardSize = CGSize(
            width: contentSize.width + borderThickness * 2,
            height: contentSize.height + borderThickness * 2
        )
        let normalizedPadding: CGFloat
        if settings.isEnabled {
            normalizedPadding = settings.padding
        } else if settings.usesCanvasLayout {
            normalizedPadding = max(settings.padding, 0.18)
        } else {
            // A border-only export should grow by exactly the outer ring, not
            // inherit the transparent breathing room used by camera effects.
            normalizedPadding = 0
        }
        let padding = max(0, shortestEdge * normalizedPadding)

        // Per-edge padding: stuck edges get zero padding
        let paddingTop: CGFloat = alignment.sticksToTop ? 0 : padding
        let paddingBottom: CGFloat = alignment.sticksToBottom ? 0 : padding
        let paddingLeading: CGFloat = alignment.sticksToLeading ? 0 : padding
        let paddingTrailing: CGFloat = alignment.sticksToTrailing ? 0 : padding

        let minimumSize = CGSize(
            width: cardSize.width + paddingLeading + paddingTrailing,
            height: cardSize.height + paddingTop + paddingBottom
        )
        let canvasSize = expandedSize(
            minimumSize,
            aspectRatio: settings.usesCanvasLayout ? settings.aspectRatio.value : nil
        )

        // Available rect accounts for per-edge padding
        let availableRect = CGRect(
            x: paddingLeading,
            y: paddingTop,
            width: canvasSize.width - paddingLeading - paddingTrailing,
            height: canvasSize.height - paddingTop - paddingBottom
        )
        let origin = CGPoint(
            x: availableRect.minX + max(0, availableRect.width - cardSize.width) * alignment.xFactor,
            y: availableRect.minY + max(0, availableRect.height - cardSize.height) * alignment.yFactor
        )
        let cardRect = CGRect(origin: origin, size: cardSize)
        let imageRect = cardRect.insetBy(dx: borderThickness, dy: borderThickness)

        return AnnotationBackgroundLayout(
            canvasSize: canvasSize,
            cardRect: cardRect,
            imageRect: imageRect,
            padding: padding
        )
    }

    func scaled(to frame: CGRect) -> AnnotationBackgroundDisplayLayout {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return AnnotationBackgroundDisplayLayout(
                canvasFrame: frame,
                cardFrame: .zero,
                imageFrame: .zero,
                scale: 1
            )
        }

        let scale = frame.width / canvasSize.width
        let cardFrame = CGRect(
            x: frame.minX + cardRect.minX * scale,
            y: frame.minY + cardRect.minY * scale,
            width: cardRect.width * scale,
            height: cardRect.height * scale
        )
        let imageFrame = CGRect(
            x: frame.minX + imageRect.minX * scale,
            y: frame.minY + imageRect.minY * scale,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
        return AnnotationBackgroundDisplayLayout(
            canvasFrame: frame,
            cardFrame: cardFrame,
            imageFrame: imageFrame,
            scale: scale
        )
    }

    private static func expandedSize(_ size: CGSize, aspectRatio: CGFloat?) -> CGSize {
        guard let aspectRatio, aspectRatio > 0, size.width > 0, size.height > 0 else {
            return size
        }

        let currentRatio = size.width / size.height
        if currentRatio < aspectRatio {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        }

        return CGSize(width: size.width, height: size.width / aspectRatio)
    }
}

struct AnnotationBackgroundDisplayLayout {
    let canvasFrame: CGRect
    let cardFrame: CGRect
    let imageFrame: CGRect
    let scale: CGFloat
}
