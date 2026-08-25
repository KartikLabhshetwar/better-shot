import AppKit
import SwiftUI

/// The annotation layer: one `NSView` that draws every shape and the selection chrome.
///
/// It is a pure renderer. Pointer input still arrives through `AnnotationCanvas`'s existing
/// gesture, which already unprojects the camera transform and owns zoom and pan - so the engine
/// gets clean page-space points without this view having to re-implement any of that.
///
/// Ported in spirit from the drawing-app's `UI/CanvasView.swift`, minus the parts that belong to
/// BetterShot's chrome (grid, background, its own camera).
struct AnnoCanvasLayer: NSViewRepresentable {
    let editor: AnnoEditor
    let sourceImage: CGImage?
    let imageFrame: CGRect
    let imageSize: CGSize
    let spotlightClip: CGPath?
    /// Bumped by the model on every change, so SwiftUI knows to push a redraw through.
    let revision: Int

    func makeNSView(context: Context) -> AnnoCanvasNSView {
        let view = AnnoCanvasNSView()
        view.configure(
            editor: editor,
            sourceImage: sourceImage,
            imageFrame: imageFrame,
            imageSize: imageSize,
            spotlightClip: spotlightClip
        )
        return view
    }

    func updateNSView(_ view: AnnoCanvasNSView, context: Context) {
        view.configure(
            editor: editor,
            sourceImage: sourceImage,
            imageFrame: imageFrame,
            imageSize: imageSize,
            spotlightClip: spotlightClip
        )
    }
}

@MainActor
final class AnnoCanvasNSView: NSView {
    private var editor: AnnoEditor?
    private var sourceImage: CGImage?
    private var imageFrame: CGRect = .zero
    private var imageSize: CGSize = .zero
    private var spotlightClip: CGPath?

    private var textOverlay: AnnoTextEditorOverlay?

    /// Page space is y-down, like the image and like the engine.
    override var isFlipped: Bool { true }

    /// Transparent to the pointer except where the text caret is: the drag gesture that drives the
    /// engine lives in SwiftUI, and it only fires if this view declines the event.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let textOverlay else { return nil }
        return textOverlay.frame.contains(convert(point, from: superview)) ? textOverlay : nil
    }

    func configure(
        editor: AnnoEditor,
        sourceImage: CGImage?,
        imageFrame: CGRect,
        imageSize: CGSize,
        spotlightClip: CGPath?
    ) {
        if self.editor !== editor {
            self.editor = editor
            editor.onEditingTextChanged = { [weak self] id in
                self?.updateTextOverlay(for: id)
            }
        }
        self.sourceImage = sourceImage
        self.spotlightClip = spotlightClip
        self.imageFrame = imageFrame
        self.imageSize = imageSize
        // The editor's camera has to track the layout even when no pointer event has fired -
        // otherwise a window resize leaves the selection chrome drawing against a stale frame.
        editor.viewport = AnnoViewport(imageFrame: imageFrame, imageSize: imageSize)

        // Attach or tear down the caret to match the engine, and keep it lined up with its shape
        // as the document, the camera or the layout move underneath it.
        if textOverlay?.window != nil || editor.editingTextId != nil {
            updateTextOverlay(for: editor.editingTextId)
        }
        textOverlay?.sync()
        needsDisplay = true
    }

    /// Attach, detach or retarget the editing overlay to follow `editingTextId`.
    private func updateTextOverlay(for id: AnnoShapeID?) {
        guard let editor else { return }
        if let id, textOverlay?.editedShapeId == id { return }

        textOverlay?.removeFromSuperview()
        textOverlay = nil
        guard let id else { return }

        let overlay = AnnoTextEditorOverlay(editor: editor, shapeId: id)
        addSubview(overlay)
        overlay.loadText()
        window?.makeFirstResponder(overlay)
        textOverlay = overlay
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let editor,
              let context = NSGraphicsContext.current?.cgContext,
              imageSize.width > 0, imageFrame.width > 0 else { return }

        // Every colour below is dynamic; resolving them needs the view's appearance to be current.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            render(editor: editor, in: context)
        }
    }

    private var pageToView: CGAffineTransform {
        let scale = imageFrame.width / imageSize.width
        return CGAffineTransform(translationX: imageFrame.minX, y: imageFrame.minY)
            .scaledBy(x: scale, y: scale)
    }

    private func render(editor: AnnoEditor, in context: CGContext) {
        let target = AnnoShapeDrawing.Target(
            transform: pageToView,
            pageSize: imageSize,
            sample: { [sourceImage] rect in
                // The rect arrives in view coordinates; both spaces are y-down, so this is a
                // straight scale into the screenshot's own pixels.
                guard let sourceImage, self.imageFrame.width > 0, self.imageFrame.height > 0 else { return nil }
                let sx = CGFloat(sourceImage.width) / self.imageFrame.width
                let sy = CGFloat(sourceImage.height) / self.imageFrame.height
                let crop = CGRect(
                    x: (rect.minX - self.imageFrame.minX) * sx,
                    y: (rect.minY - self.imageFrame.minY) * sy,
                    width: rect.width * sx,
                    height: rect.height * sy
                ).integral.intersection(
                    CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
                )
                guard crop.width >= 1, crop.height >= 1 else { return nil }
                return sourceImage.cropping(to: crop)
            },
            spotlightClip: spotlightClip,
            isFlippedContext: true
        )

        // The shape being typed into is drawn by its text overlay instead, so the two don't double
        // up while the caret is live.
        let skipped: Set<AnnoShapeID> = editor.editingTextId.map { [$0] } ?? []
        AnnoShapeDrawing.draw(editor.document, in: context, target: target, skipping: skipped)

        drawOverlays(editor: editor, in: context)
    }

    // MARK: - Overlays

    /// Selection, handles and the brush, drawn in view space so they keep a constant weight at any
    /// zoom.
    private func drawOverlays(editor: AnnoEditor, in context: CGContext) {
        let accent = AnnoTheme.selectionStroke
        let lineWidth = 1.5

        if let hintedId = editor.hintedBindingId, let corners = editor.document.pageCorners(hintedId) {
            let path = CGMutablePath()
            path.addLines(between: corners.map { editor.pageToScreen($0).cgPoint })
            path.closeSubpath()
            context.addPath(path)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
            context.addPath(path)
            context.setFillColor(AnnoTheme.selectionFill.cgColor)
            context.fillPath()
        }

        if let brush = editor.brush {
            let origin = editor.pageToScreen(Vec(brush.minX, brush.minY))
            let end = editor.pageToScreen(Vec(brush.maxX, brush.maxY))
            let rect = CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
            context.setFillColor(AnnoTheme.selectionFill.cgColor)
            context.fill(rect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(lineWidth)
            context.stroke(rect)
        }

        // While text is being typed the selection frame stays hidden - the text view is the only
        // affordance.
        guard editor.editingTextId == nil, editor.tool == .select, !editor.selectedIds.isEmpty else { return }

        // A lone arrow shows its own handles, since resizing it as a box makes no sense.
        if editor.selectedIds.count == 1, let shape = editor.selectedShapes.first, shape.isArrow,
           let info = editor.document.arrowInfo(shape.id) {
            let transform = shape.pageTransform
            var combined = transform.cgAffineTransform.concatenating(pageToView)
            if let guidePath = ArrowPath.handles(info).solidPath().copy(using: &combined) {
                context.addPath(guidePath)
                context.setStrokeColor(accent.withAlphaComponent(0.5).cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }

            for point in [info.start.handle, info.middle, info.end.handle] {
                drawRoundHandle(at: editor.pageToScreen(transform.applyToPoint(point)), in: context)
            }
            return
        }

        guard let bounds = editor.selectionBounds else { return }

        // Draw in the selection's own frame so the box and its corner squares follow a rotated
        // shape. Sizes are divided by the scale to come out fixed on screen.
        let transform = bounds.transform.cgAffineTransform.concatenating(pageToView)
        let scale = imageFrame.width / imageSize.width
        let box = bounds.box

        let framePath = CGMutablePath()
        framePath.addRect(box.cgRect, transform: transform)
        context.addPath(framePath)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()

        // Only the corners are drawn. The edge and rotate handles stay live for hit testing but are
        // invisible, which is what keeps the selection quiet.
        let handleSize = 8.0 / scale
        let cornersPath = CGMutablePath()
        for corner in box.corners {
            cornersPath.addRect(
                CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                ),
                transform: transform
            )
        }
        context.addPath(cornersPath)
        context.setFillColor(AnnoTheme.handleFill.cgColor)
        context.fillPath()
        context.addPath(cornersPath)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }

    private func drawRoundHandle(at point: Vec, in context: CGContext) {
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        context.setFillColor(AnnoTheme.handleFill.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(AnnoTheme.selectionStroke.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect)
    }
}
