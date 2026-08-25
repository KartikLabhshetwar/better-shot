//
//  ScreenshotCompressionService.swift
//  BetterShot
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotCompressionResult: Equatable, Sendable {
    let outputURL: URL
    let originalByteCount: Int64
    let compressedByteCount: Int64

    var savingsPercent: Int {
        guard originalByteCount > 0 else { return 0 }
        let rawPercent = (1 - (Double(compressedByteCount) / Double(originalByteCount))) * 100
        return max(0, Int(rawPercent.rounded()))
    }

    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedByteCount, countStyle: .file)
    }

    var displaySummary: String {
        if savingsPercent > 0 {
            return "↓\(savingsPercent)% · \(formattedCompressedSize)"
        }

        return formattedCompressedSize
    }
}

enum ScreenshotCompressionService {
    static let defaultJPEGQuality = 0.75

    nonisolated static func compressToTemporaryJPEG(sourceURL: URL, quality: Double) throws -> ScreenshotCompressionResult {
        let originalByteCount = try byteCount(at: sourceURL)
        let outputURL = try temporaryJPEGURL(for: sourceURL)

        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let sourceImage = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCache: true] as CFDictionary
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let flattenedImage = try flattenedJPEGImage(from: sourceImage)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 1)
        ]
        CGImageDestinationAddImage(destination, flattenedImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return ScreenshotCompressionResult(
            outputURL: outputURL,
            originalByteCount: originalByteCount,
            compressedByteCount: try byteCount(at: outputURL)
        )
    }

    nonisolated private static func temporaryJPEGURL(for sourceURL: URL) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BetterShot/CompressedImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent("\(baseName)-compressed-\(UUID().uuidString.prefix(6))")
            .appendingPathExtension("jpg")
    }

    nonisolated private static func flattenedJPEGImage(from image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor.white)
        context.fill(rect)
        context.draw(image, in: rect)

        guard let flattened = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return flattened
    }

    nonisolated private static func byteCount(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
