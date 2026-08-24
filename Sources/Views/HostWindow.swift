import AppKit
import SwiftUI

/// Reports the NSWindow hosting a SwiftUI view, so actions can close it without trusting `NSApp.keyWindow`.
private struct HostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if window !== nsView.window { window = nsView.window }
        }
    }
}

extension View {
    func hostWindow(_ window: Binding<NSWindow?>) -> some View {
        background(HostWindowReader(window: window).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
