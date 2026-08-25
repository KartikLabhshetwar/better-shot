//
//  AnnotationBackgroundPreviewViews.swift
//  BetterShot
//

import AppKit
import CoreGraphics
import SwiftUI

struct AnnotationBackgroundStageFill: View {
    let style: AnnotationBackgroundStyle

    var body: some View {
        switch style {
        case .none:
            Color.clear

        case .solid(let color):
            color.color

        case .gradient(let gradient):
            LinearGradient(
                colors: gradient.colors.map(\.color),
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )

        case .customWallpaper(let wallpaper):
            AnnotationCustomWallpaperPreview(wallpaper: wallpaper, maxPixelSize: 2048)
        }
    }
}

struct AnnotationWatermarkOverlay: View {
    let settings: AnnotationWatermarkSettings
    let fontScale: CGFloat

    var body: some View {
        Canvas { context, size in
            let rows = max(2, Int(round(settings.density)))
            let spacingY = size.height / CGFloat(rows)
            let spacingX = max(1, spacingY * 2.2)
            let diagonal = hypot(size.width, size.height)
            let columnCount = max(2, Int(ceil(diagonal / spacingX)))
            let rowCount = max(2, Int(ceil(diagonal / spacingY)))
            let originX = size.width / 2 - CGFloat(columnCount) * spacingX / 2
            let originY = size.height / 2 - CGFloat(rowCount) * spacingY / 2
            let label = Text(settings.text)
                .font(AnnotationWatermarkTypography.font(size: settings.fontSize * fontScale))
                .foregroundStyle(settings.color.color.opacity(min(0.75, max(0, settings.opacity))))

            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(Double(settings.rotationDegrees)))
            context.translateBy(x: -size.width / 2, y: -size.height / 2)

            for row in 0...rowCount {
                for column in 0...columnCount {
                    context.draw(
                        label,
                        at: CGPoint(
                            x: originX + CGFloat(column) * spacingX,
                            y: originY + CGFloat(row) * spacingY
                        ),
                        anchor: .center
                    )
                }
            }
        }
    }
}

struct AnnotationCustomWallpaperPreview: View {
    let wallpaper: AnnotationCustomWallpaper
    var maxPixelSize: CGFloat = 900

    @State private var image: CGImage?
    @State private var isLoading = true
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else if didFail {
                Color.black
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        .task(id: cacheID) {
            await loadImage()
        }
    }

    private var cacheID: String {
        AnnotationWallpaperPreviewCache.cacheID(for: wallpaper.url, maxPixelSize: maxPixelSize)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        isLoading = true
        didFail = false

        let loadedImage = await AnnotationWallpaperPreviewCache.shared.image(
            for: wallpaper.url,
            maxPixelSize: maxPixelSize
        )

        guard !Task.isCancelled else { return }
        image = loadedImage
        didFail = loadedImage == nil
        isLoading = false
    }
}
