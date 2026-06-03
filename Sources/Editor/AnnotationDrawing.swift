import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum AnnotationDrawing {

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func draw(_ items: [AnnotationItem], in ctx: CGContext, canvasSize: CGSize, sourceImage: CGImage?) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let hasRedaction = items.contains { $0.tool.isRedactionTool }
        let canvasSnapshot: CGImage? = hasRedaction ? ctx.makeImage() : nil

        for item in items {
            autoreleasepool {
                ctx.setStrokeColor(item.swatch.nsColor.cgColor)
                ctx.setFillColor(item.swatch.nsColor.cgColor)

                let lineWidth = renderedLineWidth(for: item, imageSize: canvasRect.size)
                ctx.setLineWidth(lineWidth)

                switch item.tool {
                case .select:
                    return

                case .rectangle:
                    ctx.stroke(renderedRect(item.bounds, in: canvasRect))

                case .filledRectangle:
                    let rect = renderedRect(item.bounds, in: canvasRect)
                    ctx.addPath(CGPath(
                        roundedRect: rect,
                        cornerWidth: AnnotationFilledRectangleMetrics.cornerRadius(for: rect),
                        cornerHeight: AnnotationFilledRectangleMetrics.cornerRadius(for: rect),
                        transform: nil
                    ))
                    ctx.fillPath()

                case .ellipse:
                    ctx.strokeEllipse(in: renderedRect(item.bounds, in: canvasRect))

                case .numberedCircle:
                    drawNumberedCircle(item, in: renderedRect(item.bounds, in: canvasRect), context: ctx)

                case .pixelate:
                    guard let canvasSnapshot else { return }
                    applyPixelation(
                        in: renderedRect(item.bounds, in: canvasRect),
                        canvasSnapshot: canvasSnapshot,
                        context: ctx,
                        canvasSize: canvasSize,
                        colorSpace: CGColorSpaceCreateDeviceRGB(),
                        density: item.redactionDensity
                    )

                case .blur:
                    guard let canvasSnapshot else { return }
                    applyBlur(
                        in: renderedRect(item.bounds, in: canvasRect),
                        canvasSnapshot: canvasSnapshot,
                        context: ctx,
                        canvasSize: canvasSize,
                        density: item.redactionDensity
                    )

                case .spotlight:
                    let targetRect = renderedRect(item.bounds, in: canvasRect)
                    let overlayColor = CGColor(gray: 0, alpha: item.redactionDensity)
                    ctx.saveGState()
                    let fullPath = CGMutablePath()
                    fullPath.addRect(canvasRect)
                    fullPath.addRect(targetRect)
                    ctx.addPath(fullPath)
                    ctx.setFillColor(overlayColor)
                    ctx.fillPath(using: .evenOdd)
                    ctx.restoreGState()

                case .text:
                    drawText(item, in: renderedRect(item.bounds, in: canvasRect), imageHeight: canvasRect.height, context: ctx)

                case .line:
                    guard let first = item.points.first,
                          let last = item.points.last else { return }
                    let start = renderedPoint(first, in: canvasRect)
                    let end = renderedPoint(last, in: canvasRect)
                    ctx.beginPath()
                    ctx.move(to: start)
                    ctx.addLine(to: end)
                    ctx.strokePath()

                case .freehand:
                    drawFreehand(points: item.points, imageRect: canvasRect, context: ctx)

                case .arrow:
                    guard let first = item.points.first,
                          let control = item.controlPoint,
                          let last = item.points.last,
                          let geometry = AnnotationArrowGeometry(
                            start: renderedPoint(first, in: canvasRect),
                            control: renderedPoint(control, in: canvasRect),
                            end: renderedPoint(last, in: canvasRect),
                            lineWidth: lineWidth
                          ) else { return }
                    ctx.beginPath()
                    ctx.move(to: renderedPoint(first, in: canvasRect))
                    ctx.addQuadCurve(to: geometry.tip, control: geometry.shaftControl)
                    ctx.strokePath()
                    drawArrowHead(geometry, context: ctx)
                }
            }
        }
    }

    private static func renderedRect(_ rect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + (1 - rect.maxY) * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    private static func renderedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + (1 - point.y) * imageRect.height
        )
    }

    private static func drawArrowHead(_ geometry: AnnotationArrowGeometry, context: CGContext) {
        context.beginPath()
        context.move(to: geometry.firstWing)
        context.addLine(to: geometry.tip)
        context.addLine(to: geometry.secondWing)
        context.strokePath()
    }

    private static func drawNumberedCircle(_ item: AnnotationItem, in rect: CGRect, context: CGContext) {
        let diameter = min(rect.width, rect.height)
        guard diameter > 1 else { return }

        let outlineWidth = AnnotationNumberedCircleMetrics.outlineWidth(for: diameter)
        context.saveGState()
        context.setFillColor(item.swatch.nsColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(item.swatch.numberedCircleOutlineNSColor.cgColor)
        context.setLineWidth(outlineWidth)
        context.strokeEllipse(in: rect.insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2))
        context.restoreGState()

        let fontSize = AnnotationNumberedCircleMetrics.fontSize(for: diameter, text: item.text)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.swatch.numberedCircleTextNSColor,
            .paragraphStyle: paragraphStyle
        ]
        let attributedText = NSAttributedString(string: item.text, attributes: attributes)
        let measuredRect = attributedText.boundingRect(
            with: CGSize(width: rect.width, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - measuredRect.height / 2 - fontSize * 0.04,
            width: rect.width,
            height: measuredRect.height + 2
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedText.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawFreehand(points: [CGPoint], imageRect: CGRect, context: CGContext) {
        let renderedPoints = points.map { renderedPoint($0, in: imageRect) }
        guard let first = renderedPoints.first else { return }

        context.beginPath()
        context.move(to: first)
        guard renderedPoints.count > 1 else { return }

        if renderedPoints.count == 2 {
            context.addLine(to: renderedPoints[1])
            context.strokePath()
            return
        }

        for index in 1..<renderedPoints.count {
            let previous = renderedPoints[index - 1]
            let current = renderedPoints[index]
            context.addQuadCurve(to: midpoint(previous, current), control: previous)
        }

        context.addLine(to: renderedPoints[renderedPoints.count - 1])
        context.strokePath()
    }

    private static func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }

    private static func drawText(_ item: AnnotationItem, in rect: CGRect, imageHeight: CGFloat, context: CGContext) {
        let text = item.text.trimmingCharacters(in: .newlines)
        guard !text.isEmpty, rect.width > 1, rect.height > 1 else { return }

        let fontSize = AnnotationTextMetrics.renderedFontSize(lineHeight: item.textLineHeight, imagePixelHeight: imageHeight)
        let font = item.resolvedFont(size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = item.textAlignment
        paragraphStyle.lineBreakMode = .byClipping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.swatch.nsColor,
            .paragraphStyle: paragraphStyle,
            .shadow: AnnotationTextMetrics.textShadow
        ]
        if item.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedText.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func applyPixelation(
        in rect: CGRect,
        canvasSnapshot: CGImage,
        context: CGContext,
        canvasSize: CGSize,
        colorSpace: CGColorSpace,
        density: CGFloat
    ) {
        let targetRect = rect.integral.intersection(CGRect(origin: .zero, size: canvasSize))
        guard targetRect.width >= 1,
              targetRect.height >= 1,
              let croppedImage = canvasSnapshot.cropping(to: imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height))) else {
            return
        }

        let pixelSize = RedactionImageProcessor.pixelBlockSize(for: density)
        let lowWidth = max(1, Int(targetRect.width / pixelSize))
        let lowHeight = max(1, Int(targetRect.height / pixelSize))

        guard let lowContext = CGContext(
            data: nil, width: lowWidth, height: lowHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        lowContext.interpolationQuality = .medium
        lowContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: lowWidth, height: lowHeight))
        guard let pixelatedImage = lowContext.makeImage() else { return }

        context.saveGState()
        context.clip(to: targetRect)
        context.interpolationQuality = .none
        context.draw(pixelatedImage, in: targetRect)
        context.restoreGState()
    }

    private static func applyBlur(
        in rect: CGRect,
        canvasSnapshot: CGImage,
        context: CGContext,
        canvasSize: CGSize,
        density: CGFloat
    ) {
        let targetRect = rect.integral.intersection(CGRect(origin: .zero, size: canvasSize))
        guard targetRect.width >= 1,
              targetRect.height >= 1,
              let croppedImage = canvasSnapshot.cropping(to: imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height))) else {
            return
        }

        let radius = RedactionImageProcessor.blurRadius(for: density)
        let fullImageRect = CGRect(x: 0, y: 0, width: canvasSnapshot.width, height: canvasSnapshot.height)
        let cropRectInImage = imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height))
        let paddedCropRect = cropRectInImage
            .insetBy(dx: -ceil(radius * 2), dy: -ceil(radius * 2))
            .intersection(fullImageRect)
            .integral

        let paddedImage: CGImage
        if let padded = canvasSnapshot.cropping(to: paddedCropRect) {
            paddedImage = padded
        } else {
            paddedImage = croppedImage
        }

        let inputImage = CIImage(cgImage: paddedImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = inputImage.clampedToExtent()
        filter.radius = Float(radius)

        let outputRect = CGRect(
            x: cropRectInImage.minX - paddedCropRect.minX,
            y: cropRectInImage.minY - paddedCropRect.minY,
            width: cropRectInImage.width,
            height: cropRectInImage.height
        )

        guard let outputImage = filter.outputImage,
              let blurredImage = ciContext.createCGImage(outputImage, from: outputRect) else {
            return
        }

        context.saveGState()
        context.clip(to: targetRect)
        context.draw(blurredImage, in: targetRect)
        context.restoreGState()
        ciContext.clearCaches()
    }

    private static func renderedLineWidth(for item: AnnotationItem, imageSize: CGSize) -> CGFloat {
        max(1.5, item.strokeWidth * max(imageSize.width, imageSize.height) / 900)
    }

    private static func imageCropRect(for contextRect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: contextRect.minX,
            y: imageHeight - contextRect.maxY,
            width: contextRect.width,
            height: contextRect.height
        ).integral
    }
}
