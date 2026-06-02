import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var window: NSWindow?
    private var currentURL: CurrentURL?

    private init() {}

    func open(url: URL) {
        if let window, window.isVisible {
            currentURL?.url = url
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let urlHolder = CurrentURL(url: url)
        currentURL = urlHolder

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
        win.title = "BetterShot"
        win.isReleasedWhenClosed = false
        win.delegate = WindowCloseDelegate.shared

        centerOnActiveScreen(win)

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    func close() {
        window?.close()
        window = nil
        currentURL = nil
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

@MainActor
@Observable
final class CurrentURL {
    var url: URL

    init(url: URL) {
        self.url = url
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
