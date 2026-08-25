//
//  AnnotationInspector.swift
//  BetterShot
//

import AppKit
import SwiftUI

// MARK: - Inspector

enum AnnotationEditorFocusedField: Hashable {
    case watermarkText
}

private enum AnnotationInspectorAdvancedSection: String, Hashable, CaseIterable {
    case camera
    case progressiveBlur
    case background
    case border
    case watermark
}

private enum AnnotationInspectorSectionState {
    static let expandedSectionsKey = "annotationInspector.expandedAdvancedSections"

    static func loadExpandedSections() -> Set<AnnotationInspectorAdvancedSection> {
        let rawValues = UserDefaults.standard.stringArray(forKey: expandedSectionsKey) ?? []
        return Set(rawValues.compactMap(AnnotationInspectorAdvancedSection.init(rawValue:)))
    }

    static func saveExpandedSections(_ sections: Set<AnnotationInspectorAdvancedSection>) {
        UserDefaults.standard.set(sections.map(\.rawValue), forKey: expandedSectionsKey)
    }
}

struct AnnotationEditorInspector: View {
    private static let minimumColumnWidth: CGFloat = 260
    private static let idealColumnWidth: CGFloat = 280
    private static let maximumColumnWidth: CGFloat = 440

    @Bindable var model: AnnotationEditorModel
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    @Bindable var backgroundPresetStore: AnnotationBackgroundPresetStore
    let focusedField: FocusState<AnnotationEditorFocusedField?>.Binding
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var expandedAdvancedSections: Set<AnnotationInspectorAdvancedSection> = AnnotationInspectorSectionState.loadExpandedSections()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                InspectorSection("Tools") {
                    AnnotationInspectorToolGrid(selectedTool: model.selectedTool) { tool in
                        onEditorAction()
                        model.selectTool(tool)
                    }
                }

                InspectorSectionDivider()

                InspectorSection("Smart Redaction") {
                    HStack(spacing: 8) {
                        SmartRedactionButton(
                            title: "Pixelate",
                            systemImage: "app.background.dotted",
                            isRunning: model.isSmartRedacting
                        ) {
                            onEditorAction()
                            model.smartRedact(using: .pixelate)
                        }

                        SmartRedactionButton(
                            title: "Blur",
                            systemImage: "drop.fill",
                            isRunning: model.isSmartRedacting
                        ) {
                            onEditorAction()
                            model.smartRedact(using: .blur)
                        }
                    }

                    if model.isSmartRedacting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning screenshot…")
                                .font(.inspectorLabel)
                                .foregroundStyle(.secondary)
                        }
                    } else if let message = model.smartRedactionMessage {
                        Text(message)
                            .font(.inspectorLabel)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.hasInspectorStyleControls {
                    InspectorSectionDivider()

                    InspectorSection("Style") {
                        if model.selectionCount > 1 {
                            Text("\(model.selectionCount) annotations selected")
                                .font(.inspectorLabel)
                                .foregroundStyle(.secondary)
                        }

                        if model.isTextStyleAvailable {
                            AnnotationTextStyleControls(model: model)
                        } else {
                            if model.isColorStyleAvailable {
                                InspectorRow("Color") {
                                    AnnotationSwatchStrip(selectedSwatch: model.selectedSwatch) { swatch in
                                        onEditorAction()
                                        model.setSwatch(swatch)
                                    }
                                }
                            }

                            if model.isStrokeStyleAvailable {
                                InspectorRow("Stroke") {
                                    AnnotationStrokePicker(strokeWidth: model.strokeWidth) { strokeWidth in
                                        onEditorAction()
                                        model.setStrokeWidth(strokeWidth)
                                    }
                                }
                            }

                            if model.isRedactionStyleAvailable {
                                InspectorSlider(
                                    "Strength",
                                    value: Binding(
                                        get: { model.redactionDensity },
                                        set: {
                                            onEditorAction()
                                            model.setRedactionDensity($0)
                                        }
                                    ),
                                    range: 0.15...1,
                                    format: .percent()
                                )
                            }
                        }
                    }
                }

                InspectorSectionDivider()

                InspectorDisclosureSection(
                    title: "Camera",
                    isExpanded: expansionBinding(for: .camera),
                    accessory: {
                        if !model.backgroundSettings.camera.isDefault {
                            InspectorClearButton(help: "Reset camera") {
                                onEditorAction()
                                withAnimation(.snappy(duration: 0.2)) {
                                    model.backgroundSettings.camera = AnnotationCameraSettings()
                                }
                            }
                        }
                    }
                ) {
                    AnnotationCameraInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.camera },
                            set: { model.backgroundSettings.camera = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                }

                InspectorDisclosureSection(
                    title: "Progressive Blur",
                    isExpanded: expansionBinding(for: .progressiveBlur),
                    accessory: {
                        HStack(spacing: 5) {
                            if model.backgroundSettings.progressiveBlur != AnnotationProgressiveBlurSettings() {
                                InspectorClearButton(help: "Reset progressive blur") {
                                    onEditorAction()
                                    model.backgroundSettings.progressiveBlur = AnnotationProgressiveBlurSettings()
                                    if expandedAdvancedSections.contains(.progressiveBlur) {
                                        withAnimation(sectionAnimation) {
                                            expandedAdvancedSections.remove(.progressiveBlur)
                                        }
                                    }
                                }
                            }

                            Toggle(
                                "Enable progressive blur",
                                isOn: Binding(
                                    get: { model.backgroundSettings.progressiveBlur.isEnabled },
                                    set: { value in
                                        onEditorAction()
                                        model.backgroundSettings.progressiveBlur.isEnabled = value
                                        withAnimation(sectionAnimation) {
                                            if value {
                                                expandedAdvancedSections.insert(.progressiveBlur)
                                            } else {
                                                expandedAdvancedSections.remove(.progressiveBlur)
                                            }
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                ) {
                    AnnotationProgressiveBlurInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.progressiveBlur },
                            set: { model.backgroundSettings.progressiveBlur = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                    .disabled(!model.backgroundSettings.progressiveBlur.isEnabled)
                    .opacity(model.backgroundSettings.progressiveBlur.isEnabled ? 1 : 0.48)
                }

                InspectorDisclosureSection(
                    title: "Background",
                    isExpanded: expansionBinding(for: .background),
                    accessory: {
                        if model.backgroundSettings.style != .none {
                            InspectorClearButton(help: "Remove background") {
                                onEditorAction()
                                model.backgroundSettings.style = .none
                            }
                        }
                    }
                ) {
                    AnnotationBackgroundInspector(
                        settings: Binding(
                            get: { model.backgroundSettings },
                            set: { model.backgroundSettings = $0 }
                        ),
                        wallpaperStore: wallpaperStore,
                        onEditorAction: onEditorAction,
                        onPickWallpaper: onPickWallpaper
                    )
                }

                InspectorDisclosureSection(
                    title: "Border",
                    isExpanded: expansionBinding(for: .border),
                    accessory: {
                        HStack(spacing: 5) {
                            if model.backgroundSettings.border != AnnotationScreenshotBorderSettings() {
                                InspectorClearButton(help: "Reset border") {
                                    onEditorAction()
                                    model.backgroundSettings.border = AnnotationScreenshotBorderSettings()
                                    if expandedAdvancedSections.contains(.border) {
                                        withAnimation(sectionAnimation) {
                                            expandedAdvancedSections.remove(.border)
                                        }
                                    }
                                }
                            }

                            Toggle(
                                "Enable border",
                                isOn: Binding(
                                    get: { model.backgroundSettings.border.isEnabled },
                                    set: { value in
                                        onEditorAction()
                                        model.backgroundSettings.border.isEnabled = value
                                        withAnimation(sectionAnimation) {
                                            if value {
                                                expandedAdvancedSections.insert(.border)
                                            } else {
                                                expandedAdvancedSections.remove(.border)
                                            }
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                ) {
                    AnnotationScreenshotBorderInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.border },
                            set: { model.backgroundSettings.border = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                    .disabled(!model.backgroundSettings.border.isEnabled)
                    .opacity(model.backgroundSettings.border.isEnabled ? 1 : 0.48)
                }

                InspectorDisclosureSection(
                    "Watermark",
                    isExpanded: expansionBinding(for: .watermark)
                ) {
                    AnnotationWatermarkInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.watermark },
                            set: { model.backgroundSettings.watermark = $0 }
                        ),
                        focusedField: focusedField,
                        onFocusCleared: onEditorAction
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Reserve clearance so the final inspector controls are never
            // hidden behind the floating preview peek pill.
            .padding(.bottom, PreviewPeekTab.pillHeight * 1.1)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                AnnotationBackgroundPresetBar(
                    model: model,
                    presetStore: backgroundPresetStore,
                    onEditorAction: onEditorAction
                )

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.45))
                    .frame(height: 0.5)
            }
            .background(sidebarBackground)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectSoftIfAvailable()
        .background(sidebarBackground)
        .inspectorColumnWidth(
            min: Self.minimumColumnWidth,
            ideal: Self.idealColumnWidth,
            max: Self.maximumColumnWidth
        )
        .frame(
            minWidth: Self.minimumColumnWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var sidebarBackground: Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white
    }

    private var sectionAnimation: Animation? {
        accessibilityReduceMotion ? nil : .snappy(duration: 0.18)
    }

    private func expansionBinding(
        for section: AnnotationInspectorAdvancedSection
    ) -> Binding<Bool> {
        Binding(
            get: { expandedAdvancedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedAdvancedSections.insert(section)
                } else {
                    expandedAdvancedSections.remove(section)
                }
                AnnotationInspectorSectionState.saveExpandedSections(expandedAdvancedSections)
            }
        )
    }
}

// MARK: - Smart redaction

private struct SmartRedactionButton: View {
    let title: String
    let systemImage: String
    let isRunning: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.inspectorValue)
            }
            .foregroundStyle(.primary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .inspectorField(height: 28)
            .overlay {
                if isHovering && !isRunning {
                    RoundedRectangle(cornerRadius: InspectorMetrics.fieldRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .opacity(isRunning ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tools

private struct AnnotationInspectorToolGrid: View {
    let selectedTool: AnnotationTool
    let onSelect: (AnnotationTool) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4), count: 6
    )
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: InspectorMetrics.sliderRadius,
            style: .continuous
        )

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                AnnotationToolCell(
                    tool: tool,
                    isSelected: selectedTool == tool,
                    action: { onSelect(tool) }
                )
            }
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .padding(InspectorMetrics.controlInset)
        .background(shape.fill(InspectorControlPalette.trackFill(for: colorScheme)))
        .overlay(shape.stroke(InspectorControlPalette.border, lineWidth: 0.5))
        .clipShape(shape)
    }
}

private struct AnnotationToolCell: View {
    let tool: AnnotationTool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear

                Image(systemName: tool.systemImage)
                    .font(.system(size: 13, weight: .medium))
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: InspectorMetrics.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isSelected ? InspectorControlPalette.selectedForeground : Color.secondary)
        .background {
            RoundedRectangle(cornerRadius: InspectorMetrics.tileRadius, style: .continuous)
                .fill(background)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: InspectorMetrics.tileRadius, style: .continuous)
                            .stroke(InspectorControlPalette.border, lineWidth: 0.5)
                    }
                }
        }
        .help(tool.helpText)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.helpText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected {
            return InspectorControlPalette.selectionFill(for: colorScheme)
        }
        return isHovering ? InspectorControlPalette.hoverFill : .clear
    }
}
