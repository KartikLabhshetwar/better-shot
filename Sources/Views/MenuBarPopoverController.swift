import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MenuBarPopoverController: NSObject {
    static let shared = MenuBarPopoverController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private(set) var isOpen = false
    private var eventMonitor: Any?

    var originScreen: NSScreen? {
        statusItem?.button?.window?.screen
    }

    private override init() { super.init() }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        if let window = item.button?.window {
            window.registerForDraggedTypes([.fileURL])
            window.delegate = self
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

        let closingPanel = panel
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            closingPanel.animator().alphaValue = 0
        }, completionHandler: {
            closingPanel.orderOut(nil)
            closingPanel.contentView = nil
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
            DispatchQueue.main.async {
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

extension MenuBarPopoverController: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedImageURLs(from: sender).isEmpty else { return [] }
        showDropTargetHint()
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTargetHint()
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        clearDropTargetHint()
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearDropTargetHint()
        let urls = droppedImageURLs(from: sender)
        guard !urls.isEmpty else { return false }
        for url in urls {
            PreviewPanelPresenter.shared.onAnnotate?(url)
        }
        return true
    }

    private func showDropTargetHint() {
        guard let button = statusItem?.button else { return }
        button.isHighlighted = true
        let hint = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Drop image to edit")
        hint?.isTemplate = true
        setIcon(hint, on: button, duration: 0.18)
    }

    private func clearDropTargetHint() {
        guard let button = statusItem?.button else { return }
        button.isHighlighted = false
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        setIcon(icon, on: button, duration: 0.12)
    }

    private func setIcon(_ image: NSImage?, on button: NSStatusBarButton, duration: CFTimeInterval) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            button.wantsLayer = true
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.layer?.add(fade, forKey: "iconFade")
        }
        button.image = image
    }

    private func droppedImageURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
