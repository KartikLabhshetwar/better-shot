import AppKit
import SwiftUI

@MainActor
final class ToastWindow {
    static let shared = ToastWindow()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(title: String = "Saved", message: String, icon: NSImage? = nil, systemIcon: String? = nil, duration: TimeInterval = 2.5) {
        dismiss(animated: false)

        let toastView = ToastContentView(title: title, message: message, icon: icon, systemIcon: systemIcon)
        let hostingView = NSHostingView(rootView: toastView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss(animated: true)
        }
    }

    func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel, panel.isVisible else {
            self.panel = nil
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    panel.orderOut(nil)
                    self?.panel = nil
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

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
