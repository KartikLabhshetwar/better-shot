import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import BetterShot

@MainActor
func checkImageTransforms(imageURL: URL) throws {
    func require(_ condition: Bool, _ message: String = "Image transform check failed") {
        precondition(condition, message)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var temporary: [URL] = []
    defer { for url in temporary { try? FileManager.default.removeItem(at: url) } }
    let sourceURL = directory.appendingPathComponent("pixels.png")
    let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Unique opaque and translucent pixels expose direction, resampling, and alpha errors.
    for y in 0..<3 { for x in 0..<4 {
        context.setFillColor(CGColor(red: CGFloat(x) / 3, green: CGFloat(y) / 2,
                                     blue: 0.5, alpha: x == 0 ? 0.5 : 1))
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
    } }
    let destination = CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    require(CGImageDestinationFinalize(destination))
    let original = try Data(contentsOf: sourceURL)
    let originalBitmap = NSBitmapImageRep(data: original)!
    func assertPixel(_ a: NSColor, _ b: NSColor) {
        let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
        require(abs(a.redComponent - b.redComponent) < 0.009
            && abs(a.greenComponent - b.greenComponent) < 0.009
            && abs(a.blueComponent - b.blueComponent) < 0.009
            && abs(a.alphaComponent - b.alphaComponent) < 0.001, "Transform must retain pixels and alpha")
    }
    for operation in AnnotationImageTransform.allCases {
        require(NSImage(systemSymbolName: operation.systemImage, accessibilityDescription: nil) != nil)
        let result = operation.apply(to: sourceURL)!
        temporary.append(result.url)
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: result.url))!
        require(bitmap.colorSpace.iccProfileData == originalBitmap.colorSpace.iccProfileData,
                     "Preserve the source color profile")
        for y in 0..<3 { for x in 0..<4 {
            let target: (Int, Int)
            switch operation {
            case .rotateLeft: target = (y, 3 - x)
            case .rotateRight: target = (2 - y, x)
            case .flipHorizontal: target = (3 - x, y)
            case .flipVertical: target = (x, 2 - y)
            }
            assertPixel(originalBitmap.colorAt(x: x, y: y)!, bitmap.colorAt(x: target.0, y: target.1)!)
        } }
        var cycled = result.url
        for _ in 1..<(operation == .rotateLeft || operation == .rotateRight ? 4 : 2) {
            cycled = operation.apply(to: cycled)!.url
            temporary.append(cycled)
        }
        let restored = NSBitmapImageRep(data: try Data(contentsOf: cycled))!
        require(restored.pixelsWide == 4 && restored.pixelsHigh == 3)
        for y in 0..<3 { for x in 0..<4 {
            assertPixel(originalBitmap.colorAt(x: x, y: y)!, restored.colorAt(x: x, y: y)!)
        } }
    }
    require(try Data(contentsOf: sourceURL) == original)

    let kinds: [AnnoShapeKind] = [.geo(GeoProps()), .arrow(ArrowProps(bend: 20)),
        .draw(DrawProps(points: [Vec(1, 2), Vec(40, 60)])), .text(TextProps(text: "Abc")),
        .redaction(RedactionProps()), .highlight(HighlightProps()), .numbered(NumberedProps())]
    let size = CGSize(width: 1920, height: 1080)
    for kind in kinds {
        var shape = AnnoShape(x: 70, y: 130, rotation: 0.37, kind: kind)
        let legacyData = try JSONEncoder().encode(shape)
        require(!String(decoding: legacyData, as: UTF8.self).contains("mirrored"))
        require(try JSONDecoder().decode(AnnoShape.self, from: legacyData).isMirrored == false)
        for operation in AnnotationImageTransform.allCases + AnnotationImageTransform.allCases {
            let transformed = operation.applying(to: shape, imageSize: size)
            for point in [Vec(0, 0), Vec(17, 35), Vec(-8, 100)] {
                let expected = operation.matrix(for: size).applyToPoint(shape.pageTransform.applyToPoint(point))
                let actual = transformed.pageTransform.applyToPoint(point)
                require(abs(expected.x - actual.x) < 0.000001 && abs(expected.y - actual.y) < 0.000001,
                             "Every annotation's complete geometry must follow the source pixels")
            }
            require(try JSONDecoder().decode(AnnoShape.self, from: JSONEncoder().encode(transformed)) == transformed)
            shape = transformed
        }
    }

    // Bound arrow anchors must follow the same reflection as their target shape.
    let target = AnnoShape(x: 300, y: 400, kind: .geo(GeoProps()))
    let arrow = AnnoShape(x: 20, y: 30, kind: .arrow(ArrowProps()))
    let binding = ArrowBinding(arrowId: arrow.id, toId: target.id, terminal: .end,
                               normalizedAnchor: Vec(0.25, 0.75), isPrecise: true, isExact: true)
    let bound = AnnoDocument()
    bound.restore(AnnoDocument.Snapshot(shapes: [target, arrow], bindings: [binding]))
    for operation in AnnotationImageTransform.allCases {
        let transformed = AnnoDocument()
        transformed.restore(AnnoDocument.Snapshot(
            shapes: bound.shapes.map { operation.applying(to: $0, imageSize: size) }, bindings: [binding]))
        let expected = operation.matrix(for: size).applyToPoint(
            arrow.pageTransform.applyToPoint(bound.arrowInfo(arrow.id)!.end.point))
        let actual = transformed.shape(arrow.id)!.pageTransform.applyToPoint(
            transformed.arrowInfo(arrow.id)!.end.point)
        require(abs(expected.x - actual.x) < 0.000001 && abs(expected.y - actual.y) < 0.000001)
    }

    let model = AnnotationEditorModel()
    defer { model.releaseEditorResources() }
    model.load(url: imageURL)
    let originalSize = model.imageSize
    let sourceBytes = try Data(contentsOf: imageURL)
    model.backgroundSettings.style = .none
    model.markSaved()
    let first = AnnoShape(x: 60, y: 90, kind: .geo(GeoProps()))
    func add(_ shape: AnnoShape) {
        model.engine.markUndo()
        model.engine.document.add(shape)
        model.engine.notifyChanged()
    }
    add(first)
    model.transformImage(.rotateRight)
    let rotated = model.shapes
    require(model.imageSize == CGSize(width: originalSize.height, height: originalSize.width))
    let second = AnnoShape(x: 120, y: 200, kind: .text(TextProps(text: "Editable")))
    add(second)
    let beforeCrop = model.shapes
    model.beginCropping()
    model.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    model.applyCrop()
    let cropped = model.shapes, croppedSize = model.imageSize
    model.transformImage(.flipHorizontal)
    let final = model.shapes
    model.undo(); require(model.shapes == cropped && model.imageSize == croppedSize)
    model.undo(); require(model.shapes == beforeCrop)
    model.undo(); require(model.shapes == rotated)
    model.undo(); require(model.shapes == [first] && model.imageSize == originalSize)
    model.undo(); require(model.shapes.isEmpty && !model.hasUnsavedChanges && !model.canUndo)
    for _ in 0..<5 { model.redo() }
    require(model.shapes == final && model.imageSize == croppedSize && !model.canRedo)
    require(try Data(contentsOf: imageURL) == sourceBytes, "Editing never mutates the original capture")

    // Commit through the production renderer/history store, then reopen through the real model.
    let rendered = directory.appendingPathComponent("export.png")
    try AnnotationRenderer.render(sourceURL: model.baseImageURL!, shapes: model.shapes,
        backgroundSettings: model.backgroundSettings, destinationURL: rendered, contentType: .png)
    let saved = ScreenshotHistoryStore.shared.commitAnnotations(displayURL: imageURL,
        baseURL: model.baseImageURL!, renderedURL: rendered,
        document: AnnotationDocument(shapes: model.shapes, bindings: model.bindings, background: model.backgroundSettings))
    let reopened = AnnotationEditorModel()
    defer { reopened.releaseEditorResources() }
    reopened.load(url: saved)
    require(reopened.shapes == final && reopened.imageSize == croppedSize && !reopened.hasUnsavedChanges)
    require(reopened.backgroundSettings == model.backgroundSettings)
    let reopenedExport = directory.appendingPathComponent("reopened.png")
    try AnnotationRenderer.render(sourceURL: reopened.baseImageURL!, shapes: reopened.shapes,
        backgroundSettings: reopened.backgroundSettings, destinationURL: reopenedExport, contentType: .png)
    require(try Data(contentsOf: rendered) == Data(contentsOf: reopenedExport))
    model.baseImageURL = reopened.baseImageURL
    model.markSaved()
    model.undo(); require(model.hasUnsavedChanges && model.hasImageEdits)
    model.redo(); require(!model.hasUnsavedChanges, "Undo/redo across Save retains the clean baseline")
    model.undo()
    add(AnnoShape(x: 0, y: 0, kind: .geo(GeoProps())))
    require(!model.canRedo, "Drawing after undo discards the old image redo branch")
    model.undo()
    model.transformImage(.rotateLeft)
    model.undo()
    require(!model.engine.canRedo, "A new transform discards abandoned annotation redo")

    // A plain image with no annotations/background must still save its transformed pixels.
    let plain = AnnotationEditorModel()
    defer { plain.releaseEditorResources() }
    plain.load(url: sourceURL)
    plain.backgroundSettings.style = .none
    plain.transformImage(.rotateRight)
    require(plain.hasImageEdits && plain.shapes.isEmpty)
    let plainExport = directory.appendingPathComponent("plain.png")
    try AnnotationRenderer.render(sourceURL: plain.baseImageURL!, shapes: [],
        backgroundSettings: plain.backgroundSettings, destinationURL: plainExport, contentType: .png)
    require(try Data(contentsOf: plainExport) == Data(contentsOf: plain.baseImageURL!))
    print("PASS image rotate/flip pixels, alpha/profile, annotation geometry, legacy decoding, mixed crop/draw history, save/reopen, and branching")
}
