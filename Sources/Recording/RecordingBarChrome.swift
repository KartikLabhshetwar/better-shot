import AppKit
import SwiftUI

/// Sizing and color constants shared by the recording bar and its controls.
enum RecordingBarMetrics {
    static let controlSize: CGFloat = 34
    static let height: CGFloat = 54
    static let cornerRadius: CGFloat = height / 2
    static let itemSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    static let bottomInset: CGFloat = 64
    static let hoverDiameter: CGFloat = 32
    static let edge = GlassPalette.edge
    static let activeTint = Color(nsColor: .labelColor)
    static let inactiveTint = Color(nsColor: .labelColor).opacity(0.4)

    /// Room reserved above the bar for its own tooltip pill, so the bar's fitted content view is large enough to show it without clipping.
    static let tooltipGap: CGFloat = 8
    static let tooltipPillHeight: CGFloat = 22
    static let tooltipReservedHeight: CGFloat = tooltipGap + tooltipPillHeight + 12
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

extension View {
    func recordingBarSurface(cornerRadius: CGFloat = RecordingBarMetrics.cornerRadius, isInteractive: Bool = false, castsShadow: Bool = true) -> some View {
        glassSurface(cornerRadius: cornerRadius, depth: castsShadow ? .floating : .flush, isInteractive: isInteractive)
    }
}

// MARK: - Tooltips

enum RecordingBarCoordinateSpace {
    static let bar = "recordingBar"
}

struct RecordingBarTooltipTarget: Equatable {
    var id: String
    var text: String
    var frame: CGRect
}

/// The bar's own tooltips. macOS' native `.help()` takes about a second to appear, far too slow for a bar meant to be scanned and dismissed; these show in a fraction of that and, once one has appeared, follow the pointer across the bar instantly.
@Observable
@MainActor
final class RecordingBarTooltipModel {
    private(set) var visible: RecordingBarTooltipTarget?

    private var hovered: String?
    private var isWarm = false
    private var showTask: Task<Void, Never>?
    private var coolTask: Task<Void, Never>?

    private static let showDelay = Duration.milliseconds(160)
    /// How long after leaving a control the bar stays "warm": hover another control inside this window and its tooltip appears with no delay.
    private static let warmWindow = Duration.milliseconds(500)

    func hover(id: String, text: String, frame: CGRect) {
        hovered = id
        showTask?.cancel()
        coolTask?.cancel()

        guard !isWarm else {
            visible = RecordingBarTooltipTarget(id: id, text: text, frame: frame)
            return
        }
        showTask = Task {
            try? await Task.sleep(for: Self.showDelay)
            guard !Task.isCancelled, hovered == id else { return }
            visible = RecordingBarTooltipTarget(id: id, text: text, frame: frame)
            isWarm = true
        }
    }

    /// Guarded on the item that's leaving: the new control's hover can arrive before the old one's un-hover.
    func endHover(id: String) {
        guard hovered == id else { return }
        hovered = nil
        showTask?.cancel()
        visible = nil
        coolTask = Task {
            try? await Task.sleep(for: Self.warmWindow)
            guard !Task.isCancelled, hovered == nil else { return }
            isWarm = false
        }
    }

    /// Clicking a control means the user is done reading about it; cut without a fade.
    func dismiss() {
        hovered = nil
        showTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            visible = nil
        }
    }
}

struct RecordingBarTooltipPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(RecordingBarMetrics.activeTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: RecordingBarMetrics.tooltipPillHeight)
            .recordingBarSurface(cornerRadius: RecordingBarMetrics.tooltipPillHeight / 2)
            .transition(.opacity)
    }
}

/// `.pointerStyle` needs macOS 15; BetterShot still supports 14, so this no-ops there and the AppKit hover puck carries the affordance instead.
private struct RecordingBarPointerStyle: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(isEnabled ? .link : nil)
        } else {
            content
        }
    }
}

/// Bar icon with an AppKit-tracked hover puck, so hover still works while BetterShot is in the background. Usable bare as a `Menu` label, or wrapped by `RecordingBarIconButton`.
struct RecordingBarIconLabel: View {
    /// Stable identity for the control, so the tooltip pill can glide between controls instead of cross-fading in place.
    let id: String
    /// Short text shown in the bar's own tooltip pill. The longer form goes on `accessibilityLabel`.
    let title: String
    let systemImage: String
    var tint: Color = RecordingBarMetrics.activeTint
    let accessibilityLabel: String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(RecordingBarTooltipModel.self) private var tooltip: RecordingBarTooltipModel?
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

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
            .modifier(RecordingBarPointerStyle(isEnabled: isEnabled))
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(RecordingBarCoordinateSpace.bar))
            } action: {
                frame = $0
            }
            .background {
                RecordingBarHoverTracker(isEnabled: isEnabled, onChange: setHovering)
            }
            .accessibilityLabel(accessibilityLabel)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onChange(of: title) { _, title in
                guard isHovering else { return }
                tooltip?.hover(id: id, text: title, frame: frame)
            }
            .onDisappear {
                tooltip?.endHover(id: id)
            }
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            tooltip?.hover(id: id, text: title, frame: frame)
        } else {
            tooltip?.endHover(id: id)
        }
    }
}

/// Bar icon button with an AppKit-tracked hover puck, so hover still works while BetterShot is in the background.
struct RecordingBarIconButton: View {
    let id: String
    let title: String
    let systemImage: String
    var tint: Color = RecordingBarMetrics.activeTint
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(RecordingBarTooltipModel.self) private var tooltip: RecordingBarTooltipModel?

    var body: some View {
        Button {
            tooltip?.dismiss()
            action()
        } label: {
            RecordingBarIconLabel(id: id, title: title, systemImage: systemImage, tint: tint, accessibilityLabel: accessibilityLabel)
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

final class RecordingBarHoverView: NSView {
    var onChange: ((Bool) -> Void)?
    var isTrackingEnabled = true {
        didSet { if !isTrackingEnabled { endHover() } }
    }

    private var isHovering = false

    /// The one control, at most, whose hover currently owns the pointing hand. Class-level because the claim has to be handed over atomically as the pointer slides from one control to the next.
    private static weak var handOwner: RecordingBarHoverView?

    /// Called when the panel hides: `orderOut` sends no exit events, so a hover that's live when the bar hides has to be ended by hand or it leaves the pointing hand behind.
    static func endActiveHover() {
        handOwner?.endHover()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        beginHover()
    }

    /// Re-claimed on every move, not just on entry: entry can be missed and the claim can be undone by anything that reset the cursor since the last move.
    override func mouseMoved(with event: NSEvent) {
        beginHover()
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endHover() }
    }

    private func beginHover() {
        guard isTrackingEnabled else { return }
        claimHand()
        guard !isHovering else { return }
        isHovering = true
        onChange?(true)
    }

    func endHover() {
        releaseHand()
        guard isHovering else { return }
        isHovering = false
        onChange?(false)
    }

    /// Deferred one turn of the run loop: AppKit's own cursor-rect management reasserts the arrow during the event's dispatch while BetterShot is active, so a cursor set inline gets overwritten before the user sees it.
    private func claimHand() {
        Self.handOwner = self
        DispatchQueue.main.async { [weak self] in
            guard let self, Self.handOwner === self else { return }
            NSCursor.pointingHand.set()
        }
    }

    /// Restores the arrow only if no other control claimed the hand in the same turn, so sliding along the bar doesn't blink the arrow between controls.
    private func releaseHand() {
        guard Self.handOwner === self else { return }
        Self.handOwner = nil
        DispatchQueue.main.async {
            guard Self.handOwner == nil else { return }
            NSCursor.arrow.set()
        }
    }
}
