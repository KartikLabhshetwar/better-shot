import CoreGraphics
import Foundation
import ImageIO
import libwebp

enum ImageExportError: Error, Equatable {
    case invalidDimensions
    case pixelBufferOverflow
    case bitmapContextCreationFailed
    case webPEncodeFailed
    case imageDestinationCreationFailed
    case imageFinalizeFailed
    case dataWriteFailed
}

enum ImageExporter {
    static func export(_ image: CGImage, format: ExportFormat, quality: Double, to url: URL) throws {
        switch format {
        case .webp:
            let data = try encodeWebPData(from: image, quality: quality)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ImageExportError.dataWriteFailed
            }
        case .png, .jpeg:
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                format.utType as CFString,
                1,
                nil
            ) else {
                throw ImageExportError.imageDestinationCreationFailed
            }

            var options: [CFString: Any] = [:]
            if format.supportsLossyCompressionQuality {
                options[kCGImageDestinationLossyCompressionQuality] = clampedQuality(quality)
            }

            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ImageExportError.imageFinalizeFailed
            }
        }
    }

    static func encodeWebPData(from image: CGImage, quality: Double) throws -> Data {
        let width = image.width
        let height = image.height

        guard width > 0, height > 0,
              width <= Int(Int32.max),
              height <= Int(Int32.max) else {
            throw ImageExportError.invalidDimensions
        }

        let bytesPerPixel = 4
        let row = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !row.overflow else { throw ImageExportError.pixelBufferOverflow }
        let total = row.partialValue.multipliedReportingOverflow(by: height)
        guard !total.overflow else { throw ImageExportError.pixelBufferOverflow }

        let bytesPerRow = row.partialValue
        var rgba = [UInt8](repeating: 0, count: total.partialValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let madeContext = rgba.withUnsafeMutableBytes { rawBytes -> Bool in
            guard let base = rawBytes.baseAddress else { return false }
            guard let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard madeContext else { throw ImageExportError.bitmapContextCreationFailed }

        unpremultiplyRGBAInPlace(&rgba)

        var outputPtr: UnsafeMutablePointer<UInt8>?
        let clamped = clampedQuality(quality)

        let encodedSize = rgba.withUnsafeBytes { rawBytes -> Int in
            guard let base = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            if clamped == 1.0 {
                return Int(WebPEncodeLosslessRGBA(
                    base,
                    Int32(width),
                    Int32(height),
                    Int32(bytesPerRow),
                    &outputPtr
                ))
            }

            return Int(WebPEncodeRGBA(
                base,
                Int32(width),
                Int32(height),
                Int32(bytesPerRow),
                Float(clamped * 100.0),
                &outputPtr
            ))
        }

        guard encodedSize > 0, let outputPtr else {
            throw ImageExportError.webPEncodeFailed
        }
        defer { WebPFree(outputPtr) }

        let data = Data(bytes: outputPtr, count: encodedSize)
        guard !data.isEmpty else { throw ImageExportError.webPEncodeFailed }
        return data
    }

    private static func clampedQuality(_ quality: Double) -> Double {
        max(0.0, min(1.0, quality))
    }

    private static func unpremultiplyRGBAInPlace(_ pixels: inout [UInt8]) {
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[idx + 3])
            if alpha <= 0 {
                pixels[idx] = 0
                pixels[idx + 1] = 0
                pixels[idx + 2] = 0
                continue
            }
            if alpha >= 255 { continue }

            pixels[idx] = unpremultiplyChannel(pixels[idx], alpha: alpha)
            pixels[idx + 1] = unpremultiplyChannel(pixels[idx + 1], alpha: alpha)
            pixels[idx + 2] = unpremultiplyChannel(pixels[idx + 2], alpha: alpha)
        }
    }

    private static func unpremultiplyChannel(_ value: UInt8, alpha: Int) -> UInt8 {
        let scaled = (Int(value) * 255 + (alpha / 2)) / alpha
        return UInt8(max(0, min(255, scaled)))
    }
}
