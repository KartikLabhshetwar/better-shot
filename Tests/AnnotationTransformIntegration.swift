import AppKit
import Foundation

#if canImport(BetterShot)
@testable import BetterShot
#endif

struct AnnotationTransformIntegration {
    @MainActor final class Canvas: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor static func checkEditor() throws {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        let editor = AnnoEditor()
        var imageTransform = AnnotationImageTransform.identity
        let original = AnnoShape(x: 20, y: 30, kind: .geo(GeoProps()))
        editor.markUndo()
        editor.document.add(original)
        editor.markImageUndo(undo: { imageTransform = .identity }, redo: { imageTransform = .identity.rotatedClockwise() })
        imageTransform = .identity.rotatedClockwise()
        editor.selectedIds = [original.id]
        editor.nudgeSelected(dx: 10, dy: 0)
        editor.undo()
        precondition(editor.document.shape(original.id)?.x == 20 && imageTransform.quarterTurns == 1)
        editor.undo()
        precondition(editor.document.shape(original.id) == original && imageTransform == .identity)
        editor.undo()
        precondition(editor.shapes.isEmpty && !editor.canUndo)
        editor.redo()
        editor.redo()
        editor.redo()
        precondition(editor.document.shape(original.id)?.x == 30 && imageTransform.quarterTurns == 1)
        editor.undo()
        editor.undo()
        editor.selectedIds = [original.id]
        editor.nudgeSelected(dx: 0, dy: 4)
        precondition(!editor.canRedo && imageTransform == .identity)

        let sourceSize = CGSize(width: 600, height: 400)
        let canvas = Canvas(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        var props = TextProps()
        props.text = "Rotation and mirror"
        props.fontSize = 30
        var text = AnnoShape(x: 100, y: 80, kind: .text(props))
        text.rotation = 0.2
        editor.replaceDocument(shapes: [text])
        let overlay = AnnoTextEditorOverlay(editor: editor, shapeId: text.id)
        canvas.addSubview(overlay)
        overlay.loadText()
        var rotation = AnnotationImageTransform.identity
        for _ in 0..<4 {
            for transform in [rotation, rotation.flippedHorizontally()] {
                let displaySize = transform.displaySize(for: sourceSize)
                let transformedText = text.applyingImageTransform(transform, imageSize: sourceSize)
                editor.replaceDocument(shapes: [transformedText])
                editor.viewport = AnnoViewport(
                    imageFrame: CGRect(x: 50, y: 60, width: displaySize.width / 2, height: displaySize.height / 2),
                    imageSize: displaySize
                )
                precondition(editor.viewport.scale == 0.5)
                let pagePoint = transformedText.pageTransform.applyToPoint(Vec(20, 10))
                let screenPoint = editor.pageToScreen(pagePoint)
                let restored = editor.screenToPage(screenPoint)
                precondition(abs(restored.x - pagePoint.x) < 0.0001 && abs(restored.y - pagePoint.y) < 0.0001)
                precondition(editor.hitShape(at: restored)?.id == text.id)
                let data = try JSONEncoder().encode(transformedText)
                let restoredText = try JSONDecoder().decode(AnnoShape.self, from: data)
                precondition(restoredText == transformedText)
                overlay.sync()
                let fullTransform = text.pageTransform.cgAffineTransform
                    .concatenating(transform.affineTransform(for: sourceSize))
                    .concatenating(editor.viewport.pageToView)
                for point in [CGPoint.zero, CGPoint(x: 30, y: 0), CGPoint(x: 0, y: 12)] {
                    let expected = point.applying(fullTransform)
                    let actual = overlay.convert(CGPoint(x: point.x * 0.5, y: point.y * 0.5), to: canvas)
                    precondition(hypot(expected.x - actual.x, expected.y - actual.y) < 0.001,
                        "Native text input must follow the same rotation/reflection as the rendered glyphs")
                }
            }
            rotation = rotation.rotatedClockwise()
        }
        for kind in [AnnoShapeKind.geo(GeoProps()), .draw(DrawProps()), .arrow(ArrowProps()),
                     .text(props), .redaction(RedactionProps()), .highlight(HighlightProps()), .numbered(NumberedProps())] {
            let original = AnnoShape(x: 35, y: 48, rotation: 0.35, kind: kind)
            var orientation = AnnotationImageTransform.identity
            for _ in 0..<4 {
                for transform in [orientation, orientation.flippedHorizontally()] {
                    let remapped = original.applyingImageTransform(transform, imageSize: sourceSize)
                    precondition(remapped.kind == original.kind)
                    for point in [Vec(0, 0), Vec(15, 5), Vec(80, 30)] {
                        let expected = original.pageTransform.applyToPoint(point).cgPoint
                            .applying(transform.affineTransform(for: sourceSize))
                        let actual = remapped.pageTransform.applyToPoint(point)
                        precondition(hypot(actual.x - expected.x, actual.y - expected.y) < 0.0001)
                    }
                }
                orientation = orientation.rotatedClockwise()
            }
        }
        let boundShape = AnnoShape(x: 150, y: 60, kind: .geo(GeoProps()))
        let arrow = AnnoShape(x: 20, y: 30, kind: .arrow(ArrowProps()))
        let binding = ArrowBinding(arrowId: arrow.id, toId: boundShape.id, terminal: .end,
            normalizedAnchor: Vec(0.4, 0.6), isPrecise: true, isExact: true)
        editor.replaceDocument(shapes: [boundShape, arrow], bindings: [binding])
        let originalTerminal = editor.document.arrowInfo(arrow.id)!.end.handle
        let transform = AnnotationImageTransform.identity.rotatedClockwise().flippedHorizontally()
        let remappedArrow = arrow.applyingImageTransform(transform, imageSize: sourceSize)
        editor.replaceDocument(shapes: [boundShape.applyingImageTransform(transform, imageSize: sourceSize), remappedArrow],
            bindings: [binding])
        let terminal = editor.document.arrowInfo(arrow.id)!.end.handle
        precondition(Vec.dist(originalTerminal, terminal) < 0.0001)
        precondition(editor.document.bindings == [binding])
        let legacyData = try JSONEncoder().encode(text)
        let legacyText = try JSONDecoder().decode(AnnoShape.self, from: legacyData)
        precondition(legacyText.isMirrored == nil && legacyText.pageTransform == text.pageTransform)
        print("PASS chronological image/annotation undo-redo, redo invalidation, viewport inversion, hit testing, native text transforms, all shape kinds, arrow bindings, and shape persistence")
    }

#if canImport(BetterShot)
    @MainActor static func checkModel(sourceURL: URL) throws {
        let model = AnnotationEditorModel()
        model.sourceURL = sourceURL
        model.baseImageURL = sourceURL
        model.imageSize = ScreenshotImageLoader.imageSize(at: sourceURL)!
        model.previewImage = ScreenshotImageLoader.fullResolutionImage(at: sourceURL)
        model.backgroundSettings = AnnotationBackgroundSettings()
        model.markSaved()
        defer { model.releaseEditorResources() }
        let originalData = try Data(contentsOf: sourceURL)
        let originalSize = model.imageSize
        model.rotateClockwise()
        precondition(model.imageSize == CGSize(width: originalSize.height, height: originalSize.width))
        precondition(model.isTransformed && !model.hasAnnotations && model.hasUnsavedChanges)
        precondition(model.baseImageURL != sourceURL && model.previewCGImage != nil)
        model.undo()
        precondition(!model.isTransformed && model.imageSize == originalSize && !model.hasUnsavedChanges)
        model.redo()
        let rotatedURL = model.baseImageURL!
        let rotatedSize = model.imageSize
        model.beginCropping()
        model.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        model.applyCrop()
        precondition(model.isCropped && model.imageSize.width < rotatedSize.width)
        model.flipHorizontally()
        model.undo()
        precondition(model.isCropped)
        model.undo()
        precondition(!model.isCropped && model.baseImageURL == rotatedURL && model.imageSize == rotatedSize)
        model.undo()
        precondition(!model.isTransformed && model.imageSize == originalSize && !model.hasUnsavedChanges)
        model.redo()
        var props = TextProps()
        props.text = "Saved reflection"
        let shape = AnnoShape(x: 150, y: 80, kind: .text(props))
        model.engine.markUndo()
        model.engine.document.add(shape)
        model.flipVertically()
        let renderedURL = try AnnotationRenderer.renderToTemporaryFile(sourceURL: model.baseImageURL!,
            shapes: model.shapes, backgroundSettings: model.backgroundSettings)
        defer { try? FileManager.default.removeItem(at: renderedURL) }
        let document = AnnotationDocument(shapes: model.shapes, bindings: model.bindings,
            background: model.backgroundSettings)
        let historyURL = ScreenshotHistoryStore.shared.commitAnnotations(displayURL: sourceURL,
            baseURL: model.baseImageURL!, renderedURL: renderedURL, document: document)
        let reopened = ScreenshotHistoryStore.shared.loadEditDocument(for: historyURL)!
        precondition(reopened.shapes == model.shapes && reopened.shapes.first?.isMirrored == true)
        let baseURL = ScreenshotHistoryStore.baseImageURL(for: historyURL)
        precondition(ScreenshotImageLoader.imageSize(at: baseURL) == model.imageSize)
        let rerenderedURL = try AnnotationRenderer.renderToTemporaryFile(sourceURL: baseURL,
            shapes: reopened.shapes, backgroundSettings: reopened.backgroundSettings)
        defer { try? FileManager.default.removeItem(at: rerenderedURL) }
        let firstRender = try Data(contentsOf: renderedURL)
        let secondRender = try Data(contentsOf: rerenderedURL)
        precondition(firstRender == secondRender)
        let sourceAfter = try Data(contentsOf: sourceURL)
        precondition(sourceAfter == originalData)
        print("PASS transform-only edits, preview dimensions, crop/transform undo-redo, saved base PNG, sidecar shapes, and reopen rendering")
    }
#endif
}
