import AppKit
import SwiftUI

/// Sizing and color constants shared by the recording bar and its controls.
enum RecordingBarMetrics {
    static let controlSize: CGFloat = 34
    static let height: CGFloat = 54
    static let cornerRadius: CGFloat = 18
    static let itemSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    static let bottomInset: CGFloat = 64
    static let hoverDiameter: CGFloat = 32
    static let edge = Color(nsColor: .separatorColor).opacity(0.5)
    static let shadowOpacity: Double = 0.35
    static let shadowRadius: CGFloat = 16
    static let shadowY: CGFloat = 5
    static let activeTint = Color(nsColor: .labelColor)
    static let inactiveTint = Color(nsColor: .labelColor).opacity(0.4)
}

/// Reduced-motion aware animation curves, checked live rather than cached.
@MainActor
enum RecordingMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var showHideSpring: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)
    }

    static var modeChange: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.28)
    }
}

/// Drives the bar's spring show/hide, separate from `ScreenRecordingManager` so the panel can animate before ordering out.
@Observable
@MainActor
final class RecordingBarPresentation {
    static let shared = RecordingBarPresentation()

    var isPresented = false

    private init() {}
}

/// Frosted HUD-style backing for the floating bar.
struct RecordingBarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Bar icon with an AppKit-tracked hover puck, so hover still works while BetterShot is in the background. Usable bare as a `Menu` label, or wrapped by `RecordingBarIconButton`.
struct RecordingBarIconLabel: View {
    let systemImage: String
    var tint: Color = RecordingBarMetrics.activeTint
    let accessibilityLabel: String

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.35))
            .frame(width: RecordingBarMetrics.controlSize, height: RecordingBarMetrics.controlSize)
            .background {
                Circle()
                    .fill(Color(nsColor: .labelColor).opacity(0.12))
                    .frame(width: RecordingBarMetrics.hoverDiameter, height: RecordingBarMetrics.hoverDiameter)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape(Circle())
            .background {
                RecordingBarHoverTracker(isEnabled: isEnabled) { isHovering = $0 }
            }
            .accessibilityLabel(accessibilityLabel)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Bar icon button with an AppKit-tracked hover puck, so hover still works while BetterShot is in the background.
struct RecordingBarIconButton: View {
    let systemImage: String
    var tint: Color = RecordingBarMetrics.activeTint
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            RecordingBarIconLabel(systemImage: systemImage, tint: tint, accessibilityLabel: accessibilityLabel)
        }
        .buttonStyle(RecordingBarButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Thin vertical separator between bar sections.
struct RecordingBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(RecordingBarMetrics.edge)
            .frame(width: 1, height: 22)
            .padding(.horizontal, RecordingBarMetrics.sectionSpacing - RecordingBarMetrics.itemSpacing)
    }
}

private struct RecordingBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct RecordingBarHoverTracker: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> RecordingBarHoverView {
        let view = RecordingBarHoverView()
        view.onChange = onChange
        view.isTrackingEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: RecordingBarHoverView, context: Context) {
        nsView.onChange = onChange
        nsView.isTrackingEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: RecordingBarHoverView, coordinator: ()) {
        nsView.endHover()
    }
}

private final class RecordingBarHoverView: NSView {
    var onChange: ((Bool) -> Void)?
    var isTrackingEnabled = true {
        didSet { if !isTrackingEnabled { endHover() } }
    }

    private var isHovering = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isTrackingEnabled, !isHovering else { return }
        isHovering = true
        onChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endHover() }
    }

    func endHover() {
        guard isHovering else { return }
        isHovering = false
        onChange?(false)
    }
}
