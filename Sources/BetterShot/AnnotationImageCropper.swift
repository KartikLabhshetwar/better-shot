//
//  AnnotationImageCropper.swift
//  BetterShot
//
//  Crops a source image at its native pixel resolution and writes the result
//  to a temporary PNG. Cropping happens on the full-resolution `CGImage`, so no
//  quality is lost. The returned `normalizedRect` reflects the exact (integral)
//  pixel rect that was used, so callers can remap annotations to match it
//  precisely.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AnnotationImageCropper {
    struct Result {
        let url: URL
        let pixelSize: CGSize
        /// The normalized rect (relative to the original image) that was
        /// actually used after rounding to integral pixels.
        let normalizedRect: CGRect
    }

    /// Crop the image at `url` to `normalizedRect` (0...1, top-left origin).
    static func crop(url: URL, normalizedRect: CGRect) -> Result? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            return nil
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }

        let rect = normalizedRect.standardized
        var pixelRect = CGRect(
            x: rect.minX * width,
            y: rect.minY * height,
            width: rect.width * width,
            height: rect.height * height
        ).integral
        pixelRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect) else {
            return nil
        }

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BetterShot_Crop_\(UUID().uuidString.prefix(8)).png")

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            return nil
        }

        let usedRect = CGRect(
            x: pixelRect.minX / width,
            y: pixelRect.minY / height,
            width: pixelRect.width / width,
            height: pixelRect.height / height
        )

        return Result(
            url: destinationURL,
            pixelSize: CGSize(width: pixelRect.width, height: pixelRect.height),
            normalizedRect: usedRect
        )
    }
}
