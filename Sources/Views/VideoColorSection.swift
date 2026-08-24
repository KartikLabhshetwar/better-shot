import AppKit
import CoreImage
import SwiftUI

private let swatchContext = CIContext(options: [.useSoftwareRenderer: false])
private let swatchSide: CGFloat = 52

/// Presets are shown as the user's own frame under each grade, because a named swatch tells you nothing about what it will do to this footage.
private func gradedSwatch(_ source: NSImage, grade: ColorGrade) -> NSImage? {
    guard let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let image = CIImage(cgImage: cgSource)
    let side = min(image.extent.width, image.extent.height)
    let square = image.cropped(to: CGRect(
        x: image.extent.midX - side / 2,
        y: image.extent.midY - side / 2,
        width: side,
        height: side
    ))
    let centered = square.transformed(by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY))
    let graded = grade.applied(to: centered, extent: centered.extent, frameTime: 0)
    guard let output = swatchContext.createCGImage(graded, from: centered.extent) else { return nil }
    return NSImage(cgImage: output, size: CGSize(width: swatchSide, height: swatchSide))
}

private struct ColorGradeSwatch: View {
    let preset: ColorGrade.Preset
    let thumbnail: NSImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: swatchSide, height: swatchSide)
                .modifier(InspectorSwatchChrome(isSelected: isSelected, radius: 7))

                Text(preset.name)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.inspectorPress(scale: 0.94))
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private enum GradeTarget: String, CaseIterable {
    case screen = "Screen"
    case camera = "Camera"
}

struct VideoColorSection: View {
    @Bindable var model: VideoEditorModel

    @State private var target: GradeTarget = .screen
    @State private var swatches: [String: NSImage] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var grade: ColorGrade {
        target == .camera ? model.cameraGrade : model.screenGrade
    }

    private var gradeBinding: Binding<ColorGrade> {
        target == .camera ? $model.cameraGrade : $model.screenGrade
    }

    private var sourceThumbnail: NSImage? {
        guard !model.thumbnails.isEmpty else { return nil }
        return model.thumbnails[model.thumbnails.count / 2]
    }

    var body: some View {
        InspectorSection("Color") {
            VStack(alignment: .leading, spacing: 12) {
                if model.hasCamera {
                    Picker("", selection: $target) {
                        ForEach(GradeTarget.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                presetStrip

                InspectorSlider(
                    "Intensity",
                    value: knob(\.intensity),
                    range: 0...1,
                    format: .percent()
                )
                .disabled(grade == .neutral)

                DisclosureGroup("Adjust") {
                    VStack(alignment: .leading, spacing: 10) {
                        InspectorSlider("Exposure", value: knob(\.exposure), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Contrast", value: knob(\.contrast), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Saturation", value: knob(\.saturation), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Warmth", value: knob(\.temperature), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Tint", value: knob(\.tint), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Fade", value: knob(\.fade), range: 0...1, format: .percent())
                        InspectorSlider("Split Tone", value: knob(\.splitTone), range: -1...1, format: .percent(signed: true))
                        InspectorSlider("Vignette", value: knob(\.vignette), range: 0...1, format: .percent())
                        InspectorSlider("Grain", value: knob(\.grain), range: 0...1, format: .percent())
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 11, weight: .medium))
                .tint(.secondary)

                if grade != .neutral {
                    InspectorPill("Reset Color", systemImage: "arrow.counterclockwise", fillsWidth: true) {
                        gradeBinding.wrappedValue = .neutral
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : InspectorMotion.reveal, value: grade == .neutral)
            .animation(reduceMotion ? nil : InspectorMotion.reveal, value: target)
        }
        .task(id: model.thumbnails.count) { rebuildSwatches() }
    }

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ColorGrade.presets) { preset in
                    ColorGradeSwatch(
                        preset: preset,
                        thumbnail: swatches[preset.id],
                        isSelected: grade.matchingPresetID == preset.id,
                        action: { model.applyGradePreset(preset, toCamera: target == .camera) }
                    )
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
        }
        .frame(height: swatchSide + 24)
    }

    private func knob(_ path: WritableKeyPath<ColorGrade, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { grade[keyPath: path] },
            set: { gradeBinding.wrappedValue[keyPath: path] = $0 }
        )
    }

    private func rebuildSwatches() {
        guard let sourceThumbnail else { return }
        swatches = ColorGrade.presets.reduce(into: [:]) { result, preset in
            result[preset.id] = gradedSwatch(sourceThumbnail, grade: preset.grade)
        }
    }
}
