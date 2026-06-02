import SwiftUI
import UniformTypeIdentifiers

/// Right-hand inspector panel with background, layout, and annotation controls.
struct EditorInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Background
                BackgroundPickerSection(model: model)

                Divider()

                // MARK: - Layout (Alignment + Aspect Ratio)
                LayoutSection(model: model)

                Divider()

                // MARK: - Beautifier Controls
                BeautifierControlsSection(model: model)

                Divider()

                // MARK: - Annotation Tools
                AnnotationToolsSection(model: model)

                Spacer()

                // Save as default
                Button {
                    model.saveConfigAsDefault()
                } label: {
                    Label("Set as Default", systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Background Picker

struct BackgroundPickerSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Background")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Solid colors grid
            Text("Solid")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7), spacing: 6) {
                ForEach(SolidColor.presets) { color in
                    let isSelected: Bool = {
                        if case .solid(let c) = model.config.style { return c.id == color.id }
                        return false
                    }()

                    Button {
                        model.updateConfig { $0.style = .solid(color) }
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
                }

                // None (transparent)
                Button {
                    model.updateConfig { $0.style = .none }
                } label: {
                    TransparencyGrid()
                        .frame(width: 28, height: 28)
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

            // Gradients
            Text("Gradients")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7), spacing: 6) {
                ForEach(GradientPreset.presets) { preset in
                    let isSelected: Bool = {
                        if case .gradient(let g) = model.config.style { return g.id == preset.id }
                        return false
                    }()

                    Button {
                        model.updateConfig { $0.style = .gradient(preset) }
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
            }

            // Bundled image backgrounds (wallpapers, mesh gradients, mac assets)
            ForEach(BundledBackgrounds.Category.allCases, id: \.self) { category in
                let assets = assetsForCategory(category)
                if !assets.isEmpty {
                    Text(category.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 4), spacing: 6) {
                        ForEach(assets) { asset in
                            let isSelected: Bool = {
                                if case .bundledImage(let id) = model.config.style { return id == asset.id }
                                return false
                            }()

                            Button {
                                model.updateConfig { $0.style = .bundledImage(asset.id) }
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
                            .help(asset.filename)
                        }
                    }
                }
            }

            // Custom wallpaper from disk
            Button {
                pickCustomWallpaper()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption2)
                    Text("Custom Image...")
                        .font(.caption2)
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

    private func assetsForCategory(_ category: BundledBackgrounds.Category) -> [BundledBackgrounds.ImageAsset] {
        switch category {
        case .wallpapers: return BundledBackgrounds.wallpapers
        case .gradients: return BundledBackgrounds.gradients
        case .mac: return BundledBackgrounds.macAssets
        }
    }

    private func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            model.updateConfig { $0.style = .wallpaper(WallpaperSource(path: url.path)) }
        }
    }
}

// MARK: - Layout Section

struct LayoutSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Layout")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                // Alignment 3x3 grid
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alignment")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        ForEach(0..<3) { row in
                            GridRow {
                                ForEach(0..<3) { col in
                                    let alignment = alignmentFor(row: row, col: col)
                                    let isSelected = model.config.alignment == alignment

                                    Button {
                                        model.updateConfig { $0.alignment = alignment }
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                                .frame(width: 24, height: 18)

                                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.3))
                                                .frame(width: 8, height: 6)
                                                .offset(
                                                    x: CGFloat(col - 1) * 6,
                                                    y: CGFloat(row - 1) * 4
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(alignment.rawValue)
                                }
                            }
                        }
                    }
                    .padding(4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                // Aspect ratio pills
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ratio")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 2) {
                        ForEach(CanvasAspectRatio.allCases, id: \.self) { ratio in
                            let isSelected = model.config.aspectRatio == ratio
                            Button {
                                model.updateConfig { $0.aspectRatio = ratio }
                            } label: {
                                Text(ratio.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func alignmentFor(row: Int, col: Int) -> ImageAlignment {
        let grid: [[ImageAlignment]] = [
            [.topLeading, .top, .topTrailing],
            [.leading, .center, .trailing],
            [.bottomLeading, .bottom, .bottomTrailing],
        ]
        return grid[row][col]
    }
}

// MARK: - Beautifier Controls

struct BeautifierControlsSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LabeledSlider(
                label: "Padding",
                value: Binding(
                    get: { model.config.padding },
                    set: { model.config.padding = $0 }
                ),
                range: 0.0...0.45,
                format: { "\(Int($0 * 100))%" }
            )

            LabeledSlider(
                label: "Corner Radius",
                value: Binding(
                    get: { model.config.cornerRadius },
                    set: { model.config.cornerRadius = $0 }
                ),
                range: 0.0...0.12,
                format: { "\(Int($0 * 1000))" }
            )

            LabeledSlider(
                label: "Shadow",
                value: Binding(
                    get: { model.config.shadowStrength },
                    set: { model.config.shadowStrength = $0 }
                ),
                range: 0.0...1.0,
                format: { "\(Int($0 * 100))%" }
            )
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: (CGFloat) -> String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(format(value))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

// MARK: - Annotation Tools

struct AnnotationToolsSection: View {
    @Bindable var model: EditorModel

    private let tools: [(AnnotationTool, String, String)] = [
        (.select, "arrow.up.left", "Select"),
        (.rectangle, "rectangle", "Rectangle"),
        (.filledRect, "rectangle.fill", "Filled Rect"),
        (.ellipse, "circle", "Ellipse"),
        (.line, "line.diagonal", "Line"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.freehand, "pencil.tip", "Freehand"),
        (.numberedBadge, "1.circle", "Number"),
        (.pixelate, "square.grid.3x3", "Pixelate"),
        (.blur, "aqi.medium", "Blur"),
        (.text, "textformat", "Text"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6), spacing: 4) {
                ForEach(tools, id: \.0) { tool, icon, label in
                    let isSelected = model.activeTool == tool
                    Button {
                        model.activeTool = tool
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .frame(width: 32, height: 28)
                            .background(
                                isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(label)
                }
            }

            // Color swatches for annotations
            if model.activeTool != .select && model.activeTool != .pixelate && model.activeTool != .blur {
                HStack(spacing: 4) {
                    ForEach(Array(ColorSwatch.presets.enumerated()), id: \.offset) { _, swatch in
                        Circle()
                            .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }
}
