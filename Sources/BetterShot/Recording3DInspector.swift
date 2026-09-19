// SPDX-License-Identifier: AGPL-3.0-only
// Thumbnail geometry adapts Cap's three-d.ts, Copyright (c) 2023-present Cap Software, Inc.
// Swift adaptation Copyright (c) 2026 Kartik Labhshetwar. See Resources/Licenses/NOTICE.md.
import SwiftUI
import simd

struct Recording3DInspector: View {
    enum Panel: String, CaseIterable {
        case look = "Look", camera = "Camera", blur = "Depth Blur", keyframes = "Keyframes", timing = "Timing"
    }
    @Bindable var model: RecordingStudioModel
    @State var panel: Panel = .look
    @State private var showsMoves = true
    @State private var editsEnd = false
    @State private var showsAutoScene = false
    @State private var confirmsRemoval = false

    var body: some View {
        StudioEffectSection(title: "3D Shots", systemImage: "cube.transparent", accessory: {
            Button { model.add3DShot(at: model.currentTime) } label: { Image(systemName: "plus") }
                .buttonStyle(EditorButtonStyle()).accessibilityLabel("Add 3D shot at playhead")
                .help("Add 3D shot at playhead")
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Button { showsAutoScene = true } label: {
                    Label("Auto Scene…", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorButtonStyle(bordered: true))
                .popover(isPresented: $showsAutoScene, arrowEdge: .trailing) {
                    Recording3DAutoScenePicker(model: model) { showsAutoScene = false }
                }
                if let shot = model.selected3DShot {
                    HStack(spacing: 8) {
                        Text(shot.title).font(.callout.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                        Toggle("Enable 3D shot", isOn: Binding(get: { shot.isEnabled }, set: { value in change { $0.isEnabled = value } }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    HStack(spacing: 8) {
                        Button { model.isPlaying ? model.pause() : model.play3DShot() } label: {
                            Label(model.isPlaying ? "Pause" : "Play Shot", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                        }
                        Spacer(minLength: 0)
                        Button { confirmsRemoval = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove 3D shot").help("Remove this shot")
                    }.buttonStyle(EditorButtonStyle())
                    Divider()
                    Picker("Edit", selection: $panel) {
                        ForEach(Panel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    switch panel {
                    case .look: lookControls(shot)
                    case .camera: cameraControls(shot)
                    case .blur: Recording3DBlurInspector(model: model)
                    case .keyframes: Recording3DKeyframeEditor(model: model)
                    case .timing: timingControls(shot)
                    }
                } else {
                    Text(model.timeline3D.shots.isEmpty
                        ? "Arrange a scene automatically, or add a shot at the playhead and choose its look."
                        : "Select a shot in the timeline to change its look, camera, or timing.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.timeline3D.shots.isEmpty {
                        Button("Add a Shot") { model.add3DShot(at: model.currentTime) }
                            .buttonStyle(EditorButtonStyle())
                    }
                }
                if let error = model.shot3DError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onChange(of: model.selected3DShotID, initial: true) { _, _ in
            if let shot = model.selected3DShot {
                showsMoves = Recording3DPreset.allCases.first(where: { $0.rawValue == shot.title })?.isMove ?? true
            }
            editsEnd = false
        }
        .onDisappear { model.end3DShotEdit(); model.cancel3DScenePreview() }
        .disabled(!model.isLoaded || model.isCroppingVideo || model.isEditingMasks)
        .alert("Remove this 3D shot?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Shot", role: .destructive) {
                if let shot = model.selected3DShot { model.remove3DShot(id: shot.id) }
            }
        }
    }

    private func lookControls(_ shot: Recording3DShot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Look type", selection: $showsMoves) {
                Text("Moves").tag(true)
                Text("Angles").tag(false)
            }.pickerStyle(.segmented).labelsHidden()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Recording3DPreset.allCases.filter { $0.isMove == showsMoves }, id: \.self) { preset in
                    Recording3DLookTile(preset: preset, selected: shot.title == preset.rawValue) {
                        change { $0.apply(preset) }
                        editsEnd = false
                        previewPose()
                    }
                }
            }
            Divider()
            Text("Scenes").font(.caption.weight(.semibold))
            ForEach(Recording3DScene.allCases, id: \.self) { scene in
                Button {
                    model.apply3DScene(scene.presets, weights: scene.weights, showcaseFinish: scene == .showcase)
                } label: {
                    HStack {
                        Label(scene.rawValue, systemImage: "square.stack.3d.up")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(EditorButtonStyle(bordered: true))
                .help(scene.summary + ". Replaces this shot’s range; shorter ranges use fewer shots.")
            }
            Text("Scenes replace the selected shot. Auto Scene arranges the whole video.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cameraControls(_ shot: Recording3DShot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Camera position", selection: $editsEnd) {
                Text("Start").tag(false)
                Text("End").tag(true)
            }.pickerStyle(.segmented).labelsHidden().onChange(of: editsEnd) { previewPose() }
            Recording3DPoseThumbnail(pose: editsEnd ? shot.endPose : shot.startPose).frame(height: 100)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button { change { $0.reverse() }; previewPose() } label: { Label("Reverse", systemImage: "arrow.left.arrow.right") }
                Button { change { $0.holdCamera() }; previewPose() } label: { Label("Still", systemImage: "pause") }
                    .disabled(shot.startPose == shot.endPose)
            }.buttonStyle(EditorButtonStyle())
            if shot.tracks?.contains(where: { $0.property.cameraKey != nil }) == true {
                Text("Keyframes control the animated properties. Open Keyframes to edit them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if (editsEnd ? shot.endPose : shot.startPose).camera != nil {
                cameraSlider("Tilt up/down", key: \.tiltX, range: -70...70, format: .degrees(signed: true))
                cameraSlider("Tilt left/right", key: \.tiltY, range: -60...60, format: .degrees(signed: true))
                cameraSlider("Distance", key: \.distance, range: 0.5...10, format: .decimal(fractionDigits: 2))
                cameraSlider("Roll", key: \.roll, range: -180...180, format: .degrees(signed: true))
                cameraSlider("Horizontal", key: \.panX, range: -3...3, format: .decimal(fractionDigits: 2))
                cameraSlider("Vertical", key: \.panY, range: -3...3, format: .decimal(fractionDigits: 2))
                DisclosureGroup("Advanced") {
                    VStack(spacing: 10) {
                        cameraSlider("Fold X", key: \.rotateX, range: -90...90, format: .degrees(signed: true))
                        cameraSlider("Fold Y", key: \.rotateY, range: -50...50, format: .degrees(signed: true))
                        cameraSlider("Field of view", key: \.fieldOfView, range: 10...100, format: .degrees())
                    }.padding(.top, 8)
                }
            } else {
                poseSlider("Tilt X", key: \.tiltX, range: -65...65, format: .degrees(signed: true))
                poseSlider("Tilt Y", key: \.tiltY, range: -65...65, format: .degrees(signed: true))
                poseSlider("Roll", key: \.roll, range: -45...45, format: .degrees(signed: true))
                poseSlider("Scale", key: \.scale, range: 0.3...2.5, format: .percent())
                poseSlider("Horizontal", key: \.panX, range: -0.5...0.5, format: .percent(signed: true))
                poseSlider("Vertical", key: \.panY, range: -0.5...0.5, format: .percent(signed: true))
                poseSlider("Perspective", key: \.perspective, range: 20...70, format: .degrees())
            }
            HStack {
                Button { flip(horizontal: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .accessibilityLabel("Flip horizontally").help("Mirror the camera horizontally")
                Button { flip(horizontal: false) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    .accessibilityLabel("Flip vertically").help("Mirror the camera vertically")
                Spacer(minLength: 0)
                Button("Reset") {
                    change { shot in
                        shot.tracks = shot.tracks?.filter { $0.property.cameraKey == nil }
                        let modern = (editsEnd ? shot.endPose : shot.startPose).camera != nil
                        let pose = modern ? Recording3DPose(camera: .init(distance: 4.5, fieldOfView: 24)) : .identity
                        if editsEnd { shot.endPose = pose } else { shot.startPose = pose }
                    }
                    previewPose()
                }.help("Reset this position and remove camera keyframes")
            }.buttonStyle(EditorButtonStyle())
        }
    }

    private func timingControls(_ shot: Recording3DShot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shotSlider("Start (s)", key: \.start, range: model.boundsFor3DShot(shot).lowerBound...(shot.end - Recording3DShot.minimumDuration))
            shotSlider("End (s)", key: \.end, range: (shot.start + Recording3DShot.minimumDuration)...model.boundsFor3DShot(shot).upperBound)
            Picker("Motion", selection: Binding(get: { shot.easing }, set: { value in change { $0.easing = value } })) {
                ForEach(Recording3DEasing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            transitionSlider("Ease in (s)", entry: true)
            transitionSlider("Ease out (s)", entry: false)
            Text("Zero cuts directly to the shot. Add an ease to blend with the flat view.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func change(_ edit: (inout Recording3DShot) -> Void) {
        guard var shot = model.selected3DShot else { return }
        edit(&shot)
        model.update3DShot(shot)
    }

    private func previewPose() {
        guard let shot = model.selected3DShot else { return }
        model.pause()
        let inset = min((editsEnd ? shot.transitionOut : shot.transitionIn) ?? shot.transition, (shot.end - shot.start) / 2)
        let time = editsEnd ? floor((shot.end - max(inset, 0.001)) * 60) / 60 : ceil((shot.start + inset) * 60 - 0.000_001) / 60
        model.seek(to: max(shot.start, time))
    }

    private func poseSlider(_ title: String, key: WritableKeyPath<Recording3DPose, Double>,
                            range: ClosedRange<CGFloat>, format: InspectorValueFormat) -> some View {
        InspectorSlider(title, value: Binding(get: {
            guard let shot = model.selected3DShot else { return 0 }
            return CGFloat((editsEnd ? shot.endPose : shot.startPose)[keyPath: key])
        }, set: { value in
            change { if editsEnd { $0.endPose[keyPath: key] = value } else { $0.startPose[keyPath: key] = value } }
        }), range: range, format: format, onEditingChanged: { editing in
            if editing { model.begin3DShotEdit(); previewPose() }
            else { model.end3DShotEdit() }
        })
    }

    private func cameraSlider(_ title: String, key: WritableKeyPath<Recording3DCamera, Double>,
                              range: ClosedRange<CGFloat>, format: InspectorValueFormat) -> some View {
        InspectorSlider(title, value: Binding(get: {
            guard let shot = model.selected3DShot else { return 0 }
            return CGFloat((editsEnd ? shot.endPose : shot.startPose).camera?[keyPath: key] ?? 0)
        }, set: { value in
            change { shot in
                if editsEnd { shot.endPose.camera?[keyPath: key] = value }
                else { shot.startPose.camera?[keyPath: key] = value }
            }
        }), range: range, format: format, onEditingChanged: { editing in
            if editing { model.begin3DShotEdit(); previewPose() }
            else { model.end3DShotEdit() }
        })
        .disabled(model.selected3DShot?.tracks?.contains(where: { $0.property.cameraKey == key }) == true)
    }

    private func transitionSlider(_ title: String, entry: Bool) -> some View {
        InspectorSlider(title, value: Binding(get: {
            guard let shot = model.selected3DShot else { return 0 }
            return CGFloat((entry ? shot.transitionIn : shot.transitionOut) ?? shot.transition)
        }, set: { value in
            change { if entry { $0.transitionIn = value } else { $0.transitionOut = value } }
        }), range: 0...min(2, ((model.selected3DShot?.end ?? 0) - (model.selected3DShot?.start ?? 0)) / 2),
            format: .decimal(fractionDigits: 2), onEditingChanged: { active in
                if active { model.begin3DShotEdit() } else { model.end3DShotEdit() }
            })
    }

    private func shotSlider(_ title: String, key: WritableKeyPath<Recording3DShot, Double>,
                            range: ClosedRange<Double>) -> some View {
        InspectorSlider(title, value: Binding(get: { model.selected3DShot?[keyPath: key] ?? 0 },
            set: { value in change { $0[keyPath: key] = value } }), range: CGFloat(range.lowerBound)...CGFloat(range.upperBound),
            format: .decimal(fractionDigits: 2), onEditingChanged: { editing in
                if editing { model.begin3DShotEdit() } else { model.end3DShotEdit() }
            })
    }

    private func flip(horizontal: Bool) {
        change { $0.flip(horizontal: horizontal) }
        previewPose()
    }
}

struct Recording3DBlurInspector: View {
    @Bindable var model: RecordingStudioModel
    private var blur: Recording3DBlur { model.selected3DShot?.blur ?? .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Depth Blur").font(.caption.weight(.semibold))
            Picker("Focus", selection: Binding(get: { blur.mode }, set: { mode in
                change { blur in
                    blur.mode = mode
                    switch mode {
                    case .none: break
                    case .radial: blur.focusX = 0.37; blur.focusY = 0.5; blur.focusSize = 0.5
                    case .directional: blur.position = 0.5; blur.angle = 0
                    case .tiltShift: blur.focusSize = 0.1; blur.focusY = 0.5; blur.angle = 45
                    }
                    if mode != .none && blur.strength == 0 { blur.strength = 19 }
                }
            })) {
                ForEach(Recording3DBlur.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            if blur.mode != .none {
                Toggle("Bokeh highlights", isOn: Binding(get: { blur.bokeh }, set: { enabled in change { $0.bokeh = enabled } }))
                    .toggleStyle(.switch).controlSize(.small)
                slider("Strength", .strength, format: .decimal(fractionDigits: 1))
                slider("Falloff", .falloff)
                if blur.mode == .directional {
                    slider("Position", .position)
                } else {
                    slider("Focus X", .focusX)
                    slider("Focus Y", .focusY)
                    slider("Focus size", .focusSize)
                }
                if blur.mode != .radial { slider("Angle", .angle, format: .degrees()) }
                Text("Bokeh softens highlights into discs. Focus Y runs from bottom to top. Animated controls are edited in Keyframes.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func change(_ edit: (inout Recording3DBlur) -> Void) {
        guard var shot = model.selected3DShot else { return }
        var next = shot.blur ?? .none
        edit(&next); shot.blur = next.sanitized
        model.update3DShot(shot)
    }
    private func slider(_ title: String, _ property: Recording3DProperty, format: InspectorValueFormat = .percent()) -> some View {
        let key = property.blurKey!, range = property.bounds(blur: blur)
        return InspectorSlider(title, value: Binding(get: { CGFloat(self.blur[keyPath: key]) }, set: { value in change { $0[keyPath: key] = Double(value) } }),
            range: CGFloat(range.lowerBound)...CGFloat(range.upperBound), format: format, onEditingChanged: { active in
                if active { model.begin3DShotEdit() } else { model.end3DShotEdit() }
            })
            .disabled(model.selected3DShot?.tracks?.contains(where: { $0.property == property }) == true)
    }
}

struct Recording3DAutoScenePicker: View {
    @Bindable var model: RecordingStudioModel
    var dismiss: () -> Void
    @State private var count = 3
    @State private var confirmsReplacement = false
    private var maximum: Int { Recording3DTimeline.maximumAutoShots(duration: model.duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Auto Scene").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Arrange camera moves across your video, with cuts aligned to your edits.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Shots", selection: $count) {
                ForEach(1...max(1, maximum), id: \.self) { value in Text("\(value)").tag(value) }
            }.pickerStyle(.segmented).disabled(maximum == 0)
            let shots = model.suggested3DShots(count: count)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(shots.enumerated()), id: \.offset) { index, shot in
                    HStack {
                        Text("\(index + 1). \(shot.title)").lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\((shot.end - shot.start).formatted(.number.precision(.fractionLength(1))))s")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }.font(.callout)
                }
            }
            Text(maximum == 0 ? "Auto Scene needs at least one second. You can still add a shot manually."
                : model.suggested3DScene == nil ? "Preview first. Apply when you’re happy with the sequence."
                : "Preview only — your existing shots are unchanged until you apply.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.suggested3DScene != nil && model.isPlaying ? "Pause" : "Preview") {
                    if model.suggested3DScene != nil && model.isPlaying { model.pause() }
                    else { model.previewAuto3DScene(count: count) }
                }.disabled(maximum == 0)
                Spacer(minLength: 8)
                Button("Cancel") { model.cancel3DScenePreview(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    model.pause()
                    if model.shots3D.isEmpty { apply() } else { confirmsReplacement = true }
                }.buttonStyle(EditorButtonStyle(selected: true)).keyboardShortcut(.defaultAction)
                    .disabled(maximum == 0)
            }.buttonStyle(EditorButtonStyle())
        }
        .padding(20).frame(width: 320)
        .onAppear { count = min(max(1, model.timeline3D.shots.isEmpty ? 3 : model.timeline3D.shots.count), max(1, maximum)) }
        .onChange(of: count) { model.cancel3DScenePreview() }
        .onDisappear { model.cancel3DScenePreview() }
        .alert("Replace all 3D shots?", isPresented: $confirmsReplacement) {
            Button("Cancel", role: .cancel) { }
            Button("Replace Shots", role: .destructive) { apply() }
        } message: { Text("This replaces the 3D track. You can undo the entire change once.") }
    }
    private func apply() { model.applyAuto3DScene(count: count); dismiss() }
}

private struct Recording3DLookTile: View {
    let preset: Recording3DPreset
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Recording3DPoseThumbnail(pose: hovered || focused ? preset.poses.1 : preset.poses.0)
                    .frame(height: 66)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected || focused ? Color.accentColor : Color.primary.opacity(hovered ? 0.25 : 0.12), lineWidth: selected || focused ? 2 : 1) }
                Text(preset.rawValue).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1).frame(maxWidth: .infinity)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).focused($focused)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered || focused)
        .accessibilityLabel(preset.rawValue)
        .accessibilityHint("Apply this look to the selected shot")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(preset.rawValue)
    }
}

/// Native vector thumbnails follow Cap's cssPreviewTransform geometry. Drawing
/// projected paths also works in accessibility/offscreen snapshots, without a
/// second decoder or a compositor-backed 3D layer for every preset card.
struct Recording3DPoseThumbnail: View {
    let pose: Recording3DPose
    var body: some View {
        Canvas { context, size in
            let p = pose.camera ?? Recording3DCamera(tiltX: pose.tiltX, tiltY: pose.tiltY,
                roll: pose.roll, distance: 2 / pose.scale, fieldOfView: pose.perspective,
                panX: pose.panX, panY: pose.panY)
            let tangent = tan(p.fieldOfView * .pi / 360)
            let scale = 0.5 / (max(p.distance, 0.05) * tangent)
            let perspective = size.height / (2 * tangent)
            let offset = size.height / 2 * scale
            func rotation(_ angle: Double, _ axis: SIMD3<Double>) -> simd_quatd {
                simd_quatd(angle: angle * .pi / 180, axis: axis)
            }
            let x = SIMD3<Double>(1, 0, 0), y = SIMD3<Double>(0, 1, 0), z = SIMD3<Double>(0, 0, 1)
            let orientation = rotation(p.tiltY, y) * rotation(-p.tiltX, x) * rotation(p.roll, z)
                * rotation(p.rotateY, y) * rotation(-p.rotateX, x)
            func project(_ point: CGPoint) -> CGPoint {
                let q = orientation.act(SIMD3((point.x - size.width / 2) * scale,
                    (point.y - size.height / 2) * scale, 0))
                let depth = max(0.05, 1 - q.z / perspective)
                return CGPoint(x: size.width / 2 + (q.x + p.panX * offset) / depth,
                    y: size.height / 2 + (q.y - p.panY * offset) / depth)
            }
            func projectedRect(_ rect: CGRect) -> Path {
                Path { path in
                    path.move(to: project(CGPoint(x: rect.minX, y: rect.minY)))
                    path.addLine(to: project(CGPoint(x: rect.maxX, y: rect.minY)))
                    path.addLine(to: project(CGPoint(x: rect.maxX, y: rect.maxY)))
                    path.addLine(to: project(CGPoint(x: rect.minX, y: rect.maxY)))
                    path.closeSubpath()
                }
            }
            let width = size.width * 0.75, height = width / 1.6
            let card = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            let outline = projectedRect(card)
            context.fill(outline, with: .color(Color(nsColor: .textBackgroundColor)))
            context.stroke(outline, with: .color(.primary.opacity(0.25)), lineWidth: 1)
            for (row, fraction) in [0.6, 0.75, 0.35].enumerated() {
                let rect = CGRect(x: card.minX + width * 0.1, y: card.minY + height * (0.22 + Double(row) * 0.22),
                    width: width * fraction, height: height * 0.09)
                context.fill(projectedRect(rect), with: .color(row == 2 ? .accentColor : .secondary.opacity(0.5)))
            }
        }.clipped().accessibilityHidden(true)
    }
}
