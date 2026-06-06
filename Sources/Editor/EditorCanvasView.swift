import SwiftUI

struct EditorCanvasView: View {
    @Bindable var model: EditorModel

    @State private var hasActiveInteraction = false
    @State private var hoveredLocation: CGPoint?
    @State private var currentCursor: AnnotationCanvasCursor = .arrow

    var body: some View {
        GeometryReader { proxy in
            if let sourceImage = model.sourceImage {
                let imgW = CGFloat(sourceImage.width)
                let imgH = CGFloat(sourceImage.height)
                let shortEdge = min(imgW, imgH)
                let pad = shortEdge * model.config.padding

                var canvasW = imgW + pad * 2
                var canvasH = imgH + pad * 2
                let _ = {
                    if let ratio = model.config.aspectRatio.numericValue {
                        let current = canvasW / canvasH
                        if current < ratio { canvasW = canvasH * ratio }
                        else { canvasH = canvasW / ratio }
                    }
                }()

                let canvasSize = CGSize(width: canvasW, height: canvasH)
                let canvasFrame = aspectFitRect(imageSize: canvasSize, in: proxy.size)

                let totalHPad = canvasW - imgW
                let totalVPad = canvasH - imgH
                let imgXNorm = model.config.alignment.xFactor * totalHPad / canvasW
                let imgYNorm = model.config.alignment.yFactor * totalVPad / canvasH
                let imgWNorm = imgW / canvasW
                let imgHNorm = imgH / canvasH

                let sourceImageFrame = CGRect(
                    x: canvasFrame.minX + imgXNorm * canvasFrame.width,
                    y: canvasFrame.minY + imgYNorm * canvasFrame.height,
                    width: imgWNorm * canvasFrame.width,
                    height: imgHNorm * canvasFrame.height
                )

                let baseRadius = model.config.cornerRadius * shortEdge
                let m = model.config.alignment.cornerMultipliers
                let cornerScale = min(canvasFrame.width / canvasW, canvasFrame.height / canvasH)
                let viewRadii = (
                    tl: baseRadius * m.tl * cornerScale,
                    tr: baseRadius * m.tr * cornerScale,
                    br: baseRadius * m.br * cornerScale,
                    bl: baseRadius * m.bl * cornerScale
                )

                ZStack(alignment: .topLeading) {
                    // Background layer
                    CanvasBackgroundView(style: model.config.style)
                        .frame(width: canvasFrame.width, height: canvasFrame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .position(x: canvasFrame.midX, y: canvasFrame.midY)

                    // Shadow + Screenshot layer
                    CanvasScreenshotView(
                        image: sourceImage,
                        frame: sourceImageFrame,
                        cornerRadii: viewRadii,
                        shadowStrength: model.config.shadowStrength,
                        shortEdge: shortEdge * cornerScale
                    )

                    // Annotations
                    ForEach(model.items) { item in
                        AnnotationItemView(
                            item: item,
                            image: model.previewImage ?? NSImage(),
                            sourceImage: model.sourceImage,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            canvasFrame: canvasFrame,
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
                                model.setTextViewContentSize(size, for: item.id, imageFrame: sourceImageFrame, allowedBounds: model.annotationBounds(for: sourceImageFrame, boundaryFrame: canvasFrame))
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
                            canvasFrame: canvasFrame,
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
                        let viewSel = viewRect(selectionRect, in: sourceImageFrame)
                        AnnotationMarqueeSelectionView()
                            .frame(
                                width: max(viewSel.width, 1),
                                height: max(viewSel.height, 1)
                            )
                            .position(x: viewSel.midX, y: viewSel.midY)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(interactionGesture(imageFrame: sourceImageFrame, boundaryFrame: canvasFrame))
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

// MARK: - SwiftUI Background Layer

private struct CanvasBackgroundView: View {
    let style: BackgroundStyle

    var body: some View {
        switch style {
        case .none:
            TransparencyGrid()

        case .solid(let color):
            Rectangle().fill(color.color)

        case .gradient(let preset):
            Rectangle().fill(preset.swiftUIGradient)

        case .wallpaper(let source):
            if let nsImage = NSImage(contentsOfFile: source.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }

        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }
}

// MARK: - Screenshot Layer with Shadow and Rounded Corners

private struct CanvasScreenshotView: View {
    let image: CGImage
    let frame: CGRect
    let cornerRadii: (tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat)
    let shadowStrength: CGFloat
    let shortEdge: CGFloat

    private var clipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadii.tl,
            bottomLeadingRadius: cornerRadii.bl,
            bottomTrailingRadius: cornerRadii.br,
            topTrailingRadius: cornerRadii.tr,
            style: .continuous
        )
    }

    private var shadowRadius: CGFloat {
        max(2, shortEdge * (0.035 + shadowStrength * 0.035))
    }

    private var shadowOffset: CGFloat {
        shortEdge * (0.012 + shadowStrength * 0.018)
    }

    private var shadowOpacity: Double {
        Double(shadowStrength * 0.36)
    }

    var body: some View {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .clipShape(clipShape)
            .shadow(
                color: shadowStrength > 0 ? .black.opacity(shadowOpacity) : .clear,
                radius: shadowStrength > 0 ? shadowRadius : 0,
                x: 0,
                y: shadowStrength > 0 ? shadowOffset : 0
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

// MARK: - Supporting Types

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
