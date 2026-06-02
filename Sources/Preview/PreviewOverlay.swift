import AppKit
import SwiftUI

/// Shows a floating preview card after capture. Uses a borderless NSPanel.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    private(set) var currentURL: URL?
    private(set) var isVisible = false
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(url: URL) {
        currentURL = url
        isVisible = true

        if panel == nil {
            createPanel()
        }

        positionPanel()
        panel?.orderFront(nil)

        scheduleDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        panel?.orderOut(nil)
        isVisible = false
        currentURL = nil
    }

    // MARK: - Panel Setup

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: PreviewCardView(overlay: self))
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }

        let margin: CGFloat = 16
        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame

        let x: CGFloat
        let y: CGFloat

        switch AppPreferences.overlayPosition {
        case .bottomRight:
            x = screenFrame.maxX - panelSize.width - margin
            y = screenFrame.minY + margin
        case .bottomLeft:
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

// MARK: - Preview Card SwiftUI View

struct PreviewCardView: View {
    let overlay: PreviewOverlay

    var body: some View {
        Group {
            if let url = overlay.currentURL, let image = NSImage(contentsOf: url) {
                VStack(spacing: 0) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 12) {
                        Button("Copy") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.writeObjects([image])
                            overlay.dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                        Button("Save") {
                            overlay.dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            overlay.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            }
        }
        .frame(width: 320, height: 200)
    }
}
