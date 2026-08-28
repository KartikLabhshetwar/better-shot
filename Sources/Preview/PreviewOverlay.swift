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
    private var targetScreen: NSScreen?

    private init() {}

    func show(url: URL, on screen: NSScreen? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        currentURL = url
        targetScreen = screen
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
        panel = nil
        isVisible = false
        currentURL = nil
    }

    // MARK: - Panel Setup

    func openAnnotateEditor() {
        guard let url = currentURL else { return }
        dismiss()
        PreviewPanelPresenter.shared.openEditor(for: url)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 130),
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
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let panel, let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = AppPreferences.overlayCardSize.panelSize

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
        guard AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay) else { return }
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
    @State private var thumbnail: NSImage?

    // Read fresh each time a card is shown rather than cached: `dismiss()`
    // always nils the panel and `show()` always rebuilds it, so a size change
    // in Settings takes effect on the next capture without any extra wiring.
    private var cardSize: CGSize { AppPreferences.overlayCardSize.thumbnailSize }
    private var panelSize: CGSize { AppPreferences.overlayCardSize.panelSize }

    private var isVideo: Bool {
        guard let url = overlay.currentURL else { return false }
        return Self.isVideo(url)
    }

    private static func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "mp4"
    }

    var body: some View {
        Group {
            if let image = thumbnail {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()

                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }

                    if isHovered {
                        hoverOverlay()
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
                .onTapGesture {
                    overlay.openAnnotateEditor()
                }
                .onDrag {
                    if let url = overlay.currentURL,
                       let provider = NSItemProvider(contentsOf: url) {
                        provider.suggestedName = url.lastPathComponent
                        return provider
                    }
                    return NSItemProvider(object: image)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .frame(width: panelSize.width, height: panelSize.height)
        .onChange(of: overlay.currentURL) { _, newURL in
            loadThumbnail(from: newURL)
        }
        .onAppear {
            loadThumbnail(from: overlay.currentURL)
        }
    }

    private func loadThumbnail(from url: URL?) {
        guard let url else {
            thumbnail = nil
            return
        }

        // Both kinds go through the history store's decoder: it samples a bounded
        // thumbnail rather than the full bitmap, and it is nonisolated, so the
        // decode runs off the main actor instead of on the tick that just
        // finished rendering the capture.
        let source = HistoryStore.ThumbnailSource(
            url: url,
            kind: Self.isVideo(url) ? .recording : .screenshot
        )
        let sampleSize = max(cardSize.width, cardSize.height) * 2 // retina headroom at the current card size
        Task.detached(priority: .userInitiated) {
            let image = HistoryStore.decodeThumbnail(source, maxSize: sampleSize)
            // Two captures in quick succession race: the older decode can land last
            // and paint the previous capture onto the current card.
            await MainActor.run {
                if overlay.currentURL == url { thumbnail = image }
            }
        }
    }

    @ViewBuilder
    private func hoverOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    overlay.openAnnotateEditor()
                }

            // Corner actions
            VStack {
                HStack {
                    // Delete
                    cornerButton("trash.circle.fill") {
                        if let url = overlay.currentURL {
                            if let record = HistoryStore.shared.records.first(where: {
                                HistoryStore.shared.urlForRecord($0) == url
                            }) {
                                HistoryStore.shared.deleteRecord(record)
                            } else {
                                try? FileManager.default.removeItem(at: url)
                            }
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
                    Spacer()
                    // Pin screenshot
                    cornerButton("pin.circle.fill") {
                        if let url = overlay.currentURL {
                            PinnedScreenshotController.shared.pin(url: url)
                        }
                        overlay.dismiss()
                    }
                }
            }
            .padding(6)

            // Center pill actions
            HStack(spacing: 6) {
                pillButton("Copy") {
                    // Copy the capture itself, not the card's thumbnail.
                    if let url = overlay.currentURL {
                        if isVideo {
                            try? VideoFileActions.copyToClipboard(from: url)
                        } else {
                            try? ScreenshotFileActions.copyImageToClipboard(from: url)
                        }
                    }
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
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
