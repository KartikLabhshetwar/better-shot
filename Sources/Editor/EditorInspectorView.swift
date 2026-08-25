import SwiftUI
import UniformTypeIdentifiers

struct EditorInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                annotationSections
                InspectorDivider()
                ImageCropSection(model: model)
                InspectorDivider()
                EffectsSection(config: configBinding, onEditingChanged: model.recordConfigEdit)
                InspectorDivider()
                ImageColorSection(config: configBinding, source: model.sourceImage, onEditingChanged: model.recordConfigEdit)
                InspectorDivider()
                LayoutSection(config: configBinding, onEditingChanged: model.recordConfigEdit)
                InspectorDivider()
                BackgroundPickerSection(config: configBinding, onEditingChanged: model.recordConfigEdit)

                Spacer(minLength: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .background(InspectorMaterial())
    }

    @ViewBuilder
    private var annotationSections: some View {
        InspectorSection("Tools") {
            AnnotationInspectorToolGrid(selectedTool: model.selectedTool) { tool in
                model.selectTool(tool)
            }
        }

        if !model.items.isEmpty {
            InspectorPill("Clear All", systemImage: "trash", role: .destructive, fillsWidth: true) {
                model.clearAnnotations()
            }
            .padding(.horizontal, InspectorMetrics.gutter)
            .padding(.bottom, InspectorMetrics.gutter)
        }

        if model.inspectedTool != nil {
            InspectorDivider()

            InspectorSection("Style") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.selectionCount > 1 {
                        InspectorCaption("\(model.selectionCount) annotations selected")
                    }

                    InspectorRow("Color") {
                        AnnotationColorMenu(selectedSwatch: model.selectedSwatch) { swatch in
                            model.setSwatch(swatch)
                        }
                    }

                    if model.isStrokeStyleAvailable {
                        InspectorRow("Stroke") {
                            AnnotationStrokeMenu(strokeWidth: model.strokeWidth) { strokeWidth in
                                model.setStrokeWidth(strokeWidth)
                            }
                        }
                    }

                    if model.isRedactionStyleAvailable {
                        InspectorSlider(
                            "Density",
                            value: Binding(
                                get: { model.redactionDensity },
                                set: { model.setRedactionDensity($0) }
                            ),
                            range: 0.15...1,
                            format: .percent()
                        )
                    }
                }
            }
        }

        if model.isTextStyleAvailable {
            InspectorDivider()

            InspectorSection("Text") {
                AnnotationTextStyleControls(model: model)
            }
        }
    }

    private var configBinding: Binding<BeautifierConfig> {
        Binding(get: { model.config }, set: { model.config = $0 })
    }
}

private struct AnnotationInspectorToolGrid: View {
    let selectedTool: AnnotationTool
    let onSelect: (AnnotationTool) -> Void

    @State private var hoveredTool: AnnotationTool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 2), count: 5
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(AnnotationTool.toolbarCases) { tool in
                toolButton(tool)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : InspectorMotion.press, value: selectedTool)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = selectedTool == tool

        return Button {
            onSelect(tool)
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .overlay(alignment: .bottomTrailing) {
                    Text(String(tool.shortcut).uppercased())
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 3)
                        .padding(.bottom, 2)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : (hoveredTool == tool ? Color.primary.opacity(0.07) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.72))
        .onHover { hoveredTool = $0 ? tool : nil }
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help("\(tool.title) (\(String(tool.shortcut).uppercased()))")
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .inspectorField()
        }
        .buttonStyle(.inspectorPress(scale: 0.98))
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
            .inspectorField()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fontFamilies: [String] = {
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
            ForEach(Self.fontFamilies, id: \.self) { family in
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .inspectorField()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            stepperButton("minus") { adjustFontSize(by: -1) }

            Divider().frame(height: 14)

            TextField("", text: $fontSizeText)
                .focused($isFontSizeFieldFocused)
                .onSubmit(commitFontSizeText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 32)

            Divider().frame(height: 14)

            stepperButton("plus") { adjustFontSize(by: 1) }
        }
        .inspectorField(isFocused: isFontSizeFieldFocused)
    }

    private func stepperButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.inspectorPress(scale: 0.85))
        .foregroundStyle(.secondary)
        .accessibilityLabel(icon == "plus" ? "Increase font size" : "Decrease font size")
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
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func styleToggle(_ label: String, isActive: Bool, font: Font, underline: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .underline(underline)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background { if isActive { Capsule().fill(Color.accentColor) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
        .animation(reduceMotion ? nil : InspectorMotion.press, value: isActive)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var textAlignmentControl: some View {
        HStack(spacing: 0) {
            alignmentButton(.left, "text.alignleft")
            alignmentButton(.center, "text.aligncenter")
            alignmentButton(.right, "text.alignright")
            alignmentButton(.justified, "text.justify.leading")
        }
        .padding(3)
        .frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func alignmentButton(_ alignment: NSTextAlignment, _ icon: String) -> some View {
        let isSelected = model.selectedTextAlignment == alignment
        return Button {
            model.selectedTextAlignment = alignment
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background { if isSelected { Capsule().fill(Color.accentColor) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
        .animation(reduceMotion ? nil : InspectorMotion.press, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
        .buttonStyle(.inspectorPress(scale: 0.9))
        .accessibilityLabel("Text color: \(selectedSwatch.title)")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            AnnotationColorPopover(
                selectedSwatch: selectedSwatch,
                onSelect: { swatch in onSelect(swatch); isPresented = false },
                onCustomSelect: onSelect
            )
        }
    }
}

private struct ImageCropSection: View {
    @Bindable var model: EditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Crop", collapsedByDefault: true) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isCropping {
                    InspectorCaption("Drag the frame on the canvas, then press Done.")
                } else {
                    HStack(spacing: 6) {
                        InspectorPill("Crop Image", systemImage: "crop", fillsWidth: true) {
                            withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.beginCrop() }
                        }

                        if model.hasCrop {
                            InspectorPill("Reset", systemImage: "arrow.counterclockwise") {
                                withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.resetCrop() }
                            }
                        }
                    }

                    Text("\(model.sourceImage?.width ?? 0) x \(model.sourceImage?.height ?? 0) px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}
