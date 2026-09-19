import SwiftUI

struct Recording3DInspector: View {
    @Bindable var model: RecordingStudioModel
    @State private var showsMoves = true
    @State private var editsEnd = false
    @State private var detail = 0
    @State private var autoCount = 3
    @State private var confirmsAutoScene = false
    @State private var confirmsRemoval = false

    var body: some View {
        StudioEffectSection(title: "3D Shots", systemImage: "cube.transparent", accessory: {
            Button { model.add3DShot(at: model.currentTime) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(EditorButtonStyle())
            .accessibilityLabel("Add 3D shot at playhead")
            .help("Add 3D shot at playhead")
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if model.timeline3D.shots.isEmpty {
                    Text("Give your recording depth with a camera move or a drifting angle.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Add 3D Shot") { model.add3DShot(at: model.currentTime) }
                        .buttonStyle(EditorButtonStyle())
                }
                Text("Auto scene").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Auto scene", selection: $autoCount) {
                        ForEach(1...6, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Auto scene shot count")
                    Button("Generate") {
                        if model.shots3D.isEmpty { applyAutoScene() }
                        else { confirmsAutoScene = true }
                    }
                    .buttonStyle(EditorButtonStyle())
                    .disabled(model.duration < Double(autoCount) * Recording3DShot.minimumDuration)
                    .help("Auto Scene: arrange shots across the whole video")
                    .accessibilityLabel("Generate auto scene")
                }
                if let shot = model.selected3DShot {
                    selectedControls(shot)
                } else if !model.timeline3D.shots.isEmpty {
                    Text("Select a 3D shot in the timeline to edit its look and timing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.shot3DError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onChange(of: model.selected3DShotID, initial: true) { _, _ in
            if let shot = model.selected3DShot { showsMoves = Recording3DPreset.allCases.first(where: { $0.rawValue == shot.title })?.isMove ?? (shot.startPose != shot.endPose) }
            editsEnd = false
        }
        .disabled(!model.isLoaded || model.isCroppingVideo || model.isEditingMasks)
        .alert("Replace all 3D shots?", isPresented: $confirmsAutoScene) {
            Button("Cancel", role: .cancel) { }
            Button("Replace Shots", role: .destructive) { applyAutoScene() }
        } message: { Text("Auto Scene replaces the 3D track. You can undo this change.") }
        .alert("Remove this 3D shot?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Shot", role: .destructive) {
                if let shot = model.selected3DShot { model.remove3DShot(id: shot.id) }
            }
        }
    }

    private func applyAutoScene() {
        let pool: [Recording3DPreset] = autoCount == 1 ? [.glide] : [.closeUp, .topDown, .pullBack, .unfold, .perspective, .center]
        model.apply3DScene(Array(pool.prefix(autoCount)), wholeMovie: true, showcaseFinish: autoCount >= 3)
    }

    private func selectedControls(_ shot: Recording3DShot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(shot.title).font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Toggle("Enable 3D shot", isOn: Binding(get: { shot.isEnabled }, set: { value in
                    change { $0.isEnabled = value }
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            HStack {
                Button { model.play3DShot() } label: { Label("Play Shot", systemImage: "play.fill") }
                Spacer(minLength: 0)
                Button { confirmsRemoval = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove 3D shot")
            }
            .buttonStyle(EditorButtonStyle())

            Picker("Look", selection: $showsMoves) {
                Text("Moves").tag(true)
                Text("Angles").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
                ForEach(Recording3DPreset.allCases.filter { $0.isMove == showsMoves }, id: \.self) { preset in
                    Button {
                        change { $0.apply(preset) }
                        previewPose()
                    } label: {
                        VStack(spacing: 5) {
                            Recording3DPoseThumbnail(pose: preset.poses.0)
                                .frame(height: 42)
                            Text(preset.rawValue).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorButtonStyle(selected: shot.title == preset.rawValue, horizontalPadding: 4))
                    .accessibilityLabel(preset.rawValue)
                    .accessibilityAddTraits(shot.title == preset.rawValue ? .isSelected : [])
                }
            }
            Menu {
                ForEach(Recording3DScene.allCases, id: \.self) { scene in
                    Button(scene.rawValue) { model.apply3DScene(scene.presets, weights: scene.weights, showcaseFinish: scene == .showcase) }
                }
            } label: { Label("3-Shot Scene", systemImage: "square.stack.3d.up") }
            .disabled(shot.end - shot.start < 3 * Recording3DShot.minimumDuration)
            .help("Replace this shot with three shots across the same time range")

            Divider()
            Picker("3D controls", selection: $detail) {
                Text("Camera").tag(0)
                Text("Blur").tag(1)
                Text("Keyframes").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            if detail == 0 {
            Picker("Camera pose", selection: $editsEnd) {
                Text("Start").tag(false)
                Text("End").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: editsEnd) { previewPose() }
            HStack(spacing: 6) {
                Recording3DPoseThumbnail(pose: editsEnd ? shot.endPose : shot.startPose)
                    .frame(width: 68, height: 44)
                Button { change { $0.reverse() }; previewPose() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("Swap start and end")
                    .help("Swap the start and end camera positions")
                Button("Still") { change { $0.holdCamera() }; previewPose() }
                    .help("Hold the start camera position for the whole shot")
            }
            .buttonStyle(EditorButtonStyle(horizontalPadding: 6))
            if shot.tracks?.contains(where: { $0.property.cameraKey != nil }) == true {
                Text("Animated camera properties are controlled by Keyframes below.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if (editsEnd ? shot.endPose : shot.startPose).camera != nil {
                cameraSlider("Tilt X", key: \.tiltX, range: -70...70, format: .degrees(signed: true))
                cameraSlider("Tilt Y", key: \.tiltY, range: -60...60, format: .degrees(signed: true))
                cameraSlider("Roll", key: \.roll, range: -180...180, format: .degrees(signed: true))
                cameraSlider("Fold X", key: \.rotateX, range: -90...90, format: .degrees(signed: true))
                cameraSlider("Fold Y", key: \.rotateY, range: -50...50, format: .degrees(signed: true))
                cameraSlider("Distance", key: \.distance, range: 0.5...10, format: .decimal(fractionDigits: 2))
                cameraSlider("Field of view", key: \.fieldOfView, range: 10...100, format: .degrees())
                cameraSlider("Horizontal", key: \.panX, range: -3...3, format: .decimal(fractionDigits: 2))
                cameraSlider("Vertical", key: \.panY, range: -3...3, format: .decimal(fractionDigits: 2))
            } else {
            poseSlider("Tilt X", key: \.tiltX, range: -65...65, format: .degrees(signed: true))
            poseSlider("Tilt Y", key: \.tiltY, range: -65...65, format: .degrees(signed: true))
            poseSlider("Roll", key: \.roll, range: -45...45, format: .degrees(signed: true))
            poseSlider("Scale", key: \.scale, range: 0.3...2.5, format: .percent())
            poseSlider("Horizontal", key: \.panX, range: -0.5...0.5, format: .percent(signed: true))
            poseSlider("Vertical", key: \.panY, range: -0.5...0.5, format: .percent(signed: true))
            poseSlider("Perspective", key: \.perspective, range: 20...70, format: .degrees())
            }
            HStack(spacing: 4) {
                Button("Flip H") { flip(horizontal: true) }.help("Mirror the camera move horizontally")
                Button("Flip V") { flip(horizontal: false) }.help("Mirror the camera move vertically")
                Spacer(minLength: 0)
                Button("Reset") { change { $0.tracks = $0.tracks?.filter { $0.property.cameraKey == nil }; if editsEnd { $0.endPose = .identity } else { $0.startPose = .identity } }; previewPose() }
                    .help("Reset the selected camera position and remove camera keyframes")
            }
            .buttonStyle(EditorButtonStyle(horizontalPadding: 3))
            .font(.caption)
            } else if detail == 1 {
                Recording3DBlurInspector(model: model)
            } else {
                Recording3DKeyframeEditor(model: model)
            }
            Divider()
            Picker("Motion", selection: Binding(get: { shot.easing }, set: { value in change { $0.easing = value } })) {
                ForEach(Recording3DEasing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            shotSlider("Start (s)", key: \.start, range: model.boundsFor3DShot(shot).lowerBound...(shot.end - Recording3DShot.minimumDuration))
            shotSlider("End (s)", key: \.end, range: (shot.start + Recording3DShot.minimumDuration)...model.boundsFor3DShot(shot).upperBound)
            transitionSlider("Ease in (s)", entry: true)
            transitionSlider("Ease out (s)", entry: false)
            Text("Transitions ease into and out of the flat view. Crop and mask editing temporarily show the flat source.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .id(shot.id)
    }

    private func change(_ edit: (inout Recording3DShot) -> Void) {
        guard var shot = model.selected3DShot else { return }
        edit(&shot)
        model.update3DShot(shot)
    }

    private func previewPose() {
        guard let shot = model.selected3DShot else { return }
        model.pause()
        let inset = min(max((editsEnd ? shot.transitionOut : shot.transitionIn) ?? shot.transition, 0.01), (shot.end - shot.start) / 2)
        model.seek(to: editsEnd ? shot.end - inset : shot.start + inset)
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

struct Recording3DPoseThumbnail: View {
    let pose: Recording3DPose
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.secondary).frame(height: 3)
                Capsule().fill(.secondary).frame(width: size.width * 0.4, height: 3)
                Capsule().fill(Color.accentColor).frame(width: size.width * 0.25, height: 3)
            }
            .padding(8)
            .frame(width: size.width * 0.8, height: size.height * 0.75)
            .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            .position(x: size.width / 2, y: size.height / 2)
            .frame(width: size.width, height: size.height)
            .projectionEffect(ProjectionTransform(pose.projection(in: size)))
        }
        .clipped()
        .accessibilityHidden(true)
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
                Text("Bokeh softens highlights into discs. Focus Y runs from bottom to top. Animated controls are edited in the Keyframes tab.")
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
