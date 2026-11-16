import AppKit
import ImageIO
import SwiftUI
@testable import BetterShot

@MainActor
func checkScreenshotComposition() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func source(_ color: NSColor, name: String, width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = directory.appendingPathComponent(name + ".png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return url
    }
    let red = try source(.red, name: "Window A", width: 800, height: 400)
    let blue = try source(.blue, name: "Window B", width: 400, height: 600)
    var defaults = AnnotationBackgroundSettings()
    defaults.style = .solid(.graphite)
    let model = ScreenshotCompositionModel(defaultLook: defaults)
    model.importImages([red, blue])
    precondition(model.document.screenshots.count == 2 && model.selection?.name == "Window B.png")
    precondition(model.document.screenshots[0].image.width == 800, "Original image resolution must survive import")
    let importedRevision = model.document.revision
    model.beginEditing()
    model.updateSelected { $0.shadow = 0.2 }
    model.updateSelected { $0.shadow = 0.7 }
    model.endEditing()
    model.undo()
    precondition(model.document.revision == importedRevision, "One drag must undo as one edit")
    model.redo()
    precondition(model.selection?.shadow == 0.7)
    for layout in ScreenshotCompositionLayout.allCases {
        model.change { $0.arrange(layout) }
        for item in model.document.screenshots {
            precondition(model.document.contentRect.contains(item.frame))
            let ratio = CGFloat(item.image.width) / CGFloat(item.image.height)
            precondition(abs(item.frame.width / item.frame.height - ratio) < 0.02)
        }
        precondition(!model.document.screenshots[0].frame.intersects(model.document.screenshots[1].frame),
                     "Automatic layouts must keep images separate")
    }
    model.resizeCanvas(CGSize(width: 400, height: 400))
    precondition(model.document.screenshots.allSatisfy { model.document.contentRect.contains($0.frame) })
    let selected = model.selectedID
    model.moveSelection(by: -1)
    precondition(model.document.screenshots.first?.id == selected)
    model.undo()
    precondition(model.document.screenshots.last?.id == selected)
    model.removeSelection(); precondition(model.document.screenshots.count == 1)
    model.undo(); precondition(model.document.screenshots.count == 2)
    model.importImages([directory.appendingPathComponent("missing.png")])
    precondition(model.errorMessage != nil && model.document.screenshots.count == 2)

    // Sample overlapping solid images to verify actual painter order, alpha,
    // rounded clipping and the top-left canvas to Core Graphics conversion.
    var document = model.document
    document.size = CGSize(width: 400, height: 400)
    document.background = .none
    document.screenshots[0].frame = CGRect(x: 40, y: 40, width: 200, height: 100)
    document.screenshots[1].frame = CGRect(x: 80, y: 80, width: 100, height: 150)
    for index in document.screenshots.indices { document.screenshots[index].shadow = 0; document.screenshots[index].cornerRadius = 0.2 }
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> NSColor {
        NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    }
    let image = try ScreenshotCompositionRenderer.render(document, scale: 1)
    precondition(pixel(image, 100, 100).blueComponent > 0.9, "Front screenshot must cover the rear screenshot")
    precondition(pixel(image, 60, 65).redComponent > 0.9, "Canvas must retain top-left coordinates")
    precondition(pixel(image, 40, 40).alphaComponent < 0.1, "Rounded corners must stay transparent")
    precondition(pixel(image, 399, 399).alphaComponent == 0)
    document.screenshots.swapAt(0, 1)
    let reordered = try ScreenshotCompositionRenderer.render(document, scale: 1)
    precondition(pixel(reordered, 100, 100).redComponent > 0.9)
    document.screenshots[0].shadow = 0.5
    let shadowed = try ScreenshotCompositionRenderer.render(document, scale: 1)
    precondition(pixel(shadowed, 185, 160).alphaComponent > 0, "Shadows must survive transparent export")
    precondition(pixel(shadowed, 110, 190).blueComponent > 0.9, "Shadow caster must not blacken image interiors")
    let output = directory.appendingPathComponent("combined.png")
    try ScreenshotCompositionRenderer.export(document, scale: 2, to: output)
    let saved = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
    precondition(saved.width == 800 && saved.height == 800)
    precondition(pixel(saved, 799, 799).alphaComponent == 0)
    do {
        _ = try ScreenshotCompositionRenderer.outputSize(document, scale: 100)
        preconditionFailure("Oversized exports must fail before allocating a bitmap")
    } catch { precondition(error.localizedDescription.contains("64 megapixels")) }
    model.markExported(model.document.revision)
    precondition(!model.hasUnexportedChanges)
    model.updateSelected { $0.shadow = 0.1 }
    precondition(model.hasUnexportedChanges)
    model.undo(); precondition(!model.hasUnexportedChanges)

    // Exercise the worst-density layout at both supported canvas extremes.
    model.importImages(Array(repeating: red, count: 24))
    precondition(model.document.screenshots.count == 24 && model.errorMessage != nil)
    for size in [CGSize(width: 400, height: 400), CGSize(width: 6000, height: 6000)] {
        model.resizeCanvas(size)
        model.change { $0.spacing = 300 }
        for layout in ScreenshotCompositionLayout.allCases {
            model.change { $0.arrange(layout) }
            precondition(model.document.screenshots.allSatisfy {
                $0.frame.width > 0 && $0.frame.height > 0 && model.document.contentRect.contains($0.frame)
            })
        }
    }
    // Compact and normal editor snapshots use disposable images and preferences.
    let preview = ScreenshotCompositionModel(defaultLook: defaults)
    preview.importImages([red, blue]); preview.change { $0.arrange(.row) }
    let snapshots = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/editor-snapshots")
    try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        for width: CGFloat in [980, 1280] {
            try snapshot(ScreenshotCompositionWindow(model: preview), scheme: scheme, width: width,
                to: snapshots.appendingPathComponent("composition-\(scheme)-\(Int(width)).png"), height: 780)
        }
    }
    print("PASS composition import, source resolution, undo, layouts, bounds, layer order, rounded alpha, shadows, 2x PNG, limits and compact light/dark snapshots")
}
