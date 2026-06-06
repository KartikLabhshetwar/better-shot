import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum RedactionImageProcessor {
    private static let maximumCachedPreviewCost = 12 * 1024 * 1024

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func previewImage(
        source: NSImage,
        tool: AnnotationTool,
        density: CGFloat,
        normalizedBounds: CGRect,
        originalImageSize: CGSize,
        allowsCaching: Bool = true
    ) -> NSImage? {
        guard tool.isRedactionTool else { return nil }
        guard let sourceImage = source.bestCGImage(),
              let cropRect = pixelRect(for: normalizedBounds, in: sourceImage) else {
            return nil
        }
        let previewScale = redactionScale(sourceImage: sourceImage, originalImageSize: originalImageSize)

        let quantizedDensity = Int((density * 100).rounded())
        let cacheKey = [
            "\(ObjectIdentifier(source).hashValue)",
            tool.rawValue,
            "\(quantizedDensity)",
            "\(Int((previewScale * 1000).rounded()))",
            "\(Int(cropRect.minX))",
            "\(Int(cropRect.minY))",
            "\(Int(cropRect.width))",
            "\(Int(cropRect.height))"
        ].joined(separator: "-") as NSString
        if allowsCaching, let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image: NSImage? = autoreleasepool {
            switch tool {
            case .pixelate:
                makePixelatedImage(source: sourceImage, cropRect: cropRect, density: density, scale: previewScale)
            case .blur:
                makeBlurredImage(source: sourceImage, cropRect: cropRect, density: density, scale: previewScale)
            default:
                nil
            }
        }

        if allowsCaching, let image {
            let cost = image.pixelCost
            if cost <= maximumCachedPreviewCost {
                cache.setObject(image, forKey: cacheKey, cost: cost)
            }
        }

        return image
    }

    static func previewImageFromCGImage(
        source: CGImage,
        tool: AnnotationTool,
        density: CGFloat,
        normalizedBounds: CGRect,
        viewScale: CGFloat,
        allowsCaching: Bool = true
    ) -> NSImage? {
        guard tool.isRedactionTool else { return nil }
        guard let cropRect = pixelRect(for: normalizedBounds, in: source) else { return nil }

        let quantizedDensity = Int((density * 100).rounded())
        let cacheKey = [
            "cg-\(source.width)x\(source.height)",
            tool.rawValue,
            "\(quantizedDensity)",
            "\(Int((viewScale * 1000).rounded()))",
            "\(Int(cropRect.minX))",
            "\(Int(cropRect.minY))",
            "\(Int(cropRect.width))",
            "\(Int(cropRect.height))"
        ].joined(separator: "-") as NSString
        if allowsCaching, let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let scale = max(viewScale, 0.01)
        let image: NSImage? = autoreleasepool {
            switch tool {
            case .pixelate:
                makePixelatedImage(source: source, cropRect: cropRect, density: density, scale: scale)
            case .blur:
                makeBlurredImage(source: source, cropRect: cropRect, density: density, scale: scale)
            default:
                nil
            }
        }

        if allowsCaching, let image {
            let cost = image.pixelCost
            if cost <= maximumCachedPreviewCost {
                cache.setObject(image, forKey: cacheKey, cost: cost)
            }
        }
        return image
    }

    static func removeAllCachedPreviewImages() {
        cache.removeAllObjects()
        ciContext.clearCaches()
    }

    private static func makePixelatedImage(
        source: CGImage,
        cropRect: CGRect,
        density: CGFloat,
        scale: CGFloat
    ) -> NSImage? {
        guard let croppedImage = source.cropping(to: cropRect) else { return nil }

        let pixelWidth = croppedImage.width
        let pixelHeight = croppedImage.height
        let blockSize: Int
        if scale < 1 {
            let viewWidth = max(1, CGFloat(pixelWidth) * scale)
            let baseBlockSize = pixelBlockSize(for: density)
            let blocksAcross = max(1, Int(round(viewWidth / baseBlockSize)))
            blockSize = max(1, pixelWidth / blocksAcross)
        } else {
            blockSize = max(1, Int(round(pixelBlockSize(for: density) * scale)))
        }
        let smallWidth = max(1, pixelWidth / blockSize)
        let smallHeight = max(1, pixelHeight / blockSize)
        let colorSpace = croppedImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = croppedImage.bitmapInfo

        guard let downsampleContext = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: croppedImage.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        downsampleContext.interpolationQuality = .medium
        downsampleContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let output = downsampleContext.makeImage() else { return nil }

        return NSImage(cgImage: output, size: CGSize(width: smallWidth, height: smallHeight))
    }

    private static func makeBlurredImage(
        source: CGImage,
        cropRect: CGRect,
        density: CGFloat,
        scale: CGFloat
    ) -> NSImage? {
        let radius = blurRadius(for: density)
        let fullRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let paddedRect = cropRect
            .insetBy(dx: -ceil(radius * 2), dy: -ceil(radius * 2))
            .intersection(fullRect)
            .integral

        guard paddedRect.width >= 1,
              paddedRect.height >= 1,
              let croppedImage = source.cropping(to: paddedRect) else {
            return nil
        }

        let inputImage = CIImage(cgImage: croppedImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = inputImage.clampedToExtent()
        filter.radius = Float(radius)

        let outputRect = CGRect(
            x: cropRect.minX - paddedRect.minX,
            y: cropRect.minY - paddedRect.minY,
            width: cropRect.width,
            height: cropRect.height
        )

        guard let outputImage = filter.outputImage,
              let blurredImage = ciContext.createCGImage(outputImage, from: outputRect) else {
            return nil
        }

        return NSImage(cgImage: blurredImage, size: CGSize(width: blurredImage.width, height: blurredImage.height))
    }

    private static func pixelRect(for normalizedBounds: CGRect, in image: CGImage) -> CGRect? {
        let fullRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(
            x: normalizedBounds.minX * fullRect.width,
            y: normalizedBounds.minY * fullRect.height,
            width: normalizedBounds.width * fullRect.width,
            height: normalizedBounds.height * fullRect.height
        )
        let cropRect = rect.integral.intersection(fullRect)
        guard cropRect.width >= 1, cropRect.height >= 1 else { return nil }
        return cropRect
    }

    private static func redactionScale(sourceImage: CGImage, originalImageSize: CGSize) -> CGFloat {
        guard originalImageSize.width > 0, originalImageSize.height > 0 else { return 1 }

        let scaleX = CGFloat(sourceImage.width) / originalImageSize.width
        let scaleY = CGFloat(sourceImage.height) / originalImageSize.height
        let scale = (scaleX + scaleY) / 2
        return max(scale, 0.01)
    }

    static func pixelBlockSize(for density: CGFloat) -> CGFloat {
        let normalized = min(max(density, 0), 1)
        return 4 + normalized * 36
    }

    static func blurRadius(for density: CGFloat) -> CGFloat {
        let normalized = min(max(density, 0), 1)
        return 2 + normalized * 28
    }
}

private extension NSImage {
    func bestCGImage() -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    var pixelCost: Int {
        guard let image = bestCGImage() else { return 0 }
        return image.bytesPerRow * image.height
    }
}
