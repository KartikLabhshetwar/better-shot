import SwiftUI

struct AnnotationGestureView: NSViewRepresentable {
    @Bindable var model: EditorModel

    func makeNSView(context: Context) -> AnnotationTrackingView {
        let view = AnnotationTrackingView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: AnnotationTrackingView, context: Context) {
        nsView.model = model
    }
}

final class AnnotationTrackingView: NSView {
    var model: EditorModel?
    private var dragStart: NSPoint?
    private var freehandPoints: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let model, model.activeTool.createsAnnotation else { return }
        let loc = convert(event.locationInWindow, from: nil)
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
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    private func normalize(_ point: NSPoint) -> CGPoint {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return .zero }
        return CGPoint(
            x: max(0, min(1, point.x / w)),
            y: max(0, min(1, point.y / h))
        )
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    }
}
