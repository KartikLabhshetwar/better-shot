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
    let scale = min(1, swatchSide * 4 / max(side, 1))
    let centered = square
        .transformed(by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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

/// One grade, one strip of swatches cut from the frame it will be applied to, shared by the video editor and the image editor.
struct ColorGradePicker: View {
    @Binding var grade: ColorGrade
    let thumbnail: NSImage?
    var onEditingChanged: ((Bool) -> Void)?

    @State private var swatches: [String: NSImage] = [:]
    @State private var swatchSource: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presetStrip

            InspectorSlider(
                "Intensity",
                value: knob(\.intensity),
                range: 0...1,
                format: .percent(),
                onEditingChanged: onEditingChanged
            )
            .disabled(grade == .neutral)

            DisclosureGroup("Adjust") {
                VStack(alignment: .leading, spacing: 10) {
                    InspectorSlider("Exposure", value: knob(\.exposure), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Contrast", value: knob(\.contrast), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Saturation", value: knob(\.saturation), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Warmth", value: knob(\.temperature), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Tint", value: knob(\.tint), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Fade", value: knob(\.fade), range: 0...1, format: .percent(), onEditingChanged: onEditingChanged)
                    InspectorSlider("Split Tone", value: knob(\.splitTone), range: -1...1, format: .percent(signed: true), onEditingChanged: onEditingChanged)
                    InspectorSlider("Vignette", value: knob(\.vignette), range: 0...1, format: .percent(), onEditingChanged: onEditingChanged)
                    InspectorSlider("Grain", value: knob(\.grain), range: 0...1, format: .percent(), onEditingChanged: onEditingChanged)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 11, weight: .medium))
            .tint(.secondary)

            if grade != .neutral {
                InspectorPill("Reset Color", systemImage: "arrow.counterclockwise", fillsWidth: true) {
                    apply(.neutral)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : InspectorMotion.reveal, value: grade == .neutral)
        .onChange(of: thumbnail) { rebuildSwatches() }
        .onAppear { rebuildSwatches() }
    }

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ColorGrade.presets) { preset in
                    ColorGradeSwatch(
                        preset: preset,
                        thumbnail: swatches[preset.id],
                        isSelected: grade.matchingPresetID == preset.id,
                        action: { apply(preset.grade) }
                    )
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
        }
        .frame(height: swatchSide + 24)
    }

    private func apply(_ next: ColorGrade) {
        onEditingChanged?(true)
        grade = next
        onEditingChanged?(false)
    }

    private func knob(_ path: WritableKeyPath<ColorGrade, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { grade[keyPath: path] },
            set: { grade[keyPath: path] = $0 }
        )
    }

    private func rebuildSwatches() {
        guard let thumbnail, thumbnail !== swatchSource else { return }
        swatchSource = thumbnail
        swatches = ColorGrade.presets.reduce(into: [:]) { result, preset in
            result[preset.id] = gradedSwatch(thumbnail, grade: preset.grade)
        }
    }
}

private enum GradeTarget: String, CaseIterable {
    case screen = "Screen"
    case camera = "Camera"
}

struct VideoColorSection: View {
    @Bindable var model: VideoEditorModel

    @State private var target: GradeTarget = .screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                ColorGradePicker(grade: gradeBinding, thumbnail: sourceThumbnail)
                    .id(target)
            }
            .animation(reduceMotion ? nil : InspectorMotion.reveal, value: target)
        }
    }
}

/// The image editor grades the still with the same presets the recorder uses, so a set of screenshots and a clip can match.
struct ImageColorSection: View {
    @Binding var config: BeautifierConfig
    let source: CGImage?
    var onEditingChanged: ((Bool) -> Void)?

    @State private var thumbnail: NSImage?

    var body: some View {
        InspectorSection("Color", collapsedByDefault: true) {
            ColorGradePicker(grade: $config.grade, thumbnail: thumbnail, onEditingChanged: onEditingChanged)
        }
        .task(id: source.map(ObjectIdentifier.init)) {
            thumbnail = source.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }
}
