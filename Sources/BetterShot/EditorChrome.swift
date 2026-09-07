import AppKit
import SwiftUI

/// Native neutral chrome shared by editors and settings.
enum StudioChrome {
    static let accentNSColor = NSColor.secondaryLabelColor
    static let accent = Color(nsColor: accentNSColor)
}

private struct StudioGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(EditorChrome.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(EditorChrome.border) }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }
}

/// Shared editor chrome built on native controls; rendering stays in the existing canvases.
enum EditorChrome {
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let workspace = Color(nsColor: .windowBackgroundColor)
    static let border = Color.primary.opacity(0.10)
}

struct EditorButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .foregroundStyle(Color.primary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.20 : selected ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct EditorPopover<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
        .buttonStyle(EditorButtonStyle(selected: isPresented))
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
    func studioGlass() -> some View { modifier(StudioGlassSurface()) }

    func studioEffectCard() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(EditorChrome.border) }
    }

    func editorPanel() -> some View {
        background(EditorChrome.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(EditorChrome.border)
            }
    }
}
