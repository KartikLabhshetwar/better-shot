import SwiftUI

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
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                selected ? Color.accentColor.opacity(0.12)
                    : configuration.isPressed ? Color.primary.opacity(0.08) : .clear,
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
    func editorPanel() -> some View {
        background(EditorChrome.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(EditorChrome.border)
            }
    }
}
