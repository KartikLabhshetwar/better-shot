import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The displayed frame is also the export source; selecting never takes a second shot.
struct FrozenScreenFrame: Sendable {
    let displayID: CGDirectDisplayID
    let pointsRect: CGRect
    let image: CGImage

    nonisolated func croppedImage(in region: CGRect) throws -> CGImage {
        guard pointsRect.width > 0, pointsRect.height > 0,
              region.width > 0, region.height > 0, pointsRect.contains(region) else {
            throw NSError(domain: "BetterShot.FrozenScreenCapture", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The selected area is outside the captured display. Try capturing again."
            ])
        }
        let sx = CGFloat(image.width) / pointsRect.width
        let sy = CGFloat(image.height) / pointsRect.height
        let pixels = CGRect(
            x: (region.minX - pointsRect.minX) * sx,
            y: (region.minY - pointsRect.minY) * sy,
            width: region.width * sx,
            height: region.height * sy
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let cropped = image.cropping(to: pixels) else { throw CocoaError(.fileReadCorruptFile) }
        return cropped
    }

    nonisolated func writePNG(in region: CGRect, to url: URL) throws {
        let cropped = try croppedImage(in: region)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
