import SwiftUI

/// Cap's captions: the recording's own speech, transcribed on device and drawn as one subtitle line under the video.
struct VideoCaptionSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Captions") {
            if !model.captions.isEmpty {
                Text("\(model.captions.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 3) {
                    InspectorPill(
                        model.isTranscribing ? "Listening" : (model.captions.isEmpty ? "Transcribe Audio" : "Transcribe Again"),
                        systemImage: model.isTranscribing ? "waveform" : "text.bubble",
                        fillsWidth: true
                    ) {
                        Task { await model.transcribeCaptions() }
                    }
                    .disabled(model.isTranscribing)
                    .symbolEffect(.variableColor.iterative, isActive: model.isTranscribing)
                    .help("Transcribe the recording's audio into timed captions.")

                    if !model.captions.isEmpty {
                        InspectorPill("Clear", systemImage: "trash") {
                            withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.clearCaptions() }
                        }
                        .help("Remove every caption")
                    }
                }

                if let error = model.transcriptionError {
                    InspectorCaption(error)
                }

                if model.captions.isEmpty {
                    InspectorCaption("Speech is recognised on device when your Mac supports it, so the recording never leaves the machine.")
                } else {
                    CaptionStyleControls(model: model)

                    VStack(spacing: 3) {
                        ForEach(model.captions) { cue in
                            CaptionRow(
                                cue: cue,
                                isActive: model.currentTime >= cue.start && model.currentTime <= cue.end,
                                seek: { model.seekTo(cue.start) },
                                write: { text in
                                    var updated = cue
                                    updated.text = text
                                    model.updateCaption(updated)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct CaptionRow: View {
    let cue: CaptionCue
    let isActive: Bool
    let seek: () -> Void
    let write: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.pillRadius, style: .continuous)

        HStack(spacing: 6) {
            Button(action: seek) {
                Text(VideoMaskSection.range(cue.start, cue.end))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.inspectorPress)
            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            .help("Jump the playhead here")

            TextField("", text: Binding(get: { cue.text }, set: write))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
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

private struct CaptionStyleControls: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(CaptionStyle.Position.allCases) { position in
                    InspectorPill(position.title, systemImage: position.icon, isActive: model.captionStyle.position == position, fillsWidth: true) {
                        model.captionStyle.position = position
                    }
                }
            }

            HStack(spacing: 3) {
                ForEach(TextOverlay.Weight.allCases) { weight in
                    InspectorPill(weight.title, isActive: model.captionStyle.weight == weight, fillsWidth: true) {
                        model.captionStyle.weight = weight
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

            InspectorRow("Width") {
                Slider(value: number(\.maxWidth), in: 0.3...1)
                    .controlSize(.small)
            }

            InspectorRow("Backdrop") {
                Slider(value: number(\.backgroundOpacity), in: 0...1)
                    .controlSize(.small)
            }

            HStack(spacing: 6) {
                Toggle("Enabled", isOn: $model.captionStyle.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 4)

                Toggle("Uppercase", isOn: $model.captionStyle.isUppercase)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))
            }

            InspectorCaption("Edit any line above. Captions sit on the canvas, so they stay readable while the recording zooms.")
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: { Color(red: model.captionStyle.red, green: model.captionStyle.green, blue: model.captionStyle.blue) },
            set: { new in
                guard let components = NSColor(new).usingColorSpace(.sRGB) else { return }
                model.captionStyle.red = components.redComponent
                model.captionStyle.green = components.greenComponent
                model.captionStyle.blue = components.blueComponent
            }
        )
    }

    private func number(_ keyPath: WritableKeyPath<CaptionStyle, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(model.captionStyle[keyPath: keyPath]) },
            set: { new in model.captionStyle[keyPath: keyPath] = CGFloat(new) }
        )
    }
}
