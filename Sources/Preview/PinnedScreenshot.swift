import AppKit
import SwiftUI

// MARK: - PinnedScreenshotController

/// Manages multiple pinned screenshot floating windows.
@MainActor
final class PinnedScreenshotController {
    static let shared = PinnedScreenshotController()
    private var panels: [NSPanel] = []
    private init() {}

    var hasPinnedWindows: Bool {
        !panels.isEmpty
    }

    /// Creates a new borderless, always-on-top floating panel showing the image at `url`.
    func pin(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }

        // Compute initial panel size: scale image to max 400pt on longest side.
        let maxSide: CGFloat = 400
        let imgSize = image.size
        let scale: CGFloat
        if imgSize.width >= imgSize.height {
            scale = min(maxSide / imgSize.width, 1)
        } else {
            scale = min(maxSide / imgSize.height, 1)
        }
        let panelSize = CGSize(
            width: max(imgSize.width * scale, 80),
            height: max(imgSize.height * scale, 60)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let contentView = PinnedScreenshotView(
            image: image,
            originalDisplaySize: panelSize,
            onClose: { [weak self, weak panel] in
                guard let self, let panel else { return }
                panel.orderOut(nil)
                self.panels.removeAll { $0 === panel }
            }
        )
        panel.contentView = NSHostingView(rootView: contentView)

        // Center on screen, offset slightly so multiple pins don't fully overlap.
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - panelSize.width / 2 + CGFloat(panels.count) * 20
            let y = sf.midY - panelSize.height / 2 - CGFloat(panels.count) * 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panels.append(panel)
        panel.orderFront(nil)
    }

    /// Closes all pinned panels.
    func unpinAll() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

// MARK: - PinnedScreenshotView

/// SwiftUI content view for a single pinned screenshot panel.
struct PinnedScreenshotView: View {
    let image: NSImage
    let originalDisplaySize: CGSize
    let onClose: () -> Void

    @State private var scaleFactor: CGFloat = 1.0
    @State private var isHovered: Bool = false

    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0

    var body: some View {
        let w = originalDisplaySize.width * scaleFactor
        let h = originalDisplaySize.height * scaleFactor

        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: w, height: h)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }

            // Close (X) button — visible on hover
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(4)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(width: w, height: h)
        // Resize via scroll wheel
        .onScrollWheel { delta in
            let newScale = (scaleFactor + delta * 0.05).clamped(to: minScale...maxScale)
            scaleFactor = newScale
            resizeWindow(to: CGSize(width: originalDisplaySize.width * newScale,
                                    height: originalDisplaySize.height * newScale))
        }
        // Right-click context menu
        .contextMenu {
            Button("Copy Image") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
            }
            Button("Close") {
                onClose()
            }
        }
    }

    private func resizeWindow(to newSize: CGSize) {
        guard let window = NSApp.windows.first(where: {
            ($0.contentView as? NSHostingView<PinnedScreenshotView>) != nil
        }) ?? findHostingWindow() else { return }

        var frame = window.frame
        // Keep the top-left corner anchored.
        frame.origin.y += frame.size.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: false)
    }

    private func findHostingWindow() -> NSWindow? {
        // Walk all app windows to find the one hosting this view.
        for window in NSApp.windows {
            if let hv = window.contentView as? NSHostingView<PinnedScreenshotView> {
                // Check it's ours by comparing image size as a proxy.
                if hv.rootView.image.size == image.size {
                    return window
                }
            }
        }
        return nil
    }
}

// MARK: - Scroll-wheel modifier

private struct ScrollWheelModifier: ViewModifier {
    let handler: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(handler: handler)
        )
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (CGFloat) -> Void

    func makeNSView(context: Context) -> _ScrollWheelNSView {
        let v = _ScrollWheelNSView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: _ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _ScrollWheelNSView: NSView {
    var handler: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        handler?(delta)
    }
}

private extension View {
    func onScrollWheel(_ handler: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(handler: handler))
    }
}

// MARK: - Comparable clamped helper (local, no collision risk)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
