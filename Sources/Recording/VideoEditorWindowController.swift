import AppKit
import SwiftUI

@MainActor
final class VideoEditorWindowController {
    static let shared = VideoEditorWindowController()
    private var window: NSWindow?

    private init() {}

    func open(url: URL) {
        if let existing = window {
            existing.close()
        }

        let view = VideoEditorView(url: url)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Video Editor"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 520)

        window.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
