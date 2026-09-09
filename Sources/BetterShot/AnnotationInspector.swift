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

    @Bindable var model: AnnotationEditorModel
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    @Bindable var backgroundPresetStore: AnnotationBackgroundPresetStore
    let focusedField: FocusState<AnnotationEditorFocusedField?>.Binding
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var expandedAdvancedSections: Set<AnnotationInspectorAdvancedSection> = AnnotationInspectorSectionState.loadExpandedSections()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
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
            .background(.regularMaterial)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectSoftIfAvailable()
        .background(.regularMaterial)
        .frame(
            minWidth: Self.minimumColumnWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
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

struct AnnotationSmartRedactionControls: View {
    @Bindable var model: AnnotationEditorModel
    let onEditorAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatically hide sensitive information")
                .font(.subheadline).foregroundStyle(.secondary)
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
