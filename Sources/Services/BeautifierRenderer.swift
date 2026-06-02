import CoreGraphics
import AppKit

/// Renders a screenshot with background, padding, shadow, alignment, and corner radii.
enum BeautifierRenderer {

    /// Compose a screenshot onto a beautified background canvas.
    static func render(
        image: CGImage,
        config: BeautifierConfig,
        annotations: ((CGContext, CGRect) -> Void)? = nil
    ) -> CGImage? {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let shortEdge = min(imgW, imgH)

        // Compute padding in pixels (config.padding is fractional 0…0.5)
        let pad = shortEdge * config.padding

        // Canvas size before aspect ratio
        var canvasW = imgW + pad * 2
        var canvasH = imgH + pad * 2

        // Apply forced aspect ratio
        if let ratio = config.aspectRatio.numericValue {
            let current = canvasW / canvasH
            if current < ratio {
                canvasW = canvasH * ratio
            } else {
                canvasH = canvasW / ratio
            }
        }

        // Alignment: compute image origin within canvas
        let totalHPad = canvasW - imgW
        let totalVPad = canvasH - imgH
        let imgX = config.alignment.xFactor * totalHPad
        let imgY = config.alignment.yFactor * totalVPad

        // Corner radii (fractional -> pixels, zeroed on stuck edges)
        let baseRadius = config.cornerRadius * shortEdge
        let m = config.alignment.cornerMultipliers
        let radii = PerCornerRadii(
            topLeft: baseRadius * m.tl,
            topRight: baseRadius * m.tr,
            bottomRight: baseRadius * m.br,
            bottomLeft: baseRadius * m.bl
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: Int(canvasW),
            height: Int(canvasH),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvasRect = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)

        // 1. Draw background
        drawBackground(in: ctx, rect: canvasRect, style: config.style, colorSpace: colorSpace)

        // 2. Draw shadow
        let imageRect = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
        if config.shadowStrength > 0 {
            drawShadow(in: ctx, rect: imageRect, radii: radii, strength: config.shadowStrength, shortEdge: shortEdge)
        }

        // 3. Clip and draw image with per-corner radii
        ctx.saveGState()
        let clipPath = radii.path(in: imageRect)
        ctx.addPath(clipPath)
        ctx.clip()
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()

        // 4. Draw annotations on top of the image
        if let annotations {
            ctx.saveGState()
            annotations(ctx, imageRect)
            ctx.restoreGState()
        }

        return ctx.makeImage()
    }

    // MARK: - Background Drawing

    private static func drawBackground(
        in ctx: CGContext,
        rect: CGRect,
        style: BackgroundStyle,
        colorSpace: CGColorSpace
    ) {
        switch style {
        case .none:
            break

        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)

        case .gradient(let preset):
            guard let gradient = preset.cgGradient(in: colorSpace) else { return }
            let start = CGPoint(
                x: rect.origin.x + preset.startPoint.x * rect.width,
                y: rect.origin.y + (1 - preset.startPoint.y) * rect.height
            )
            let end = CGPoint(
                x: rect.origin.x + preset.endPoint.x * rect.width,
                y: rect.origin.y + (1 - preset.endPoint.y) * rect.height
            )
            ctx.drawLinearGradient(
                gradient,
                start: start, end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )

        case .wallpaper(let source):
            guard let wallpaperImage = loadImage(at: source.path) else { return }
            ctx.draw(wallpaperImage, in: rect)

        case .bundledImage(let assetID):
            guard let asset = BundledBackgrounds.asset(byID: assetID),
                  let url = asset.url,
                  let bgImage = loadImage(at: url.path) else { return }
            ctx.draw(bgImage, in: rect)
        }
    }

    // MARK: - Shadow

    private static func drawShadow(
        in ctx: CGContext,
        rect: CGRect,
        radii: PerCornerRadii,
        strength: CGFloat,
        shortEdge: CGFloat
    ) {
        let blurRadius = max(2, shortEdge * (0.035 + strength * 0.035))
        let yOffset = -shortEdge * (0.012 + strength * 0.018)
        let alpha = strength * 0.36

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: yOffset),
            blur: blurRadius,
            color: CGColor(gray: 0, alpha: alpha)
        )

        // Draw an opaque shape to cast the shadow (will be drawn over by the image)
        let path = radii.path(in: rect)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Clear the filled shape so only the shadow remains
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.clear(rect)
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func loadImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Per-Corner Radii

struct PerCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        // Start at top-left, move clockwise (in CG coordinates: bottom-left visually)
        path.move(to: CGPoint(x: minX + topLeft, y: maxY))

        // Top edge -> top-right corner
        path.addLine(to: CGPoint(x: maxX - topRight, y: maxY))
        if topRight > 0 {
            path.addArc(center: CGPoint(x: maxX - topRight, y: maxY - topRight),
                        radius: topRight, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        }

        // Right edge -> bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: minY + bottomRight))
        if bottomRight > 0 {
            path.addArc(center: CGPoint(x: maxX - bottomRight, y: minY + bottomRight),
                        radius: bottomRight, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        }

        // Bottom edge -> bottom-left corner
        path.addLine(to: CGPoint(x: minX + bottomLeft, y: minY))
        if bottomLeft > 0 {
            path.addArc(center: CGPoint(x: minX + bottomLeft, y: minY + bottomLeft),
                        radius: bottomLeft, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
        }

        // Left edge -> top-left corner
        path.addLine(to: CGPoint(x: minX, y: maxY - topLeft))
        if topLeft > 0 {
            path.addArc(center: CGPoint(x: minX + topLeft, y: maxY - topLeft),
                        radius: topLeft, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        }

        path.closeSubpath()
        return path
    }
}
