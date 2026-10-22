import CoreGraphics
import Foundation
import ImageIO

@main
enum FrozenScreenFrameCheck {
    static func main() throws {
        let width = 8, height = 6
        var bytes = [UInt8]()
        for y in 0..<height {
            for x in 0..<width { bytes += [UInt8(x * 20), UInt8(y * 30), 100, 255] }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!

        let frame = FrozenScreenFrame(displayID: 2, pointsRect: CGRect(x: -4, y: -3, width: 4, height: 3), image: image)
        let region = CGRect(x: -3, y: -2.5, width: 2, height: 1.5)
        let cropped = try frame.croppedImage(in: region)
        precondition(cropped.width == 4 && cropped.height == 3, "Retina dimensions must remain intact")
        let data = cropped.dataProvider!.data!
        let pixels = CFDataGetBytePtr(data)!
        for y in 0..<3 {
            for x in 0..<4 {
                let i = y * cropped.bytesPerRow + x * 4
                precondition(pixels[i] == UInt8((x + 2) * 20))
                precondition(pixels[i + 1] == UInt8((y + 1) * 30), "Crop must use a top-left pixel origin")
            }
        }
        let global = CGRect(x: -3, y: 101, width: 2, height: 1.5)
        precondition(RegionGeometry.pointsRect(global: global, primaryHeight: 100) == region)
        let full = try frame.croppedImage(in: frame.pointsRect)
        precondition(full.width == 8 && full.height == 6)
        let singleScale = FrozenScreenFrame(displayID: 3, pointsRect: CGRect(x: 100, y: 50, width: 8, height: 6), image: image)
        let singleCrop = try singleScale.croppedImage(in: CGRect(x: 102, y: 51, width: 4, height: 3))
        precondition(singleCrop.width == 4 && singleCrop.height == 3, "Each display must use its own scale")
        let fractional = try frame.croppedImage(in: CGRect(x: -3.9, y: -2.9, width: 0.3, height: 0.3))
        precondition(fractional.width == 1 && fractional.height == 1, "Fractional edges must cover whole source pixels")
        for invalid in [CGRect.zero, CGRect(x: -5, y: -3, width: 2, height: 2), CGRect(x: 0, y: 0, width: 1, height: 1)] {
            do {
                _ = try frame.croppedImage(in: invalid)
                fatalError("An empty or out-of-display crop must fail")
            } catch {}
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frozen-screen-check-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try frame.writePNG(in: region, to: url)
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let exported = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(exported.width == cropped.width && exported.height == cropped.height)
        precondition(rgba(exported) == rgba(cropped), "PNG must retain the frozen pixels regardless of decoded channel layout")
        print("FrozenScreenFrameCheck passed: display origins, 1x/2x crops, orientation, bounds, and lossless PNG pixels")
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
