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
    var bordered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        // Darken system red on light surfaces so small destructive labels stay readable.
        let destructiveColor = colorScheme == .light
            ? NSColor.systemRed.blended(withFraction: 0.25, of: .black) ?? .systemRed
            : NSColor.systemRed
        let accent = destructive ? Color(nsColor: destructiveColor) : EditorChrome.accent
        let active = isEnabled && (configuration.isPressed || isHovered)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 32)
            .foregroundStyle(!isEnabled ? Color.secondary : selected ? Color.white : destructive ? accent : Color.primary)
            .background(
                selected && isEnabled ? accent.opacity(active ? 0.8 : 1)
                    : (destructive && isEnabled ? accent : Color.primary)
                        .opacity(active ? (configuration.isPressed ? 0.16 : 0.10) : bordered ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                if bordered || (active && !selected) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder((destructive && isEnabled ? accent : Color.primary)
                            .opacity(contrast == .increased ? 0.5 : active ? 0.25 : 0.15))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
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
            ScrollView(showsIndicators: false) {
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
