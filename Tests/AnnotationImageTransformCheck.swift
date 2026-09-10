import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct AnnotationImageTransformCheck {
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let data = CFDataGetBytePtr(image.dataProvider!.data!)!
        let offset = y * image.bytesPerRow + x * 4
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }

    static func main() throws {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(data: nil, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<4 {
            for x in 0..<6 {
                context.setFillColor(CGColor(colorSpace: colorSpace,
                    components: [CGFloat(x + 1) / 8, CGFloat(y + 1) / 8, 0.5, 1])!)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let source = context.makeImage()!
        let size = CGSize(width: source.width, height: source.height)
        var rotation = AnnotationImageTransform.identity
        for turns in 0..<4 {
            for transform in [rotation, rotation.flippedHorizontally()] {
                let image = try transform.render(source)
                precondition(image.colorSpace?.name == colorSpace.name)
                precondition(CGSize(width: image.width, height: image.height) == transform.displaySize(for: size))
                let affine = transform.affineTransform(for: size)
                for y in 0..<source.height {
                    for x in 0..<source.width {
                        let center = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                        let destination = center.applying(affine)
                        precondition(pixel(source, x, y) == pixel(image, Int(destination.x), Int(destination.y)),
                            "The transformed image must preserve each source pixel")
                        let restored = destination.applying(affine.inverted())
                        precondition(restored == center)
                    }
                }
                let horizontal = try transform.flippedHorizontally().render(source)
                let vertical = try transform.flippedVertically().render(source)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        precondition(pixel(image, x, y) == pixel(horizontal, image.width - 1 - x, y))
                        precondition(pixel(image, x, y) == pixel(vertical, x, image.height - 1 - y))
                    }
                }
                precondition(transform.flippedHorizontally().flippedHorizontally() == transform)
                precondition(transform.flippedVertically().flippedVertically() == transform)
            }
            if turns == 1 {
                let clockwise = try rotation.render(source)
                precondition(pixel(source, 0, 0) == pixel(clockwise, 3, 0))
                precondition(pixel(source, 5, 3) == pixel(clockwise, 0, 5))
            }
            rotation = rotation.rotatedClockwise()
        }
        precondition(rotation == .identity)
        let restoredImage = try rotation.render(source)
        precondition(restoredImage === source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var temporaryURLs: [URL] = []
        defer {
            for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appendingPathComponent("source.png")
        let destination = CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, source, nil)
        precondition(CGImageDestinationFinalize(destination))
        let originalData = try Data(contentsOf: sourceURL)
        var currentURL = sourceURL
        for index in 0..<4 {
            let result = try AnnotationImageTransform.identity.rotatedClockwise().apply(to: currentURL)
            temporaryURLs.append(result.url)
            precondition(result.pixelSize == (index.isMultiple(of: 2) ? CGSize(width: 4, height: 6) : size))
            currentURL = result.url
        }
        let restoredSource = CGImageSourceCreateWithURL(currentURL as CFURL, nil)!
        let restoredPixels = CGImageSourceCreateImageAtIndex(restoredSource, 0, nil)!
        let rgba = CGContext(data: nil, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rgba.draw(restoredPixels, in: CGRect(origin: .zero, size: size))
        let normalizedPixels = rgba.makeImage()!
        for y in 0..<4 {
            for x in 0..<6 { precondition(pixel(source, x, y) == pixel(normalizedPixels, x, y)) }
        }
        let transformed = try AnnotationImageTransform.identity.rotatedClockwise().apply(to: sourceURL)
        temporaryURLs.append(transformed.url)
        let cropped = AnnotationImageCropper.crop(url: transformed.url,
            normalizedRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5))!
        temporaryURLs.append(cropped.url)
        precondition(cropped.pixelSize == CGSize(width: 2, height: 3))
        let croppedSource = CGImageSourceCreateWithURL(cropped.url as CFURL, nil)!
        let cropPixels = CGImageSourceCreateImageAtIndex(croppedSource, 0, nil)!
        let cropContext = CGContext(data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cropContext.draw(cropPixels, in: CGRect(x: 0, y: 0, width: 2, height: 3))
        let normalizedCrop = cropContext.makeImage()!
        let expectedTransform = try AnnotationImageTransform.identity.rotatedClockwise().render(source)
        for y in 0..<3 {
            for x in 0..<2 { precondition(pixel(normalizedCrop, x, y) == pixel(expectedTransform, x + 1, y)) }
        }
        let unchangedSource = try Data(contentsOf: sourceURL)
        precondition(unchangedSource == originalData)
        print("PASS PNG bake, four rotations, crop after rotation, source preservation")
        print("PASS eight orientations, clockwise direction, horizontal/vertical flips, inverse coordinates, native pixels, Display P3")
    }
}
