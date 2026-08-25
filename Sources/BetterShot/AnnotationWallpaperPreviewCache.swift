//
//  AnnotationWallpaperPreviewCache.swift
//  BetterShot
//

import CoreGraphics
import Foundation
import ImageIO

actor AnnotationWallpaperPreviewCache {
    static let shared = AnnotationWallpaperPreviewCache()

    private let imageCache = NSCache<NSString, CGImageBox>()
    private var inFlightImages: [String: Task<CGImage?, Never>] = [:]

    private init() {
        imageCache.countLimit = 48
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        let key = Self.cacheID(for: url, maxPixelSize: maxPixelSize)
        if let cachedImage = imageCache.object(forKey: key as NSString)?.image {
            return cachedImage
        }

        if let task = inFlightImages[key] {
            return await task.value
        }

        let task = Task.detached(priority: .userInitiated) {
            Self.downsampledCGImage(at: url, maxPixelSize: maxPixelSize)
        }
        inFlightImages[key] = task

        let image = await task.value
        inFlightImages[key] = nil

        if let image {
            imageCache.setObject(CGImageBox(image), forKey: key as NSString)
        }

        return image
    }

    /// Stable identity for a downsampled image. Includes the file signature so
    /// a file replaced in place (same path) is treated as a distinct entry.
    /// Used both as the cache key and as the SwiftUI `.task(id:)` value so the
    /// preview reloads exactly when the cache would produce a different image.
    nonisolated static func cacheID(for url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.standardizedFileURL.path)#\(Int(maxPixelSize.rounded(.up)))#\(fileSignature(for: url))"
    }

    private static func fileSignature(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return "unknown"
        }

        let fileSize = values.fileSize ?? 0
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(fileSize)-\(modified)"
    }

    private static func downsampledCGImage(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

nonisolated private final class CGImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
