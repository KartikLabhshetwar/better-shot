import SwiftUI

/// Direct orbit editing; the adjacent tilt sliders provide precise keyboard input.
struct Recording3DOrbitPad: View {
    @Binding var pose: Recording3DPose
    let editing: (Bool) -> Void
    @State private var dragStart: Recording3DPose?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.primary.opacity(0.035)
                Path { path in
                    for fraction in [1.0 / 3, 2.0 / 3] {
                        path.move(to: CGPoint(x: geometry.size.width * fraction, y: 0))
                        path.addLine(to: CGPoint(x: geometry.size.width * fraction, y: geometry.size.height))
                        path.move(to: CGPoint(x: 0, y: geometry.size.height * fraction))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * fraction))
                    }
                }.stroke(.primary.opacity(0.12), lineWidth: 0.5)
                Recording3DPoseThumbnail(pose: pose).padding(12)
                let xLimit = pose.camera == nil ? 65.0 : 60.0
                let yLimit = pose.camera == nil ? 65.0 : 70.0
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                    .position(x: 10 + ((pose.camera?.tiltY ?? pose.tiltY) / xLimit + 1) / 2 * max(0, geometry.size.width - 20),
                              y: 10 + (1 - (pose.camera?.tiltX ?? pose.tiltX) / yLimit) / 2 * max(0, geometry.size.height - 20))
                Text("Drag to orbit").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(EditorChrome.border, lineWidth: 0.5) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { event in
                    if dragStart == nil { dragStart = pose; editing(true) }
                    if let dragStart { pose = Self.orbit(dragStart, translation: event.translation, size: geometry.size) }
                }
                .onEnded { _ in dragStart = nil; editing(false) })
        }
        .frame(height: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera orbit preview")
        .accessibilityHint("Use the Tilt up/down and Tilt left/right controls below for precise adjustments.")
        .help("Drag to orbit. Use the tilt sliders below for exact angles.")
        .onDisappear { if dragStart != nil { dragStart = nil; editing(false) } }
    }

    static func orbit(_ start: Recording3DPose, translation: CGSize, size: CGSize) -> Recording3DPose {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              translation.width.isFinite, translation.height.isFinite else { return start }
        var pose = start
        if pose.camera != nil {
            pose.camera?.tiltX -= Double(translation.height / size.height) * 140
            pose.camera?.tiltY += Double(translation.width / size.width) * 120
        } else {
            pose.tiltX -= Double(translation.height / size.height) * 130
            pose.tiltY += Double(translation.width / size.width) * 130
        }
        return pose.sanitized
    }
}
