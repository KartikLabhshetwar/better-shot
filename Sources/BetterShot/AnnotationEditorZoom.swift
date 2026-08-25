//
//  AnnotationEditorZoom.swift
//  BetterShot
//

import CoreGraphics

extension AnnotationEditorModel {
    /// The full canvas size (image + optional background padding) in image pixels.
    var canvasPixelSize: CGSize {
        AnnotationBackgroundLayout.make(contentSize: imageSize, settings: backgroundSettings).canvasSize
    }

    /// Scale at which the canvas is shown at its "actual" (100%) size: 1 image
    /// pixel maps to 1 logical point divided by the backing scale factor.
    var pixelToPointScale: CGFloat {
        displayScale > 0 ? 1 / displayScale : 1
    }

    /// Scale that fits the whole canvas inside the current viewport.
    var fitZoomScale: CGFloat {
        let canvas = canvasPixelSize
        guard canvas.width > 0, canvas.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return pixelToPointScale
        }
        let fitContainer = fitContainerSize(for: viewportSize)
        return min(fitContainer.width / canvas.width, fitContainer.height / canvas.height)
    }

    /// The container size used to compute the fit scale. While cropping, this is
    /// inset by `cropHandleMargin` on every side so the image leaves room for
    /// the crop resize handles, keeping them fully on-screen and clickable even
    /// when the crop is dragged to the image's edge.
    private func fitContainerSize(for container: CGSize) -> CGSize {
        guard isCropping else { return container }
        let inset = Self.cropHandleMargin * 2
        return CGSize(
            width: max(container.width - inset, 1),
            height: max(container.height - inset, 1)
        )
    }

    /// The scale currently applied to the canvas.
    var resolvedZoomScale: CGFloat {
        zoomToFit ? fitZoomScale : manualZoomScale
    }

    /// The displayed zoom percentage (relative to actual size).
    var zoomPercent: Int {
        guard pixelToPointScale > 0 else { return 100 }
        return max(1, Int((resolvedZoomScale / pixelToPointScale * 100).rounded()))
    }

    /// `true` when the zoomed content is larger than the viewport in either axis.
    var canPan: Bool {
        let scaled = scaledCanvasSize
        return scaled.width > viewportSize.width + 0.5 || scaled.height > viewportSize.height + 0.5
    }

    private var scaledCanvasSize: CGSize {
        let canvas = canvasPixelSize
        return CGSize(width: canvas.width * resolvedZoomScale, height: canvas.height * resolvedZoomScale)
    }

    private var minZoomScale: CGFloat { pixelToPointScale * CGFloat(Self.minZoomPercent) / 100 }
    private var maxZoomScale: CGFloat { pixelToPointScale * CGFloat(Self.maxZoomPercent) / 100 }

    /// The on-screen rect of the canvas for the given viewport, accounting for
    /// the current zoom scale and (clamped) pan offset.
    func displayCanvasFrame(in container: CGSize) -> CGRect {
        let canvas = canvasPixelSize
        guard canvas.width > 0, canvas.height > 0,
              container.width > 0, container.height > 0 else { return .zero }

        let fitContainer = fitContainerSize(for: container)
        let fit = min(fitContainer.width / canvas.width, fitContainer.height / canvas.height)
        let scale = zoomToFit ? fit : manualZoomScale
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let pan = clampedPan(panOffset, scaledSize: size, container: container)
        return CGRect(
            x: (container.width - size.width) / 2 + pan.width,
            y: (container.height - size.height) / 2 + pan.height,
            width: size.width,
            height: size.height
        )
    }

    func resetZoom() {
        zoomToFit = true
        manualZoomScale = 1
        panOffset = .zero
    }

    func fitCanvas() {
        zoomToFit = true
        panOffset = .zero
    }

    func setZoomPercent(_ percent: Int) {
        manualZoomScale = clampScale(pixelToPointScale * CGFloat(percent) / 100)
        zoomToFit = false
        panOffset = .zero
    }

    /// Set an absolute display scale (used for continuous pinch/scroll zoom).
    func setZoomScale(_ scale: CGFloat) {
        manualZoomScale = clampScale(scale)
        zoomToFit = false
        clampPanToBounds()
    }

    func zoomIn() { applyZoomFactor(1.25) }

    func zoomOut() { applyZoomFactor(0.8) }

    func zoomBy(_ factor: CGFloat) {
        setZoomScale(resolvedZoomScale * factor)
    }

    func panBy(dx: CGFloat, dy: CGFloat) {
        panOffset = clampedPan(
            CGSize(width: panOffset.width + dx, height: panOffset.height + dy),
            scaledSize: scaledCanvasSize,
            container: viewportSize
        )
    }

    private func applyZoomFactor(_ factor: CGFloat) {
        manualZoomScale = clampScale(resolvedZoomScale * factor)
        zoomToFit = false
        clampPanToBounds()
    }

    private func clampScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minZoomScale), maxZoomScale)
    }

    private func clampPanToBounds() {
        panOffset = clampedPan(panOffset, scaledSize: scaledCanvasSize, container: viewportSize)
    }

    private func clampedPan(_ pan: CGSize, scaledSize: CGSize, container: CGSize) -> CGSize {
        let maxX = max(0, (scaledSize.width - container.width) / 2)
        let maxY = max(0, (scaledSize.height - container.height) / 2)
        return CGSize(
            width: min(max(pan.width, -maxX), maxX),
            height: min(max(pan.height, -maxY), maxY)
        )
    }
}
