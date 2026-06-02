import SwiftUI

struct AnnotationGestureView: NSViewRepresentable {
    @Bindable var model: EditorModel
    let imageAspectRatio: CGFloat

    func makeNSView(context: Context) -> AnnotationTrackingView {
        let view = AnnotationTrackingView()
        view.model = model
        view.imageAspectRatio = imageAspectRatio
        return view
    }

    func updateNSView(_ nsView: AnnotationTrackingView, context: Context) {
        nsView.model = model
        nsView.imageAspectRatio = imageAspectRatio
    }
}

final class AnnotationTrackingView: NSView {
    var model: EditorModel?
    var imageAspectRatio: CGFloat = 1.0
    private var dragStart: NSPoint?
    private var freehandPoints: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }

    private var imageDisplayRect: CGRect {
        let viewW = bounds.width
        let viewH = bounds.height
        guard viewW > 0, viewH > 0, imageAspectRatio > 0 else { return bounds }

        let viewAspect = viewW / viewH
        let w: CGFloat
        let h: CGFloat

        if viewAspect > imageAspectRatio {
            h = viewH
            w = h * imageAspectRatio
        } else {
            w = viewW
            h = w / imageAspectRatio
        }

        let x = (viewW - w) / 2
        let y = (viewH - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    override func mouseDown(with event: NSEvent) {
        guard let model, model.activeTool.createsAnnotation else { return }
        let loc = convert(event.locationInWindow, from: nil)
        guard imageDisplayRect.contains(loc) else { return }
        dragStart = loc
        freehandPoints = []

        if model.activeTool == .freehand {
            freehandPoints.append(normalize(loc))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, model.activeTool.createsAnnotation, dragStart != nil else { return }
        let loc = convert(event.locationInWindow, from: nil)

        if model.activeTool == .freehand {
            freehandPoints.append(normalize(loc))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model, model.activeTool.createsAnnotation, let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        dragStart = nil

        let normStart = normalize(start)
        let normEnd = normalize(end)

        let minX = min(normStart.x, normEnd.x)
        let minY = min(normStart.y, normEnd.y)
        let w = abs(normEnd.x - normStart.x)
        let h = abs(normEnd.y - normStart.y)

        guard w > 0.005 || h > 0.005 || model.activeTool == .freehand else { return }

        let rect = CGRect(x: minX, y: minY, width: max(w, 0.01), height: max(h, 0.01))

        var item = AnnotationItem(
            tool: model.activeTool,
            rect: rect,
            swatch: model.currentSwatch,
            strokeWidth: model.currentStrokeWidth
        )

        switch model.activeTool {
        case .line, .arrow:
            item.points = [normStart, normEnd]
        case .freehand:
            item.points = freehandPoints
            if let bounds = boundingRect(of: freehandPoints) {
                item.rect = bounds
            }
        case .numberedBadge:
            item.badgeNumber = (model.annotations.filter { $0.tool == .numberedBadge }.count) + 1
        case .text:
            item.text = "Text"
        default:
            break
        }

        Task { @MainActor in
            model.addAnnotation(item)
        }
        freehandPoints = []
    }

    override func resetCursorRects() {
        if let model, model.activeTool.createsAnnotation {
            addCursorRect(imageDisplayRect, cursor: .crosshair)
        }
    }

    private func normalize(_ point: NSPoint) -> CGPoint {
        let imgRect = imageDisplayRect
        guard imgRect.width > 0, imgRect.height > 0 else { return .zero }
        return CGPoint(
            x: max(0, min(1, (point.x - imgRect.minX) / imgRect.width)),
            y: max(0, min(1, (point.y - imgRect.minY) / imgRect.height))
        )
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    }
}
