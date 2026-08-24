import AppKit
import SwiftUI

/// Delivers the escape key to a whole window, which SwiftUI otherwise only offers as a button shortcut.
private struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Bool

    func makeNSView(context: Context) -> EscapeKeyMonitorView {
        let view = EscapeKeyMonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: EscapeKeyMonitorView, context: Context) {
        nsView.onEscape = onEscape
    }
}

final class EscapeKeyMonitorView: NSView {
    var onEscape: (() -> Bool)?

    nonisolated(unsafe) private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, event.keyCode == 53 else { return event }
            return self.onEscape?() == true ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

extension View {
    /// Return true from `action` to swallow the key, false to let it fall through.
    func onEscapeKey(_ action: @escaping () -> Bool) -> some View {
        background(EscapeKeyMonitor(onEscape: action).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
