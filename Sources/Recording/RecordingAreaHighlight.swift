import AppKit

/// Click-through overlay that outlines the region being recorded, dimming everything outside
/// it so the recording boundary stays visible under whatever windows the user brings forward.
/// Purely decorative: ignores mouse events and, like the recording bar, never appears in the
/// recording itself because BetterShot excludes its own app from every `SCContentFilter`.
@MainActor
final class RecordingAreaHighlightPresenter {
    static let shared = RecordingAreaHighlightPresenter()

    private var panel: NSPanel?

    private init() {}

    /// - Parameter rect: the recorded area in AppKit/global screen coordinates (bottom-left origin).
    func show(rect: CGRect, on screen: NSScreen? = nil) {
        hide()

        guard let targetScreen = screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main
        else { return }

        let panel = NSPanel(
            contentRect: targetScreen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none

        let localRect = CGRect(
            x: rect.minX - targetScreen.frame.minX,
            y: rect.minY - targetScreen.frame.minY,
            width: rect.width,
            height: rect.height
        )
        panel.contentView = RecordingAreaHighlightView(
            frame: CGRect(origin: .zero, size: targetScreen.frame.size),
            highlightRect: localRect
        )

        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class RecordingAreaHighlightView: NSView {
    private let highlightRect: CGRect
    private let borderLayer = CAShapeLayer()

    init(frame frameRect: NSRect, highlightRect: CGRect) {
        self.highlightRect = highlightRect
        super.init(frame: frameRect)
        wantsLayer = true
        configureBorderLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func configureBorderLayer() {
        borderLayer.frame = bounds
        borderLayer.path = CGPath(rect: highlightRect.insetBy(dx: 1.25, dy: 1.25), transform: nil)
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = 2.5
        layer?.addSublayer(borderLayer)

        guard !RecordingMotion.reduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderLayer.add(pulse, forKey: "recordingAreaPulse")
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let overlayColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.24)
        overlayColor.setFill()
        bounds.fill()

        NSColor.clear.setFill()
        highlightRect.fill(using: .clear)
    }
}
