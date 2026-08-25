//
//  RecordingBarChrome.swift
//  BetterShot
//
//  Shared chrome for the floating recording bar - its geometry, its tooltip
//  system and the control style both of its modes are built from. The
//  pre-record picker and the in-session controls are the same bar with
//  different contents, not two bars that resemble each other, which is what
//  lets one morph into the other.
//

import AppKit
import SwiftUI

enum BarMetrics {
    /// Sized off the control row rather than a caption: the icons carry the
    /// bar and the tooltip carries the naming.
    static let controlSize: CGFloat = 40
    static let height: CGFloat = 52
    static let cornerRadius: CGFloat = 16
    static let itemSpacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 6

    /// Transparent slack around the bar so the shadow Liquid Glass casts
    /// isn't clipped by the panel edge. The panel is positioned lower by
    /// exactly this much so the bar itself doesn't move.
    static let shadowSlack: CGFloat = 28

    /// The panel is a fixed size that both modes sit centred inside, so
    /// morphing between them never resizes the window - only the bar's own
    /// rounded rect animates. Wide enough for the widest mode plus the room a
    /// tooltip needs beyond the end controls.
    static let panelWidth: CGFloat = 760
    static var panelHeight: CGFloat { BarTooltip.reservedHeight + height + shadowSlack }

    /// The bar's surface is Liquid Glass, which brings its own fill and
    /// shadow. These are the marks drawn on top of it.
    ///
    /// They're all AppKit label colours rather than SwiftUI's `.primary` and
    /// friends. Hierarchical styles also resolve against the *control* active
    /// state, and this bar lives in a `.nonactivatingPanel` that never becomes
    /// key - so `.primary` renders dimmed to near-invisible inside a `Button`
    /// while a `Menu` label right beside it stays full strength. These invert
    /// with the appearance and nothing else.
    static let activeTint = Color(nsColor: .labelColor)
    /// A control that's off is dimmed, never shrunk - the target stays the
    /// same size whichever state it's in.
    static let inactiveTint = Color(nsColor: .labelColor).opacity(0.4)
    static let stroke = Color(nsColor: .separatorColor)
    /// A hairline to define the pill's edge against a background of the same
    /// brightness - grey in light mode, white in dark, and faint in both.
    static let edge = Color(nsColor: .labelColor).opacity(0.12)
    /// Stop and the recording dot. The system red so it stays legible
    /// whichever variant the glass is in.
    static let recordTint = Color(nsColor: .systemRed)

    /// The puck that appears behind an icon on hover. Faint enough to read as
    /// the pointer resting on a target rather than as a second control state -
    /// the toggles already use tint for on/off.
    static let hoverFill = Color(nsColor: .labelColor).opacity(0.11)
    static let hoverDiameter: CGFloat = 32

    /// The morph between modes. Enough travel to read as one bar changing
    /// shape rather than two bars swapping.
    static let modeChange = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

// MARK: - Tooltips

/// Geometry and timing for the bar's own tooltips. macOS' native `.help()`
/// tooltip takes about a second to appear, which is far too slow for a bar
/// you're meant to scan and dismiss; these show in a fraction of that and,
/// once one has appeared, follow the pointer across the bar instantly.
enum BarTooltip {
    static let pillHeight: CGFloat = 24
    /// Space between the top of the bar and the bottom of the pill.
    static let gap: CGFloat = 8
    /// Transparent slack the panel reserves above the bar for the pill and
    /// its shadow.
    static let reservedHeight: CGFloat = gap + pillHeight + 16

    static let showDelay = Duration.milliseconds(160)
    /// How long after leaving a control the bar stays "warm" - hover another
    /// control inside this window and its tooltip appears with no delay.
    static let warmWindow = Duration.milliseconds(500)
}

/// Stable identity per control, so the pill can glide between controls
/// instead of cross-fading in place. It has to survive the control's own
/// label changing - Pause becomes Resume without becoming a different
/// control.
enum BarTooltipID: String {
    case display
    case window
    case area
    case camera
    case microphone
    case systemAudio
    case teleprompter
    case timer
    case close

    case pauseResume
    case restart
    case stop
    case discard
}

struct BarTooltipTarget: Equatable {
    var id: BarTooltipID
    var text: String
    var frame: CGRect
}

@Observable
@MainActor
final class BarTooltipModel {
    private(set) var visible: BarTooltipTarget?

    private var hovered: BarTooltipID?
    private var isWarm = false
    private var showTask: Task<Void, Never>?
    private var coolTask: Task<Void, Never>?

    func hover(id: BarTooltipID, text: String, frame: CGRect) {
        hovered = id
        showTask?.cancel()
        coolTask?.cancel()

        guard !isWarm else {
            visible = BarTooltipTarget(id: id, text: text, frame: frame)
            return
        }
        showTask = Task {
            try? await Task.sleep(for: BarTooltip.showDelay)
            guard !Task.isCancelled, hovered == id else { return }
            visible = BarTooltipTarget(id: id, text: text, frame: frame)
            isWarm = true
        }
    }

    /// Guarded on the item that's leaving: the new control's hover can arrive
    /// before the old one's un-hover, and an unguarded hide would blank the
    /// tooltip that just took over.
    func endHover(id: BarTooltipID) {
        guard hovered == id else { return }
        hovered = nil
        showTask?.cancel()
        visible = nil
        coolTask = Task {
            try? await Task.sleep(for: BarTooltip.warmWindow)
            guard !Task.isCancelled, hovered == nil else { return }
            isWarm = false
        }
    }

    /// Clicking a control means the user is done reading about it. Cut
    /// without a fade: the click already happened, and a pill dissolving
    /// after the fact reads as lag.
    func dismiss() {
        hovered = nil
        showTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            visible = nil
        }
    }
}

struct BarTooltipPill: View {
    let text: String

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BarMetrics.activeTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: BarTooltip.pillHeight)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(BarMetrics.edge, lineWidth: 0.5)
            }
            .transition(.opacity)
    }
}

// MARK: - Controls

/// The bar's only control shape: an icon sized for a comfortable pointer
/// target rather than for the glyph. Used bare as a `Menu` label and wrapped
/// by `BarActionButton` everywhere else.
///
/// It owns the hover puck and the tooltip because every control in the bar is
/// one of these - including the ones that are only a `Menu`'s label, which a
/// wrapper around the button couldn't reach.
struct BarActionLabel: View {
    let id: BarTooltipID
    /// What the tooltip says. Short - the long form goes on `accessibility`.
    let title: String
    let systemImage: String
    var tint: Color = BarMetrics.activeTint

    @Environment(\.isEnabled) private var isEnabled
    @Environment(BarTooltipModel.self) private var tooltip: BarTooltipModel?
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
            .frame(width: BarMetrics.controlSize, height: BarMetrics.controlSize)
            // As a background so the puck never takes part in layout - it's
            // wider than the icon and would otherwise spread the bar.
            .background {
                Circle()
                    .fill(BarMetrics.hoverFill)
                    .frame(
                        width: BarMetrics.hoverDiameter,
                        height: BarMetrics.hoverDiameter
                    )
                    .opacity(isHovering ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // One of two cursor paths, for the two states the bar lives in.
            // While BetterShot is the active app the system's pointer-style
            // engine owns the cursor and enforces the declared style against
            // any NSCursor.set - so the style has to be declared. It resolves
            // against the key window, which is why the presenter makes the
            // panel key when showing it. While BetterShot is inactive the
            // engine doesn't consult it at all and BarControlHover's NSCursor
            // path takes over.
            .pointerStyle(isEnabled ? .link : nil)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(BarCoordinateSpace.bar))
            } action: {
                frame = $0
            }
            .background {
                BarControlHover(isEnabled: isEnabled, onChange: setHovering)
            }
            .onChange(of: title) { _, title in
                // Pause becomes Resume under a pointer that never moved; the
                // pill it's showing has to follow.
                guard isHovering else { return }
                tooltip?.hover(id: id, text: title, frame: frame)
            }
            .onDisappear {
                // A mode morph swaps the controls out from under a pointer
                // that never leaves the bar, so no exit event is coming.
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

/// Renders the label and nothing else.
///
/// `.plain` isn't neutral on macOS: it still fades its content for the
/// inactive control state, and this bar lives in a `.nonactivatingPanel` that
/// never becomes key - so every button reads as permanently disabled no matter
/// what colour it's given. Owning `makeBody` opts out of that, and buys a real
/// press state on the way past.
struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct BarActionButton: View {
    let id: BarTooltipID
    let title: String
    let systemImage: String
    var tint: Color = BarMetrics.activeTint
    /// Only worth setting where the tooltip leaves something out - the device
    /// a control is bound to, what a destructive action destroys.
    var accessibility: String?
    let action: () -> Void

    @Environment(BarTooltipModel.self) private var tooltip: BarTooltipModel?

    var body: some View {
        Button {
            tooltip?.dismiss()
            action()
        } label: {
            BarActionLabel(id: id, title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(accessibility ?? title)
    }
}

struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(BarMetrics.stroke)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 5)
    }
}

// MARK: - Hover tracking

enum BarCoordinateSpace {
    /// The bar itself, which the tooltip pill is positioned in.
    static let bar = "recordingBar"
    /// The whole panel, which the bar is measured in.
    static let panel = "recordingBarPanel"
}

/// The single source of hover for a bar control: one of these sits behind
/// every `BarActionLabel`, and the cursor, the puck and the tooltip are all
/// driven from it - a control that renders at all gets all three.
///
/// It's an AppKit tracking area rather than `.onHover`/`.pointerStyle`
/// because those resolve against the active app and the key window, and this
/// bar floats in a `.nonactivatingPanel` over whatever is being recorded - it
/// is usually neither. A tracking area marked `.activeAlways` is delivered
/// in both states.
struct BarControlHover: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> BarControlHoverView {
        let view = BarControlHoverView()
        view.onChange = onChange
        view.isTrackingEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: BarControlHoverView, context: Context) {
        view.onChange = onChange
        view.isTrackingEnabled = isEnabled
    }

    /// A morph tears controls down under a pointer that never left the bar;
    /// the hover has to end with the view or the hand would outlive its
    /// button.
    static func dismantleNSView(_ view: BarControlHoverView, coordinator: ()) {
        view.endHover()
    }
}

final class BarControlHoverView: NSView {
    var onChange: ((Bool) -> Void)?
    var isTrackingEnabled = true {
        didSet {
            if !isTrackingEnabled {
                endHover()
            }
        }
    }

    private var isHovering = false

    /// The one control, at most, whose hover currently owns the pointing
    /// hand. Class-level because the claim has to be handed over atomically
    /// when the pointer slides from one control to the next.
    private static weak var handOwner: BarControlHoverView?

    /// For the bar's owner to call when it hides the panel: `orderOut`
    /// removes the window without exit events, and a hover that ends
    /// off screen must still put the arrow back and clear its puck.
    static func endActiveHover() {
        handOwner?.endHover()
    }

    /// Purely an observer - the click belongs to the SwiftUI control this
    /// sits behind.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        beginHover()
    }

    /// Re-claimed on every move, not just on entry: entry can be missed (the
    /// bar appearing under a stationary pointer) and the claim can be undone
    /// (anything that reset the cursor since the last move). Claiming again
    /// is free.
    override func mouseMoved(with event: NSEvent) {
        beginHover()
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endHover()
        }
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

    /// The set is deferred one turn of the run loop on purpose. Everything
    /// that fights for the cursor - AppKit's cursor-rect management while the
    /// app is active, the hosting view's own tracking - reasserts the arrow
    /// *during* the event's dispatch, so a cursor set inline is overwritten
    /// before the user sees it. One set after the turn outlives them all, and
    /// it's re-run on every subsequent move.
    private func claimHand() {
        Self.handOwner = self
        DispatchQueue.main.async { [weak self] in
            guard let self, Self.handOwner === self else { return }
            NSCursor.pointingHand.set()
        }
    }

    /// Restores the arrow only if no other control claimed the hand in the
    /// same turn - sliding along the bar exits one control and enters the
    /// next, and the arrow must not blink in between.
    private func releaseHand() {
        guard Self.handOwner === self else { return }
        Self.handOwner = nil
        DispatchQueue.main.async {
            guard Self.handOwner == nil else { return }
            NSCursor.arrow.set()
        }
    }
}
