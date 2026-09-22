import AppKit
import UniformTypeIdentifiers

/// An image file or image data on the pasteboard, as a file the editor can open.
enum ClipboardImage {
    /// Returns nil when the pasteboard holds no image. Throws when the image can't be written to disk.
    static func fileURL(from pasteboard: NSPasteboard = .general,
                        in directory: URL = FileManager.default.temporaryDirectory) throws -> URL? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // Keep the source encoding; TIFF is only the fallback most apps add alongside it.
        guard let item = pasteboard.pasteboardItems?.first else { return nil }
        let images = item.types.filter { UTType($0.rawValue)?.conforms(to: .image) == true }
        guard let type = images.first(where: { $0 != .tiff }) ?? images.first,
              let contentType = UTType(type.rawValue),
              var data = item.data(forType: type) else { return nil }
        var ext = contentType.preferredFilenameExtension ?? "png"
        if type == .tiff {
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
            data = png
            ext = "png"
        }
        let url = ScreenshotFileNaming.scratchURL("Clipboard", extension: ext, in: directory)
        try data.write(to: url, options: .atomic)
        return url
    }
}
