import AppKit
import SwiftUI

enum InspectorMetrics {
    static let gutter: CGFloat = 14
    static let sectionSpacing: CGFloat = 10
    static let fieldHeight: CGFloat = 26
    static let fieldRadius: CGFloat = 7
    static let pillHeight: CGFloat = 24
    static let pillRadius: CGFloat = 6
}

enum InspectorMotion {
    static let press = Animation.spring(response: 0.24, dampingFraction: 1)
    static let reveal = Animation.spring(response: 0.34, dampingFraction: 1)
    static let hover = Animation.easeOut(duration: 0.1)
}

/// AppKit sidebar material so the inspector reads as chrome instead of content.
struct InspectorMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Floating chrome that content scrolls beneath.
struct InspectorBarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct InspectorSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }
}

struct InspectorDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, InspectorMetrics.gutter)
            .opacity(0.6)
    }
}

/// Collapsible so the inspector shows the work at hand instead of eight sections deep of scrolling. Expansion is remembered per section title across launches.
struct InspectorSection<Content: View>: View {
    let title: String
    let accessory: AnyView?
    @ViewBuilder let content: () -> Content

    @AppStorage private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, collapsedByDefault: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = nil
        self.content = content
        _isExpanded = AppStorage(wrappedValue: !collapsedByDefault, "inspector.\(title).expanded")
    }

    init<Accessory: View>(
        _ title: String,
        collapsedByDefault: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = AnyView(accessory())
        self.content = content
        _isExpanded = AppStorage(wrappedValue: !collapsedByDefault, "inspector.\(title).expanded")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.sectionSpacing) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(reduceMotion ? nil : InspectorMotion.reveal) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        InspectorSectionHeader(title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.inspectorPress(scale: 0.97))
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                Spacer(minLength: 4)

                if isExpanded { accessory }
            }
            .frame(minHeight: 18)

            if isExpanded { content() }
        }
        .padding(.horizontal, InspectorMetrics.gutter)
        .padding(.vertical, isExpanded ? InspectorMetrics.gutter : 8)
    }
}

struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InspectorCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Feedback on pointer-down, critically damped so nothing overshoots on a plain tap.
struct InspectorPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : InspectorMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == InspectorPressStyle {
    static var inspectorPress: InspectorPressStyle { InspectorPressStyle() }
    static func inspectorPress(scale: CGFloat) -> InspectorPressStyle { InspectorPressStyle(scale: scale) }
}

struct InspectorPill: View {
    let title: String
    var systemImage: String?
    var role: Role = .normal
    var isActive = false
    var fillsWidth = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    enum Role { case normal, destructive, accent }

    init(
        _ title: String,
        systemImage: String? = nil,
        role: Role = .normal,
        isActive: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isActive = isActive
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.pillRadius, style: .continuous)

        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: InspectorMetrics.pillHeight)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: isActive ? 1 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.inspectorPress)
        .foregroundStyle(tint)
        .onHover { isHovering = $0 }
        .animation(InspectorMotion.hover, value: isHovering)
        .animation(InspectorMotion.hover, value: isActive)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var tint: Color {
        switch role {
        case .normal: isActive ? .accentColor : .primary.opacity(0.82)
        case .destructive: .red
        case .accent: .accentColor
        }
    }

    private var fill: Color {
        if isActive { return Color.accentColor.opacity(0.16) }
        let base: Color = role == .destructive ? .red : .primary
        return base.opacity(isHovering ? 0.11 : 0.06)
    }

    private var stroke: Color {
        isActive ? Color.accentColor.opacity(0.55) : Color.primary.opacity(isHovering ? 0.14 : 0.08)
    }
}

private struct InspectorFieldChrome: ViewModifier {
    let isFocused: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: InspectorMetrics.fieldRadius, style: .continuous)

        content
            .frame(height: InspectorMetrics.fieldHeight)
            .background(shape.fill(Color.primary.opacity(isHovering ? 0.09 : 0.06)))
            .overlay(
                shape.strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(isHovering ? 0.14 : 0.09),
                    lineWidth: isFocused ? 1 : 0.5
                )
            )
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(InspectorMotion.hover, value: isHovering)
    }
}

extension View {
    func inspectorField(isFocused: Bool = false) -> some View {
        modifier(InspectorFieldChrome(isFocused: isFocused))
    }
}

struct InspectorMenuField<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    if value == selection {
                        Label(label(value), systemImage: "checkmark")
                    } else {
                        Text(label(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .inspectorField()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

/// Swatch chrome shared by every background and preset thumbnail.
struct InspectorSwatchChrome: ViewModifier {
    let isSelected: Bool
    var radius: CGFloat = 6

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.28 : 0.12),
                    lineWidth: isSelected ? 2 : 0.5
                )
            )
            .scaleEffect(reduceMotion || !isHovering ? 1 : 1.06)
            .animation(reduceMotion ? nil : InspectorMotion.press, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func inspectorSwatch(isSelected: Bool, radius: CGFloat = 6) -> some View {
        modifier(InspectorSwatchChrome(isSelected: isSelected, radius: radius))
    }
}

private struct EditorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.26), radius: 14, y: 6)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(1.6))
                            self.message = nil
                        }
                }
            }
            .animation(InspectorMotion.reveal, value: message)
    }
}

extension View {
    func editorToast(_ message: Binding<String?>) -> some View {
        modifier(EditorToastModifier(message: message))
    }
}

/// Content plane the translucent chrome sits above.
struct EditorCanvasBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}
