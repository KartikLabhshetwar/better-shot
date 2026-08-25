import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Share links travel over the network, so the render is downscaled and re-encoded locally before a single byte is uploaded.
enum ShareImageCompressor {
    static let maxLongEdge = 2560
    static let jpegQuality = 0.85

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Flat UI compresses smaller as PNG and photographic backgrounds smaller as JPEG, so both are encoded and the lighter one wins.
    nonisolated static func write(
        _ image: CGImage,
        named name: String,
        keepingAlpha: Bool,
        into directory: URL
    ) throws -> URL {
        let scaled = downscaled(image) ?? image
        let png = try encode(scaled, as: .png, quality: nil, to: directory.appendingPathComponent("\(name).png"))
        guard !keepingAlpha else { return png }

        let jpeg = try encode(
            scaled, as: .jpeg, quality: jpegQuality, to: directory.appendingPathComponent("\(name).jpg")
        )
        let winner = byteCount(jpeg) < byteCount(png) ? jpeg : png
        try? FileManager.default.removeItem(at: winner == png ? jpeg : png)
        return winner
    }

    /// Retina captures land four to five thousand pixels wide, which no share page ever displays.
    nonisolated static func downscaled(_ image: CGImage) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return nil }

        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                ?? (CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    nonisolated static func byteCount(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? .max
    }

    private nonisolated static func encode(
        _ image: CGImage, as type: UTType, quality: Double?, to url: URL
    ) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else {
            throw Failure(errorDescription: "Could not encode the image for upload.")
        }

        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(errorDescription: "Could not write the image for upload.")
        }
        return url
    }
}
