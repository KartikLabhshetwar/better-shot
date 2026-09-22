import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Exact quarter-turns and reflections in the editor's top-left pixel coordinates.
enum AnnotationImageTransform: CaseIterable {
    case rotateLeft, rotateRight, flipHorizontal, flipVertical

    var title: String {
        switch self {
        case .rotateLeft: "Rotate Left"
        case .rotateRight: "Rotate Right"
        case .flipHorizontal: "Flip Horizontal"
        case .flipVertical: "Flip Vertical"
        }
    }

    var systemImage: String {
        switch self {
        case .rotateLeft: "rotate.left"
        case .rotateRight: "rotate.right"
        case .flipHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .flipVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        }
    }

    var shortcut: ShortcutService.Action {
        switch self {
        case .rotateLeft: .imageRotateLeft
        case .rotateRight: .imageRotateRight
        case .flipHorizontal: .imageFlipHorizontal
        case .flipVertical: .imageFlipVertical
        }
    }

    func pixelSize(for size: CGSize) -> CGSize {
        switch self {
        case .rotateLeft, .rotateRight: CGSize(width: size.height, height: size.width)
        case .flipHorizontal, .flipVertical: size
        }
    }

    func matrix(for size: CGSize) -> Mat {
        switch self {
        case .rotateLeft: Mat(0, -1, 1, 0, 0, size.width)
        case .rotateRight: Mat(0, 1, -1, 0, size.height, 0)
        case .flipHorizontal: Mat(-1, 0, 0, 1, size.width, 0)
        case .flipVertical: Mat(1, 0, 0, -1, 0, size.height)
        }
    }

    func applying(to shape: AnnoShape, imageSize: CGSize) -> AnnoShape {
        var result = shape
        let origin = matrix(for: imageSize).applyToPoint(Vec(shape.x, shape.y))
        result.x = origin.x
        result.y = origin.y
        switch self {
        case .rotateLeft: result.rotation -= .pi / 2
        case .rotateRight: result.rotation += .pi / 2
        case .flipHorizontal:
            result.rotation = -shape.rotation
            result.mirrored = shape.isMirrored ? nil : true
        case .flipVertical:
            result.rotation = .pi - shape.rotation
            result.mirrored = shape.isMirrored ? nil : true
        }
        result.rotation = result.rotation.truncatingRemainder(dividingBy: 2 * .pi)
        return result
    }

    /// Writes a private full-resolution PNG; never mutates the capture or stores EXIF rotation.
    func apply(to url: URL) -> (url: URL, pixelSize: CGSize)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        let sourceSize = CGSize(width: image.width, height: image.height)
        let outputSize = pixelSize(for: sourceSize)
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: Int(outputSize.width), height: Int(outputSize.height),
            bitsPerComponent: max(8, image.bitsPerComponent), bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setBlendMode(.copy)
        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(matrix(for: sourceSize).cgAffineTransform)
        context.translateBy(x: 0, y: sourceSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: sourceSize))
        guard let transformed = context.makeImage() else { return nil }
        let destinationURL = ScreenshotFileNaming.scratchURL("Transform", extension: "png")
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL,
            UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, transformed, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            return nil
        }
        return (destinationURL, outputSize)
    }
}
