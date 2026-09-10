import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct AnnotationImageTransform: Equatable, Sendable {
    private(set) var quarterTurns = 0
    private(set) var isMirrored = false

    static let identity = AnnotationImageTransform()

    struct Result {
        let url: URL
        let pixelSize: CGSize
    }

    func apply(to sourceURL: URL) throws -> Result {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = try render(image)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterShot_Transform_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        return Result(url: url, pixelSize: CGSize(width: output.width, height: output.height))
    }

    func rotatedClockwise() -> Self {
        var result = self
        result.quarterTurns = (quarterTurns + 1) % 4
        return result
    }

    func flippedHorizontally() -> Self {
        var result = self
        result.quarterTurns = (4 - quarterTurns) % 4
        result.isMirrored.toggle()
        return result
    }

    func flippedVertically() -> Self {
        var result = self
        result.quarterTurns = (6 - quarterTurns) % 4
        result.isMirrored.toggle()
        return result
    }

    func displaySize(for sourceSize: CGSize) -> CGSize {
        quarterTurns.isMultiple(of: 2)
            ? sourceSize
            : CGSize(width: sourceSize.height, height: sourceSize.width)
    }

    func affineTransform(for sourceSize: CGSize) -> CGAffineTransform {
        let rotation: CGAffineTransform
        switch quarterTurns {
        case 1:
            rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: sourceSize.height, ty: 0)
        case 2:
            rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: sourceSize.width, ty: sourceSize.height)
        case 3:
            rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: sourceSize.width)
        default:
            rotation = .identity
        }
        let reflection = isMirrored
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: sourceSize.width, ty: 0)
            : .identity
        return reflection.concatenating(rotation)
    }

    func render(_ source: CGImage) throws -> CGImage {
        guard self != .identity else { return source }
        let sourceSize = CGSize(width: source.width, height: source.height)
        let size = displaySize(for: sourceSize)
        let colorSpace = source.colorSpace?.model == .rgb
            ? source.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let sourceFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceSize.height)
        let displayFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        context.concatenate(sourceFlip.concatenating(affineTransform(for: sourceSize)).concatenating(displayFlip))
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(source, in: CGRect(origin: .zero, size: sourceSize))
        guard let result = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

}
