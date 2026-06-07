import AppKit
import SwiftUI

@MainActor
final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = VideoEditorWindowController()
    private var window: NSWindow?

    var hasOpenWindow: Bool { window != nil }

    private override init() { super.init() }

    func open(url: URL) {
        if let existing = window {
            existing.close()
            window = nil
        }

        let view = VideoEditorView(url: url)
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Video Editor"
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 780, height: 520)
        win.delegate = self
        win.collectionBehavior = [.transient, .moveToActiveSpace]

        centerOnActiveScreen(win)

        win.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DispatchQueue.main.async {
            if !EditorWindowController.shared.hasOpenWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
