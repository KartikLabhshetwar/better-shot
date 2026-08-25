//
//  AnnotationCameraInspector.swift
//  BetterShot
//

import SwiftUI

struct AnnotationCameraInspector: View {
    @Binding var settings: AnnotationCameraSettings
    let onEditorAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                InspectorGroupLabel("Camera angle")

                InspectorSlider(
                    "Tilt X",
                    value: binding(\.tiltXDegrees),
                    range: -45...45,
                    format: .degrees(signed: true)
                )

                InspectorSlider(
                    "Tilt Y",
                    value: binding(\.tiltYDegrees),
                    range: -45...45,
                    format: .degrees(signed: true)
                )

                InspectorSlider(
                    "Roll",
                    value: binding(\.rollDegrees),
                    range: -45...45,
                    format: .degrees(signed: true)
                )
            }
            .help("Orbit the camera around the card center, then roll the view")

            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                InspectorGroupLabel("Framing")

                InspectorSlider(
                    "FOV",
                    value: binding(\.fieldOfViewDegrees),
                    range: 18...80,
                    format: .degrees()
                )

                InspectorSlider(
                    "Zoom",
                    value: binding(\.zoom),
                    range: 0.4...2.5,
                    format: .magnification(fractionDigits: 2)
                )

                InspectorSlider(
                    "Pan X",
                    value: binding(\.panX),
                    range: -0.5...0.5,
                    format: .percent(signed: true)
                )

                InspectorSlider(
                    "Pan Y",
                    value: binding(\.panY),
                    range: -0.5...0.5,
                    format: .percent(signed: true)
                )
            }
            .help("Use a lower FOV for a calmer lens, then frame with Zoom and Pan")

            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                InspectorGroupLabel("Card rotation")

                InspectorSlider(
                    "Rotate X",
                    value: binding(\.rotationXDegrees),
                    range: -60...60,
                    format: .degrees(signed: true)
                )

                InspectorSlider(
                    "Rotate Y",
                    value: binding(\.rotationYDegrees),
                    range: -60...60,
                    format: .degrees(signed: true)
                )
            }
            .help("Rotate the card around its own horizontal and vertical center axes")
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AnnotationCameraSettings, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                onEditorAction()
                var updatedSettings = settings
                updatedSettings.upgradeProjectionIfNeeded()
                updatedSettings[keyPath: keyPath] = value
                settings = updatedSettings
            }
        )
    }

}
