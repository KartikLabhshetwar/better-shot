import AppKit
import SwiftUI

/// Native neutral chrome shared by editors and settings.
enum StudioChrome {
    static let accentNSColor = NSColor.secondaryLabelColor
    static let accent = Color(nsColor: accentNSColor)
}

/// Classic frosted macOS chrome, without Tahoe's Liquid Glass treatment.
private struct StudioGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    EditorChrome.panel
                } else {
                    VisualEffectBackdrop(material: .sidebar)
                        .opacity(opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(EditorChrome.border)
            }
    }
}

/// Shared editor chrome built on native controls; rendering stays in the existing canvases.
enum EditorChrome {
    static let accent = Color(nsColor: .systemBlue)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let workspace = Color(nsColor: .windowBackgroundColor)
    static let border = Color.primary.opacity(0.10)
}

struct EditorButtonStyle: ButtonStyle {
    var selected = false
    var horizontalPadding: CGFloat = 10
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 32)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? EditorChrome.accent.opacity(configuration.isPressed ? 0.8 : 1)
                    : Color.primary.opacity(configuration.isPressed ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct EditorPopover<Content: View>: View {
    let title: String
    let systemImage: String
    var selected = false
    @ViewBuilder var content: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
        .buttonStyle(EditorButtonStyle(selected: selected || isPresented))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.headline)
                    content()
                }
                .padding(20)
            }
            .background(EditorChrome.panel)
            .frame(width: 340)
            .frame(maxHeight: 560)
        }
    }
}

extension View {
    func studioGlass(cornerRadius: CGFloat = 8, opacity: Double = 1) -> some View {
        modifier(StudioGlassSurface(cornerRadius: cornerRadius, opacity: opacity))
    }

    func studioEffectCard() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(EditorChrome.border, lineWidth: 0.5)
            }
    }

}
