//
//  AnnotationBackgroundInspector.swift
//  BetterShot
//

import AppKit
import SwiftUI

private enum AnnotationBackgroundFillLibrary: CaseIterable, Hashable {
    case color
    case gradient
    case wallpaper

    var title: String {
        switch self {
        case .color: "Color"
        case .gradient: "Gradient"
        case .wallpaper: "Wallpaper"
        }
    }
}

struct AnnotationBackgroundInspector: View {
    @Binding var settings: AnnotationBackgroundSettings
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
    @State private var selectedFillLibrary = AnnotationBackgroundFillLibrary.color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Fill library")

                InspectorSegmented(
                    options: AnnotationBackgroundFillLibrary.allCases,
                    isSelected: { $0 == selectedFillLibrary },
                    onTap: { library in
                        withAnimation(.snappy(duration: 0.16)) {
                            selectedFillLibrary = library
                        }
                    },
                    label: { library in
                        Text(library.title)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                )
            }

            selectedFillPicker
                .transition(.opacity)

            innerDivider

            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Layout")

                VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                    InspectorSlider(
                        "Padding",
                        value: $settings.padding,
                        range: 0.04...0.45,
                        format: .percent()
                    )

                    InspectorSlider(
                        "Shadow",
                        value: $settings.shadow,
                        range: 0...1,
                        format: .percent()
                    )

                    InspectorSlider(
                        "Corners",
                        value: $settings.cornerRadius,
                        range: 0...0.12,
                        format: .percent()
                    )
                }
            }

            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Shadow style")

                InspectorSegmented(
                    options: AnnotationShadowStyle.allCases,
                    isSelected: { $0 == settings.shadowStyle },
                    onTap: {
                        onEditorAction()
                        settings.shadowStyle = $0
                    },
                    label: { style in
                        Text(style.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                )
            }
            .opacity(settings.shadow > 0 ? 1 : 0.45)

            InspectorRow("Alignment") {
                AlignmentPositionPicker(
                    alignment: $settings.alignment,
                    isEnabled: !settings.camera.hasEffect,
                    onEditorAction: onEditorAction
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                InspectorGroupLabel("Aspect ratio")

                InspectorSegmented(
                    options: AnnotationBackgroundAspectRatio.allCases,
                    isSelected: { $0 == settings.aspectRatio },
                    onTap: {
                        onEditorAction()
                        settings.aspectRatio = $0
                    },
                    label: { ratio in
                        Text(ratio.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                )
            }
        }
        .onAppear {
            syncFillLibrary(with: settings.style)
        }
        .onChange(of: settings.style) { _, style in
            syncFillLibrary(with: style)
        }
    }

    private var innerDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.4))
            .frame(height: 0.5)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private var selectedFillPicker: some View {
        switch selectedFillLibrary {
        case .color:
            LazyVGrid(columns: swatchColumns, spacing: 6) {
                ForEach(AnnotationBackgroundColor.plainPresets) { color in
                    InspectorTile(isSelected: settings.style == .solid(color)) {
                        onEditorAction()
                        settings.style = .solid(color)
                    } content: {
                        Rectangle().fill(color.color)
                    }
                    .help(color.title)
                }
            }

        case .gradient:
            LazyVGrid(columns: swatchColumns, spacing: 6) {
                ForEach(AnnotationBackgroundGradient.presets) { gradient in
                    InspectorTile(isSelected: settings.style == .gradient(gradient)) {
                        onEditorAction()
                        settings.style = .gradient(gradient)
                    } content: {
                        Rectangle().fill(LinearGradient(
                            colors: gradient.colors.map(\.color),
                            startPoint: gradient.startPoint,
                            endPoint: gradient.endPoint
                        ))
                    }
                    .help(gradient.title)
                }
            }

        case .wallpaper:
            AnnotationWallpaperLibraryPicker(
                wallpaperStore: wallpaperStore,
                selected: selectedWallpaper,
                onSelect: { wallpaper in
                    onEditorAction()
                    wallpaperStore.addRecentWallpaper(wallpaper.url)
                    settings.customWallpaper = wallpaper
                    settings.style = .customWallpaper(wallpaper)
                },
                onPickCustom: {
                    onEditorAction()
                    onPickWallpaper()
                },
                onInteract: onEditorAction
            )
        }
    }

    private var selectedWallpaper: AnnotationCustomWallpaper? {
        guard case .customWallpaper(let wallpaper) = settings.style else { return nil }
        return wallpaper
    }

    private func syncFillLibrary(with style: AnnotationBackgroundStyle) {
        switch style {
        case .none:
            break
        case .solid:
            selectedFillLibrary = .color
        case .gradient:
            selectedFillLibrary = .gradient
        case .customWallpaper:
            selectedFillLibrary = .wallpaper
        }
    }

}

struct AnnotationWallpaperLibraryPicker: View {
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let selected: AnnotationCustomWallpaper?
    let onSelect: (AnnotationCustomWallpaper) -> Void
    let onPickCustom: () -> Void
    var onInteract: () -> Void = {}

    @State private var selectedWallpaperSourceID = AnnotationWallpaperSource.recentID
    private static let maxVisibleRecentWallpapers = 4
    private let recentWallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorSegmented(
                options: wallpaperSources.map(\.id),
                isSelected: { $0 == selectedWallpaperSourceID },
                onTap: { id in
                    onInteract()
                    withAnimation(.snappy(duration: 0.16)) {
                        selectedWallpaperSourceID = id
                    }
                },
                label: { id in
                    Text(title(forSourceID: id))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            )

            if selectedWallpaperSourceID == AnnotationWallpaperSource.recentID {
                recentWallpaperGrid
            } else {
                wallpaperGrid(BundledBackgrounds.macWallpapers)
            }
        }
    }

    private var wallpaperSources: [AnnotationWallpaperSourceOption] {
        [AnnotationWallpaperSourceOption.recent, AnnotationWallpaperSourceOption.mac]
    }

    private func title(forSourceID id: String) -> String {
        wallpaperSources.first { $0.id == id }?.title ?? id
    }

    private var visibleRecentWallpapers: [AnnotationCustomWallpaper] {
        var wallpapers = wallpaperStore.recentWallpapers
        if let selected, wallpaperStore.isAvailable(selected) {
            let selectedURL = selected.url.standardizedFileURL
            if let selectedIndex = wallpapers.firstIndex(where: {
                $0.url.standardizedFileURL == selectedURL
            }) {
                if selectedIndex >= Self.maxVisibleRecentWallpapers {
                    wallpapers.remove(at: selectedIndex)
                    wallpapers.insert(selected, at: 0)
                }
            } else {
                wallpapers.insert(selected, at: 0)
            }
        }
        return Array(wallpapers.prefix(Self.maxVisibleRecentWallpapers))
    }

    private var recentWallpaperGrid: some View {
        LazyVGrid(columns: recentWallpaperColumns, spacing: 6) {
            wallpaperTiles(visibleRecentWallpapers)

            AnnotationAddWallpaperTile(action: onPickCustom)
                .help("Choose wallpaper")
        }
    }

    @ViewBuilder
    private func wallpaperGrid(_ wallpapers: [AnnotationCustomWallpaper]) -> some View {
        LazyVGrid(columns: wallpaperColumns, spacing: 7) {
            wallpaperTiles(wallpapers)
        }
    }

    @ViewBuilder
    private func wallpaperTiles(_ wallpapers: [AnnotationCustomWallpaper]) -> some View {
        ForEach(wallpapers) { wallpaper in
            InspectorTile(
                aspectRatio: 1.35,
                isSelected: isSelectedWallpaper(wallpaper)
            ) {
                onSelect(wallpaper)
            } content: {
                AnnotationCustomWallpaperPreview(wallpaper: wallpaper)
            }
            .help(wallpaper.title)
        }
    }

    private func isSelectedWallpaper(_ wallpaper: AnnotationCustomWallpaper) -> Bool {
        guard let selected else { return false }
        return selected.url.standardizedFileURL == wallpaper.url.standardizedFileURL
    }
}

struct AnnotationWatermarkInspector: View {
    @Binding var settings: AnnotationWatermarkSettings
    let focusedField: FocusState<AnnotationEditorFocusedField?>.Binding
    let onFocusCleared: () -> Void

    @State private var isTextEditing = false

    private var watermarkText: Binding<String> {
        Binding(
            get: { settings.text },
            set: { text in
                settings.text = text
                settings.isEnabled = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }

    private var watermarkColor: Binding<Color> {
        Binding(
            get: { settings.color.color },
            set: { settings.color = .custom(from: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            if isTextEditing {
                watermarkTextField
            } else {
                watermarkActivationButton
            }

            if hasWatermarkText {
                InspectorSlider(
                    "Density",
                    value: $settings.density,
                    range: 2...10,
                    format: .integer
                )

                InspectorSlider(
                    "Size",
                    value: $settings.fontSize,
                    range: 8...160,
                    format: .pixels
                )

                InspectorSlider(
                    "Angle",
                    value: $settings.rotationDegrees,
                    range: -90...90,
                    format: .degrees()
                )

                InspectorSlider(
                    "Opacity",
                    value: $settings.opacity,
                    range: 0...0.75,
                    format: .percent()
                )

                HStack(spacing: 10) {
                    Text("Color")
                        .font(.inspectorLabel)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    ColorPicker("", selection: watermarkColor, supportsOpacity: false)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: focusedField.wrappedValue) { _, newValue in
            guard newValue != .watermarkText else { return }
            isTextEditing = false
        }
    }

    private var watermarkActivationButton: some View {
        Button(action: beginTextEditing) {
            HStack(spacing: 7) {
                Image(systemName: hasWatermarkText ? "textformat" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(hasWatermarkText ? settings.text : "Add watermark")
                    .font(.inspectorValue)
                    .foregroundColor(hasWatermarkText ? Color.primary.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: hasWatermarkText ? "pencil" : "chevron.right")
                    .font(.system(size: hasWatermarkText ? 10 : 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .inspectorField(height: 26)
        }
        .buttonStyle(.plain)
        .help(hasWatermarkText ? "Edit watermark text" : "Add watermark")
    }

    private var watermarkTextField: some View {
        TextField("Watermark text", text: watermarkText)
            .focused(focusedField, equals: .watermarkText)
            .onSubmit(finishTextEditing)
            .textFieldStyle(.plain)
            .font(.inspectorValue)
            .padding(.horizontal, 8)
            .inspectorField(height: 26)
            .onAppear {
                focusedField.wrappedValue = .watermarkText
            }
            .onClickOutside(enabled: true, perform: finishTextEditing)
    }

    private var hasWatermarkText: Bool {
        !settings.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginTextEditing() {
        isTextEditing = true
    }

    private func finishTextEditing() {
        isTextEditing = false
        focusedField.wrappedValue = nil
        onFocusCleared()
    }

}

private enum AnnotationWallpaperSource {
    static let recentID = "recent"
    static let macID = "macos"
}

private struct AnnotationWallpaperSourceOption: Identifiable, Hashable {
    let id: String
    let title: String

    static let recent = AnnotationWallpaperSourceOption(
        id: AnnotationWallpaperSource.recentID,
        title: "Recent"
    )

    static let mac = AnnotationWallpaperSourceOption(
        id: AnnotationWallpaperSource.macID,
        title: "macOS"
    )
}

private struct AnnotationAddWallpaperTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: InspectorMetrics.tileRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                .foregroundStyle(.quaternary)
                .aspectRatio(1.35, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(2.5)
                .contentShape(RoundedRectangle(cornerRadius: InspectorMetrics.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AlignmentPositionPicker: View {
    @Binding var alignment: AnnotationBackgroundAlignment
    let isEnabled: Bool
    let onEditorAction: () -> Void

    private let size: CGFloat = 44
    private let markerSize: CGFloat = 6
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 2

    @State private var hoveredAlignment: AnnotationBackgroundAlignment?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: InspectorMetrics.sliderRadius,
            style: .continuous
        )
        let columns = Array(
            repeating: GridItem(.fixed(cellSize), spacing: spacing),
            count: 3
        )

        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(AnnotationBackgroundAlignment.allCases) { option in
                Button {
                    onEditorAction()
                    withAnimation(accessibilityReduceMotion ? nil : .snappy(duration: 0.18)) {
                        alignment = option
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(markerFill(for: option))
                        .frame(width: markerSize, height: markerSize)
                        .frame(width: cellSize, height: cellSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(!isEnabled)
                .help(option.title)
                .onHover { isHovering in
                    guard isEnabled else {
                        hoveredAlignment = nil
                        return
                    }
                    if isHovering {
                        hoveredAlignment = option
                    } else if hoveredAlignment == option {
                        hoveredAlignment = nil
                    }
                }
                .accessibilityLabel("\(option.title) alignment")
                .accessibilityValue(displayedAlignment == option ? "Selected" : "")
                .accessibilityAddTraits(displayedAlignment == option ? .isSelected : [])
            }
        }
        .padding(InspectorMetrics.controlInset)
        .frame(width: size, height: size)
        .background(shape.fill(InspectorControlPalette.trackFill(for: colorScheme)))
        .overlay(shape.stroke(InspectorControlPalette.border, lineWidth: 0.5))
        .clipShape(shape)
        .opacity(isEnabled ? 1 : 0.46)
        .help(isEnabled ? "Image alignment" : "Reset Camera to use alignment")
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                hoveredAlignment = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image alignment")
    }

    private var displayedAlignment: AnnotationBackgroundAlignment {
        isEnabled ? alignment : .center
    }

    private func markerFill(for option: AnnotationBackgroundAlignment) -> Color {
        if displayedAlignment == option {
            return InspectorControlPalette.selectedForeground
        }
        if hoveredAlignment == option {
            return Color.primary.opacity(0.48)
        }
        return Color.primary.opacity(0.22)
    }
}
