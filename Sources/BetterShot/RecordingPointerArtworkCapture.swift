//
//  RecordingPointerArtworkCapture.swift
//  BetterShot
//
//  Converts AppKit-provided cursor images into the recording sidecar format.
//  Captured and editor-selected artwork share one format for preview and export.
//

import AppKit
import Foundation

@MainActor
enum PointerArtworkCapture {
    private static var styledCache: [RecordingCursorAppearance: PointerArtwork] = [:]

    static func styledArtwork(_ appearance: RecordingCursorAppearance) -> PointerArtwork? {
        guard appearance != .recorded else { return nil }
        if let cached = styledCache[appearance] { return cached }
        if appearance == .macOS || appearance == .hand {
            let artwork = capture(appearance == .macOS ? NSCursor.arrow : NSCursor.pointingHand,
                                  id: "bettershot-cursor-" + appearance.rawValue)
            if let artwork { styledCache[appearance] = artwork }
            return artwork
        }
        let isDot = appearance == .dot
        let size = NSSize(width: 32, height: 40)
        // Keep logical size / hotspot independent of raster resolution. At 32×,
        // even a 4× cursor in a 4K export is drawn down from this vector master.
        let rasterScale: CGFloat = 32
        guard let context = CGContext(data: nil,
            width: Int(size.width * rasterScale), height: Int(size.height * rasterScale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * rasterScale)
        context.scaleBy(x: rasterScale, y: -rasterScale)
        let path = CGMutablePath()
        if isDot {
            path.addEllipse(in: CGRect(x: 5, y: 9, width: 22, height: 22))
        } else {
            path.move(to: CGPoint(x: 5, y: 4))
            for point in [CGPoint(x: 26, y: 23), CGPoint(x: 17, y: 24),
                          CGPoint(x: 22, y: 34), CGPoint(x: 17, y: 36),
                          CGPoint(x: 12, y: 26), CGPoint(x: 5, y: 32)] {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        context.setFillColor(CGColor(gray: appearance == .dark ? 0 : 1, alpha: 1))
        context.setStrokeColor(CGColor(gray: appearance == .dark ? 1 : 0, alpha: 1))
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        context.addPath(path)
        context.drawPath(using: .fillStroke)
        guard let image = context.makeImage() else { return nil }
        let artwork = encode(image, size: size,
            hotSpot: isDot ? CGPoint(x: 16, y: 20) : CGPoint(x: 5, y: 4),
            id: "bettershot-cursor-" + appearance.rawValue)
        if let artwork { styledCache[appearance] = artwork }
        return artwork
    }

    static func defaultArtwork() -> PointerArtwork? {
        capture(NSCursor.arrow, id: "pointer-default")
    }

    static func capture(_ cursor: NSCursor, id: String) -> PointerArtwork? {
        let image = cursor.image
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep.imageReps(with: tiffData)
                .compactMap({ $0 as? NSBitmapImageRep })
                .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
              let cgImage = bitmap.cgImage else { return nil }

        let imageSize = image.size
        let width = imageSize.width.isFinite && imageSize.width > 0
            ? imageSize.width
            : CGFloat(bitmap.pixelsWide)
        let height = imageSize.height.isFinite && imageSize.height > 0
            ? imageSize.height
            : CGFloat(bitmap.pixelsHigh)
        guard width > 0, height > 0 else { return nil }

        return encode(cgImage, size: CGSize(width: width, height: height), hotSpot: cursor.hotSpot, id: id)
    }

    private static func encode(_ image: CGImage, size: CGSize, hotSpot: CGPoint, id: String) -> PointerArtwork? {
        guard let imageData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              !imageData.isEmpty else { return nil }
        let width = size.width
        let height = size.height
        return PointerArtwork(
            artworkID: id,
            imageData: imageData,
            anchorPoint: PointerArtwork.Point(
                x: min(max(hotSpot.x.isFinite ? hotSpot.x : 0, 0), width),
                y: min(max(hotSpot.y.isFinite ? hotSpot.y : 0, 0), height)
            ),
            referenceSize: PointerArtwork.Size(
                width: width,
                height: height
            )
        )
    }
}
