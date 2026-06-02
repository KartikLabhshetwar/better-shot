import SwiftUI

struct AnnotationCanvas: View {
    @Bindable var model: EditorModel
    let imageFrame: CGRect

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var freehandPoints: [CGPoint] = []

    var body: some View {
        ZStack {
            ForEach(model.annotations) { item in
                AnnotationItemShape(item: item, imageFrame: imageFrame)
                    .allowsHitTesting(false)
            }

            if model.activeTool != .select, let start = dragStart, let current = dragCurrent {
                liveDrawingShape(from: start, to: current)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(drawingGesture)
        .onHover { inside in
            if inside && model.activeTool != .select {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("annotationSpace"))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
                dragCurrent = value.location

                if model.activeTool == .freehand {
                    freehandPoints.append(normalizePoint(value.location))
                }
            }
            .onEnded { value in
                commitAnnotation(from: value.startLocation, to: value.location)
                dragStart = nil
                dragCurrent = nil
                freehandPoints = []
            }
    }

    // MARK: - Commit

    private func commitAnnotation(from start: CGPoint, to end: CGPoint) {
        guard model.activeTool.createsAnnotation else { return }
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }

        let normStart = normalizePoint(start)
        let normEnd = normalizePoint(end)

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
            item.badgeNumber = model.annotations.filter { $0.tool == .numberedBadge }.count + 1
        case .text:
            item.text = "Text"
        default:
            break
        }

        model.addAnnotation(item)
    }

    // MARK: - Coordinate Helpers

    private func normalizePoint(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        let x = ((point.x - imageFrame.minX) / imageFrame.width).clamped(to: 0...1)
        let y = ((point.y - imageFrame.minY) / imageFrame.height).clamped(to: 0...1)
        return CGPoint(x: x, y: y)
    }

    private func denormalizePoint(_ normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + normalized.x * imageFrame.width,
            y: imageFrame.minY + normalized.y * imageFrame.height
        )
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.01), height: max(maxY - minY, 0.01))
    }

    // MARK: - Live Drawing Shape

    @ViewBuilder
    private func liveDrawingShape(from start: CGPoint, to end: CGPoint) -> some View {
        let color = Color(cgColor: model.currentSwatch.cgColor)
        let lineWidth: CGFloat = model.currentStrokeWidth

        switch model.activeTool {
        case .rectangle:
            let rect = dragRect(from: start, to: end)
            Rectangle()
                .strokeBorder(color, lineWidth: lineWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        case .filledRect:
            let rect = dragRect(from: start, to: end)
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.7))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        case .ellipse:
            let rect = dragRect(from: start, to: end)
            Ellipse()
                .strokeBorder(color, lineWidth: lineWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        case .line:
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .arrow:
            ArrowShape(from: start, to: end)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        case .freehand:
            if freehandPoints.count >= 2 {
                Path { path in
                    let screenPoints = freehandPoints.map { denormalizePoint($0) }
                    guard let first = screenPoints.first else { return }
                    path.move(to: first)
                    for pt in screenPoints.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }

        case .pixelate, .blur:
            let rect = dragRect(from: start, to: end)
            Rectangle()
                .fill(color.opacity(0.1))
                .overlay(Rectangle().strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        case .numberedBadge:
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .position(x: end.x, y: end.y)

        case .text:
            let rect = dragRect(from: start, to: end)
            Rectangle()
                .strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        default:
            EmptyView()
        }
    }

    private func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        return CGRect(x: minX, y: minY, width: max(abs(end.x - start.x), 1), height: max(abs(end.y - start.y), 1))
    }
}

// MARK: - Arrow Shape

struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)

            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength: CGFloat = 14
            let headAngle: CGFloat = .pi / 6

            let left = CGPoint(
                x: to.x - headLength * cos(angle - headAngle),
                y: to.y - headLength * sin(angle - headAngle)
            )
            let right = CGPoint(
                x: to.x - headLength * cos(angle + headAngle),
                y: to.y - headLength * sin(angle + headAngle)
            )

            path.move(to: left)
            path.addLine(to: to)
            path.addLine(to: right)
        }
    }
}

// MARK: - Rendered Annotation Item (committed shapes)

struct AnnotationItemShape: View {
    let item: AnnotationItem
    let imageFrame: CGRect

    var body: some View {
        let color = Color(cgColor: item.swatch.cgColor)

        switch item.tool {
        case .rectangle:
            Rectangle()
                .strokeBorder(color, lineWidth: item.strokeWidth)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)

        case .filledRect:
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.7))
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)

        case .ellipse:
            Ellipse()
                .strokeBorder(color, lineWidth: item.strokeWidth)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)

        case .line:
            if item.points.count >= 2 {
                Path { path in
                    path.move(to: denormalize(item.points[0]))
                    path.addLine(to: denormalize(item.points[1]))
                }
                .stroke(color, style: StrokeStyle(lineWidth: item.strokeWidth, lineCap: .round))
            }

        case .arrow:
            if item.points.count >= 2 {
                ArrowShape(from: denormalize(item.points[0]), to: denormalize(item.points[1]))
                    .stroke(color, style: StrokeStyle(lineWidth: item.strokeWidth, lineCap: .round, lineJoin: .round))
            }

        case .freehand:
            if item.points.count >= 2 {
                Path { path in
                    let pts = item.points.map { denormalize($0) }
                    path.move(to: pts[0])
                    for i in 1..<pts.count {
                        if i < pts.count - 1 {
                            let mid = CGPoint(x: (pts[i].x + pts[i+1].x) / 2, y: (pts[i].y + pts[i+1].y) / 2)
                            path.addQuadCurve(to: mid, control: pts[i])
                        } else {
                            path.addLine(to: pts[i])
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: item.strokeWidth, lineCap: .round, lineJoin: .round))
            }

        case .numberedBadge:
            ZStack {
                Circle()
                    .fill(color)
                Text("\(item.badgeNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: max(screenRect.width, 26), height: max(screenRect.height, 26))
            .position(x: screenRect.midX, y: screenRect.midY)

        case .text:
            Text(item.text)
                .font(.system(size: item.fontSize, weight: item.isBold ? .bold : .regular))
                .foregroundColor(color)
                .position(x: screenRect.midX, y: screenRect.midY)

        case .pixelate, .blur:
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)

        default:
            EmptyView()
        }
    }

    private var screenRect: CGRect {
        CGRect(
            x: imageFrame.minX + item.rect.origin.x * imageFrame.width,
            y: imageFrame.minY + item.rect.origin.y * imageFrame.height,
            width: item.rect.width * imageFrame.width,
            height: item.rect.height * imageFrame.height
        )
    }

    private func denormalize(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + point.x * imageFrame.width,
            y: imageFrame.minY + point.y * imageFrame.height
        )
    }
}

// MARK: - Clamped helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
