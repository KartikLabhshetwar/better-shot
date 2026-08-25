import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var hasOpenWindow: Bool { window != nil }

    private override init() { super.init() }

    func open(on screen: NSScreen? = nil) {
        if let existing = window, existing.isVisible {
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: PreferencesView())

        let win = NSWindow(contentViewController: controller)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.setContentSize(NSSize(width: 820, height: 660))
        win.titlebarAppearsTransparent = true
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.collectionBehavior = [.transient, .moveToActiveSpace]

        centerOnCurrentScreen(win, preferring: screen)

        window = win

        win.orderFrontRegardless()
        AppActivationPolicy.enter()
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivationPolicy.leave()
    }

    private func centerOnCurrentScreen(_ window: NSWindow, preferring preferred: NSScreen? = nil) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = preferred
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
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
