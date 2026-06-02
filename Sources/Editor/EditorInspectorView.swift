import SwiftUI
import UniformTypeIdentifiers

struct EditorInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Tools
                    VStack(alignment: .leading, spacing: 10) {
                        InspectorSectionHeader("TOOLS")
                        AnnotationInspectorToolGrid(selectedTool: model.selectedTool) { tool in
                            model.selectTool(tool)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                    if !model.items.isEmpty {
                        Button(role: .destructive) {
                            model.clearAnnotations()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }

                    if model.inspectedTool != nil {
                        InspectorDivider()

                        // MARK: Style
                        VStack(alignment: .leading, spacing: 10) {
                            InspectorSectionHeader("STYLE")

                            if model.selectionCount > 1 {
                                Text("\(model.selectionCount) annotations selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            InspectorRow(title: "Color") {
                                AnnotationColorMenu(selectedSwatch: model.selectedSwatch) { swatch in
                                    model.setSwatch(swatch)
                                }
                            }

                            if model.isStrokeStyleAvailable {
                                InspectorRow(title: "Stroke") {
                                    AnnotationStrokeMenu(strokeWidth: model.strokeWidth) { strokeWidth in
                                        model.setStrokeWidth(strokeWidth)
                                    }
                                }
                            }

                            if model.isRedactionStyleAvailable {
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Density")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Text("\(Int(model.redactionDensity * 100))%")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Slider(
                                        value: Binding(
                                            get: { model.redactionDensity },
                                            set: { model.setRedactionDensity($0) }
                                        ),
                                        in: 0.15...1
                                    )
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }

                    if model.isTextStyleAvailable {
                        InspectorDivider()

                        // MARK: Text
                        VStack(alignment: .leading, spacing: 10) {
                            InspectorSectionHeader("TEXT")
                            AnnotationTextStyleControls(model: model)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }

                    InspectorDivider()

                    // MARK: Effects
                    BeautifierControlsSection(model: model)

                    InspectorDivider()

                    // MARK: Background
                    BackgroundPickerSection(model: model)

                    Spacer(minLength: 20)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Inspector Components

private struct InspectorSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
    }
}

private struct InspectorDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14)
    }
}

private struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AnnotationInspectorToolGrid: View {
    let selectedTool: AnnotationTool
    let onSelect: (AnnotationTool) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 2), count: 6
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    onSelect(tool)
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTool == tool ? Color.accentColor : .primary.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedTool == tool ? Color.accentColor.opacity(0.15) : .clear)
                )
                .help(tool.title)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Color Menu

private struct AnnotationColorMenu: View {
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(selectedSwatch.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))

                Text(selectedSwatch.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            AnnotationColorPopover(
                selectedSwatch: selectedSwatch,
                onSelect: { swatch in onSelect(swatch); isPresented = false },
                onCustomSelect: onSelect
            )
        }
    }
}

private struct AnnotationColorPopover: View {
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void
    let onCustomSelect: (AnnotationSwatch) -> Void

    private var customColor: Binding<Color> {
        Binding(
            get: { selectedSwatch.color },
            set: { onCustomSelect(.custom(from: $0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(AnnotationSwatch.allCases) { swatch in
                Button {
                    onSelect(swatch)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))
                            .overlay {
                                if selectedSwatch == swatch {
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.38), lineWidth: 6)
                                        .frame(width: 32, height: 32)
                                }
                            }
                        Text(swatch.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .background {
                        if selectedSwatch == swatch {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 4)

            ColorPicker(selection: customColor, supportsOpacity: false) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        ))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
                    Text("Custom")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .padding(8)
        .frame(width: 172)
    }
}

// MARK: - Stroke Menu

private struct AnnotationStrokeMenu: View {
    let strokeWidth: CGFloat
    let onSelect: (CGFloat) -> Void
    private let widths: [CGFloat] = [2, 4, 6, 8, 12]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                StrokePreview(width: strokeWidth)
                    .frame(width: 30, height: 16)

                Text("\(Int(strokeWidth))px")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(minWidth: 28, alignment: .leading)

                Spacer(minLength: 10)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(spacing: 7) {
                ForEach(widths, id: \.self) { width in
                    Button {
                        onSelect(width)
                        isPresented = false
                    } label: {
                        ZStack {
                            if strokeWidth == width {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            }
                            StrokePreview(width: width, color: strokeWidth == width ? Color.accentColor : Color.primary.opacity(0.58))
                                .frame(width: 48, height: 32)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .frame(width: 92)
        }
    }
}

private struct StrokePreview: View {
    let width: CGFloat
    var color: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width * 0.24, y: proxy.size.height * 0.68))
                path.addLine(to: CGPoint(x: proxy.size.width * 0.76, y: proxy.size.height * 0.32))
            }
            .stroke(color, style: StrokeStyle(lineWidth: min(width, 7), lineCap: .round))
        }
    }
}

// MARK: - Text Style Controls

private struct AnnotationTextStyleControls: View {
    @Bindable var model: EditorModel
    @State private var fontSizeText = ""
    @FocusState private var isFontSizeFieldFocused: Bool

    private let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                fontFamilyMenu
                    .frame(minWidth: 0, maxWidth: .infinity)

                AnnotationColorWellMenu(selectedSwatch: model.selectedSwatch) { swatch in
                    model.setSwatch(swatch)
                }
            }

            HStack(spacing: 6) {
                fontSizeStepper
                Spacer()
                textStyleToggles
                    .frame(width: 96)
            }

            textAlignmentControl
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: syncFontSizeText)
        .onChange(of: model.selectedTextFontSize) { _, _ in
            guard !isFontSizeFieldFocused else { return }
            syncFontSizeText()
        }
        .onChange(of: model.selectedItemID) { _, _ in
            guard !isFontSizeFieldFocused else { return }
            syncFontSizeText()
        }
        .onChange(of: isFontSizeFieldFocused) { _, isFocused in
            if isFocused { syncFontSizeText() } else { commitFontSizeText() }
        }
    }

    private var fontFamilyMenu: some View {
        Menu {
            ForEach(fontFamilies, id: \.self) { family in
                Button {
                    model.selectedTextFontName = family
                } label: {
                    if model.selectedTextFontName == family {
                        Label(family, systemImage: "checkmark")
                    } else {
                        Text(family)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.selectedTextFontName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            Button { adjustFontSize(by: -1) } label: {
                Image(systemName: "minus").font(.system(size: 10, weight: .medium)).frame(width: 22, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)

            Divider().frame(height: 14)

            TextField("", text: $fontSizeText)
                .focused($isFontSizeFieldFocused)
                .onSubmit(commitFontSizeText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 32)

            Divider().frame(height: 14)

            Button { adjustFontSize(by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .medium)).frame(width: 22, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private var textStyleToggles: some View {
        HStack(spacing: 0) {
            styleToggle("B", isActive: model.selectedTextIsBold, font: .system(size: 12, weight: .bold)) {
                model.selectedTextIsBold.toggle()
            }
            styleToggle("I", isActive: model.selectedTextIsItalic, font: .system(size: 12, weight: .regular, design: .serif).italic()) {
                model.selectedTextIsItalic.toggle()
            }
            styleToggle("U", isActive: model.selectedTextIsUnderline, font: .system(size: 12, weight: .regular), underline: true) {
                model.selectedTextIsUnderline.toggle()
            }
        }
        .padding(3)
        .frame(height: 34)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.65)))
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5))
    }

    private func styleToggle(_ label: String, isActive: Bool, font: Font, underline: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .underline(underline)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .background { if isActive { Capsule().fill(Color.accentColor) } }
    }

    private var textAlignmentControl: some View {
        HStack(spacing: 0) {
            alignmentButton(.left, "text.alignleft")
            alignmentButton(.center, "text.aligncenter")
            alignmentButton(.right, "text.alignright")
            alignmentButton(.justified, "text.justify.leading")
        }
        .padding(3)
        .frame(height: 34)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.65)))
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5))
    }

    private func alignmentButton(_ alignment: NSTextAlignment, _ icon: String) -> some View {
        let isSelected = model.selectedTextAlignment == alignment
        return Button {
            model.selectedTextAlignment = alignment
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background { if isSelected { Capsule().fill(Color.accentColor) } }
    }

    private func syncFontSizeText() {
        fontSizeText = String(Int(model.selectedTextFontSize.rounded()))
    }

    private func commitFontSizeText() {
        let trimmedText = fontSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let size = Double(trimmedText) else { syncFontSizeText(); return }
        let clampedSize = max(size.rounded(), Double(AnnotationTextMetrics.minimumFontSize))
        model.selectedTextFontSize = CGFloat(clampedSize)
        fontSizeText = String(Int(clampedSize))
    }

    private func adjustFontSize(by delta: CGFloat) {
        commitFontSizeText()
        let size = max(model.selectedTextFontSize + delta, AnnotationTextMetrics.minimumFontSize)
        model.selectedTextFontSize = size
        syncFontSizeText()
    }
}

private struct AnnotationColorWellMenu: View {
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(selectedSwatch.color)
                .frame(width: 28, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            AnnotationColorPopover(
                selectedSwatch: selectedSwatch,
                onSelect: { swatch in onSelect(swatch); isPresented = false },
                onCustomSelect: onSelect
            )
        }
    }
}

// MARK: - Background Picker

struct BackgroundPickerSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorSectionHeader("BACKGROUND")

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

            Button {
                pickCustomWallpaper()
            } label: {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
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

// MARK: - Beautifier Controls

struct BeautifierControlsSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSectionHeader("EFFECTS")

            LabeledSlider(
                label: "Padding",
                value: Binding(get: { model.config.padding }, set: { model.config.padding = $0 }),
                range: 0.0...0.45,
                format: { "\(Int($0 * 100))%" }
            )

            LabeledSlider(
                label: "Corner Radius",
                value: Binding(get: { model.config.cornerRadius }, set: { model.config.cornerRadius = $0 }),
                range: 0.0...0.12,
                format: { "\(Int($0 * 1000))" }
            )

            LabeledSlider(
                label: "Shadow",
                value: Binding(get: { model.config.shadowStrength }, set: { model.config.shadowStrength = $0 }),
                range: 0.0...1.0,
                format: { "\(Int($0 * 100))%" }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
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
