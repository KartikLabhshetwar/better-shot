import AppKit
import SwiftUI

@MainActor
final class MenuBarPopoverController: NSObject {
    static let shared = MenuBarPopoverController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private(set) var isOpen = false
    private var eventMonitor: Any?

    private override init() { super.init() }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        statusItem = item
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if isOpen {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        let panelWidth = panel.frame.width
        let panelX = screenRect.midX - panelWidth / 2
        let panelY = screenRect.minY - panel.frame.height

        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isOpen = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        }

        startEventMonitor()
    }

    func closePopover() {
        guard let panel, isOpen else { return }
        isOpen = false
        stopEventMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard self?.isOpen != true else { return }
                panel.orderOut(nil)
                self?.panel?.contentView = nil
                self?.panel = nil
            }
        })
    }

    private func createPanel() {
        let dismiss: @MainActor () -> Void = { [weak self] in
            self?.closePopover()
        }

        let contentView = MenuBarPanelView(dismissPopover: dismiss)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
