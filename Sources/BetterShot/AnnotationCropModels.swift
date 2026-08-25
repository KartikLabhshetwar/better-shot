//
//  AnnotationCropModels.swift
//  BetterShot
//
//  Geometry and presets for the crop tool. All crop math operates in the
//  image's normalized coordinate space (0...1, top-left origin, y-down), the
//  same convention used throughout the annotation editor. Aspect ratios are
//  expressed in *pixel* terms and converted to a normalized width/height ratio
//  using the source image dimensions.
//

import CoreGraphics

/// Aspect ratio presets offered while cropping.
enum CropAspectRatio: String, CaseIterable, Identifiable {
    case freeform
    case original
    case square
    case sixteenNine
    case nineSixteen
    case fourThree
    case threeTwo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeform: "Freeform"
        case .original: "Original"
        case .square: "1:1"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        }
    }

    /// The pixel width / height ratio for this preset, or `nil` for freeform.
    func pixelRatio(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .freeform:
            return nil
        case .original:
            return imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .square:
            return 1
        case .sixteenNine:
            return 16.0 / 9.0
        case .nineSixteen:
            return 9.0 / 16.0
        case .fourThree:
            return 4.0 / 3.0
        case .threeTwo:
            return 3.0 / 2.0
        }
    }

    /// The desired normalized `width / height` ratio of the crop rect that
    /// produces `pixelRatio` once scaled back into pixels.
    func normalizedRatio(imageSize: CGSize) -> CGFloat? {
        guard let pixelRatio = pixelRatio(imageSize: imageSize),
              imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }
        return pixelRatio * imageSize.height / imageSize.width
    }

    var locksAspect: Bool {
        self != .freeform
    }
}

/// The eight drag handles around a crop rectangle.
enum CropHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: true
        default: false
        }
    }

    /// Unit position (0...1) of the handle within the crop rect.
    var unitPoint: CGPoint {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .top: CGPoint(x: 0.5, y: 0)
        case .topRight: CGPoint(x: 1, y: 0)
        case .left: CGPoint(x: 0, y: 0.5)
        case .right: CGPoint(x: 1, y: 0.5)
        case .bottomLeft: CGPoint(x: 0, y: 1)
        case .bottom: CGPoint(x: 0.5, y: 1)
        case .bottomRight: CGPoint(x: 1, y: 1)
        }
    }

    fileprivate var isLeft: Bool {
        self == .topLeft || self == .left || self == .bottomLeft
    }

    fileprivate var isTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }
}

/// Pure functions that edit a normalized crop rect. Everything is clamped to
/// the unit rect and never collapses below the supplied minimum size.
enum CropRectEditor {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Resize the crop rect by dragging `handle` to a new normalized position.
    /// When `aspect` (normalized width/height) is supplied, corner drags keep
    /// the ratio. Edge drags ignore the aspect lock. When `fromCenter` is true
    /// the rect grows/shrinks symmetrically about its center (Figma/CleanShot
    /// style), keeping the center fixed.
    static func resize(
        _ rect: CGRect,
        handle: CropHandle,
        to point: CGPoint,
        aspect: CGFloat?,
        minWidth: CGFloat,
        minHeight: CGFloat,
        fromCenter: Bool = false
    ) -> CGRect {
        let p = CGPoint(x: clamp(point.x), y: clamp(point.y))

        if fromCenter {
            return resizeFromCenter(
                rect,
                handle: handle,
                to: p,
                aspect: aspect,
                minWidth: minWidth,
                minHeight: minHeight
            )
        }

        if handle.isCorner {
            return resizeCorner(
                rect,
                isLeft: handle.isLeft,
                isTop: handle.isTop,
                to: p,
                aspect: aspect,
                minWidth: minWidth,
                minHeight: minHeight
            )
        }

        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .left:
            minX = min(p.x, maxX - minWidth)
        case .right:
            maxX = max(p.x, minX + minWidth)
        case .top:
            minY = min(p.y, maxY - minHeight)
        case .bottom:
            maxY = max(p.y, minY + minHeight)
        default:
            break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Translate the whole crop rect, keeping it fully inside the unit rect.
    static func move(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let x = clamp(rect.minX + delta.width, max: 1 - rect.width)
        let y = clamp(rect.minY + delta.height, max: 1 - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Fit the largest rect of the given normalized `aspect` centered on
    /// `rect`, clamped to the unit rect.
    static func applyAspect(to rect: CGRect, aspect: CGFloat) -> CGRect {
        guard aspect > 0 else { return rect }

        var width = rect.width
        var height = rect.height
        if width / height > aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }

        // Don't exceed the available space anchored at the unit rect.
        width = min(width, 1)
        height = min(height, 1)
        if width / height > aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }

        var result = CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )

        if result.minX < 0 { result.origin.x = 0 }
        if result.minY < 0 { result.origin.y = 0 }
        if result.maxX > 1 { result.origin.x = 1 - result.width }
        if result.maxY > 1 { result.origin.y = 1 - result.height }
        return result
    }

    // MARK: Private

    /// Symmetric resize about the rect's center. The center stays fixed and the
    /// opposite edge/corner mirrors the dragged one.
    private static func resizeFromCenter(
        _ rect: CGRect,
        handle: CropHandle,
        to point: CGPoint,
        aspect: CGFloat?,
        minWidth: CGFloat,
        minHeight: CGFloat
    ) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var halfWidth = rect.width / 2
        var halfHeight = rect.height / 2

        if handle.isCorner {
            halfWidth = abs(point.x - center.x)
            halfHeight = abs(point.y - center.y)
            if let aspect, aspect > 0 {
                if halfWidth / halfHeight > aspect {
                    halfWidth = halfHeight * aspect
                } else {
                    halfHeight = halfWidth / aspect
                }
            }
        } else {
            switch handle {
            case .left, .right:
                halfWidth = abs(point.x - center.x)
            case .top, .bottom:
                halfHeight = abs(point.y - center.y)
            default:
                break
            }
        }

        // Enforce the minimum size (about the center).
        halfWidth = max(halfWidth, minWidth / 2)
        halfHeight = max(halfHeight, minHeight / 2)

        // Keep the symmetric rect inside the unit rect (bounded by the nearer
        // edge so the center can't drift).
        let maxHalfWidth = min(center.x, 1 - center.x)
        let maxHalfHeight = min(center.y, 1 - center.y)
        halfWidth = min(halfWidth, maxHalfWidth)
        halfHeight = min(halfHeight, maxHalfHeight)

        // Re-fit the aspect after clamping so corners stay locked at the edges.
        if let aspect, aspect > 0, handle.isCorner {
            if halfWidth / halfHeight > aspect {
                halfWidth = halfHeight * aspect
            } else {
                halfHeight = halfWidth / aspect
            }
        }

        return CGRect(
            x: center.x - halfWidth,
            y: center.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
    }

    private static func resizeCorner(
        _ rect: CGRect,
        isLeft: Bool,
        isTop: Bool,
        to point: CGPoint,
        aspect: CGFloat?,
        minWidth: CGFloat,
        minHeight: CGFloat
    ) -> CGRect {
        let anchorX = isLeft ? rect.maxX : rect.minX
        let anchorY = isTop ? rect.maxY : rect.minY

        var cornerX = isLeft ? min(point.x, anchorX - minWidth) : max(point.x, anchorX + minWidth)
        var cornerY = isTop ? min(point.y, anchorY - minHeight) : max(point.y, anchorY + minHeight)

        if let aspect, aspect > 0 {
            var width = abs(cornerX - anchorX)
            var height = abs(cornerY - anchorY)

            if width / height > aspect {
                width = height * aspect
            } else {
                height = width / aspect
            }

            // Keep the aspect-locked corner inside the unit rect.
            let maxWidth = isLeft ? anchorX : (1 - anchorX)
            let maxHeight = isTop ? anchorY : (1 - anchorY)
            if width > maxWidth {
                width = maxWidth
                height = width / aspect
            }
            if height > maxHeight {
                height = maxHeight
                width = height * aspect
            }

            cornerX = isLeft ? anchorX - width : anchorX + width
            cornerY = isTop ? anchorY - height : anchorY + height
        }

        return CGRect(
            x: min(cornerX, anchorX),
            y: min(cornerY, anchorY),
            width: abs(cornerX - anchorX),
            height: abs(cornerY - anchorY)
        )
    }

    private static func clamp(_ value: CGFloat, max upper: CGFloat = 1) -> CGFloat {
        min(max(value, 0), upper)
    }
}
