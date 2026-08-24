import SwiftUI

enum CropMetrics {
    static let hitSize: CGFloat = 24
    static let bracketLeg: CGFloat = 22
    static let bracketWeight: CGFloat = 3
    static let edgeLeg: CGFloat = 30
}

private struct CropDimShape: Shape {
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(box)
        return path
    }
}

private struct CropBoxShape: Shape {
    let box: CGRect

    func path(in rect: CGRect) -> Path { Path(box) }
}

private struct CropThirdsShape: Shape {
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...2 {
            let x = box.minX + box.width / 3 * CGFloat(step)
            let y = box.minY + box.height / 3 * CGFloat(step)
            path.move(to: CGPoint(x: x, y: box.minY))
            path.addLine(to: CGPoint(x: x, y: box.maxY))
            path.move(to: CGPoint(x: box.minX, y: y))
            path.addLine(to: CGPoint(x: box.maxX, y: y))
        }
        return path
    }
}

private struct CropBracketsShape: Shape {
    let box: CGRect

    func path(in rect: CGRect) -> Path {
        let leg = min(CropMetrics.bracketLeg, box.width / 3, box.height / 3)
        let inset = CropMetrics.bracketWeight / 2
        let inner = box.insetBy(dx: inset, dy: inset)
        var path = Path()

        for corner in [
            (CGPoint(x: inner.minX, y: inner.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: inner.maxX, y: inner.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: inner.minX, y: inner.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: inner.maxX, y: inner.maxY), CGFloat(-1), CGFloat(-1))
        ] {
            let (origin, sx, sy) = corner
            path.move(to: CGPoint(x: origin.x + leg * sx, y: origin.y))
            path.addLine(to: origin)
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + leg * sy))
        }

        let edgeLeg = min(CropMetrics.edgeLeg, box.width / 2, box.height / 2)
        path.move(to: CGPoint(x: inner.midX - edgeLeg / 2, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.midX + edgeLeg / 2, y: inner.minY))
        path.move(to: CGPoint(x: inner.midX - edgeLeg / 2, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.midX + edgeLeg / 2, y: inner.maxY))
        path.move(to: CGPoint(x: inner.minX, y: inner.midY - edgeLeg / 2))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.midY + edgeLeg / 2))
        path.move(to: CGPoint(x: inner.maxX, y: inner.midY - edgeLeg / 2))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.midY + edgeLeg / 2))

        return path
    }
}

/// The live crop rectangle: everything outside it is dimmed, corner brackets resize it, dragging inside reframes it.
struct CropBox: View {
    @Binding var rect: CGRect
    let frameSize: CGSize

    @State private var dragOrigin: CGRect?
    @State private var isAdjusting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var box: CGRect {
        CGRect(
            x: rect.minX * frameSize.width,
            y: rect.minY * frameSize.height,
            width: rect.width * frameSize.width,
            height: rect.height * frameSize.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CropDimShape(box: box)
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            CropBoxShape(box: box)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)

            CropThirdsShape(box: box)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                .opacity(isAdjusting ? 1 : 0)

            CropBracketsShape(box: box)
                .stroke(Color.white, style: StrokeStyle(lineWidth: CropMetrics.bracketWeight, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.35), radius: 2)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
                .gesture(reframeGesture)

            handle(at: CGPoint(x: box.minX, y: box.minY), edges: [.left, .top])
            handle(at: CGPoint(x: box.maxX, y: box.minY), edges: [.right, .top])
            handle(at: CGPoint(x: box.minX, y: box.maxY), edges: [.left, .bottom])
            handle(at: CGPoint(x: box.maxX, y: box.maxY), edges: [.right, .bottom])
            handle(at: CGPoint(x: box.midX, y: box.minY), edges: .top)
            handle(at: CGPoint(x: box.midX, y: box.maxY), edges: .bottom)
            handle(at: CGPoint(x: box.minX, y: box.midY), edges: .left)
            handle(at: CGPoint(x: box.maxX, y: box.midY), edges: .right)
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isAdjusting)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func handle(at point: CGPoint, edges: CropGeometry.Edges) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: CropMetrics.hitSize, height: CropMetrics.hitSize)
            .offset(x: point.x - CropMetrics.hitSize / 2, y: point.y - CropMetrics.hitSize / 2)
            .gesture(resizeGesture(edges: edges))
    }

    private func resizeGesture(edges: CropGeometry.Edges) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isAdjusting = true
                rect = CropGeometry.resized(rect, edges: edges, to: CGPoint(
                    x: value.location.x / max(frameSize.width, 1),
                    y: value.location.y / max(frameSize.height, 1)
                ))
            }
            .onEnded { _ in isAdjusting = false }
    }

    private var reframeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isAdjusting = true
                let start = dragOrigin ?? rect
                dragOrigin = start
                rect = CropGeometry.moved(start, by: CGSize(
                    width: value.translation.width / max(frameSize.width, 1),
                    height: value.translation.height / max(frameSize.height, 1)
                ))
            }
            .onEnded { _ in
                dragOrigin = nil
                isAdjusting = false
            }
    }
}

/// Floating crop controls, the way Photos puts them under the image instead of hiding them in a sidebar.
struct CropToolbar: View {
    let dimensions: String
    let canReset: Bool
    let onReset: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(dimensions)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .frame(minWidth: 76)

            Divider().frame(height: 16)

            InspectorPill("Reset", systemImage: "arrow.counterclockwise", action: onReset)
                .disabled(!canReset)

            InspectorPill("Cancel", action: onCancel)

            InspectorPill("Done", systemImage: "checkmark", role: .accent, isActive: true, action: onApply)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 14, depth: .raised)
        .padding(.bottom, 18)
    }
}
