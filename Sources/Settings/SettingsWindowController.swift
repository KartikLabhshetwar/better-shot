import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: PreferencesView())

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.collectionBehavior = [.moveToActiveSpace]

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        win.toolbar = toolbar
        win.toolbarStyle = .unified
        win.titlebarSeparatorStyle = .line

        centerOnCurrentScreen(win)

        window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if EditorWindowController.shared.hasOpenWindows == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .toggleSidebar {
            return NSToolbarItem(itemIdentifier: .toggleSidebar)
        }
        return nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar]
    }

    // MARK: - Private

    private func centerOnCurrentScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
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
