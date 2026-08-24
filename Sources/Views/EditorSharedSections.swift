import AppKit
import SwiftUI

/// Brackets a discrete config change so undo collapses it into one step.
private func editConfig(
    _ config: Binding<BeautifierConfig>,
    _ onEditingChanged: ((Bool) -> Void)?,
    _ mutate: (inout BeautifierConfig) -> Void
) {
    onEditingChanged?(true)
    mutate(&config.wrappedValue)
    onEditingChanged?(false)
}

struct EffectsSection: View {
    @Binding var config: BeautifierConfig
    var onEditingChanged: ((Bool) -> Void)?

    var body: some View {
        InspectorSection("Effects") {
            VStack(alignment: .leading, spacing: 10) {
                InspectorSlider(
                    "Padding",
                    value: $config.padding,
                    range: 0.0...0.45,
                    format: .percent(),
                    onEditingChanged: onEditingChanged
                )

                InspectorSlider(
                    "Corner Radius",
                    value: $config.cornerRadius,
                    range: 0.0...0.12,
                    format: .scaled(by: 1000),
                    onEditingChanged: onEditingChanged
                )

                InspectorSlider(
                    "Shadow",
                    value: $config.shadowStrength,
                    range: 0.0...1.0,
                    format: .percent(),
                    onEditingChanged: onEditingChanged
                )
            }
        }
    }
}

struct LayoutSection: View {
    @Binding var config: BeautifierConfig
    var onEditingChanged: ((Bool) -> Void)?
    var showsAlignment = true

    var body: some View {
        InspectorSection("Layout", collapsedByDefault: true) {
            VStack(alignment: .leading, spacing: 10) {
                InspectorRow("Ratio") {
                    InspectorMenuField(
                        values: CanvasAspectRatio.allCases,
                        selection: Binding(
                            get: { config.aspectRatio },
                            set: { ratio in editConfig($config, onEditingChanged) { $0.aspectRatio = ratio } }
                        ),
                        label: \.rawValue
                    )
                }

                if showsAlignment {
                    HStack(alignment: .top, spacing: 10) {
                        Text("Align")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                            .padding(.top, 8)

                        AlignmentGridPicker(selection: Binding(
                            get: { config.alignment },
                            set: { alignment in editConfig($config, onEditingChanged) { $0.alignment = alignment } }
                        ))
                    }
                }
            }
        }
    }
}

private struct AlignmentGridPicker: View {
    @Binding var selection: ImageAlignment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rows: [[ImageAlignment]] = [
        [.topLeading, .top, .topTrailing],
        [.leading, .center, .trailing],
        [.bottomLeading, .bottom, .bottomTrailing],
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { alignment in
                        cell(alignment)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : InspectorMotion.press, value: selection)
    }

    private func cell(_ alignment: ImageAlignment) -> some View {
        let isSelected = selection == alignment

        return Button {
            selection = alignment
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)

                Circle()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.24))
                    .frame(width: isSelected ? 9 : 6, height: isSelected ? 9 : 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .accessibilityLabel(alignment.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct BackgroundPickerSection: View {
    @Binding var config: BeautifierConfig
    var onEditingChanged: ((Bool) -> Void)?

    private let swatchColumns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 7)
    private let imageColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        InspectorSection("Background") {
            VStack(alignment: .leading, spacing: 12) {
                group("Solid") {
                    LazyVGrid(columns: swatchColumns, spacing: 6) {
                        noneButton
                        ForEach(SolidColor.presets) { solidButton($0) }
                    }
                }

                group("Gradients") {
                    LazyVGrid(columns: swatchColumns, spacing: 6) {
                        ForEach(GradientPreset.presets) { gradientButton($0) }
                    }
                }

                group("macOS") {
                    LazyVGrid(columns: imageColumns, spacing: 6) {
                        ForEach(BundledBackgrounds.macAssets) { bundledImageButton($0) }
                    }
                }

                customImageSection
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func select(_ style: BackgroundStyle) {
        editConfig($config, onEditingChanged) { $0.style = style }
    }

    private var noneButton: some View {
        let isSelected = config.style == .none

        return Button {
            select(.none)
        } label: {
            ZStack {
                Color.white
                Path { path in
                    path.move(to: CGPoint(x: 26, y: 2))
                    path.addLine(to: CGPoint(x: 2, y: 26))
                }
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
            .frame(width: 28, height: 28)
            .inspectorSwatch(isSelected: isSelected)
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .accessibilityLabel("No background")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help("No background")
    }

    private func solidButton(_ color: SolidColor) -> some View {
        let isSelected: Bool = {
            if case .solid(let existing) = config.style { return existing.id == color.id }
            return false
        }()

        return Button {
            select(.solid(color))
        } label: {
            color.color
                .frame(width: 28, height: 28)
                .inspectorSwatch(isSelected: isSelected)
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(color.name)
    }

    private func gradientButton(_ preset: GradientPreset) -> some View {
        let isSelected: Bool = {
            if case .gradient(let existing) = config.style { return existing.id == preset.id }
            return false
        }()

        return Button {
            select(.gradient(preset))
        } label: {
            Rectangle()
                .fill(preset.swiftUIGradient)
                .frame(width: 28, height: 28)
                .inspectorSwatch(isSelected: isSelected)
        }
        .buttonStyle(.inspectorPress(scale: 0.9))
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(preset.name)
    }

    private func bundledImageButton(_ asset: BundledBackgrounds.ImageAsset) -> some View {
        let isSelected: Bool = {
            if case .bundledImage(let id) = config.style { return id == asset.id }
            return false
        }()

        return Button {
            select(.bundledImage(asset.id))
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
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .inspectorSwatch(isSelected: isSelected)
        }
        .buttonStyle(.inspectorPress(scale: 0.94))
        .accessibilityLabel(asset.id)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var customImageSection: some View {
        if case .wallpaper(let source) = config.style {
            HStack(spacing: 8) {
                if let image = ImageCache.shared.image(atPath: source.path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .inspectorSwatch(isSelected: true)
                }

                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                InspectorPill("Change", action: pickCustomWallpaper)
            }
        } else {
            Button(action: pickCustomWallpaper) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Custom Image")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .foregroundStyle(.secondary)
                .background(
                    RoundedRectangle(cornerRadius: InspectorMetrics.fieldRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: InspectorMetrics.fieldRadius, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.inspectorPress)
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
        select(.wallpaper(WallpaperSource(path: url.path)))
    }
}
