import SwiftUI
import AVKit
import AVFoundation

struct AVPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct VideoEditorView: View {
    @State var model = VideoEditorModel()
    let url: URL

    var body: some View {
        HSplitView {
            videoInspector
                .frame(width: 260)

            VStack(spacing: 0) {
                videoPreview
                    .frame(minWidth: 460, minHeight: 280)

                Divider()

                controlsBar
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                Divider()

                timelineSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.toastMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { model.toastMessage = nil }
                        }
                    }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { model.loadVideo(from: url) }
        .onDisappear { model.cleanup() }
    }

    // MARK: - Inspector Sidebar

    private var videoInspector: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VideoEffectsSection(model: model)

                VideoInspectorDivider()

                VideoCropSection(model: model)

                VideoInspectorDivider()

                VideoBackgroundSection(model: model)

                Spacer(minLength: 20)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Video Preview with Effects

    @ViewBuilder
    private var videoPreview: some View {
        GeometryReader { geo in
            let config = model.config
            let videoAspect: CGFloat = model.videoWidth > 0 && model.videoHeight > 0
                ? CGFloat(model.videoWidth) / CGFloat(model.videoHeight)
                : 16.0 / 9.0

            let shortEdge = min(geo.size.width, geo.size.height) * 0.8
            let videoW = min(geo.size.width * 0.7, shortEdge * videoAspect)
            let videoH = videoW / videoAspect
            let effectivePadding = (config.style != .none && config.padding <= 0) ? CGFloat(0.06) : config.padding
            let pad = min(videoW, videoH) * effectivePadding
            let canvasW = videoW + pad * 2
            let canvasH = videoH + pad * 2
            let cornerRadius = config.cornerRadius * min(videoW, videoH)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ZStack {
                    videoBackground(config.style, size: CGSize(width: canvasW, height: canvasH))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    ZStack {
                        Group {
                            if let player = model.player {
                                AVPlayerRepresentable(player: player)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: videoW, height: videoH)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .shadow(
                            color: config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength) * 0.4) : .clear,
                            radius: config.shadowStrength > 0 ? max(4, 20 * config.shadowStrength) : 0,
                            y: config.shadowStrength > 0 ? max(2, 8 * config.shadowStrength) : 0
                        )

                        if model.isCropping {
                            VideoCropOverlay(cropRect: $model.cropRect, videoSize: CGSize(width: videoW, height: videoH))
                        }
                    }
                }
                .frame(width: canvasW, height: canvasH)
            }
        }
    }

    @ViewBuilder
    private func videoBackground(_ style: BackgroundStyle, size: CGSize) -> some View {
        switch style {
        case .none:
            Color.clear
        case .solid(let color):
            Rectangle().fill(color.color)
        case .gradient(let preset):
            Rectangle().fill(preset.swiftUIGradient)
        case .wallpaper(let source):
            if let nsImage = NSImage(contentsOfFile: source.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle().fill(.quaternary)
            }
        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }

    // MARK: - Transport Controls

    private var controlsBar: some View {
        HStack {
            Text(model.formattedCurrentTime)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50)

            Spacer()

            HStack(spacing: 16) {
                Button { model.stepBackward() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Button { model.stepForward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            Spacer()

            Text(model.formattedDuration)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50)
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 48

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, thumb in
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width / max(1, CGFloat(model.thumbnails.count)), height: height)
                            .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: trimX(model.trimStart, in: width))

                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: width - trimX(model.trimEnd, in: width))
                    .offset(x: trimX(model.trimEnd, in: width))

                trimHandle(time: model.trimStart, in: width, isStart: true)
                trimHandle(time: model.trimEnd, in: width, isStart: false)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height + 8)
                    .offset(x: trimX(model.currentTime, in: width) - 1)
                    .shadow(radius: 1)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let frac = max(0, min(value.location.x / width, 1))
                        let time = frac * model.duration
                        model.seekTo(max(model.trimStart, min(time, model.trimEnd)))
                    }
            )
        }
        .frame(height: 48)
    }

    private func trimHandle(time: Double, in width: CGFloat, isStart: Bool) -> some View {
        let x = trimX(time, in: width)
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.yellow)
            .frame(width: 8, height: 56)
            .offset(x: isStart ? x - 8 : x)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let frac = max(0, min(value.location.x / width, 1))
                        let newTime = frac * model.duration
                        if isStart {
                            model.setTrimStart(newTime)
                        } else {
                            model.setTrimEnd(newTime)
                        }
                    }
            )
    }

    private func trimX(_ time: Double, in width: CGFloat) -> CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(time / model.duration) * width
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button("Cancel") {
                model.cleanup()
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task {
                    model.isExporting = true
                    if await model.exportTrimmed() != nil {
                        let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
                        ToastWindow.shared.show(message: "Recording exported!", icon: appIcon)
                        model.cleanup()
                        NSApp.keyWindow?.close()
                    }
                    model.isExporting = false
                }
            } label: {
                if model.isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Export")
                        .fontWeight(.semibold)
                }
            }
            .disabled(model.isExporting)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Video Effects Section

private struct VideoInspectorSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
    }
}

private struct VideoInspectorDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14)
    }
}

private struct VideoEffectsSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoInspectorSectionHeader("EFFECTS")

            VStack(spacing: 4) {
                HStack {
                    Text("Padding")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(model.config.padding * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $model.config.padding, in: 0.0...0.45)
                    .controlSize(.small)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Corner Radius")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(model.config.cornerRadius * 1000))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $model.config.cornerRadius, in: 0.0...0.12)
                    .controlSize(.small)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Shadow")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(model.config.shadowStrength * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $model.config.shadowStrength, in: 0.0...1.0)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

// MARK: - Video Background Section

private struct VideoBackgroundSection: View {
    @Bindable var model: VideoEditorModel

    private let swatchColumns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoInspectorSectionHeader("BACKGROUND")

            Text("Solid")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: swatchColumns, spacing: 6) {
                noneButton

                ForEach(SolidColor.presets) { color in
                    solidButton(color)
                }
            }

            Text("Gradients")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: swatchColumns, spacing: 6) {
                ForEach(GradientPreset.presets) { preset in
                    gradientButton(preset)
                }
            }

            Text("macOS")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 4), spacing: 6) {
                ForEach(BundledBackgrounds.macAssets) { asset in
                    bundledImageButton(asset)
                }
            }

            customImageSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var noneButton: some View {
        Button {
            model.config.style = .none
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                Path { path in
                    path.move(to: CGPoint(x: 26, y: 2))
                    path.addLine(to: CGPoint(x: 2, y: 26))
                }
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        model.config.style == .none ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: model.config.style == .none ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func solidButton(_ color: SolidColor) -> some View {
        let isSelected: Bool = {
            if case .solid(let c) = model.config.style { return c.id == color.id }
            return false
        }()

        return Button {
            model.config.style = .solid(color)
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.color)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    private func gradientButton(_ preset: GradientPreset) -> some View {
        let isSelected: Bool = {
            if case .gradient(let g) = model.config.style { return g.id == preset.id }
            return false
        }()

        return Button {
            model.config.style = .gradient(preset)
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(preset.swiftUIGradient)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }

    private func bundledImageButton(_ asset: BundledBackgrounds.ImageAsset) -> some View {
        let isSelected: Bool = {
            if case .bundledImage(let id) = model.config.style { return id == asset.id }
            return false
        }()

        return Button {
            model.config.style = .bundledImage(asset.id)
        } label: {
            Group {
                if let image = asset.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 48, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customImageSection: some View {
        if case .wallpaper(let source) = model.config.style {
            HStack(spacing: 6) {
                if let img = NSImage(contentsOfFile: source.path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                }

                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button { pickCustomWallpaper() } label: {
                    Text("Change").font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        } else {
            Button { pickCustomWallpaper() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.caption2)
                    Text("Custom Image...").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Choose Background Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.config.style = .wallpaper(WallpaperSource(path: url.path))
    }
}

// MARK: - Video Crop Section

private struct VideoCropSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoInspectorSectionHeader("CROP")

            HStack {
                Button {
                    model.isCropping.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                            .font(.caption)
                        Text(model.isCropping ? "Done" : "Crop")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(model.isCropping ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(model.isCropping ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: model.isCropping ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(.plain)

                if model.hasCrop {
                    Button {
                        model.resetCrop()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                            Text("Reset")
                                .font(.caption2)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.hasCrop {
                let w = Int(CGFloat(model.videoWidth) * model.cropRect.width)
                let h = Int(CGFloat(model.videoHeight) * model.cropRect.height)
                Text("\(w) × \(h)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

// MARK: - Video Crop Overlay

private struct VideoCropOverlay: View {
    @Binding var cropRect: CGRect
    let videoSize: CGSize

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
        .frame(width: videoSize.width, height: videoSize.height)
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
            .frame(width: videoSize.width, height: videoSize.height)
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

    private func cornerHandle(at point: CGPoint, corner: Corner, size: CGSize) -> some View {
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

    private func edgeHandle(at point: CGPoint, edge: Edge, size: CGSize) -> some View {
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

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum Edge { case top, bottom, left, right }
}
