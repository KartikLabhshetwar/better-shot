import CoreGraphics
import CoreImage
import AppKit

enum AnnotationRenderer {

    static func draw(_ items: [AnnotationItem], in ctx: CGContext, imageRect: CGRect, sourceImage: CGImage?) {
        for item in items {
            ctx.saveGState()
            draw(item, in: ctx, imageRect: imageRect, sourceImage: sourceImage)
            ctx.restoreGState()
        }
    }

    private static func draw(_ item: AnnotationItem, in ctx: CGContext, imageRect: CGRect, sourceImage: CGImage?) {
        let color = item.swatch.cgColor
        let lineWidth = item.strokeWidth

        let rect = CGRect(
            x: imageRect.minX + item.rect.origin.x * imageRect.width,
            y: imageRect.minY + (1 - item.rect.origin.y - item.rect.height) * imageRect.height,
            width: item.rect.width * imageRect.width,
            height: item.rect.height * imageRect.height
        )

        switch item.tool {
        case .rectangle:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.stroke(rect)

        case .filledRect:
            ctx.setFillColor(CGColor(srgbRed: item.swatch.red, green: item.swatch.green, blue: item.swatch.blue, alpha: 0.7))
            let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

        case .ellipse:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: rect)

        case .line:
            guard item.points.count >= 2 else { return }
            let p0 = denormalize(item.points[0], in: imageRect)
            let p1 = denormalize(item.points[1], in: imageRect)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()

        case .arrow:
            guard item.points.count >= 2 else { return }
            let p0 = denormalize(item.points[0], in: imageRect)
            let p1 = denormalize(item.points[1], in: imageRect)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()

            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let headLength: CGFloat = lineWidth * 4
            let headAngle: CGFloat = .pi / 6
            let left = CGPoint(
                x: p1.x - headLength * cos(angle - headAngle),
                y: p1.y - headLength * sin(angle - headAngle)
            )
            let right = CGPoint(
                x: p1.x - headLength * cos(angle + headAngle),
                y: p1.y - headLength * sin(angle + headAngle)
            )
            ctx.move(to: left)
            ctx.addLine(to: p1)
            ctx.addLine(to: right)
            ctx.strokePath()

        case .freehand:
            guard item.points.count >= 2 else { return }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let pts = item.points.map { denormalize($0, in: imageRect) }
            ctx.move(to: pts[0])
            for i in 1..<pts.count {
                if i < pts.count - 1 {
                    let mid = CGPoint(x: (pts[i].x + pts[i+1].x) / 2, y: (pts[i].y + pts[i+1].y) / 2)
                    ctx.addQuadCurve(to: mid, control: pts[i])
                } else {
                    ctx.addLine(to: pts[i])
                }
            }
            ctx.strokePath()

        case .numberedBadge:
            let size = max(rect.width, rect.height, 26)
            let badgeRect = CGRect(
                x: rect.midX - size / 2,
                y: rect.midY - size / 2,
                width: size,
                height: size
            )
            ctx.setFillColor(color)
            ctx.fillEllipse(in: badgeRect)

            let text = "\(item.badgeNumber)" as NSString
            let font = NSFont.boldSystemFont(ofSize: size * 0.55)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            text.draw(in: textRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .text:
            let text = item.text as NSString
            let font = item.isBold
                ? NSFont.boldSystemFont(ofSize: item.fontSize)
                : NSFont.systemFont(ofSize: item.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(cgColor: color) ?? .red,
            ]

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            text.draw(in: rect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .pixelate:
            drawPixelate(in: ctx, rect: rect, sourceImage: sourceImage, density: item.redactionDensity)

        case .blur:
            drawBlur(in: ctx, rect: rect, sourceImage: sourceImage)

        case .select:
            break
        }
    }

    // MARK: - Pixelate

    private static func drawPixelate(in ctx: CGContext, rect: CGRect, sourceImage: CGImage?, density: CGFloat) {
        guard let sourceImage else { return }

        let cropRect = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: rect.height
        )

        guard let cropped = sourceImage.cropping(to: cropRect) else { return }

        let blockSize = max(2, Int(density))
        let smallW = max(1, Int(rect.width) / blockSize)
        let smallH = max(1, Int(rect.height) / blockSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let smallCtx = CGContext(
            data: nil, width: smallW, height: smallH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        smallCtx.interpolationQuality = .none
        smallCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let pixelated = smallCtx.makeImage() else { return }

        ctx.interpolationQuality = .none
        ctx.draw(pixelated, in: rect)
        ctx.interpolationQuality = .default
    }

    // MARK: - Blur

    private static func drawBlur(in ctx: CGContext, rect: CGRect, sourceImage: CGImage?) {
        guard let sourceImage else { return }

        let cropRect = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: rect.height
        )

        guard let cropped = sourceImage.cropping(to: cropRect) else { return }

        let ciImage = CIImage(cgImage: cropped)
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(12.0, forKey: kCIInputRadiusKey)

        let ciCtx = CIContext(options: nil)
        guard let output = filter.outputImage,
              let blurred = ciCtx.createCGImage(output, from: ciImage.extent) else { return }

        ctx.draw(blurred, in: rect)
    }

    // MARK: - Helpers

    private static func denormalize(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + (1 - point.y) * imageRect.height
        )
    }
}
