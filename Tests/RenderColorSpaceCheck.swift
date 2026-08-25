import AppKit

@main
enum RenderColorSpaceCheck {
    static let side = 64
    static let swatch = (red: CGFloat(0.82), green: CGFloat(0.21), blue: CGFloat(0.37))

    static func solidImage(colorSpace: CGColorSpace) -> CGImage {
        let isGray = colorSpace.numberOfComponents == 1
        let bitmapInfo = isGray
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        let components: [CGFloat] = isGray ? [swatch.green, 1] : [swatch.red, swatch.green, swatch.blue, 1]
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: components)!)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    static func centerPixel(of image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = (image.height / 2) * image.bytesPerRow + (image.width / 2) * bytesPerPixel
        let pixel = Array(data[offset..<(offset + bytesPerPixel)])

        let littleEndian = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
        let alphaFirst = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first || image.alphaInfo == .noneSkipFirst
        switch (bytesPerPixel, littleEndian, alphaFirst) {
        case (1, _, _): return pixel
        case (4, true, true): return [pixel[2], pixel[1], pixel[0]]
        case (4, false, true): return [pixel[1], pixel[2], pixel[3]]
        case (4, false, false): return [pixel[0], pixel[1], pixel[2]]
        default: preconditionFailure("unrecognised pixel layout: \(bytesPerPixel)B littleEndian=\(littleEndian) alphaFirst=\(alphaFirst)")
        }
    }

    static func flatConfig() -> BeautifierConfig {
        var config = BeautifierConfig()
        config.style = .none
        config.padding = 0
        config.cornerRadius = 0
        config.shadowStrength = 0
        return config
    }

    static func main() {
        let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

        let wide = solidImage(colorSpace: displayP3)
        let widePixel = centerPixel(of: wide)
        let wideRendered = BeautifierRenderer.render(image: wide, config: flatConfig())!

        precondition(
            wideRendered.colorSpace?.name == CGColorSpace.displayP3,
            "a Display P3 screenshot must stay Display P3, not land on an untagged device canvas"
        )
        precondition(
            centerPixel(of: wideRendered) == widePixel,
            "a wide-gamut screenshot must come back byte-identical: any conversion here is the washed-out colour report"
        )

        let narrow = solidImage(colorSpace: sRGB)
        let narrowPixel = centerPixel(of: narrow)
        let narrowRendered = BeautifierRenderer.render(image: narrow, config: flatConfig())!

        precondition(narrowRendered.colorSpace?.name == CGColorSpace.sRGB, "an sRGB screenshot must stay sRGB")
        precondition(centerPixel(of: narrowRendered) == narrowPixel, "an sRGB screenshot must not be pushed into a wider space either")

        let deviceCanvas = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        deviceCanvas.draw(wide, in: CGRect(x: 0, y: 0, width: side, height: side))
        precondition(
            centerPixel(of: deviceCanvas.makeImage()!) != widePixel,
            "sanity: the old device canvas really did move these pixels, so preserving the source space is what fixes it"
        )

        let gray = solidImage(colorSpace: CGColorSpaceCreateDeviceGray())
        precondition(gray.colorSpace?.model == .monochrome, "sanity: the fallback case needs a non-RGB source")
        let grayRendered = BeautifierRenderer.render(image: gray, config: flatConfig())!
        precondition(
            grayRendered.colorSpace?.name == CGColorSpace.sRGB,
            "a source we cannot follow must fall back to tagged sRGB, not to an unmanaged device space"
        )

        precondition(BeautifierRenderer.sRGB.name == CGColorSpace.sRGB, "the shared fallback space must be real sRGB")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("RenderColorSpaceCheck-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, wideRendered, nil)
        precondition(CGImageDestinationFinalize(destination), "the render must be writable as a PNG")

        let reloaded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(file as CFURL, nil)!, 0, nil)!
        precondition(
            reloaded.colorSpace?.name == CGColorSpace.displayP3,
            "the saved PNG must carry the Display P3 profile, or every viewer repaints it as sRGB and it looks washed out"
        )
        precondition(centerPixel(of: reloaded) == widePixel, "the saved PNG must hold the same pixels the render produced")

        print("RenderColorSpaceCheck: renders keep the screenshot's own gamut, and fall back to sRGB when they cannot")
    }
}
