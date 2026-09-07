import AppKit
import SwiftUI

/// Receives native scroll/pinch events across all tracks without taking their mouse clicks.
struct RecordingTimelineInput: NSViewRepresentable {
    let onScroll: (Double, Bool, CGFloat) -> Void
    let onMagnify: (Double, CGFloat) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.stop() }

    final class InputView: NSView {
        var onScroll: ((Double, Bool, CGFloat) -> Void)?
        var onMagnify: ((Double, CGFloat) -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                if event.type == .magnify {
                    self.onMagnify?(Double(event.magnification), point.x)
                } else {
                    let zoom = !event.modifierFlags.intersection([.command, .control]).isEmpty
                    let dx = event.scrollingDeltaX
                    let dy = event.scrollingDeltaY
                    let delta = zoom ? dy : abs(dx) > abs(dy) * 0.5 ? dx : dy
                    self.onScroll?(Double(-delta) * (event.hasPreciseScrollingDeltas ? 1 : 16), zoom, point.x)
                }
                return nil
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
