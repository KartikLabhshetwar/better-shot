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

    func openAnnotateEditor() {
        guard let url = currentURL else { return }
        dismiss()
        EditorWindowController.shared.open(url: url)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 150),
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
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: PreviewCardView(overlay: self))
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = CGSize(width: 280, height: 220)

        let x: CGFloat
        let y: CGFloat

        switch AppPreferences.overlayPosition {
        case .bottomRight:
            x = screenFrame.maxX - panelSize.width
            y = screenFrame.minY
        case .bottomLeft:
            x = screenFrame.minX
            y = screenFrame.minY
        }

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
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
    @State private var isHovered = false

    private let cardSize = CGSize(width: 165, height: 124)

    var body: some View {
        Group {
            if let url = overlay.currentURL, let image = NSImage(contentsOf: url) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()

                    if isHovered {
                        hoverOverlay(image: image)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
                .onTapGesture {
                    if !isHovered {
                        overlay.openAnnotateEditor()
                    }
                }
                .draggable(image)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 28)
        .padding(.bottom, 32)
        .frame(width: 280, height: 220)
    }

    @ViewBuilder
    private func hoverOverlay(image: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.45)

            // Corner actions
            VStack {
                HStack {
                    // Delete
                    cornerButton("trash.circle.fill") {
                        if let url = overlay.currentURL {
                            try? FileManager.default.removeItem(at: url)
                        }
                        overlay.dismiss()
                    }
                    Spacer()
                    // Dismiss
                    cornerButton("xmark.circle.fill") {
                        overlay.dismiss()
                    }
                }

                Spacer()

                HStack {
                    // Annotate (pen icon)
                    cornerButton("pencil.circle.fill") {
                        overlay.openAnnotateEditor()
                    }
                    // Pin screenshot
                    cornerButton("pin.circle.fill") {
                        if let url = overlay.currentURL {
                            PinnedScreenshotController.shared.pin(url: url)
                        }
                        overlay.dismiss()
                    }
                    Spacer()
                }
            }
            .padding(8)

            // Center pill actions
            HStack(spacing: 6) {
                pillButton("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    overlay.dismiss()
                }
                pillButton("Save") {
                    overlay.dismiss()
                }
            }
        }
    }

    private func cornerButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(0.25))
                .font(.title2)
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
