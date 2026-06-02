import SwiftUI

struct EditorCanvasView: View {
    @Bindable var model: EditorModel
    @State private var cachedPreview: NSImage?
    @State private var renderTask: Task<Void, Never>?

    private var previewAspectRatio: CGFloat {
        guard let preview = cachedPreview else { return 1.0 }
        guard preview.size.height > 0 else { return 1.0 }
        return preview.size.width / preview.size.height
    }

    var body: some View {
        GeometryReader { _ in
            if model.sourceImage != nil {
                ZStack {
                    if case .none = model.config.style {
                        TransparencyGrid()
                    }

                    if let preview = cachedPreview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(24)
                            .overlay {
                                if model.activeTool.createsAnnotation {
                                    AnnotationGestureView(model: model, imageAspectRatio: previewAspectRatio)
                                        .padding(24)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Loading image...", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.config, initial: true) { _, _ in scheduleRender() }
        .onChange(of: model.sourceImage) { _, _ in scheduleRender() }
        .onChange(of: model.annotations) { _, _ in scheduleRender() }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            guard let source = model.sourceImage else { return }

            let config = model.config
            let annotations = model.annotations

            let result = await Task.detached(priority: .userInitiated) {
                renderPreview(image: source, config: config, annotations: annotations)
            }.value

            guard !Task.isCancelled, let cgImage = result else { return }
            cachedPreview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}

private func renderPreview(image: CGImage, config: BeautifierConfig, annotations: [AnnotationItem] = []) -> CGImage? {
    let maxDim: CGFloat = 2400
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
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let scaled = ctx.makeImage() else { return nil }
        previewImage = scaled
    }

    return BeautifierRenderer.render(image: previewImage, config: config, annotations: annotations)
}

// MARK: - Transparency Grid

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
    }
}
