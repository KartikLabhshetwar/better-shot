import AppKit
import SwiftUI

@MainActor
final class ToastWindow {
    static let shared = ToastWindow()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    private var panelGeneration: UInt = 0

    func show(title: String = "Saved", message: String, icon: NSImage? = nil, systemIcon: String? = nil, duration: TimeInterval = 2.5, on preferredScreen: NSScreen? = nil) {
        dismiss(animated: false)
        panelGeneration &+= 1

        let toastView = ToastContentView(title: title, message: message, icon: icon, systemIcon: systemIcon)
        let hostingView = NSHostingView(rootView: toastView)

        let panel = Self.makePanel(hostingView: hostingView)
        panel.identifier = NSUserInterfaceItemIdentifier("BetterShot.Toast")
        guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let origin = Self.origin(for: panel.frame.size, in: screen.visibleFrame)
        let x = origin.x
        let y = origin.y
        let slide: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 10
        panel.setFrameOrigin(NSPoint(x: x, y: y + slide))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(NSPoint(x: x, y: y))
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss(animated: true)
        }
    }

    /// Shared native presentation for informational and interactive transfer toasts.
    static func makePanel<Content: View>(hostingView: NSHostingView<Content>) -> NSPanel {
        // The panel owns its size. Bridging SwiftUI's min/ideal/max sizes back
        // onto this window can recursively invalidate constraints on macOS 26.
        let size = hostingView.fittingSize
        hostingView.sizingOptions = []
        hostingView.setFrameSize(size)
        hostingView.autoresizingMask = [.width, .height]
        let panel = ToastPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    static func origin(for size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - 12)
    }

    func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel, panel.isVisible else {
            self.panel = nil
            return
        }

        if animated {
            let gen = panelGeneration
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                panel.orderOut(nil)
                Task { @MainActor in
                    guard let self, self.panelGeneration == gen else { return }
                    self.panel = nil
                }
            })
        } else {
            panel.orderOut(nil)
            self.panel = nil
        }
    }
}

private struct ToastContentView: View {
    let title: String
    let message: String
    let icon: NSImage?
    let systemIcon: String?

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 14, depth: .raised)
        .accessibilityElement(children: .combine)
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
