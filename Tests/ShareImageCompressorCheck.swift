import CoreGraphics
import Foundation
import ImageIO

@main
enum ShareImageCompressorCheck {
    static func main() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImageCompressorCheck-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // MARK: - Oversized renders are downscaled to the share cap

        let huge = solidImage(width: 5120, height: 2880)
        let scaled = ShareImageCompressor.downscaled(huge)
        assert(scaled != nil, "an image past the cap must be downscaled")
        assert(scaled!.width == ShareImageCompressor.maxLongEdge, "long edge should land on the cap, got \(scaled!.width)")
        assert(scaled!.height == 1440, "aspect ratio must survive the downscale, got \(scaled!.height)")

        // MARK: - Images already under the cap are left alone

        let small = solidImage(width: 800, height: 600)
        assert(ShareImageCompressor.downscaled(small) == nil, "an image under the cap must not be resampled")

        // MARK: - Transparent renders stay lossless

        let transparent = try! ShareImageCompressor.write(huge, named: "alpha", keepingAlpha: true, into: dir)
        assert(transparent.pathExtension == "png", "transparent shares must stay PNG, got .\(transparent.pathExtension)")

        // MARK: - Opaque renders keep whichever codec came out smaller

        let flat = try! ShareImageCompressor.write(huge, named: "flat", keepingAlpha: false, into: dir)
        let photo = try! ShareImageCompressor.write(noiseImage(width: 3200, height: 2000), named: "photo", keepingAlpha: false, into: dir)
        assert(flat.pathExtension == "png", "flat UI compresses smaller as PNG, got .\(flat.pathExtension)")
        assert(photo.pathExtension == "jpg", "photographic content compresses smaller as JPEG, got .\(photo.pathExtension)")

        // MARK: - The losing encode is not left behind in the staging directory

        let staged = try! FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        assert(staged == ["alpha.png", "flat.png", "photo.jpg"], "only the winning encodes should survive, got \(staged)")

        // MARK: - Compression sheds an order of magnitude off the raw render

        let uncompressed = 5120 * 2880 * 4
        let flatBytes = ShareImageCompressor.byteCount(flat)
        assert(flatBytes < uncompressed / 10, "compression should shed an order of magnitude, got \(flatBytes)")

        // MARK: - The written file really carries the downscaled pixels

        let source = CGImageSourceCreateWithURL(flat as CFURL, nil)!
        let readBack = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        assert(readBack.width == ShareImageCompressor.maxLongEdge, "written file should carry the downscaled width")

        print("ShareImageCompressor: \(uncompressed / 1024)KB raw -> \(flatBytes / 1024)KB flat, \(ShareImageCompressor.byteCount(photo) / 1024)KB photo")
    }

    /// Fine noise defeats PNG the way a wallpaper background does, so the codec race has a case that JPEG must win.
    static func noiseImage(width: Int, height: Int) -> CGImage {
        let context = makeContext(width: width, height: height)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let v = Double((seed >> 33) % 255) / 255
                context.setFillColor(CGColor(red: v, green: 1 - v, blue: v * 0.5, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        return context.makeImage()!
    }

    static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
    }

    /// Flat bands with hard edges stand in for app chrome, which is what most captures actually are.
    static func solidImage(width: Int, height: Int) -> CGImage {
        let context = makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 0, to: width, by: 17) {
            context.setFillColor(CGColor(
                red: Double(i % 255) / 255, green: 0.7, blue: Double((i * 3) % 255) / 255, alpha: 1
            ))
            context.fill(CGRect(x: i, y: 0, width: 9, height: height))
        }
        return context.makeImage()!
    }
}
