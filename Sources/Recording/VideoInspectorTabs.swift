import SwiftUI

enum VideoInspectorTab: String, CaseIterable, Identifiable {
    case clip
    case motion
    case camera
    case overlay
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clip: "Clip"
        case .motion: "Motion"
        case .camera: "Camera"
        case .overlay: "Overlay"
        case .style: "Style"
        }
    }

    var icon: String {
        switch self {
        case .clip: "scissors"
        case .motion: "cursorarrow.motionlines"
        case .camera: "person.crop.circle"
        case .overlay: "square.on.square.dashed"
        case .style: "paintbrush"
        }
    }

    var shortcut: Character {
        switch self {
        case .clip: "1"
        case .motion: "2"
        case .camera: "3"
        case .overlay: "4"
        case .style: "5"
        }
    }
}

/// Cap groups the sidebar behind icon tabs so one scroll does not hold every control at once.
struct InspectorTabBar: View {
    @Binding var selection: VideoInspectorTab
    let isEnabled: (VideoInspectorTab) -> Bool

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VideoInspectorTab.allCases) { tab in
                let enabled = isEnabled(tab)
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium))
                            .kerning(0.1)
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                }
                .buttonStyle(.inspectorPress(scale: 0.96))
                .keyboardShortcut(KeyEquivalent(tab.shortcut), modifiers: .command)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.35)
                .help(enabled ? "\(tab.title) (\u{2318}\(tab.shortcut))" : "\(tab.title) is unavailable for this recording")
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(InspectorBarMaterial())
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: selection)
    }
}

/// Speed on the whole recording, or on just the selected clip once the timeline has been cut.
struct VideoSpeedSection: View {
    @Bindable var model: VideoEditorModel

    private static let presets: [Double] = [0.5, 1, 1.5, 2, 3, 4]

    private var scope: String {
        model.selectedClipID == nil ? "Applies to the whole recording." : "Applies to the selected clip."
    }

    var body: some View {
        InspectorSection("Speed") {
            accessory
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(Self.presets, id: \.self) { preset in
                        InspectorPill(
                            Self.label(preset),
                            isActive: abs(model.activeSpeed - preset) < 0.001,
                            fillsWidth: true
                        ) {
                            model.setSpeed(preset)
                        }
                    }
                }

                Slider(
                    value: Binding(get: { model.activeSpeed }, set: { model.setSpeed($0) }),
                    in: Clip.minimumSpeed...Clip.maximumSpeed
                )
                .controlSize(.small)

                InspectorRow("Audio") {
                    HStack(spacing: 3) {
                        ForEach(ClipSpeedAudioMode.allCases) { mode in
                            InspectorPill(
                                mode.title,
                                systemImage: mode.icon,
                                isActive: model.activeAudioMode == mode,
                                fillsWidth: true
                            ) {
                                model.setAudioMode(mode)
                            }
                            .help(Self.audioHelp(mode))
                        }
                    }
                }

                InspectorCaption(scope)
            }
        }
    }

    private var accessory: some View {
        Text(Self.timecode(model.timelineDuration))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .contentTransition(.numericText())
    }

    private static func audioHelp(_ mode: ClipSpeedAudioMode) -> String {
        switch mode {
        case .mute: "Drop the audio for this range."
        case .maintainPitch: "Resample so voices keep their pitch at any speed."
        case .matchSpeed: "Let the pitch rise and fall with the speed, the way tape does."
        }
    }

    private static func label(_ speed: Double) -> String {
        "\(speed.formatted())\u{00D7}"
    }

    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A ring where each recorded press landed, so a viewer can see the pointer act.
struct VideoCursorSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        InspectorSection("Clicks") {
            Toggle("", isOn: $model.clickHighlightsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!model.hasClicks)
        } content: {
            if model.hasClicks {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorRow("Size") {
                        Slider(value: $model.clickHighlightScale, in: 0.5...3)
                            .controlSize(.small)
                            .disabled(!model.clickHighlightsEnabled)
                    }

                    InspectorCaption("\(model.clickPresses.count) clicks were recorded. Each one draws a ring where you clicked.")
                }
            } else {
                InspectorCaption("No clicks were recorded. Pointer capture has to be on before you record.")
            }
        }
    }
}

/// Cap re-draws the pointer from the recorded path, and so can we, but only when the recording left the real one out.
struct VideoPointerSection: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        InspectorSection("Pointer") {
            Toggle("", isOn: $model.cursorStyle.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!model.canDrawCursor)
        } content: {
            if model.canDrawCursor {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(CursorStyle.Motion.allCases) { motion in
                            InspectorPill(motion.title, isActive: model.cursorStyle.motion == motion, fillsWidth: true) {
                                model.cursorStyle.motion = motion
                            }
                        }
                    }
                    .disabled(!model.cursorStyle.isEnabled)

                    InspectorRow("Size") {
                        Slider(value: $model.cursorStyle.size, in: 0.5...3)
                            .controlSize(.small)
                            .disabled(!model.cursorStyle.isEnabled)
                    }

                    InspectorCaption(model.recordedSystemCursor
                        ? "This recording kept the real pointer, so a drawn one lands on top of it. Turn off \u{201C}The mouse cursor\u{201D} in Settings, Recording to draw a smoothed one instead."
                        : "The pointer is drawn from the path you moved, so a shaky hand glides and a click lands on the spot.")
                }
            } else {
                InspectorCaption("No pointer movement was recorded, so there is nothing to draw a cursor from.")
            }
        }
    }
}

/// A transition needs a clip on each side, so it hangs off the selected clip and describes how the one before it hands over.
struct VideoTransitionSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximum: TimeInterval {
        max(ClipTransition.minimumDuration, model.maximumTransitionDuration)
    }

    var body: some View {
        InspectorSection("Transition") {
            if let transition = model.activeTransition {
                Text(Self.seconds(transition.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    InspectorPill("None", systemImage: "scissors", isActive: model.activeTransition == nil, fillsWidth: true) {
                        model.setTransition(nil)
                    }
                    .help("Cut straight from one clip to the next.")

                    ForEach(ClipTransitionKind.allCases) { kind in
                        InspectorPill(
                            kind.title,
                            systemImage: kind.icon,
                            isActive: model.activeTransition?.kind == kind,
                            fillsWidth: true
                        ) {
                            model.setTransition(ClipTransition(kind: kind, duration: model.activeTransition?.duration ?? ClipTransition.defaultDuration))
                        }
                        .help(Self.help(kind))
                    }
                }
                .disabled(!model.canSetTransition)

                if let transition = model.activeTransition {
                    InspectorRow("Length") {
                        Slider(
                            value: Binding(
                                get: { min(transition.duration, maximum) },
                                set: { model.setTransition(ClipTransition(kind: transition.kind, duration: $0)) }
                            ),
                            in: ClipTransition.minimumDuration...maximum
                        )
                        .controlSize(.small)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                InspectorCaption(caption)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 1), value: model.activeTransition)
        }
    }

    private var caption: String {
        guard model.canSetTransition else {
            return model.clips.count > 1
                ? "Select a clip to blend it into the one before it."
                : "Cut the timeline first, then blend the pieces together."
        }
        return "Blends into the clip before this one. Shows up in the export."
    }

    private static func help(_ kind: ClipTransitionKind) -> String {
        switch kind {
        case .crossFade: "Dissolve one clip straight into the next."
        case .fadeThroughBlack: "Dip to black in between, then come back up."
        }
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }
}

/// Two coupled angles deserve one control, so the pad takes the pointer straight onto the tilt instead of asking you to reason about two sliders.
private struct TiltPad: View {
    @Binding var tiltX: Double
    @Binding var tiltY: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grab: CGPoint?
    @State private var isHovering = false

    private static let side: CGFloat = 104
    private static let knob: CGFloat = 22

    private var half: Double { Double(Self.side - Self.knob) / 2 }

    private var offset: CGSize {
        CGSize(
            width: tiltY / Camera3D.maximumTilt * half,
            height: tiltX / Camera3D.maximumTilt * half
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            Path { path in
                path.move(to: CGPoint(x: Self.side / 2, y: 8))
                path.addLine(to: CGPoint(x: Self.side / 2, y: Self.side - 8))
                path.move(to: CGPoint(x: 8, y: Self.side / 2))
                path.addLine(to: CGPoint(x: Self.side - 8, y: Self.side / 2))
            }
            .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: Self.knob, height: Self.knob)
                .shadow(color: .black.opacity(0.3), radius: grab == nil ? 2 : 6, y: grab == nil ? 1 : 3)
                .scaleEffect(grab == nil ? (isHovering ? 1.08 : 1) : 1.16)
                .offset(offset)
        }
        .frame(width: Self.side, height: Self.side)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let origin = grab ?? CGPoint(x: tiltY, y: tiltX)
                    if grab == nil { grab = origin }
                    tiltY = Self.clamped(Double(origin.x) + Double(value.translation.width) / half * Camera3D.maximumTilt)
                    tiltX = Self.clamped(Double(origin.y) + Double(value.translation.height) / half * Camera3D.maximumTilt)
                }
                .onEnded { _ in grab = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.8)) {
                tiltX = 0
                tiltY = 0
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: grab == nil)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: isHovering)
        .accessibilityElement()
        .accessibilityLabel("Tilt")
        .accessibilityValue("\(Int(tiltY))° across, \(Int(tiltX))° down")
        .accessibilityAdjustableAction { direction in
            tiltY = Self.clamped(tiltY + (direction == .increment ? 5 : -5))
        }
        .help("Drag to tilt the card. Double-click to level it.")
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, -Camera3D.maximumTilt), Camera3D.maximumTilt)
    }
}

/// Cap's 3D camera, boiled down to the pose of the card: which way it faces, how far it leans, and how hard the lens sells the depth.
struct VideoPerspectiveSection: View {
    @Bindable var model: VideoEditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InspectorSection("Perspective") {
            if !model.pose.isNeutral {
                Text("\(Int(model.pose.tiltY))°, \(Int(model.pose.tiltX))°")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                TiltPad(tiltX: $model.pose.tiltX, tiltY: $model.pose.tiltY)
                    .frame(maxWidth: .infinity)

                InspectorSlider(
                    "Roll",
                    value: Binding(get: { CGFloat(model.pose.roll) }, set: { model.pose.roll = Double($0) }),
                    range: CGFloat(-Camera3D.maximumRoll)...CGFloat(Camera3D.maximumRoll),
                    format: .degrees
                )

                InspectorSlider(
                    "Depth",
                    value: Binding(get: { CGFloat(model.pose.perspective) }, set: { model.pose.perspective = Double($0) }),
                    range: 0...1,
                    format: .percent()
                )
                .disabled(model.pose.isNeutral)

                InspectorCaption("Tips the whole card in space, background and shadow included. Shows up in the export.")

                if !model.pose.isNeutral {
                    InspectorPill("Reset Perspective", systemImage: "arrow.counterclockwise", fillsWidth: true) {
                        model.pose = .neutral
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : InspectorMotion.reveal, value: model.pose.isNeutral)
        }
    }
}
