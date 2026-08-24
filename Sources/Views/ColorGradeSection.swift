import CoreGraphics
import SwiftUI

struct ColorGradeSection: View {
    @Binding var correction: ColorCorrection
    var onEditingChanged: ((Bool) -> Void)?

    @State private var showsAdjustments = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        InspectorSection("Color") {
            if !correction.isIdentity {
                InspectorPill("Reset", systemImage: "arrow.counterclockwise") {
                    onEditingChanged?(true)
                    correction = .identity
                    onEditingChanged?(false)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(ColorPreset.allCases) { preset in
                        ColorPresetChip(
                            preset: preset,
                            isSelected: correction.preset == preset,
                            action: {
                                onEditingChanged?(true)
                                correction.apply(preset)
                                onEditingChanged?(false)
                            }
                        )
                    }
                }

                InspectorSlider(
                    "Intensity",
                    value: $correction.intensity,
                    range: 0...1,
                    format: .percent(),
                    onEditingChanged: onEditingChanged
                )

                Button {
                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) {
                        showsAdjustments.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showsAdjustments ? 90 : 0))
                        Text("Adjustments")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.inspectorPress(scale: 0.98))
                .accessibilityAddTraits(showsAdjustments ? [.isButton, .isSelected] : .isButton)

                if showsAdjustments {
                    VStack(alignment: .leading, spacing: 10) {
                        slider("Exposure", \.exposure, -1...1, signed: true)
                        slider("Contrast", \.contrast, -1...1, signed: true)
                        slider("Saturation", \.saturation, -1...1, signed: true)
                        slider("Temperature", \.temperature, -1...1, signed: true)
                        slider("Tint", \.tint, -1...1, signed: true)
                        slider("Split Tone", \.splitTone, -1...1, signed: true)
                        slider("Fade", \.fade, 0...1, signed: false)
                        slider("Vignette", \.vignette, 0...1, signed: false)
                        slider("Grain", \.grain, 0...1, signed: false)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<ColorCorrection, CGFloat>,
        _ range: ClosedRange<CGFloat>,
        signed: Bool
    ) -> some View {
        InspectorSlider(
            title,
            value: $correction[dynamicMember: keyPath],
            range: range,
            format: .percent(signed: signed),
            onEditingChanged: onEditingChanged
        )
    }
}

private struct ColorPresetChip: View {
    let preset: ColorPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                swatch
                Text(preset.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.inspectorPress(scale: 0.94))
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(preset.title)
    }

    @ViewBuilder
    private var swatch: some View {
        Group {
            if let image = ColorPresetSwatch.image(for: preset) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(height: 30)
        .inspectorSwatch(isSelected: isSelected, radius: 5)
    }
}

@MainActor
enum ColorPresetSwatch {
    private static var cache: [ColorPreset: CGImage] = [:]

    static func image(for preset: ColorPreset) -> CGImage? {
        if let cached = cache[preset] { return cached }
        guard let base = referenceImage else { return nil }
        let graded = ColorGrade.apply(preset.values, to: base)
        cache[preset] = graded
        return graded
    }

    private static let referenceImage: CGImage? = {
        let width = 96
        let height = 48
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let colors = [
            CGColor(red: 0.09, green: 0.12, blue: 0.21, alpha: 1),
            CGColor(red: 0.28, green: 0.45, blue: 0.58, alpha: 1),
            CGColor(red: 0.78, green: 0.62, blue: 0.45, alpha: 1),
            CGColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1)
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.38, 0.72, 1]
        ) else { return nil }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(height)),
            end: CGPoint(x: CGFloat(width), y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return context.makeImage()
    }()
}
