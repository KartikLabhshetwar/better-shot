import SwiftUI

struct EditorCanvasView: View {
    @Bindable var model: EditorModel

    @State private var renderedPreview: NSImage?
    @State private var renderTask: Task<Void, Never>?
    @State private var hasActiveInteraction = false
    @State private var hoveredLocation: CGPoint?
    @State private var currentCursor: AnnotationCanvasCursor = .arrow

    var body: some View {
        GeometryReader { proxy in
            if model.sourceImage != nil {
                let displayImage = renderedPreview ?? model.previewImage
                let displaySize: CGSize = {
                    guard let img = displayImage else { return model.imageSize }
                    return CGSize(width: img.size.width, height: img.size.height)
                }()
                let imageFrame = aspectFitRect(imageSize: displaySize, in: proxy.size)
                let sourceImageFrame = sourceImageFrame(config: model.config, displayFrame: imageFrame, displaySize: displaySize)

                ZStack(alignment: .topLeading) {
                    if case .none = model.config.style, model.config.padding < 0.001 {
                        TransparencyGrid()
                    }

                    if let img = displayImage {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageFrame.width, height: imageFrame.height)
                            .position(x: imageFrame.midX, y: imageFrame.midY)
                    }

                    ForEach(model.items) { item in
                        AnnotationItemView(
                            item: item,
                            image: model.previewImage ?? NSImage(),
                            sourceImage: model.sourceImage,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            isSelected: model.selectedItemIDs.contains(item.id),
                            showsResizeHandles: model.selectionCount == 1,
                            isEditingText: item.id == model.editingTextItemID,
                            allowsRedactionPreviewCaching: !(model.isTransformingExistingAnnotation && model.selectedItemIDs.contains(item.id)),
                            text: Binding(
                                get: { item.text },
                                set: { model.setText($0, for: item.id) }
                            ),
                            onCommitText: model.commitTextEditing,
                            onTextSizeChange: { size in
                                model.setTextViewContentSize(size, for: item.id, imageFrame: sourceImageFrame, allowedBounds: model.annotationBounds(for: sourceImageFrame, boundaryFrame: imageFrame))
                            }
                        )
                    }

                    if let draftItem = model.draftItem {
                        AnnotationItemView(
                            item: draftItem,
                            image: model.previewImage ?? NSImage(),
                            sourceImage: model.sourceImage,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            isSelected: false,
                            showsResizeHandles: false,
                            isEditingText: false,
                            allowsRedactionPreviewCaching: false,
                            text: .constant(draftItem.text),
                            onCommitText: {},
                            onTextSizeChange: { _ in }
                        )
                    }

                    if let selectionRect = model.selectionRect {
                        AnnotationMarqueeSelectionView()
                            .frame(
                                width: max(viewRect(selectionRect, in: sourceImageFrame).width, 1),
                                height: max(viewRect(selectionRect, in: sourceImageFrame).height, 1)
                            )
                            .position(
                                x: viewRect(selectionRect, in: sourceImageFrame).midX,
                                y: viewRect(selectionRect, in: sourceImageFrame).midY
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(interactionGesture(imageFrame: sourceImageFrame, boundaryFrame: imageFrame))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredLocation = location
                        updateCursor(at: location, imageFrame: sourceImageFrame)
                    case .ended:
                        hoveredLocation = nil
                        setCursor(.arrow)
                    }
                }
                .onChange(of: model.selectedTool) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onChange(of: model.itemIDs) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onChange(of: model.selectedItemIDs) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onDisappear { setCursor(.arrow) }
            } else {
                ContentUnavailableView("Loading image...", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.config, initial: true) { _, _ in scheduleRender() }
        .onChange(of: model.sourceImage) { _, _ in scheduleRender() }
        .onChange(of: model.isSliderDragging) { _, isDragging in
            if !isDragging { scheduleRender() }
        }
    }

    @State private var lastRenderedConfig: BeautifierConfig?

    private func scheduleRender() {
        renderTask?.cancel()
        let isDragging = model.isSliderDragging
        let config = model.config
        if !isDragging, config == lastRenderedConfig { return }
        let delay: UInt64 = isDragging ? 80 : 50
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            guard let source = model.sourceImage else { return }

            let config = model.config
            let result = await Task.detached(priority: .userInitiated) {
                renderPreview(image: source, config: config, lowQuality: isDragging)
            }.value

            guard !Task.isCancelled, let cgImage = result else { return }
            renderedPreview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            lastRenderedConfig = config
        }
    }

    private func sourceImageFrame(config: BeautifierConfig, displayFrame: CGRect, displaySize: CGSize) -> CGRect {
        guard displaySize.width > 0, displaySize.height > 0 else { return displayFrame }

        let imgW = model.imageSize.width
        let imgH = model.imageSize.height
        guard imgW > 0, imgH > 0 else { return displayFrame }

        let shortEdge = min(imgW, imgH)
        let pad = shortEdge * config.padding

        var canvasW = imgW + pad * 2
        var canvasH = imgH + pad * 2

        if let ratio = config.aspectRatio.numericValue {
            let current = canvasW / canvasH
            if current < ratio { canvasW = canvasH * ratio }
            else { canvasH = canvasW / ratio }
        }

        let totalHPad = canvasW - imgW
        let totalVPad = canvasH - imgH
        let imgX = config.alignment.xFactor * totalHPad
        let imgY = config.alignment.yFactor * totalVPad

        let scaleX = displayFrame.width / canvasW
        let scaleY = displayFrame.height / canvasH
        let scale = min(scaleX, scaleY)

        return CGRect(
            x: displayFrame.minX + imgX * (displayFrame.width / canvasW),
            y: displayFrame.minY + imgY * (displayFrame.height / canvasH),
            width: imgW * (displayFrame.width / canvasW),
            height: imgH * (displayFrame.height / canvasH)
        )
    }

    private func interactionGesture(imageFrame: CGRect, boundaryFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !hasActiveInteraction {
                    hasActiveInteraction = true
                    model.beginInteraction(at: value.startLocation, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                }
                model.updateInteraction(to: value.location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                updateCursor(at: value.location, imageFrame: imageFrame)
            }
            .onEnded { value in
                model.endInteraction(at: value.location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                hasActiveInteraction = false
                updateCursor(at: value.location, imageFrame: imageFrame)
            }
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let padding: CGFloat = 24
        let availableSize = CGSize(width: containerSize.width - padding * 2, height: containerSize.height - padding * 2)
        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func viewRect(_ rect: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func refreshCursor(imageFrame: CGRect) {
        guard let hoveredLocation else { return }
        updateCursor(at: hoveredLocation, imageFrame: imageFrame)
    }

    private func updateCursor(at location: CGPoint, imageFrame: CGRect) {
        guard model.containsInteractionPoint(location, imageFrame: imageFrame, boundaryFrame: imageFrame) else {
            setCursor(.arrow)
            return
        }

        if hasActiveInteraction {
            setCursor(model.isTransformingExistingAnnotation ? .closedHand : .placement)
        } else if model.hoveredAnnotation(at: location, imageFrame: imageFrame, boundaryFrame: imageFrame) != nil {
            setCursor(.openHand)
        } else if model.selectedTool == .select {
            setCursor(.arrow)
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

private func renderPreview(image: CGImage, config: BeautifierConfig, lowQuality: Bool = false) -> CGImage? {
    let maxDim: CGFloat = lowQuality ? 900 : 1800
    let imgW = CGFloat(image.width)
    let imgH = CGFloat(image.height)
    let scale: CGFloat = max(imgW, imgH) > maxDim ? maxDim / max(imgW, imgH) : 1.0

    var previewImage = image
    if scale < 1.0 {
        let newW = Int(imgW * scale)
        let newH = Int(imgH * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = lowQuality ? .medium : .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let scaled = ctx.makeImage() else { return nil }
        previewImage = scaled
    }

    return BeautifierRenderer.render(image: previewImage, config: config)
}

private enum AnnotationCanvasCursor: Equatable {
    case arrow
    case placement
    case openHand
    case closedHand

    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .placement: .annotationPlus
        case .openHand: .openHand
        case .closedHand: .closedHand
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

struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 10
            let rows = Int(ceil(size.height / cellSize))
            let cols = Int(ceil(size.width / cellSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color.white : Color(white: 0.88))
                    )
                }
            }
        }
        .drawingGroup()
    }
}
