import CoreGraphics
import AppKit

/// Draws annotation items onto a CGContext at full pixel resolution.
enum AnnotationDrawing {
    static func draw(_ item: AnnotationItem, in ctx: CGContext, imageRect: CGRect) {
        let w = imageRect.width
        let h = imageRect.height
        let ox = imageRect.origin.x
        let oy = imageRect.origin.y

        // Convert normalized rect to pixel rect (CG coordinates: Y-up)
        let pixelRect = CGRect(
            x: ox + item.rect.origin.x * w,
            y: oy + (1 - item.rect.origin.y - item.rect.height) * h,
            width: item.rect.width * w,
            height: item.rect.height * h
        )

        let lineWidth = item.strokeWidth * max(w, h) / 900

        ctx.saveGState()

        switch item.tool {
        case .select:
            break

        case .rectangle:
            ctx.setStrokeColor(item.swatch.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.stroke(pixelRect)

        case .filledRect:
            ctx.setFillColor(item.swatch.cgColor)
            let radius = min(pixelRect.width, pixelRect.height) * 0.08
            let path = CGPath(roundedRect: pixelRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

        case .ellipse:
            ctx.setStrokeColor(item.swatch.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: pixelRect)

        case .line:
            guard item.points.count >= 2 else { break }
            let p1 = pixelPoint(item.points[0], w: w, h: h, ox: ox, oy: oy)
            let p2 = pixelPoint(item.points[1], w: w, h: h, ox: ox, oy: oy)
            ctx.setStrokeColor(item.swatch.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()

        case .arrow:
            guard item.points.count >= 2 else { break }
            let start = pixelPoint(item.points[0], w: w, h: h, ox: ox, oy: oy)
            let end = pixelPoint(item.points[1], w: w, h: h, ox: ox, oy: oy)
            let control = item.points.count > 2
                ? pixelPoint(item.points[2], w: w, h: h, ox: ox, oy: oy)
                : CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

            ctx.setStrokeColor(item.swatch.cgColor)
            ctx.setFillColor(item.swatch.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Shaft
            ctx.move(to: start)
            ctx.addQuadCurve(to: end, control: control)
            ctx.strokePath()

            // Arrowhead
            let headLength = lineWidth * 4
            let angle = atan2(end.y - control.y, end.x - control.x)
            let wing1 = CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            )
            let wing2 = CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            )

            ctx.move(to: end)
            ctx.addLine(to: wing1)
            ctx.move(to: end)
            ctx.addLine(to: wing2)
            ctx.strokePath()

        case .freehand:
            guard item.points.count >= 2 else { break }
            ctx.setStrokeColor(item.swatch.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let pts = item.points.map { pixelPoint($0, w: w, h: h, ox: ox, oy: oy) }
            ctx.move(to: pts[0])

            // Smooth with midpoint quadratic curves
            for i in 1..<pts.count {
                let mid = CGPoint(x: (pts[i-1].x + pts[i].x) / 2, y: (pts[i-1].y + pts[i].y) / 2)
                ctx.addQuadCurve(to: mid, control: pts[i-1])
            }
            ctx.addLine(to: pts.last!)
            ctx.strokePath()

        case .numberedBadge:
            let radius = min(pixelRect.width, pixelRect.height) / 2
            let center = CGPoint(x: pixelRect.midX, y: pixelRect.midY)

            ctx.setFillColor(item.swatch.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

            // Draw number text
            let text = "\(item.badgeNumber)" as NSString
            let fontSize = radius * 1.1
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )

            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            text.draw(in: textRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .pixelate:
            guard let sourceImage = ctx.makeImage() else { break }
            let density = max(0.05, item.redactionDensity)
            let blockSize = max(2, Int(min(pixelRect.width, pixelRect.height) * (1 - density) * 0.15) + 2)

            guard let cropped = sourceImage.cropping(to: pixelRect) else { break }
            let smallW = max(1, Int(pixelRect.width) / blockSize)
            let smallH = max(1, Int(pixelRect.height) / blockSize)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let smallCtx = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { break }
            smallCtx.interpolationQuality = .none
            smallCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))

            guard let smallImage = smallCtx.makeImage() else { break }
            ctx.interpolationQuality = .none
            ctx.draw(smallImage, in: pixelRect)
            ctx.interpolationQuality = .high

        case .blur:
            // Simplified: draw a semi-transparent overlay as a stand-in
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.4 * item.redactionDensity))
            ctx.fill(pixelRect)

        case .text:
            let text = item.text as NSString
            guard !text.isEqual(to: "") else { break }

            var font = NSFont(name: item.fontName, size: item.fontSize * max(w, h) / 900) ?? NSFont.systemFont(ofSize: item.fontSize * max(w, h) / 900)
            if item.isBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if item.isItalic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(cgColor: item.swatch.cgColor) ?? .white,
            ]
            if item.isUnderline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            text.draw(in: pixelRect, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }

        ctx.restoreGState()
    }

    private static func pixelPoint(_ normalized: CGPoint, w: CGFloat, h: CGFloat, ox: CGFloat, oy: CGFloat) -> CGPoint {
        CGPoint(x: ox + normalized.x * w, y: oy + (1 - normalized.y) * h)
    }
}
