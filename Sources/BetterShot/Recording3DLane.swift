import SwiftUI

struct Recording3DLane: View {
    @Bindable var model: RecordingStudioModel
    let pointsPerSecond: CGFloat
    let visibleRange: ClosedRange<Double>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { location in
                    guard pointsPerSecond > 0 else { return }
                    model.add3DShot(at: Double(location.x / pointsPerSecond))
                }
            ForEach(model.timeline3D.shots.filter { $0.end >= visibleRange.lowerBound && $0.start <= visibleRange.upperBound }) { shot in
                Recording3DBlock(model: model, shot: shot, pointsPerSecond: pointsPerSecond)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D shots timeline")
        .contextMenu {
            Button("Add 3D Shot at Playhead") { model.add3DShot(at: model.currentTime) }
        }
    }
}

private struct Recording3DBlock: View {
    @Bindable var model: RecordingStudioModel
    let shot: Recording3DShot
    let pointsPerSecond: CGFloat
    @State private var dragBase: Recording3DShot?
    @State private var confirmsRemoval = false
    private var selected: Bool { model.selected3DShotID == shot.id }

    var body: some View {
        HStack(spacing: 0) {
            handle(leading: true)
            Button {
                model.select3DShot(id: shot.id)
                model.pause()
                model.seek(to: shot.start + min(0.5, (shot.end - shot.start) / 2))
            } label: {
                Label(shot.title, systemImage: "cube.transparent")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("3D shot: \(shot.title), \(shot.start.formatted(.number.precision(.fractionLength(2)))) to \(shot.end.formatted(.number.precision(.fractionLength(2)))) seconds")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .simultaneousGesture(drag(edge: nil))
            handle(leading: false)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(width: max(20, (shot.end - shot.start) * pointsPerSecond), height: 28)
        .background(selected ? Color.accentColor : Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .opacity(shot.isEnabled ? 1 : 0.5)
        .offset(x: shot.start * pointsPerSecond, y: 4)
        .help("\(shot.title) · Drag to move, drag edges to resize. Edit exact times in Effects.")
        .onDisappear {
            if dragBase != nil {
                dragBase = nil
                model.end3DShotEdit()
            }
        }
        .contextMenu {
            Button("Play Shot") { model.select3DShot(id: shot.id); model.play3DShot() }
            Button(shot.isEnabled ? "Disable Shot" : "Enable Shot") {
                model.select3DShot(id: shot.id)
                var next = shot; next.isEnabled.toggle(); model.update3DShot(next)
            }
            Button("Remove Shot", role: .destructive) { confirmsRemoval = true }
        }
        .alert("Remove this 3D shot?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Shot", role: .destructive) { model.remove3DShot(id: shot.id) }
        }
    }

    private func handle(leading: Bool) -> some View {
        Capsule().fill(.primary.opacity(0.5)).frame(width: 2, height: 12)
            .frame(width: 8, height: 28).contentShape(Rectangle())
            .gesture(drag(edge: leading))
            .accessibilityHidden(true) // Exact keyboard-editable times are in the inspector.
    }

    private func drag(edge: Bool?) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                guard pointsPerSecond > 0 else { return }
                if dragBase == nil {
                    dragBase = shot
                    model.select3DShot(id: shot.id)
                    model.begin3DShotEdit()
                }
                guard let base = dragBase else { return }
                let delta = Double(value.translation.width / pointsPerSecond)
                let bounds = model.boundsFor3DShot(base)
                let range: ClosedRange<Double>
                if let edge {
                    range = RecordingTimelineViewport.resizing(base.start...base.end, leading: edge,
                        by: delta, within: bounds, minimumDuration: Recording3DShot.minimumDuration)
                } else {
                    range = RecordingTimelineViewport.moving(base.start...base.end, by: delta, within: bounds)
                }
                var next = base; next.start = range.lowerBound; next.end = range.upperBound
                model.update3DShot(next)
            }
            .onEnded { _ in dragBase = nil; model.end3DShotEdit() }
    }
}
