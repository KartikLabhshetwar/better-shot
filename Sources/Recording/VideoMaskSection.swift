import SwiftUI

/// Cap's mask editor: a list of boxes that hide or spotlight part of the frame for a stretch of the recording.
struct VideoMaskSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Masks") {
            if !model.masks.isEmpty {
                Text("\(model.masks.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(VideoMask.Kind.allCases) { kind in
                        InspectorPill("Add \(kind.title)", systemImage: kind.icon, fillsWidth: true) {
                            withAnimation(reduceMotion ? nil : InspectorMotion.reveal) {
                                model.addMask(kind: kind)
                            }
                        }
                        .help(kind == .hide
                            ? "Blur or pixelate a box so what is inside it never ships."
                            : "Darken everything outside a box so the eye lands where you point it.")
                    }
                }

                if model.masks.isEmpty {
                    InspectorCaption("A mask covers a box in the frame for a stretch of the recording. Drag it on the video to place it.")
                } else {
                    VStack(spacing: 3) {
                        ForEach(model.masks) { mask in
                            MaskRow(
                                mask: mask,
                                isSelected: model.selectedMaskID == mask.id,
                                select: { model.selectedMaskID = mask.id },
                                delete: {
                                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) {
                                        model.deleteMask(mask.id)
                                    }
                                }
                            )
                        }
                    }

                    if let selected = model.selectedMask {
                        MaskEditor(model: model, mask: selected)
                    } else {
                        InspectorCaption("Pick a mask to change what it does.")
                    }
                }
            }
        }
    }
}

private struct MaskRow: View {
    let mask: VideoMask
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.pillRadius, style: .continuous)

        HStack(spacing: 6) {
            Image(systemName: mask.kind.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 14)

            Text(mask.kind == .hide ? mask.effect.title : mask.kind.title)
                .font(.system(size: 11, weight: .medium))

            Spacer(minLength: 4)

            Text(VideoMaskSection.range(mask))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.inspectorPress)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Delete this mask")
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
        .opacity(mask.isEnabled ? 1 : 0.45)
    }
}

private struct MaskEditor: View {
    @Bindable var model: VideoEditorModel
    let mask: VideoMask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(VideoMask.Kind.allCases) { kind in
                    InspectorPill(kind.title, systemImage: kind.icon, isActive: mask.kind == kind, fillsWidth: true) {
                        write { $0.kind = kind }
                    }
                }
            }

            if mask.kind == .hide {
                HStack(spacing: 3) {
                    ForEach(VideoMask.Effect.allCases) { effect in
                        InspectorPill(effect.title, systemImage: effect.icon, isActive: mask.effect == effect, fillsWidth: true) {
                            write { $0.effect = effect }
                        }
                    }
                }

                InspectorRow(mask.effect == .blur ? "Blur" : "Blocks") {
                    Slider(value: value(\.amount), in: VideoMask.amountRange)
                        .controlSize(.small)
                }
            } else {
                InspectorRow("Dim") {
                    Slider(value: value(\.darkness), in: 0.2...0.95)
                        .controlSize(.small)
                }

                InspectorRow("Fade") {
                    Slider(value: seconds(\.fadeDuration), in: 0...1)
                        .controlSize(.small)
                }
            }

            InspectorRow("Feather") {
                Slider(value: value(\.feather), in: 0...0.5)
                    .controlSize(.small)
            }

            HStack(spacing: 3) {
                InspectorPill("Start Here", systemImage: "arrow.left.to.line", fillsWidth: true) {
                    write { $0.start = min(model.currentTime, $0.end - VideoMask.minimumDuration) }
                }
                .help("Move the start of this mask to the playhead.")

                InspectorPill("End Here", systemImage: "arrow.right.to.line", fillsWidth: true) {
                    write { $0.end = max(model.currentTime, $0.start + VideoMask.minimumDuration) }
                }
                .help("Move the end of this mask to the playhead.")
            }

            HStack(spacing: 6) {
                Toggle("Enabled", isOn: Binding(get: { mask.isEnabled }, set: { on in write { $0.isEnabled = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 4)

                Text(VideoMaskSection.range(mask))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }

            InspectorCaption(mask.kind == .hide
                ? "What is inside the box is destroyed in the export, not just covered."
                : "Everything outside the box dims, and the mask fades in and out so it does not blink.")
        }
    }

    private func write(_ change: (inout VideoMask) -> Void) {
        var updated = mask
        change(&updated)
        model.updateMask(updated)
    }

    private func value(_ keyPath: WritableKeyPath<VideoMask, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(mask[keyPath: keyPath]) },
            set: { new in write { $0[keyPath: keyPath] = CGFloat(new) } }
        )
    }

    private func seconds(_ keyPath: WritableKeyPath<VideoMask, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { mask[keyPath: keyPath] },
            set: { new in write { $0[keyPath: keyPath] = new } }
        )
    }
}

extension VideoMaskSection {
    static func range(_ mask: VideoMask) -> String {
        "\(stamp(mask.start))-\(stamp(mask.end))"
    }

    private static func stamp(_ seconds: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}

/// The box drawn over the video: chrome only, because the blur and the dimming are already in the frames the player hands us.
struct MaskEditingLayer: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        GeometryReader { geo in
            ForEach(model.masks) { mask in
                MaskBox(
                    mask: mask,
                    isSelected: model.selectedMaskID == mask.id,
                    isLive: mask.intensity(atSourceTime: model.currentTime) != nil,
                    frame: geo.size,
                    select: { model.selectedMaskID = mask.id },
                    move: { rect in
                        var updated = mask
                        updated.rect = rect
                        model.updateMask(updated)
                    }
                )
            }
        }
    }
}

private struct MaskBox: View {
    let mask: VideoMask
    let isSelected: Bool
    let isLive: Bool
    let frame: CGSize
    let select: () -> Void
    let move: (CGRect) -> Void

    @State private var dragOrigin: CGRect?
    @State private var isHovering = false

    private var rect: CGRect {
        CGRect(
            x: mask.rect.minX * frame.width,
            y: mask.rect.minY * frame.height,
            width: mask.rect.width * frame.width,
            height: mask.rect.height * frame.height
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let tint = mask.kind == .hide ? Color.orange : Color.yellow

        shape
            .fill(Color.white.opacity(isSelected ? 0.06 : 0.02))
            .overlay(
                shape.strokeBorder(
                    tint.opacity(isSelected ? 0.95 : (isHovering ? 0.7 : 0.4)),
                    style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: isLive ? [] : [4, 3])
                )
            )
            .overlay(alignment: .topLeading) {
                Label(mask.kind.title, systemImage: mask.kind.icon)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 9, weight: .bold))
                    .padding(4)
                    .background(Circle().fill(tint.opacity(0.9)))
                    .foregroundStyle(.black.opacity(0.8))
                    .offset(x: 4, y: 4)
                    .opacity(isSelected || isHovering ? 1 : 0)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(tint)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: -3, y: -3)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .gesture(resize)
            }
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .position(x: rect.midX, y: rect.midY)
            .opacity(mask.isEnabled ? 1 : 0.35)
            .contentShape(shape)
            .onTapGesture(perform: select)
            .onHover { isHovering = $0 }
            .gesture(reframe)
            .animation(InspectorMotion.hover, value: isSelected)
            .animation(InspectorMotion.hover, value: isHovering)
    }

    private var reframe: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragOrigin ?? mask.rect
                dragOrigin = start
                select()
                move(VideoMask.clampedRect(CGRect(
                    x: start.minX + value.translation.width / frame.width,
                    y: start.minY + value.translation.height / frame.height,
                    width: start.width,
                    height: start.height
                )))
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragOrigin ?? mask.rect
                dragOrigin = start
                move(VideoMask.clampedRect(CGRect(
                    x: start.minX,
                    y: start.minY,
                    width: max(VideoMask.minimumSize, start.width + value.translation.width / frame.width),
                    height: max(VideoMask.minimumSize, start.height + value.translation.height / frame.height)
                )))
            }
            .onEnded { _ in dragOrigin = nil }
    }
}
