//
//  AnnotationScreenshotBorderInspector.swift
//  BetterShot
//

import SwiftUI

struct AnnotationScreenshotBorderInspector: View {
    @Binding var settings: AnnotationScreenshotBorderSettings
    let onEditorAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                HStack {
                    Text("Color")
                        .font(.inspectorLabel)
                    Spacer()
                    Text(settings.color.title)
                        .font(.inspectorValue)
                }
                .foregroundStyle(.secondary)

                AnnotationSwatchStrip(selectedSwatch: settings.color) { color in
                    onEditorAction()
                    settings.color = color
                }
            }

            InspectorSlider(
                "Thickness",
                value: binding(\.thickness),
                range: 0.002...0.08,
                format: .percent(fractionDigits: 1)
            )

            InspectorSlider(
                "Opacity",
                value: binding(\.opacity),
                range: 0...1,
                format: .percent()
            )
        }
    }

    private func binding(
        _ keyPath: WritableKeyPath<AnnotationScreenshotBorderSettings, CGFloat>
    ) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                onEditorAction()
                settings[keyPath: keyPath] = value
            }
        )
    }
}
