//
//  AnnotationCanvas.swift
//  BetterShot
//

import AppKit
import SwiftUI

private enum AnnotationCanvasCursor: Equatable {
    case arrow
    case placement
    case openHand
    case closedHand

    var nsCursor: NSCursor {
        switch self {
        case .arrow:
            .arrow
        case .placement:
            .annotationPlus
        case .openHand:
            .openHand
        case .closedHand:
            .closedHand
        }
    }
}

struct AnnotationCanvas: View {
    @Bindable var model: AnnotationEditorModel
    let image: NSImage
    let onEditorInteraction: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var hasActiveInteraction = false
    @State private var hoveredLocation: CGPoint?
    @State private var currentCursor: AnnotationCanvasCursor = .arrow
    @State private var progressivelyBlurredImage: NSImage?
    @State private var progressivelyBlurredSourceID: ObjectIdentifier?
    @State private var settledScene: AnnotationSceneSettleResult?

    var body: some View {
        GeometryReader { proxy in
            let backgroundLayout = AnnotationBackgroundLayout.make(
                contentSize: model.imageSize,
                settings: model.backgroundSettings
            )
            let canvasFrame = model.displayCanvasFrame(in: proxy.size)
            let displayLayout = backgroundLayout.scaled(to: canvasFrame)
            let imageFrame = displayLayout.imageFrame
            let boundaryFrame = model.backgroundSettings.usesCanvasLayout ? displayLayout.canvasFrame : imageFrame
            let allowedBounds = model.annotationBounds(for: imageFrame, boundaryFrame: boundaryFrame)
            let screenshotGeometry = AnnotationScreenshotFrameGeometry(
                imageRect: imageFrame,
                cardRect: displayLayout.cardFrame,
                settings: model.backgroundSettings
            )
            let clipCorners = swiftUICornerRadii(screenshotGeometry.imageCornerRadii)
            let effectiveCamera = model.isCropping || model.editingTextID != nil
                ? AnnotationCameraSettings()
                : model.backgroundSettings.camera
            let projection = AnnotationCameraGeometry.projection(
                sourceRect: CGRect(origin: .zero, size: proxy.size),
                imageRect: imageFrame,
                canvasSize: displayLayout.canvasFrame.size,
                settings: effectiveCamera
            )
            let previewPixelWidth = previewContentPixelWidth(
                imageFrame: imageFrame,
                canvasFrame: displayLayout.canvasFrame,
                viewportSize: proxy.size,
                projection: projection
            )
            let blurPreviewKey = AnnotationProgressiveBlurPreviewKey(
                image: image,
                settings: model.backgroundSettings.progressiveBlur,
                contentPixelWidth: previewPixelWidth
            )
            let usesSceneBlur = model.backgroundSettings.progressiveBlur.isActive
                && model.backgroundSettings.progressiveBlur.edgeMode == .bleed
                && !model.isCropping
                && model.editingTextID == nil
            let displayedImage = model.backgroundSettings.progressiveBlur.isActive
                && model.backgroundSettings.progressiveBlur.edgeMode == .clipped
                && !model.isCropping
                && progressivelyBlurredSourceID == ObjectIdentifier(image)
                ? progressivelyBlurredImage ?? image
                : image
            let sceneSettleKey = AnnotationSceneSettleKey(
                sourceID: ObjectIdentifier(image),
                shapes: model.shapes,
                settings: model.backgroundSettings,
                contentPixelWidth: previewPixelWidth,
                isEligible: usesSceneBlur
                    && !hasActiveInteraction
                    && !model.isTransformingExistingAnnotation
                    && model.selectionCount == 0
            )

            ZStack(alignment: .topLeading) {
                sceneStage(
                    viewportSize: proxy.size,
                    canvasFrame: displayLayout.canvasFrame,
                    backgroundStyle: model.backgroundSettings.style,
                    showsBackground: model.backgroundSettings.isEnabled,
                    screenshotGeometry: screenshotGeometry,
                    allowedBounds: allowedBounds,
                    clipCorners: clipCorners,
                    displayedImage: displayedImage,
                    projection: projection,
                    clipsForegroundToCanvas: effectiveCamera.hasEffect || usesSceneBlur,
                    sceneBlurSettings: usesSceneBlur
                        ? model.backgroundSettings.progressiveBlur
                        : nil,
                    settledSceneImage: settledScene.flatMap {
                        $0.key == sceneSettleKey ? $0.image : nil
                    }
                )

                if model.backgroundSettings.watermark.isVisible {
                    AnnotationWatermarkOverlay(
                        settings: model.backgroundSettings.watermark,
                        fontScale: displayLayout.scale
                    )
                    .frame(width: boundaryFrame.width, height: boundaryFrame.height)
                    .position(x: boundaryFrame.midX, y: boundaryFrame.midY)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(AnnotationCanvasCoordinateSpace.name))
            .contentShape(Rectangle())
            .background(
                AnnotationCanvasInputHandler(
                    onPan: { dx, dy in model.panBy(dx: dx, dy: dy) },
                    onZoom: { factor in model.zoomBy(factor) }
                )
            )
            .gesture(interactionGesture(
                imageFrame: imageFrame,
                boundaryFrame: boundaryFrame,
                projection: projection,
                visibleCanvasFrame: effectiveCamera.hasEffect ? displayLayout.canvasFrame : nil
            ))
            .onAppear {
                model.viewportSize = proxy.size
                model.displayScale = displayScale
            }
            .onChange(of: proxy.size) { _, newValue in
                model.viewportSize = newValue
            }
            .onChange(of: displayScale) { _, newValue in
                model.displayScale = newValue
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if effectiveCamera.hasEffect && !displayLayout.canvasFrame.contains(location) {
                        hoveredLocation = nil
                        setCursor(.arrow)
                        return
                    }
                    let mappedLocation = projection.unproject(location)
                    hoveredLocation = mappedLocation
                    updateCursor(at: mappedLocation, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                case .ended:
                    hoveredLocation = nil
                    setCursor(.arrow)
                }
            }
            .onChange(of: model.selectedTool) { _, _ in
                refreshCursor(imageFrame: imageFrame, boundaryFrame: boundaryFrame)
            }
            .onChange(of: model.revision) { _, _ in
                refreshCursor(imageFrame: imageFrame, boundaryFrame: boundaryFrame)
            }
            .onChange(of: model.selectionCount) { _, _ in
                refreshCursor(imageFrame: imageFrame, boundaryFrame: boundaryFrame)
            }
            .onDisappear {
                setCursor(.arrow)
            }
            .task(id: blurPreviewKey) {
                await updateProgressiveBlurPreview(
                    for: image,
                    settings: model.backgroundSettings.progressiveBlur,
                    contentPixelWidth: blurPreviewKey.contentPixelWidth
                )
            }
            .task(id: sceneSettleKey) {
                await updateSceneSettlePreview(for: image, key: sceneSettleKey)
            }
        }
    }

    @ViewBuilder
    private func sceneStage(
        viewportSize: CGSize,
        canvasFrame: CGRect,
        backgroundStyle: AnnotationBackgroundStyle,
        showsBackground: Bool,
        screenshotGeometry: AnnotationScreenshotFrameGeometry,
        allowedBounds: CGRect,
        clipCorners: RectangleCornerRadii,
        displayedImage: NSImage,
        projection: AnnotationCameraProjection,
        clipsForegroundToCanvas: Bool,
        sceneBlurSettings: AnnotationProgressiveBlurSettings?,
        settledSceneImage: NSImage? = nil
    ) -> some View {
        if let sceneBlurSettings {
            let blurRadius = max(
                0.5,
                sceneBlurSettings.strength * min(canvasFrame.width, canvasFrame.height) / 1000
            )

            ZStack(alignment: .topLeading) {
                sceneContent(
                    viewportSize: viewportSize,
                    canvasFrame: canvasFrame,
                    backgroundStyle: backgroundStyle,
                    showsBackground: showsBackground,
                    screenshotGeometry: screenshotGeometry,
                    allowedBounds: allowedBounds,
                    clipCorners: clipCorners,
                    displayedImage: displayedImage,
                    projection: projection,
                    clipsForegroundToCanvas: true
                )

                ForEach(0..<3, id: \.self) { level in
                    sceneContent(
                        viewportSize: viewportSize,
                        canvasFrame: canvasFrame,
                        backgroundStyle: backgroundStyle,
                        showsBackground: showsBackground,
                        screenshotGeometry: screenshotGeometry,
                        allowedBounds: allowedBounds,
                        clipCorners: clipCorners,
                        displayedImage: displayedImage,
                        projection: projection,
                        clipsForegroundToCanvas: true
                    )
                    .compositingGroup()
                    .blur(radius: blurRadius * CGFloat(level + 1) / 3)
                    .mask {
                        progressiveBlurBlendMask(
                            settings: sceneBlurSettings,
                            canvasFrame: canvasFrame,
                            level: level,
                            levelCount: 3
                        )
                    }
                    .allowsHitTesting(false)
                }

                // Export-exact frame rendered off-main once editing settles.
                // The gradient-band approximation above stays live underneath
                // so interaction never waits on a Core Image render.
                if let settledSceneImage {
                    Image(nsImage: settledSceneImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: canvasFrame.width, height: canvasFrame.height)
                        .position(x: canvasFrame.midX, y: canvasFrame.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .mask {
                Rectangle()
                    .frame(width: canvasFrame.width, height: canvasFrame.height)
                    .position(x: canvasFrame.midX, y: canvasFrame.midY)
            }
        } else {
            sceneContent(
                viewportSize: viewportSize,
                canvasFrame: canvasFrame,
                backgroundStyle: backgroundStyle,
                showsBackground: showsBackground,
                screenshotGeometry: screenshotGeometry,
                allowedBounds: allowedBounds,
                clipCorners: clipCorners,
                displayedImage: displayedImage,
                projection: projection,
                clipsForegroundToCanvas: clipsForegroundToCanvas
            )
        }
    }

    private func sceneContent(
        viewportSize: CGSize,
        canvasFrame: CGRect,
        backgroundStyle: AnnotationBackgroundStyle,
        showsBackground: Bool,
        screenshotGeometry: AnnotationScreenshotFrameGeometry,
        allowedBounds: CGRect,
        clipCorners: RectangleCornerRadii,
        displayedImage: NSImage,
        projection: AnnotationCameraProjection,
        clipsForegroundToCanvas: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if showsBackground {
                AnnotationBackgroundStageFill(style: backgroundStyle)
                    .frame(width: canvasFrame.width, height: canvasFrame.height)
                    .position(x: canvasFrame.midX, y: canvasFrame.midY)
            }

            transformedCameraForeground(
                viewportSize: viewportSize,
                screenshotGeometry: screenshotGeometry,
                allowedBounds: allowedBounds,
                clipCorners: clipCorners,
                displayedImage: displayedImage,
                projection: projection,
                canvasFrame: canvasFrame,
                clipsToCanvas: clipsForegroundToCanvas
            )
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    private func transformedCameraForeground(
        viewportSize: CGSize,
        screenshotGeometry: AnnotationScreenshotFrameGeometry,
        allowedBounds: CGRect,
        clipCorners: RectangleCornerRadii,
        displayedImage: NSImage,
        projection: AnnotationCameraProjection,
        canvasFrame: CGRect,
        clipsToCanvas: Bool
    ) -> some View {
        cameraForeground(
            viewportSize: viewportSize,
            screenshotGeometry: screenshotGeometry,
            allowedBounds: allowedBounds,
            clipCorners: clipCorners,
            displayedImage: displayedImage
        )
        .projectionEffect(projection.swiftUITransform)
        .mask {
            if clipsToCanvas {
                Rectangle()
                    .frame(width: canvasFrame.width, height: canvasFrame.height)
                    .position(x: canvasFrame.midX, y: canvasFrame.midY)
            } else {
                Rectangle()
            }
        }
    }

    private func progressiveBlurBlendMask(
        settings: AnnotationProgressiveBlurSettings,
        canvasFrame: CGRect,
        level: Int,
        levelCount: Int
    ) -> some View {
        AnnotationProgressiveBlurBlendMask(
            settings: settings,
            level: level,
            levelCount: levelCount
        )
        .frame(width: canvasFrame.width, height: canvasFrame.height)
        .position(x: canvasFrame.midX, y: canvasFrame.midY)
    }

    private func cameraForeground(
        viewportSize: CGSize,
        screenshotGeometry: AnnotationScreenshotFrameGeometry,
        allowedBounds: CGRect,
        clipCorners: RectangleCornerRadii,
        displayedImage: NSImage
    ) -> some View {
        let imageFrame = screenshotGeometry.imageRect

        return ZStack(alignment: .topLeading) {
            screenshotFrameBacking(
                geometry: screenshotGeometry,
                imageCornerRadii: clipCorners
            )

            screenshot(
                displayedImage,
                imageFrame: imageFrame,
                clipCorners: clipCorners
            )

            // One engine-drawn layer for every annotation: redactions under the spotlight,
            // then the spotlight, then the vector shapes and the selection chrome. Replaces the
            // per-item SwiftUI views, which each owned their own geometry and could not agree
            // with the exporter.
            AnnoCanvasLayer(
                editor: model.engine,
                sourceImage: model.previewCGImage,
                imageFrame: imageFrame,
                imageSize: model.imageSize,
                spotlightClip: nil,
                revision: model.revision
            )
            // Hit testing is declined everywhere except the text caret, so the drag gesture that
            // drives the engine still receives everything else.
            .frame(width: viewportSize.width, height: viewportSize.height)

            if model.isCropping {
                AnnotationCropOverlay(model: model, imageFrame: imageFrame)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    private func screenshot(
        _ displayedImage: NSImage,
        imageFrame: CGRect,
        clipCorners: RectangleCornerRadii
    ) -> some View {
        Image(nsImage: displayedImage)
            .resizable()
            .frame(width: imageFrame.width, height: imageFrame.height)
            .clipShape(UnevenRoundedRectangle(cornerRadii: clipCorners, style: .continuous))
            .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    @MainActor
    private func updateProgressiveBlurPreview(
        for sourceImage: NSImage,
        settings: AnnotationProgressiveBlurSettings,
        contentPixelWidth: CGFloat
    ) async {
        guard settings.isActive, settings.edgeMode == .clipped else {
            progressivelyBlurredImage = nil
            progressivelyBlurredSourceID = nil
            return
        }

        // Coalesce high-frequency focus-pad and slider updates before entering
        // the serialized Core Image worker.
        do {
            try await Task.sleep(for: .milliseconds(12))
        } catch {
            return
        }
        guard !Task.isCancelled,
              let source = sourceImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            return
        }

        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let output = await AnnotationProgressiveBlurPreviewWorker.shared.render(
            source: source,
            settings: settings,
            contentPixelWidth: contentPixelWidth,
            colorSpace: colorSpace
        ) else {
            if !Task.isCancelled {
                progressivelyBlurredImage = nil
                progressivelyBlurredSourceID = nil
            }
            return
        }
        guard !Task.isCancelled else {
            return
        }

        progressivelyBlurredImage = NSImage(cgImage: output, size: sourceImage.size)
        progressivelyBlurredSourceID = ObjectIdentifier(sourceImage)
    }

    /// Pixel width for preview renders (settled scene and clipped blur):
    /// exactly the pixels the image occupies on screen, including any
    /// enlargement from the camera projection, so rendered previews are
    /// indistinguishable from the live view. A generous budget only guards
    /// pathological canvas sizes; renders are debounced, never per frame.
    private func previewContentPixelWidth(
        imageFrame: CGRect,
        canvasFrame: CGRect,
        viewportSize: CGSize,
        projection: AnnotationCameraProjection
    ) -> CGFloat {
        // The projection maps the viewport rect onto a quad; the ratio of the
        // quad's edges to the viewport approximates how much the camera
        // magnifies the content on screen.
        let quad = projection.quad
        let topWidth = hypot(
            quad.topRight.x - quad.topLeft.x,
            quad.topRight.y - quad.topLeft.y
        )
        let bottomWidth = hypot(
            quad.bottomRight.x - quad.bottomLeft.x,
            quad.bottomRight.y - quad.bottomLeft.y
        )
        let leftHeight = hypot(
            quad.bottomLeft.x - quad.topLeft.x,
            quad.bottomLeft.y - quad.topLeft.y
        )
        let rightHeight = hypot(
            quad.bottomRight.x - quad.topRight.x,
            quad.bottomRight.y - quad.topRight.y
        )
        let magnification = min(3, max(
            1,
            max(topWidth, bottomWidth) / max(viewportSize.width, 1),
            max(leftHeight, rightHeight) / max(viewportSize.height, 1)
        ))

        let renderScale = displayScale * magnification
        let canvasPixelArea = canvasFrame.width * canvasFrame.height * renderScale * renderScale
        let budget: CGFloat = 12_000_000
        let budgetScale = min(1, (budget / max(canvasPixelArea, 1)).squareRoot())
        return max(1, (imageFrame.width * renderScale * budgetScale).rounded())
    }

    @MainActor
    private func updateSceneSettlePreview(
        for sourceImage: NSImage,
        key: AnnotationSceneSettleKey
    ) async {
        guard key.isEligible else {
            settledScene = nil
            return
        }

        // Let slider and focus-pad streams go quiet before paying for an
        // export-exact render; every keystroke restarts this task.
        do {
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            return
        }
        guard !Task.isCancelled,
              let source = sourceImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            return
        }

        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let output = await AnnotationProgressiveBlurPreviewWorker.shared.renderScene(
            source: source,
            shapes: key.shapes,
            settings: key.settings,
            contentPixelWidth: key.contentPixelWidth,
            colorSpace: colorSpace
        ), !Task.isCancelled else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            settledScene = AnnotationSceneSettleResult(
                key: key,
                image: NSImage(
                    cgImage: output,
                    size: NSSize(
                        width: CGFloat(output.width) / displayScale,
                        height: CGFloat(output.height) / displayScale
                    )
                )
            )
        }
    }

    @ViewBuilder
    private func screenshotFrameBacking(
        geometry: AnnotationScreenshotFrameGeometry,
        imageCornerRadii: RectangleCornerRadii
    ) -> some View {
        let settings = model.backgroundSettings
        let castsShadow = settings.isEnabled || settings.camera.hasEffect

        if settings.border.isVisible, geometry.borderWidth > 0 {
            let cardCornerRadii = swiftUICornerRadii(geometry.cardCornerRadii)
            ZStack {
                AnnotationCardShadowBackdrop(
                    cornerRadii: cardCornerRadii,
                    size: geometry.cardRect.size,
                    strength: castsShadow ? settings.shadow : 0,
                    style: settings.shadowStyle
                )
                UnevenRoundedRectangle(cornerRadii: cardCornerRadii, style: .continuous)
                    .fill(settings.border.color.color.opacity(min(max(settings.border.opacity, 0), 1)))
            }
            .frame(width: geometry.cardRect.width, height: geometry.cardRect.height)
            .position(x: geometry.cardRect.midX, y: geometry.cardRect.midY)
        } else if castsShadow {
            AnnotationCardShadowBackdrop(
                cornerRadii: imageCornerRadii,
                size: geometry.imageRect.size,
                strength: settings.shadow,
                style: settings.shadowStyle
            )
            .position(x: geometry.imageRect.midX, y: geometry.imageRect.midY)
        }
    }

    private func swiftUICornerRadii(_ radii: PerCornerRadii) -> RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: radii.topLeft,
            bottomLeading: radii.bottomLeft,
            bottomTrailing: radii.bottomRight,
            topTrailing: radii.topRight
        )
    }

    private func interactionGesture(
        imageFrame: CGRect,
        boundaryFrame: CGRect,
        projection: AnnotationCameraProjection,
        visibleCanvasFrame: CGRect?
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard hasActiveInteraction || visibleCanvasFrame?.contains(value.startLocation) != false else {
                    return
                }
                let startLocation = projection.unproject(value.startLocation)
                let location = projection.unproject(value.location)
                if !hasActiveInteraction {
                    hasActiveInteraction = true
                    onEditorInteraction()
                    model.beginInteraction(at: startLocation, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                }

                model.updateInteraction(to: location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                updateCursor(at: location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
            }
            .onEnded { value in
                guard hasActiveInteraction else { return }
                let location = projection.unproject(value.location)
                model.endInteraction(at: location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                hasActiveInteraction = false
                updateCursor(at: location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
            }
    }

    private func viewRect(_ rect: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func refreshCursor(imageFrame: CGRect, boundaryFrame: CGRect) {
        guard let hoveredLocation else { return }
        updateCursor(at: hoveredLocation, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
    }

    private func updateCursor(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !model.isCropping else {
            setCursor(.arrow)
            return
        }
        guard model.containsInteractionPoint(location, imageFrame: imageFrame, boundaryFrame: boundaryFrame) else {
            setCursor(.arrow)
            return
        }

        if hasActiveInteraction {
            setCursor(model.isTransformingExistingAnnotation ? .closedHand : .placement)
        } else if model.selectedTool == .select {
            // The grab cursor is a promise that a press picks the shape up, which only
            // Select keeps. A drawing tool draws over whatever is under the pointer, so
            // it stays on the crosshair however many shapes are already there.
            let hovering = model.hoveredAnnotation(
                at: location,
                imageFrame: imageFrame,
                boundaryFrame: boundaryFrame
            ) != nil
            setCursor(hovering ? .openHand : .arrow)
        } else {
            setCursor(.placement)
        }
    }

    private func setCursor(_ cursor: AnnotationCanvasCursor) {
        guard currentCursor != cursor else { return }
        currentCursor = cursor
        cursor.nsCursor.set()
    }
}

/// Captures scroll-wheel and pinch-magnify events over the canvas region to
/// drive panning and zooming, without interfering with SwiftUI drawing gestures.
private struct AnnotationCanvasInputHandler: NSViewRepresentable {
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.onPan = onPan
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {
        nsView.onPan = onPan
        nsView.onZoom = onZoom
    }

    final class InputView: NSView {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        var onZoom: ((CGFloat) -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func installMonitor() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self,
                      let window = self.window,
                      window.isKeyWindow,
                      event.window == window else {
                    return event
                }

                if window.firstResponder is NSTextView {
                    return event
                }

                let pointInView = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(pointInView) else {
                    return event
                }

                switch event.type {
                case .magnify:
                    self.onZoom?(1 + event.magnification)
                    return nil
                case .scrollWheel:
                    if event.modifierFlags.intersection([.command, .option]).isEmpty {
                        self.onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
                    } else {
                        self.onZoom?(1 + event.scrollingDeltaY * 0.0025)
                    }
                    return nil
                default:
                    return event
                }
            }
        }
    }
}

private struct AnnotationMarqueeSelectionView: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                Rectangle()
                    .stroke(
                        Color.accentColor.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
    }
}
