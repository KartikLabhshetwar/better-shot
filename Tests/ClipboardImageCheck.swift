import AppKit
import UniformTypeIdentifiers

@main
enum ClipboardImageCheck {
    @MainActor static func main() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardImageCheck-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A private pasteboard; the check must never touch the user's clipboard.
        let pasteboard = NSPasteboard(name: .init("ClipboardImageCheck-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        func read() -> URL? { try! ClipboardImage.fileURL(from: pasteboard, in: dir) { "pasted.\($0)" } }

        let source = pngImage(width: 7, height: 5)
        let tiff = NSBitmapImageRep(data: source)!.tiffRepresentation!

        // MARK: - PNG alongside TIFF keeps the original PNG bytes

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        item.setData(source, forType: .png)
        pasteboard.writeObjects([item])
        let fromPNG = read()
        assert(fromPNG?.pathExtension == "png", "PNG data should stay PNG, got \(String(describing: fromPNG))")
        assert(fromPNG.flatMap { try? Data(contentsOf: $0) } == source, "PNG bytes must not be re-encoded")
        assert(fromPNG?.lastPathComponent == "pasted.png", "pasted image data takes the given name, got \(String(describing: fromPNG))")
        assert(read()?.lastPathComponent == "pasted-1.png", "a second paste with the same name must not overwrite the first")

        // MARK: - TIFF-only clipboards become lossless PNG

        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)
        let fromTIFF = read()
        let rep = fromTIFF.flatMap { NSBitmapImageRep(data: try! Data(contentsOf: $0)) }
        assert(fromTIFF?.pathExtension == "png", "TIFF-only data should be written as PNG")
        assert(rep?.pixelsWide == 7 && rep?.pixelsHigh == 5 && rep?.hasAlpha == true, "TIFF conversion must keep size and alpha")

        // MARK: - JPEG data keeps its bytes

        pasteboard.clearContents()
        let jpeg = NSBitmapImageRep(data: source)!.representation(using: .jpeg, properties: [:])!
        pasteboard.setData(jpeg, forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier))
        assert(read().flatMap { try? Data(contentsOf: $0) } == jpeg, "JPEG bytes must not be re-encoded")

        // MARK: - Copied image files open in place

        let file = dir.appendingPathComponent("copied.png")
        try! source.write(to: file)
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        assert(read()?.standardizedFileURL == file.standardizedFileURL, "a copied image file should be returned as-is")

        // MARK: - A deleted file reference falls back to the image data

        pasteboard.clearContents()
        let stale = NSPasteboardItem()
        stale.setString(dir.appendingPathComponent("deleted.png").absoluteString, forType: .fileURL)
        stale.setData(source, forType: .png)
        pasteboard.writeObjects([stale])
        assert(read().flatMap { try? Data(contentsOf: $0) } == source, "a missing file should fall back to pasteboard data")

        // MARK: - No image means nil, not an error

        pasteboard.clearContents()
        pasteboard.setString("not an image", forType: .string)
        assert(read() == nil, "text is not an image")
        let text = dir.appendingPathComponent("notes.txt")
        try! "notes".write(to: text, atomically: true, encoding: .utf8)
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSURL])
        assert(read() == nil, "a non-image file is not an image")
        pasteboard.clearContents()
        assert(read() == nil, "an empty pasteboard is not an image")

        // MARK: - A failed write throws instead of looking like an empty clipboard

        pasteboard.clearContents()
        pasteboard.setData(source, forType: .png)
        let unwritable = file.appendingPathComponent("inside-a-file")
        assert((try? ClipboardImage.fileURL(from: pasteboard, in: unwritable) { "x.\($0)" }) == nil,
               "write failure must not return a URL")
        var threw = false
        do { _ = try ClipboardImage.fileURL(from: pasteboard, in: unwritable) { "x.\($0)" } } catch { threw = true }
        assert(threw, "write failure must throw")

        print("ClipboardImageCheck: PNG/JPEG bytes kept, TIFF to PNG, file references, fallbacks, and write failures verified")
    }

    static func pngImage(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.setColor(NSColor(red: 1, green: 0, blue: 0, alpha: 0.5), atX: 1, y: 1)
        return rep.representation(using: .png, properties: [:])!
    }
}
