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

    private var icon: String {
        switch tool {
        case .pin: "pin.fill"
        case .dismiss: "xmark"
        case .edit: "pencil"
        default: tool.symbol
        }
    }

    var body: some View {
        if slot.isCenter {
            Group {
                if tool == .copy || tool == .save {
                    Text(tool.title)
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 3 * scale)
            .background(.white.opacity(0.85), in: Capsule())
        } else {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .font(.system(size: 10 * scale, weight: .semibold))
                .frame(width: 22 * scale, height: 22 * scale)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .contentShape(Circle())
        }
    }
}
