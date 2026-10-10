import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    var hasOpenWindow: Bool { window != nil }

    private override init() { super.init() }

    func open(on screen: NSScreen? = nil, section: SettingsSection? = nil) {
        if let window {
            if let section { navigation.page = section }
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        navigation.page = section ?? .home
        let controller = NSHostingController(rootView: PreferencesView(navigation: navigation) { [weak self] in
            self?.window?.title = $0.title
        })

        let win = NSWindow(contentViewController: controller)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.setContentSize(NSSize(width: 820, height: 660))
        win.minSize = NSSize(width: 780, height: 620)
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified
        win.title = navigation.page.title
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
        guard notification.object as? NSWindow === window else { return }
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
