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
                    .allowsHitTesting(!model.isCropping)

                    if model.isCropping {
                        ImageCropOverlay(cropRect: $model.cropRect, imageSize: CGSize(width: sourceImageFrame.width, height: sourceImageFrame.height))
                            .position(x: sourceImageFrame.midX, y: sourceImageFrame.midY)
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

// MARK: - Image Crop Overlay

private struct ImageCropOverlay: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize

    private let handleSize: CGFloat = 10
    private let minCropFraction: CGFloat = 0.1
    @State private var startRect: CGRect = .zero

    var body: some View {
        Canvas { context, size in
            let crop = pixelRect(in: size)

            var dimPath = Path()
            dimPath.addRect(CGRect(origin: .zero, size: size))
            dimPath.addRect(crop)
            context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

            let border = crop.insetBy(dx: -1, dy: -1)
            context.stroke(Path(border), with: .color(.white), lineWidth: 1.5)

            let dashes: [CGFloat] = [4, 4]
            let thirdW = crop.width / 3
            let thirdH = crop.height / 3
            for i in 1...2 {
                var vLine = Path()
                vLine.move(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.minY))
                vLine.addLine(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.maxY))
                context.stroke(vLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))

                var hLine = Path()
                hLine.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH * CGFloat(i)))
                hLine.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH * CGFloat(i)))
                context.stroke(hLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))
            }
        }
        .allowsHitTesting(false)
        .frame(width: imageSize.width, height: imageSize.height)
        .overlay {
            GeometryReader { geo in
                let size = geo.size
                let crop = pixelRect(in: size)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .gesture(dragGesture(size: size))

                cornerHandle(at: CGPoint(x: crop.minX, y: crop.minY), corner: .topLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.minY), corner: .topRight, size: size)
                cornerHandle(at: CGPoint(x: crop.minX, y: crop.maxY), corner: .bottomLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.maxY), corner: .bottomRight, size: size)

                edgeHandle(at: CGPoint(x: crop.midX, y: crop.minY), edge: .top, size: size)
                edgeHandle(at: CGPoint(x: crop.midX, y: crop.maxY), edge: .bottom, size: size)
                edgeHandle(at: CGPoint(x: crop.minX, y: crop.midY), edge: .left, size: size)
                edgeHandle(at: CGPoint(x: crop.maxX, y: crop.midY), edge: .right, size: size)
            }
            .frame(width: imageSize.width, height: imageSize.height)
        }
    }

    private func pixelRect(in size: CGSize) -> CGRect {
        CGRect(
            x: cropRect.origin.x * size.width,
            y: cropRect.origin.y * size.height,
            width: cropRect.width * size.width,
            height: cropRect.height * size.height
        )
    }

    private func cornerHandle(at point: CGPoint, corner: CropCorner, size: CGSize) -> some View {
        Circle()
            .fill(.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch corner {
                        case .topLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.x = max(0, newX)
                            r.origin.y = max(0, newY)
                        case .topRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottomLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .bottomRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        }
                        cropRect = r
                    }
            )
    }

    private func edgeHandle(at point: CGPoint, edge: CropEdge, size: CGSize) -> some View {
        Capsule()
            .fill(.white)
            .frame(
                width: edge == .top || edge == .bottom ? 24 : 6,
                height: edge == .left || edge == .right ? 24 : 6
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch edge {
                        case .top:
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottom:
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .left:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                        case .right:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                        }
                        cropRect = r
                    }
            )
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if startRect == .zero { startRect = cropRect }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                var r = startRect
                r.origin.x = max(0, min(1 - r.width, startRect.origin.x + dx))
                r.origin.y = max(0, min(1 - r.height, startRect.origin.y + dy))
                cropRect = r
            }
            .onEnded { _ in startRect = .zero }
    }

    private enum CropCorner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum CropEdge { case top, bottom, left, right }
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
