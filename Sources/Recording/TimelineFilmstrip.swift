import AppKit

/// Composites the editor's thumbnails into a single image, cached until the thumbnails or the track size change. Drawing the `NSImage`s directly re-rasterized all twenty of them on every frame of playback.
@MainActor
final class TimelineFilmstrip {
    private struct Key: Equatable {
        let images: [ObjectIdentifier]
        let width: Int
        let height: Int
    }

    private var key: Key?
    private var image: CGImage?

    func image(for thumbnails: [NSImage], size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * max(scale, 1)).rounded())
        let height = Int((size.height * max(scale, 1)).rounded())
        guard !thumbnails.isEmpty, width > 0, height > 0 else { return nil }

        let key = Key(images: thumbnails.map(ObjectIdentifier.init), width: width, height: height)
        if key == self.key, let image { return image }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        let tileWidth = CGFloat(width) / CGFloat(thumbnails.count)
        for (index, thumbnail) in thumbnails.enumerated() {
            guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let tile = CGRect(x: CGFloat(index) * tileWidth, y: 0, width: tileWidth.rounded(.up), height: CGFloat(height))
            context.draw(cgImage, in: tile)
        }

        guard let rendered = context.makeImage() else { return nil }
        self.key = key
        self.image = rendered
        return rendered
    }
}

extension CGContext {
    /// Draws a bottom-up `CGImage` into a flipped `NSView` the right way up.
    func drawFlipped(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }
}
