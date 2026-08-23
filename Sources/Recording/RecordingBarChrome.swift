import AppKit
import SwiftUI

/// Sizing and color constants shared by the recording bar and its controls.
enum RecordingBarMetrics {
    static let controlSize: CGFloat = 30
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 14
    static let itemSpacing: CGFloat = 2
    static let hoverDiameter: CGFloat = 28
    static let edge = Color(nsColor: .separatorColor).opacity(0.5)
    static let shadowOpacity: Double = 0.35
    static let shadowRadius: CGFloat = 16
    static let shadowY: CGFloat = 5
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
}

/// Drives the bar's spring show/hide, kept separate from `ScreenRecordingManager` so the
/// panel controller can animate the transition before actually ordering the window out.
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

/// A bar icon button with a hover puck and a press state, tracked via AppKit so hover keeps
/// working while BetterShot is in the background - true for the entire life of a recording.
struct RecordingBarIconButton: View {
    let systemImage: String
    var tint: Color = Color(nsColor: .labelColor)
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
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
        }
        .buttonStyle(RecordingBarButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
