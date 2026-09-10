import SwiftUI

/// Shared positions and control artwork for the real overlay and the layout editor.
struct OverlayToolArrangement<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder var content: (OverlayToolSlot) -> Content

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    content(.topLeft)
                    Spacer(minLength: 0)
                    content(.topRight)
                }
                Spacer(minLength: 0)
                HStack {
                    content(.bottomLeft)
                    Spacer(minLength: 0)
                    content(.bottomRight)
                }
            }
            .padding(6 * scale)
            HStack(spacing: 6 * scale) {
                content(.centerLeft)
                content(.centerRight)
            }
        }
    }
}

struct OverlayToolLabel: View {
    let tool: OverlayTool
    let slot: OverlayToolSlot
    let scale: CGFloat

    var body: some View {
        if slot.isCenter {
            Group {
                if tool == .copy || tool == .save {
                    Text(tool.title)
                } else {
                    Image(systemName: tool.symbol)
                }
            }
            .font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 3 * scale)
            .background(.white.opacity(0.85), in: Capsule())
        } else {
            Image(systemName: tool.symbol)
                .symbolRenderingMode(tool == .share ? .monochrome : .palette)
                .foregroundStyle(.white, .white.opacity(0.25))
                .font(.system(size: 16 * scale))
                .frame(width: 22 * scale, height: 22 * scale)
                .contentShape(Rectangle())
        }
    }
}
