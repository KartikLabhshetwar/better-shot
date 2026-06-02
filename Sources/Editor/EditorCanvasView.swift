import SwiftUI

/// The main canvas area that shows the screenshot with its background.
struct EditorCanvasView: View {
    @Bindable var model: EditorModel

    var body: some View {
        GeometryReader { proxy in
            if let image = model.sourceImage {
                let displayImage = renderPreview(image: image)
                let nsImage = displayImage.flatMap {
                    NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
                }

                if let nsImage {
                    ZStack {
                        if case .none = model.config.style {
                            TransparencyGrid()
                        }

                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(24)
                            .id(model.sourceURL)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Loading image...", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func renderPreview(image: CGImage) -> CGImage? {
        BeautifierRenderer.render(image: image, config: model.config)
    }
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
