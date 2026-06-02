import CoreGraphics
import CoreImage
import AppKit

enum AnnotationDrawing {

    static func draw(_ items: [AnnotationItem], in ctx: CGContext, canvasSize: CGSize, sourceImage: CGImage?) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        for item in items {
            ctx.saveGState()
            drawItem(item, in: ctx, canvasRect: canvasRect, sourceImage: sourceImage)
            ctx.restoreGState()
        }
    }

    private static func drawItem(_ item: AnnotationItem, in ctx: CGContext, canvasRect: CGRect, sourceImage: CGImage?) {
        let color = item.swatch.cgColor
        let lw = item.strokeWidth

        let rect = denormRect(item.rect, in: canvasRect)

        switch item.tool {
        case .rectangle:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.stroke(rect)

        case .filledRect:
            ctx.setFillColor(CGColor(srgbRed: item.swatch.red, green: item.swatch.green, blue: item.swatch.blue, alpha: 0.7))
            let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

        case .ellipse:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: rect)

        case .line:
            guard item.points.count >= 2 else { return }
            let p0 = denormPoint(item.points[0], in: canvasRect)
            let p1 = denormPoint(item.points[1], in: canvasRect)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()

        case .arrow:
            guard item.points.count >= 2 else { return }
            let p0 = denormPoint(item.points[0], in: canvasRect)
            let p1 = denormPoint(item.points[1], in: canvasRect)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()

            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let hl: CGFloat = lw * 3.5
            let ha: CGFloat = .pi / 6
            ctx.move(to: CGPoint(x: p1.x - hl * cos(angle - ha), y: p1.y - hl * sin(angle - ha)))
            ctx.addLine(to: p1)
            ctx.addLine(to: CGPoint(x: p1.x - hl * cos(angle + ha), y: p1.y - hl * sin(angle + ha)))
            ctx.strokePath()

        case .freehand:
            guard item.points.count >= 2 else { return }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let pts = item.points.map { denormPoint($0, in: canvasRect) }
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
            let size = max(rect.width, rect.height, 24)
            let badgeRect = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: badgeRect)

            let text = "\(item.badgeNumber)" as NSString
            let font = NSFont.boldSystemFont(ofSize: size * 0.5)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2,
                width: textSize.width, height: textSize.height
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            text.draw(in: textRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .text:
            let text = item.text as NSString
            let font = item.isBold ? NSFont.boldSystemFont(ofSize: item.fontSize) : NSFont.systemFont(ofSize: item.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .red]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            text.draw(in: rect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .pixelate:
            guard let sourceImage else { return }
            let pixelRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height
            )
            guard pixelRect.width > 0, pixelRect.height > 0,
                  let cropped = sourceImage.cropping(to: pixelRect) else { return }
            let blockSize = max(2, Int(item.redactionDensity))
            let smallW = max(1, Int(pixelRect.width) / blockSize)
            let smallH = max(1, Int(pixelRect.height) / blockSize)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let smallCtx = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            smallCtx.interpolationQuality = .none
            smallCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
            guard let pixelated = smallCtx.makeImage() else { return }
            ctx.interpolationQuality = .none
            ctx.draw(pixelated, in: pixelRect)
            ctx.interpolationQuality = .default

        case .blur:
            guard let sourceImage else { return }
            let pixelRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height
            )
            guard pixelRect.width > 0, pixelRect.height > 0,
                  let cropped = sourceImage.cropping(to: pixelRect) else { return }
            let ciImage = CIImage(cgImage: cropped)
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(12.0, forKey: kCIInputRadiusKey)
            let ciCtx = CIContext()
            guard let output = filter.outputImage, let blurred = ciCtx.createCGImage(output, from: ciImage.extent) else { return }
            ctx.draw(blurred, in: pixelRect)

        case .select:
            break
        }
    }

    // All coordinates are stored normalized (0..1). Convert to pixel coords.
    private static func denormPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + (1 - point.y) * rect.height
        )
    }

    private static func denormRect(_ normalized: CGRect, in canvas: CGRect) -> CGRect {
        CGRect(
            x: canvas.minX + normalized.origin.x * canvas.width,
            y: canvas.minY + (1 - normalized.origin.y - normalized.height) * canvas.height,
            width: normalized.width * canvas.width,
            height: normalized.height * canvas.height
        )
    }
}
