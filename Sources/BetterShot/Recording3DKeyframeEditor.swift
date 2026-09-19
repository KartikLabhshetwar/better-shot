import SwiftUI

struct Recording3DKeyframeEditor: View {
    @Bindable var model: RecordingStudioModel
    @State private var property = Recording3DProperty.panX
    @State private var selectedID: UUID?
    @State private var confirmsRemoval = false
    @State private var confirmsClear = false

    private var shot: Recording3DShot? { model.selected3DShot }
    private var frames: [Recording3DKeyframe] {
        shot?.tracks?.first(where: { $0.property == property })?.keyframes ?? []
    }
    private var selectedIndex: Int? { frames.firstIndex { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyframes").font(.caption.weight(.semibold))
            Picker("Property", selection: $property) {
                ForEach(Recording3DProperty.allCases.filter {
                    $0.blurKey != nil || shot?.startPose.camera != nil || shot?.endPose.camera != nil
                }) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: property) { selectedID = frames.first?.id }
            if property.blurKey != nil && (shot?.blur?.mode ?? Recording3DBlur.Mode.none) == Recording3DBlur.Mode.none {
                Text("Choose a focus mode in Depth Blur to preview this animation.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button { addKeyframe() } label: { Label("Add at Playhead", systemImage: "plus.diamond") }
                Spacer(minLength: 0)
                Button { confirmsRemoval = true } label: { Image(systemName: "trash") }
                    .disabled(selectedIndex == nil).accessibilityLabel("Remove selected keyframe")
            }
            .buttonStyle(EditorButtonStyle(horizontalPadding: 5))
            if frames.isEmpty {
                Text("Add a keyframe to adjust this property over time. Start and end positions are kept when the first keyframe is added.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.2)).frame(height: 2)
                        ForEach(frames) { frame in
                            Button {
                                selectedID = frame.id
                                if let shot { model.pause(); model.seek(to: shot.start + frame.position * (shot.end - shot.start)) }
                            } label: {
                                Image(systemName: frame.id == selectedID ? "diamond.fill" : "diamond")
                                    .foregroundStyle(frame.id == selectedID ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Keyframe at \((frame.position * ((shot?.end ?? 0) - (shot?.start ?? 0))).formatted(.number.precision(.fractionLength(2)))) seconds")
                            .accessibilityAddTraits(frame.id == selectedID ? .isSelected : [])
                            .position(x: 8 + frame.position * max(0, geometry.size.width - 16), y: 14)
                        }
                    }
                }
                .frame(height: 28)
            }
            if let index = selectedIndex, let shot {
                let frame = frames[index]
                let lower = index > 0 ? min(frame.position, frames[index - 1].position + 0.000_001) : 0
                let upper = index + 1 < frames.count ? max(frame.position, frames[index + 1].position - 0.000_001) : 1
                InspectorSlider("Time (s)", value: Binding(get: { CGFloat(frame.position * (shot.end - shot.start)) }, set: { value in
                    editFrame { $0.position = Double(value) / (shot.end - shot.start) }
                }), range: CGFloat(lower * (shot.end - shot.start))...CGFloat(upper * (shot.end - shot.start)), format: .decimal(fractionDigits: 2), onEditingChanged: editing)
                let range = property.bounds(blur: shot.blur ?? .none)
                InspectorSlider("Value", value: Binding(get: { CGFloat(frame.value) }, set: { value in editFrame { $0.value = Double(value) } }),
                    range: CGFloat(range.lowerBound)...CGFloat(range.upperBound), format: .decimal(fractionDigits: 2), onEditingChanged: editing)
                if index + 1 < frames.count {
                    Text("Curve to next keyframe").font(.caption2).foregroundStyle(.secondary)
                    Menu {
                        Button("Linear") { setCurve(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)) }
                        Button("Smooth") { setCurve(CGPoint(x: 0.65, y: 0), CGPoint(x: 0.35, y: 1)) }
                        Button("Ease In") { setCurve(CGPoint(x: 0.32, y: 0), CGPoint(x: 1, y: 1)) }
                        Button("Ease Out") { setCurve(CGPoint(x: 0, y: 0), CGPoint(x: 0.68, y: 1)) }
                    } label: { Label("Curve Preset", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    Recording3DCurveEditor(outgoing: handleBinding(incoming: false), incoming: handleBinding(incoming: true), editing: editing)
                    handleSlider("Out X", incoming: false, component: \.x)
                    handleSlider("Out Y", incoming: false, component: \.y)
                    handleSlider("In X", incoming: true, component: \.x)
                    handleSlider("In Y", incoming: true, component: \.y)
                } else {
                    Text("Select an earlier keyframe to edit the curve into the next one.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !frames.isEmpty {
                Button("Clear Property Animation") { confirmsClear = true }
                    .buttonStyle(EditorButtonStyle())
                    .help("Restore this property’s start/end settings")
            }
            Text("Keyframe times scale with the shot when you resize it. Curves override the shot’s Motion setting for this property.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: model.selected3DShotID, initial: true) { _, _ in
            property = shot?.tracks?.first?.property ?? (shot?.startPose.camera != nil ? .panX : .strength)
            selectedID = frames.first?.id
        }
        .onDisappear { model.end3DShotEdit() }
        .alert("Remove this keyframe?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Keyframe", role: .destructive) {
                updateFrames { $0.removeAll { $0.id == selectedID } }
                selectedID = nil
            }
        }
        .alert("Clear this property’s animation?", isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Animation", role: .destructive) {
                updateFrames { $0.removeAll() }; selectedID = nil
            }
        } message: { Text("Its start and end settings will apply again. Other properties keep their keyframes.") }
    }

    private func editing(_ active: Bool) {
        if active {
            model.begin3DShotEdit()
            if let shot, let index = selectedIndex {
                let time = shot.start + frames[index].position * (shot.end - shot.start)
                model.seek(to: min(time, shot.end - 1.0 / 60))
            }
        } else { model.end3DShotEdit() }
    }
    private func updateFrames(_ edit: (inout [Recording3DKeyframe]) -> Void) {
        guard var shot else { return }
        var next = frames
        edit(&next)
        var tracks = shot.tracks ?? []
        tracks.removeAll { $0.property == property }
        if !next.isEmpty { tracks.append(Recording3DTrack(property: property, keyframes: next)) }
        shot.tracks = tracks.isEmpty ? nil : tracks
        model.update3DShot(shot)
    }
    private func editFrame(_ edit: (inout Recording3DKeyframe) -> Void) {
        updateFrames { frames in
            if let index = frames.firstIndex(where: { $0.id == selectedID }) { edit(&frames[index]) }
        }
    }
    private func addKeyframe() {
        guard let shot else { return }
        let position = min(max((model.currentTime - shot.start) / (shot.end - shot.start), 0), 1)
        if let existing = frames.first(where: { abs($0.position - position) < 0.000_001 }) {
            selectedID = existing.id; return
        }
        func value(at position: Double) -> Double { shot.keyframeValue(for: property, at: position) }
        var key = Recording3DKeyframe(position: position, value: value(at: position))
        key.incoming = CGPoint(x: 1, y: 1); key.outgoing = .zero
        updateFrames { frames in
            if frames.isEmpty {
                frames = [0.0, 1.0].filter { abs($0 - position) >= 0.000_001 }.map {
                    Recording3DKeyframe(position: $0, value: value(at: $0), incoming: CGPoint(x: 1, y: 1), outgoing: .zero)
                }
            }
            frames.append(key)
        }
        selectedID = key.id
    }
    private func setCurve(_ outgoing: CGPoint, _ incoming: CGPoint) {
        updateFrames { frames in
            guard let i = frames.firstIndex(where: { $0.id == selectedID }), i + 1 < frames.count else { return }
            frames[i].outgoing = outgoing; frames[i + 1].incoming = incoming
        }
    }
    private func handleBinding(incoming: Bool) -> Binding<CGPoint> {
        Binding(get: {
            guard let index = selectedIndex, index + 1 < frames.count else { return .zero }
            return incoming ? frames[index + 1].incoming : frames[index].outgoing
        }, set: { value in
            updateFrames { frames in
                guard let i = frames.firstIndex(where: { $0.id == selectedID }), i + 1 < frames.count else { return }
                if incoming { frames[i + 1].incoming = value } else { frames[i].outgoing = value }
            }
        })
    }
    private func handleSlider(_ title: String, incoming: Bool, component: WritableKeyPath<CGPoint, CGFloat>) -> some View {
        let binding = handleBinding(incoming: incoming)
        return InspectorSlider(title, value: Binding(get: { binding.wrappedValue[keyPath: component] }, set: { value in
            var point = binding.wrappedValue; point[keyPath: component] = value; binding.wrappedValue = point
        }), range: 0...1, format: .decimal(fractionDigits: 2), onEditingChanged: editing)
    }
}

private struct Recording3DCurveEditor: View {
    @Binding var outgoing: CGPoint
    @Binding var incoming: CGPoint
    let editing: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let origin = CGPoint(x: 0, y: size.height), end = CGPoint(x: size.width, y: 0)
            let first = point(outgoing, size), second = point(incoming, size)
            ZStack {
                Path { path in
                    path.move(to: origin); path.addLine(to: first)
                    path.move(to: end); path.addLine(to: second)
                }.stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { path in
                    path.move(to: origin); path.addCurve(to: end, control1: first, control2: second)
                }.stroke(Color.accentColor, lineWidth: 2)
                handle($outgoing, at: first, size: size)
                handle($incoming, at: second, size: size)
            }
            .coordinateSpace(name: "3D curve")
        }
        .frame(height: 110).padding(8)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true) // The four InspectorSliders expose the same handles to keyboard/VoiceOver.
        .onDisappear { if dragging { editing(false) } }
    }
    private func point(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
    private func handle(_ value: Binding<CGPoint>, at point: CGPoint, size: CGSize) -> some View {
        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
            .frame(width: 24, height: 24).contentShape(Circle()).position(point)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("3D curve"))
                .onChanged { event in
                    if !dragging { dragging = true; editing(true) }
                    value.wrappedValue = CGPoint(x: min(max(event.location.x / size.width, 0), 1),
                                                 y: min(max(1 - event.location.y / size.height, 0), 1))
                }
                .onEnded { _ in dragging = false; editing(false) })
    }
}
