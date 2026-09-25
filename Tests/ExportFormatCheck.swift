import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Settings > General > File Format drives every screenshot save. A format the
/// picker offers but ImageIO cannot encode makes every capture and editor Save
/// fail, so pin that each offered format actually encodes, and that a stored
/// value for a removed format falls back to lossless PNG.
@main @MainActor
enum ExportFormatCheck {
    static func main() {
        // AppPreferences reads UserDefaults.standard. A bare test executable has
        // no bundle identifier, so this is the check's own domain, never the app's.
        guard Bundle.main.bundleIdentifier == nil else {
            fatalError("refusing to touch a bundled app's defaults")
        }

        checkEveryOfferedFormatEncodes()
        checkStoredWebPFallsBackToPNG()

        print("export format: \(ExportFormat.allCases.count) formats encode, stale values fall back to PNG")
    }

    private static func checkEveryOfferedFormatEncodes() {
        let pixels = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        pixels.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        pixels.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = pixels.makeImage()!

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportFormatCheck-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("capture.\(format.fileExtension)")
            // The same call CaptureOrchestrator.saveImage makes.
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format.utType as CFString, 1, nil
            ) else {
                fatalError("\(format.rawValue): ImageIO has no encoder for \(format.utType)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            assert(CGImageDestinationFinalize(destination), "\(format.rawValue): encoding failed")

            // Editor Save picks the encoder from the export's file extension.
            let byExtension = UTType(filenameExtension: format.fileExtension)
            assert(
                byExtension.map { $0.conforms(to: UTType(format.utType)!) } == true,
                "\(format.rawValue): .\(format.fileExtension) does not map back to \(format.utType)"
            )
        }
    }

    private static func checkStoredWebPFallsBackToPNG() {
        let key = "bs_exportFormat"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("webp", forKey: key)
        assert(AppPreferences.exportFormat == .png, "a stored WebP choice resolves to PNG")

        UserDefaults.standard.set("jpeg", forKey: key)
        assert(AppPreferences.exportFormat == .jpeg, "a valid stored choice is kept")

        UserDefaults.standard.removeObject(forKey: key)
        assert(AppPreferences.exportFormat == .png, "no stored choice is PNG")
    }
}
