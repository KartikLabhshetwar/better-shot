//
//  RecordingZoomFocusPad.swift
//  BetterShot
//

import SwiftUI

/// A direct-manipulation editor for a fixed zoom cue's normalized source
/// target. The dot is the requested subject; the outlined rectangle is the
/// actual source area that remains visible at the cue's magnification.
struct RecordingZoomFocusPad: View {
    @Binding var position: CGPoint
    let magnification: Double

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let sourceSize = proxy.size
            let targetPoint = CGPoint(
                x: normalized(position.x) * sourceSize.width,
                y: normalized(position.y) * sourceSize.height
            )
            let safeMagnification = max(1, magnification)
            let viewportSize = CGSize(
                width: sourceSize.width / safeMagnification,
                height: sourceSize.height / safeMagnification
            )
            let halfViewport = CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
            let viewportCenter = CGPoint(
                x: min(max(targetPoint.x, halfViewport.x), sourceSize.width - halfViewport.x),
                y: min(max(targetPoint.y, halfViewport.y), sourceSize.height - halfViewport.y)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.055 : 0.035))

                RecordingZoomFocusGrid()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.34), lineWidth: 1)
                    }
                    .frame(width: viewportSize.width, height: viewportSize.height)
                    .position(viewportCenter)
                    .animation(
                        accessibilityReduceMotion ? nil : .snappy(duration: 0.16),
                        value: magnification
                    )

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: isDragging ? 12 : 10, height: isDragging ? 12 : 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
                    .position(targetPoint)
                    .animation(
                        accessibilityReduceMotion ? nil : .snappy(duration: 0.12),
                        value: isDragging
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        position = CGPoint(
                            x: normalized(value.location.x / max(sourceSize.width, 1)),
                            y: normalized(value.location.y / max(sourceSize.height, 1))
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(accessibilityReduceMotion ? nil : .snappy(duration: 0.18)) {
                            position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
            )
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fixed camera target")
            .accessibilityValue(
                "X \(Int(position.x * 100)), Y \(Int(position.y * 100)), \(magnification.formatted(.number.precision(.fractionLength(1)))) times zoom"
            )
            .accessibilityHint("Drag to move the target. Double-click to center.")
        }
        .frame(height: 118)
        .help("Drag to position the fixed camera target. The outline shows the visible area. Double-click to center.")
    }

    private func normalized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

private struct RecordingZoomFocusGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
