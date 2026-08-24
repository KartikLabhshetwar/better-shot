import SwiftUI

/// Cap's keyboard overlay: what was typed during the recording, grouped into words and shortcuts and drawn under the video.
struct VideoKeyboardSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Keyboard") {
            if !model.keystrokeSegments.isEmpty {
                Text("\(model.keystrokeSegments.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if model.keystrokeSegments.isEmpty {
                    InspectorCaption("Nothing was typed in this recording, or key capture was off. Turn on \u{201C}The keys I type\u{201D} in Settings, Recording to record keystrokes next time.")
                } else {
                    KeystrokeStyleControls(model: model)

                    VStack(spacing: 3) {
                        ForEach(model.keystrokeSegments) { segment in
                            KeystrokeRow(
                                segment: segment,
                                isActive: model.currentTime >= segment.start && model.currentTime <= segment.end,
                                seek: { model.seekTo(segment.start) },
                                delete: {
                                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) {
                                        model.deleteKeystroke(segment.id)
                                    }
                                },
                                write: { text in
                                    var updated = segment
                                    updated.text = text
                                    model.updateKeystroke(updated)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct KeystrokeRow: View {
    let segment: KeystrokeSegment
    let isActive: Bool
    let seek: () -> Void
    let delete: () -> Void
    let write: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.pillRadius, style: .continuous)

        HStack(spacing: 6) {
            Button(action: seek) {
                Text(VideoMaskSection.range(segment.start, segment.end))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.inspectorPress)
            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            .help("Jump the playhead here")

            TextField("", text: Binding(get: { segment.text }, set: write))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.inspectorPress)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Drop this line")
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(shape.fill(isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0.03)))
        .overlay(shape.strokeBorder(isActive ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1))
        .onHover { isHovering = $0 }
        .animation(InspectorMotion.hover, value: isHovering)
        .animation(InspectorMotion.hover, value: isActive)
    }
}

private struct KeystrokeStyleControls: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(KeystrokeStyle.Position.allCases) { position in
                    InspectorPill(position.title, systemImage: position.icon, isActive: model.keystrokeStyle.position == position, fillsWidth: true) {
                        model.keystrokeStyle.position = position
                    }
                }
            }

            HStack(spacing: 3) {
                ForEach(TextOverlay.Weight.allCases) { weight in
                    InspectorPill(weight.title, isActive: model.keystrokeStyle.weight == weight, fillsWidth: true) {
                        model.keystrokeStyle.weight = weight
                    }
                }

                ColorPicker("", selection: color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            InspectorRow("Size") {
                Slider(value: number(\.fontSize), in: TextOverlay.fontSizeRange)
                    .controlSize(.small)
            }

            InspectorRow("Backdrop") {
                Slider(value: number(\.backgroundOpacity), in: 0...1)
                    .controlSize(.small)
            }

            HStack(spacing: 6) {
                Toggle("Enabled", isOn: $model.keystrokeStyle.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 4)

                Toggle("Uppercase", isOn: $model.keystrokeStyle.isUppercase)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))
            }

            InspectorCaption("Typing is grouped into words, and shortcuts like \u{2318}S get their own moment. Edit or drop any line above.")
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: { Color(red: model.keystrokeStyle.red, green: model.keystrokeStyle.green, blue: model.keystrokeStyle.blue) },
            set: { new in
                guard let components = NSColor(new).usingColorSpace(.sRGB) else { return }
                model.keystrokeStyle.red = components.redComponent
                model.keystrokeStyle.green = components.greenComponent
                model.keystrokeStyle.blue = components.blueComponent
            }
        )
    }

    private func number(_ keyPath: WritableKeyPath<KeystrokeStyle, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(model.keystrokeStyle[keyPath: keyPath]) },
            set: { new in model.keystrokeStyle[keyPath: keyPath] = CGFloat(new) }
        )
    }
}
