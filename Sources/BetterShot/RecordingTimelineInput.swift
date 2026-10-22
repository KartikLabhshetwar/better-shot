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

/// Positions and observes the enclosing scroll view from inside its content, for systems without `ScrollPosition`.
struct RecordingTimelineScrollSync: NSViewRepresentable {
    let targetX: CGFloat
    let request: Int
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> SyncView { SyncView() }
    func updateNSView(_ view: SyncView, context: Context) {
        view.onScroll = onScroll
        guard view.request != request else { return }
        view.request = request
        view.scroll(toX: targetX)
    }

    final class SyncView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var request = 0
        private var pendingX: CGFloat?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
            guard window != nil, let clip = enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipDidScroll),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }

        /// Waits for the pending layout so the new content width bounds the offset.
        func scroll(toX x: CGFloat) {
            pendingX = x
            DispatchQueue.main.async { [weak self] in
                guard let self, let x = self.pendingX else { return }
                self.pendingX = nil
                let maxX = max(0, self.bounds.width - self.visibleRect.width)
                self.scroll(CGPoint(x: min(max(x, 0), maxX), y: self.visibleRect.minY))
            }
        }

        @objc private func clipDidScroll() {
            guard pendingX == nil else { return }
            onScroll?(visibleRect.minX)
        }
    }
}
