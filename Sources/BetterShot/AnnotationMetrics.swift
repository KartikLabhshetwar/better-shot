//
//  AnnotationMetrics.swift
//  BetterShot
//

import AppKit

enum AnnotationTextMetrics {
    static let minimumFontSize: CGFloat = 9
    static let defaultNormalizedLineHeight: CGFloat = 0.06
    static let defaultFontName: String = "SF Pro"
    /// Maps normalized lineHeight to a screen font size given imageFrame height.
    static let fontScale: CGFloat = 0.72

    static var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 1.4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    /// Font size for the on-screen text view.
    static func viewFontSize(lineHeight: CGFloat, imageFrameHeight: CGFloat) -> CGFloat {
        max(lineHeight * imageFrameHeight * fontScale, minimumFontSize)
    }

    /// Font size for the final image render (uses pixel height).
    static func renderedFontSize(lineHeight: CGFloat, imagePixelHeight: CGFloat) -> CGFloat {
        max(lineHeight * imagePixelHeight * fontScale, minimumFontSize)
    }

    static func lineCount(for text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        return max(lines.count, 1)
    }

    /// Minimum normalized width for an empty text annotation (caret placeholder).
    static func minimumNormalizedWidth(lineHeight: CGFloat, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0.02 }
        let fontSize = renderedFontSize(lineHeight: lineHeight, imagePixelHeight: imageSize.height)
        return max(0.02, (fontSize * 0.5 + 4) / imageSize.width)
    }

    /// Resolve an NSFont from annotation properties.
    static func resolvedFont(name: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        // Try the family name first, fall back to system font.
        var descriptor: NSFontDescriptor
        if let family = NSFontManager.shared.availableMembers(ofFontFamily: name), !family.isEmpty {
            descriptor = NSFontDescriptor(fontAttributes: [.family: name]).withSize(size)
        } else {
            descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits)
        }

        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

enum AnnotationNumberedCircleMetrics {
    static let normalizedDiameter: CGFloat = 0.039

    static func defaultRect(
        centeredAt point: CGPoint,
        imageSize: CGSize,
        within allowedBounds: CGRect
    ) -> CGRect {
        let height = normalizedDiameter
        let width = imageSize.width > 0
            ? height * max(imageSize.height, 1) / imageSize.width
            : height
        let maxX = max(allowedBounds.minX, allowedBounds.maxX - width)
        let maxY = max(allowedBounds.minY, allowedBounds.maxY - height)

        return CGRect(
            x: min(max(point.x - width / 2, allowedBounds.minX), maxX),
            y: min(max(point.y - height / 2, allowedBounds.minY), maxY),
            width: width,
            height: height
        )
    }

    static func fontSize(for diameter: CGFloat, text: String) -> CGFloat {
        let digitCount = max(text.count, 1)
        let scale: CGFloat
        if digitCount <= 2 {
            scale = 0.54
        } else if digitCount == 3 {
            scale = 0.44
        } else {
            scale = 0.34
        }

        return max(8, diameter * scale)
    }

    static func outlineWidth(for diameter: CGFloat) -> CGFloat {
        max(1, diameter * 0.055)
    }
}

enum AnnotationFilledRectangleMetrics {
    static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(12, max(3, min(rect.width, rect.height) * 0.08))
    }
}
