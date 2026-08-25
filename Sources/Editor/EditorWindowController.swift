import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var windows: [NSWindow] = []

    var hasOpenWindows: Bool { !windows.isEmpty }

    private init() {}

    func open(url: URL, on screen: NSScreen? = nil) {
        let urlHolder = CurrentURL(url: url)

        let hostingView = NSHostingView(rootView:
            EditorWindowView(urlHolder: urlHolder)
                .frame(minWidth: 800, minHeight: 550)
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = url.deletingPathExtension().lastPathComponent
        win.subtitle = "Screenshot"
        win.minSize = NSSize(width: 800, height: 550)
        win.isReleasedWhenClosed = false
        win.delegate = EditorWindowDelegate.shared
        win.collectionBehavior = [.transient, .moveToActiveSpace]

        centerOnActiveScreen(win, preferring: screen)

        windows.append(win)

        win.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidClose(_ window: NSWindow) {
        windows.removeAll { $0 === window }
        if windows.isEmpty {
            ActivationPolicy.dropIfNoWindowsLeft()
        }
    }

    private func centerOnActiveScreen(_ window: NSWindow, preferring preferred: NSScreen? = nil) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? preferred
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
@Observable
final class CurrentURL {
    var url: URL

    init(url: URL) {
        self.url = url
    }
}

private final class EditorWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = EditorWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated { EditorCloseGuard.shared.shouldClose(sender) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            EditorCloseGuard.shared.unregister(window)
            EditorWindowController.shared.windowDidClose(window)
        }
    }
}
