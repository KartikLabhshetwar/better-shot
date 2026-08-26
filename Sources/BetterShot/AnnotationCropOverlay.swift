//
//  AnnotationCropOverlay.swift
//  BetterShot
//
//  The modal crop UI rendered over the canvas: a dimmed exterior, rule-of-thirds
//  grid, draggable interior, and corner/edge resize handles. All interaction is
//  expressed in the image's normalized coordinate space and forwarded to the
//  model, which owns the crop geometry.
//

import SwiftUI

/// Shared coordinate-space name so the overlay's drag gestures resolve to the
/// same coordinates as the canvas `imageFrame`.
enum AnnotationCanvasCoordinateSpace {
    static let name = "AnnotationCanvasSpace"
}

struct AnnotationCropOverlay: View {
    @Bindable var model: AnnotationEditorModel
    /// The on-screen rect (canvas-local points) the image occupies.
    let imageFrame: CGRect

    var body: some View {
        CropAdjustmentOverlay(
            imageFrame: imageFrame,
            coordinateSpaceName: AnnotationCanvasCoordinateSpace.name,
            cropRect: model.cropRect.standardized,
            showsEdgeHandles: !model.cropAspect.locksAspect,
            onResize: { handle, point in
                model.updateCrop(handle: handle, toNormalized: point)
            },
            onMove: { start, delta in
                model.cropRect = CropRectEditor.move(start, by: delta)
            }
        )
    }
}

struct CropAdjustmentOverlay: View {
    let imageFrame: CGRect
    let coordinateSpaceName: String
    let cropRect: CGRect
    let showsEdgeHandles: Bool
    let onResize: (CropHandle, CGPoint) -> Void
    let onMove: (CGRect, CGSize) -> Void

    @State private var moveStartCrop: CGRect?

    private var cropViewRect: CGRect {
        viewRect(cropRect)
    }

    private var visibleHandles: [CropHandle] {
        showsEdgeHandles ? CropHandle.allCases : CropHandle.allCases.filter(\.isCorner)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimmedExterior
            grid
            border
            moveSurface
            handles
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    // MARK: Layers

    private var dimmedExterior: some View {
        Path { path in
            path.addRect(imageFrame)
            path.addRect(cropViewRect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private var border: some View {
        Rectangle()
            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
            .frame(width: cropViewRect.width, height: cropViewRect.height)
            .position(x: cropViewRect.midX, y: cropViewRect.midY)
            .shadow(color: .black.opacity(0.3), radius: 1)
            .allowsHitTesting(false)
    }

    private var grid: some View {
        Path { path in
            let rect = cropViewRect
            for index in 1...2 {
                let x = rect.minX + rect.width * CGFloat(index) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))

                let y = rect.minY + rect.height * CGFloat(index) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
        .allowsHitTesting(false)
    }

    private var moveSurface: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: max(cropViewRect.width, 1), height: max(cropViewRect.height, 1))
            .position(x: cropViewRect.midX, y: cropViewRect.midY)
            .gesture(moveGesture)
    }

    private var handles: some View {
        ForEach(visibleHandles, id: \.self) { handle in
            let point = handlePoint(handle)
            CropHandleView(isCorner: handle.isCorner, handle: handle)
                .position(x: point.x, y: point.y)
                .gesture(handleGesture(handle))
        }
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let start = moveStartCrop ?? cropRect
                if moveStartCrop == nil { moveStartCrop = start }
                guard imageFrame.width > 0, imageFrame.height > 0 else { return }
                let delta = CGSize(
                    width: value.translation.width / imageFrame.width,
                    height: value.translation.height / imageFrame.height
                )
                onMove(start, delta)
            }
            .onEnded { _ in moveStartCrop = nil }
    }

    private func handleGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                onResize(handle, normalized(value.location))
            }
    }

    // MARK: Geometry

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - imageFrame.minX) / imageFrame.width,
            y: (point.y - imageFrame.minY) / imageFrame.height
        )
    }

    private func handlePoint(_ handle: CropHandle) -> CGPoint {
        let rect = cropViewRect
        let unit = handle.unitPoint
        return CGPoint(
            x: rect.minX + rect.width * unit.x,
            y: rect.minY + rect.height * unit.y
        )
    }
}

private struct CropHandleView: View {
    let isCorner: Bool
    let handle: CropHandle

    var body: some View {
        ZStack {
            // Large, invisible hit target for comfortable grabbing.
            Color.white.opacity(0.001)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())

            shape
        }
    }

    @ViewBuilder
    private var shape: some View {
        if isCorner {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 13, height: 13)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
        } else {
            let isHorizontalEdge = handle == .top || handle == .bottom
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(
                    width: isHorizontalEdge ? 26 : 7,
                    height: isHorizontalEdge ? 7 : 26
                )
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
        }
    }
}
