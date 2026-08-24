import SwiftUI

/// Cap's text segments: a line that lives on the canvas for a stretch of the recording, dragged where you want it and animated in and out.
struct VideoTextSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Text") {
            if !model.texts.isEmpty {
                Text("\(model.texts.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                InspectorPill("Add Text", systemImage: "textformat", fillsWidth: true) {
                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { model.addText() }
                }
                .help("Drop a line of text on the canvas at the playhead.")

                if model.texts.isEmpty {
                    InspectorCaption("Text sits on the canvas, not inside the video, so it stays put while the recording zooms.")
                } else {
                    VStack(spacing: 3) {
                        ForEach(model.texts) { overlay in
                            TextRow(
                                overlay: overlay,
                                isSelected: model.selectedTextID == overlay.id,
                                select: { model.selectedTextID = overlay.id },
                                delete: {
                                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) {
                                        model.deleteText(overlay.id)
                                    }
                                }
                            )
                        }
                    }

                    if let selected = model.selectedText {
                        TextEditorControls(model: model, overlay: selected)
                    } else {
                        InspectorCaption("Pick a line to edit it.")
                    }
                }
            }
        }
    }
}

private struct TextRow: View {
    let overlay: TextOverlay
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.pillRadius, style: .continuous)

        HStack(spacing: 6) {
            Image(systemName: "textformat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 14)

            Text(overlay.content.isEmpty ? "Empty" : overlay.content)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(VideoMaskSection.range(overlay.start, overlay.end))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.inspectorPress)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Delete this text")
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(shape.fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0.03)))
        .overlay(shape.strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .animation(InspectorMotion.hover, value: isHovering)
        .animation(InspectorMotion.hover, value: isSelected)
        .opacity(overlay.isEnabled ? 1 : 0.45)
    }
}

private struct TextEditorControls: View {
    @Bindable var model: VideoEditorModel
    let overlay: TextOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Text", text: content, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .lineLimit(1...4)

            HStack(spacing: 3) {
                ForEach(TextOverlay.Weight.allCases) { weight in
                    InspectorPill(weight.title, isActive: overlay.weight == weight, fillsWidth: true) {
                        write { $0.weight = weight }
                    }
                }
            }

            HStack(spacing: 3) {
                ForEach(TextOverlay.Align.allCases) { align in
                    InspectorPill("", systemImage: align.icon, isActive: overlay.align == align, fillsWidth: true) {
                        write { $0.align = align }
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
                Slider(value: number(\.maxWidth), in: 0.1...1)
                    .controlSize(.small)
            }

            InspectorRow("Shadow") {
                Slider(value: number(\.shadow), in: 0...1)
                    .controlSize(.small)
            }

            InspectorRow("In") {
                motionPicker(\.animationIn)
            }

            InspectorRow("Out") {
                motionPicker(\.animationOut)
            }

            InspectorRow("Length") {
                Slider(value: animationLength, in: 0...1.2)
                    .controlSize(.small)
            }

            HStack(spacing: 3) {
                InspectorPill("Start Here", systemImage: "arrow.left.to.line", fillsWidth: true) {
                    write { $0.start = min(model.currentTime, $0.end - TextOverlay.minimumDuration) }
                }

                InspectorPill("End Here", systemImage: "arrow.right.to.line", fillsWidth: true) {
                    write { $0.end = max(model.currentTime, $0.start + TextOverlay.minimumDuration) }
                }
            }

            HStack(spacing: 6) {
                Toggle("Enabled", isOn: Binding(get: { overlay.isEnabled }, set: { on in write { $0.isEnabled = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 4)

                Text(VideoMaskSection.range(overlay.start, overlay.end))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }

            InspectorCaption("Drag the text on the video to move it. Size is measured against a 1080p frame, so it scales with whatever you export.")
        }
    }

    private func motionPicker(_ keyPath: WritableKeyPath<TextOverlay, TextOverlay.Motion>) -> some View {
        Picker("", selection: Binding(
            get: { overlay[keyPath: keyPath] },
            set: { motion in write { $0[keyPath: keyPath] = motion } }
        )) {
            ForEach(TextOverlay.Motion.allCases) { motion in
                Label(motion.title, systemImage: motion.icon).tag(motion)
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func write(_ change: (inout TextOverlay) -> Void) {
        var updated = overlay
        change(&updated)
        model.updateText(updated)
    }

    private var content: Binding<String> {
        Binding(get: { overlay.content }, set: { new in write { $0.content = new } })
    }

    private var animationLength: Binding<Double> {
        Binding(
            get: { max(overlay.animationInDuration, overlay.animationOutDuration) },
            set: { new in write { $0.animationInDuration = new; $0.animationOutDuration = new } }
        )
    }

    private var color: Binding<Color> {
        Binding(
            get: { Color(red: overlay.red, green: overlay.green, blue: overlay.blue) },
            set: { new in
                let components = NSColor(new).usingColorSpace(.sRGB) ?? .white
                write {
                    $0.red = components.redComponent
                    $0.green = components.greenComponent
                    $0.blue = components.blueComponent
                }
            }
        )
    }

    private func number(_ keyPath: WritableKeyPath<TextOverlay, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(overlay[keyPath: keyPath]) },
            set: { new in write { $0[keyPath: keyPath] = CGFloat(new) } }
        )
    }
}

/// The same resolve the exporter runs, drawn with SwiftUI so the text on the canvas is the text in the file.
struct TextOverlayLayer: View {
    @Bindable var model: VideoEditorModel
    let canvasSize: CGSize
    let isEditing: Bool

    var body: some View {
        ZStack {
            ForEach(model.texts) { overlay in
                if let resolved = TextOverlay.resolved([overlay], atSourceTime: model.currentTime, canvasSize: canvasSize).first {
                    DrawnText(
                        text: resolved,
                        isSelected: isEditing && model.selectedTextID == overlay.id,
                        isEditing: isEditing,
                        canvasSize: canvasSize,
                        select: { model.selectedTextID = overlay.id },
                        move: { center in
                            var updated = overlay
                            updated.center = center
                            model.updateText(updated)
                        }
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(isEditing)
    }
}

private struct DrawnText: View {
    let text: ResolvedText
    let isSelected: Bool
    let isEditing: Bool
    let canvasSize: CGSize
    let select: () -> Void
    let move: (CGPoint) -> Void

    @State private var dragOrigin: CGPoint?
    @State private var isHovering = false

    var body: some View {
        Text(text.content)
            .font(.system(size: text.fontSize, weight: text.weight.swiftUI))
            .foregroundStyle(Color(red: text.red, green: text.green, blue: text.blue))
            .multilineTextAlignment(text.align.swiftUI)
            .lineSpacing(text.fontSize * (text.lineHeight - 1))
            .shadow(
                color: .black.opacity(0.55 * text.shadow),
                radius: text.fontSize * 0.14 * text.shadow,
                y: text.fontSize * 0.06 * text.shadow
            )
            .frame(maxWidth: text.maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.9 : (isHovering ? 0.5 : 0)), lineWidth: 1)
            }
            .scaleEffect(text.scale)
            .opacity(text.opacity)
            .position(text.placement)
            .onHover { isHovering = isEditing && $0 }
            .onTapGesture(perform: select)
            .gesture(drag)
            .animation(InspectorMotion.hover, value: isSelected)
            .animation(InspectorMotion.hover, value: isHovering)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragOrigin ?? CGPoint(x: text.center.x / canvasSize.width, y: text.center.y / canvasSize.height)
                dragOrigin = start
                select()
                move(CGPoint(
                    x: start.x + value.translation.width / canvasSize.width,
                    y: start.y + value.translation.height / canvasSize.height
                ))
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

extension TextOverlay.Weight {
    var swiftUI: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

extension TextOverlay.Align {
    var swiftUI: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}
