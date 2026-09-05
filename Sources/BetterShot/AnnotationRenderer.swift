//
//  AnnotationRenderer.swift
//  BetterShot
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AnnotationRenderer {
    /// Off-main variants: large exports (full-resolution compose + Core Image
    /// blur) are slow enough to beachball the UI, and the whole render graph
    /// is nonisolated, so hop to a background thread and await the result.
    static func renderInBackground(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings(),
        destinationURL: URL,
        contentType: UTType
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try render(
                sourceURL: sourceURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings,
                destinationURL: destinationURL,
                contentType: contentType
            )
        }.value
    }

    static func renderToTemporaryFileInBackground(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings()
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try renderToTemporaryFile(
                sourceURL: sourceURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings
            )
        }.value
    }

    nonisolated static func renderToTemporaryFile(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings()
    ) throws -> URL {
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BetterShot_Annotated_\(UUID().uuidString.prefix(6)).png")
        try render(
            sourceURL: sourceURL,
            shapes: shapes,
            backgroundSettings: backgroundSettings,
            destinationURL: destinationURL,
            contentType: .png
        )
        return destinationURL
    }

    nonisolated static func render(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings(),
        destinationURL: URL,
        contentType: UTType
    ) throws {
        // Encode beside the destination, then replace atomically. A failed
        // render must never remove the user's previous export.
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".BetterShot-\(UUID().uuidString).\(destinationURL.pathExtension)")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        if shapes.isEmpty, !backgroundSettings.hasRenderableContent,
           contentType == .png,
           let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
           CGImageSourceGetType(source) as String? == UTType.png.identifier {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
        } else {
            try autoreleasepool {
                let sourceImage = try loadSourceImage(sourceURL: sourceURL)
                // Keep the screenshot's own (typically Display P3) color space so
                // wide-gamut colors survive the export instead of being pulled
                // down to device RGB. Previews already render this way.
                let colorSpace = exportColorSpace(for: sourceImage)
                let renderedImage: CGImage
                if backgroundSettings.hasRenderableContent {
                    renderedImage = try AnnotationBackgroundRenderer.compose(
                        contentImage: sourceImage,
                        settings: backgroundSettings,
                        colorSpace: colorSpace,
                        foregroundOverlay: { context, layout, imageRect, imageClipPath in
                            drawAnnotations(
                                shapes,
                                in: imageRect,
                                pageSize: CGSize(width: sourceImage.width, height: sourceImage.height),
                                canvasSize: layout.canvasSize,
                                context: context,
                                colorSpace: colorSpace,
                                highlightClipPath: imageClipPath
                            )
                        },
                        canvasOverlay: { context, layout, _ in
                            AnnotationBackgroundRenderer.drawWatermark(
                                backgroundSettings.watermark,
                                in: CGRect(origin: .zero, size: layout.canvasSize),
                                context: context
                            )
                        }
                    )
                } else {
                    renderedImage = try renderAnnotatedImage(sourceImage, shapes: shapes, colorSpace: colorSpace)
                }

                guard let destination = CGImageDestinationCreateWithURL(
                    stagingURL as CFURL,
                    contentType.identifier as CFString,
                    1,
                    nil
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }

                var options: CFDictionary?
                if contentType != .png {
                    options = [
                        kCGImageDestinationLossyCompressionQuality: BetterShotPreferences.compressionQuality
                    ] as CFDictionary
                }

                CGImageDestinationAddImage(destination, renderedImage, options)

                guard CGImageDestinationFinalize(destination) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    nonisolated private static func loadSourceImage(sourceURL: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
              let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return cgImage
    }

    nonisolated private static func exportColorSpace(for image: CGImage) -> CGColorSpace {
        // Fall back to device RGB unless the source space can actually back
        // the 8-bit premultiplied contexts the render pipeline creates -
        // otherwise an exotic embedded profile would fail the whole export.
        guard let colorSpace = image.colorSpace,
              colorSpace.model == .rgb,
              CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) != nil else {
            return CGColorSpaceCreateDeviceRGB()
        }
        return colorSpace
    }

    nonisolated private static func renderAnnotatedImage(
        _ cgImage: CGImage,
        shapes: [AnnoShape],
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        guard !shapes.isEmpty else { return cgImage }
        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: fullRect)
        drawAnnotations(
            shapes,
            in: fullRect,
            pageSize: fullRect.size,
            canvasSize: fullRect.size,
            context: context,
            colorSpace: colorSpace,
            highlightClipPath: nil
        )

        guard let renderedImage = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        return renderedImage
    }

    /// Draw the annotations over an already-composed context.
    ///
    /// `imageRect` is where the screenshot sits in the context; page space is the screenshot's own
    /// pixel space, so the transform between them is the only thing that differs from the canvas.
    nonisolated static func drawAnnotations(
        _ shapes: [AnnoShape],
        in imageRect: CGRect,
        pageSize: CGSize,
        canvasSize: CGSize,
        context: CGContext,
        colorSpace: CGColorSpace,
        highlightClipPath: CGPath?
    ) {
        guard !shapes.isEmpty else { return }

        let document = AnnoDocument()
        document.restore(AnnoDocument.Snapshot(shapes: shapes, bindings: []))

        // Page space is the screenshot's own pixels; `imageRect` is where those pixels ended up in
        // this context, which is smaller than page space whenever the render is downscaled (the
        // settled scene preview does exactly that).
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let scale = imageRect.width / pageSize.width

        // Page space is y-down from the image's top-left; the bitmap is y-up. One reflecting
        // transform carries the whole engine across, rather than flipping the context globally and
        // having to un-flip every image and glyph run inside it.
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: -scale,
            tx: imageRect.minX, ty: imageRect.maxY
        )

        let target = AnnoShapeDrawing.Target(
            transform: transform,
            pageSize: pageSize,
            sample: { rect in
                // Snapshot what has been composed so far, so a blur picks up the background behind
                // a transparent screenshot as well as the screenshot itself.
                guard let snapshot = context.makeImage() else { return nil }
                let flipped = CGRect(
                    x: rect.minX,
                    y: CGFloat(snapshot.height) - rect.maxY,
                    width: rect.width,
                    height: rect.height
                ).integral.intersection(
                    CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
                )
                guard flipped.width >= 1, flipped.height >= 1 else { return nil }
                return snapshot.cropping(to: flipped)
            },
            spotlightClip: highlightClipPath,
            isFlippedContext: false
        )

        _ = canvasSize
        AnnoShapeDrawing.draw(document, in: context, target: target)
    }
}
