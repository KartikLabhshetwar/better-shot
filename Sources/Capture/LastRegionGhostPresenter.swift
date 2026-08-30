import AppKit

/// Draws the remembered region as a dashed ghost while the capture bar is
/// up, so it can be re-captured with A without redrawing it. Click-through:
/// whatever is under it stays usable.
@MainActor
final class LastRegionGhostPresenter {
    static let shared = LastRegionGhostPresenter()

    private var panel: NSPanel?

    private init() {}

    func show() {
        hide()
        guard let rect = AppPreferences.lastRegionRect,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }) else { return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = LastRegionGhostView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            ghost: RegionGeometry.localRect(global: rect, screenFrame: screen.frame),
            scale: screen.backingScaleFactor
        )
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class LastRegionGhostView: NSView {
    private let ghost: CGRect
    private let scale: CGFloat

    init(frame: NSRect, ghost: CGRect, scale: CGFloat) {
        self.ghost = ghost
        self.scale = scale
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        ghost.fill()

        let outline = NSBezierPath(rect: ghost.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        NSColor.black.withAlphaComponent(0.5).setStroke()
        outline.stroke()
        outline.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.setStroke()
        outline.stroke()

        drawLabel("\(Int(ghost.width * scale)) × \(Int(ghost.height * scale))  ·  A to capture again")
    }

    private func drawLabel(_ text: String) {
        let label = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let below = ghost.minY - size.height - 8
        let labelRect = CGRect(
            x: ghost.midX - size.width / 2 - 6,
            y: below >= bounds.minY ? below : ghost.minY + 4,
            width: size.width + 12,
            height: size.height + 4
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }
}
