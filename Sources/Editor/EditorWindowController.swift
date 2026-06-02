import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var window: NSWindow?

    private init() {}

    func open(url: URL) {
        close()

        let hostingView = NSHostingView(rootView:
            EditorWindowView(imageURL: url)
                .frame(minWidth: 800, minHeight: 550)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "BetterShot — Annotate"
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseDelegate.shared

        centerOnActiveScreen(window)

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
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

private final class WindowCloseDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = WindowCloseDelegate()

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            EditorWindowController.shared.close()
        }
    }
}
