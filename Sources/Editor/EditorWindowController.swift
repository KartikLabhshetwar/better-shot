import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var windows: [NSWindow] = []

    var hasOpenWindows: Bool { !windows.isEmpty }

    private init() {}

    func open(url: URL) {
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
        win.isReleasedWhenClosed = false
        win.delegate = EditorWindowDelegate.shared
        win.collectionBehavior = [.transient, .moveToActiveSpace]

        centerOnActiveScreen(win)

        windows.append(win)

        win.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(window: NSWindow? = nil) {
        if let window {
            windows.removeAll { $0 === window }
            window.close()
        } else {
            let windowToClose = NSApp.keyWindow ?? windows.last
            if let windowToClose {
                windows.removeAll { $0 === windowToClose }
                windowToClose.close()
            }
        }

        if windows.isEmpty {
            DispatchQueue.main.async {
                if !VideoEditorWindowController.shared.hasOpenWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func windowDidClose(_ window: NSWindow) {
        windows.removeAll { $0 === window }
        if windows.isEmpty {
            DispatchQueue.main.async {
                if !VideoEditorWindowController.shared.hasOpenWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
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

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async {
            EditorWindowController.shared.windowDidClose(window)
        }
    }
}
