import AppKit
import SwiftUI

/// Shows a floating deck of preview cards after capture. Uses a borderless NSPanel.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    static let maxItems = 5
    private static let cardSpacing: CGFloat = 10
    private static let clearAllHeight: CGFloat = 26

    private(set) var items: [URL] = []
    private var panel: NSPanel?
    private var dismissTasks: [URL: Task<Void, Never>] = [:]
    private var targetScreen: NSScreen?

    var currentScreen: NSScreen? { targetScreen }

    var panelSize: CGSize {
        let size = AppPreferences.overlayCardSize
        let extraCards = CGFloat(max(items.count - 1, 0))
        let height = size.panelSize.height
            + extraCards * (size.thumbnailSize.height + Self.cardSpacing)
            + (items.count > 1 ? Self.clearAllHeight : 0)
        return CGSize(width: size.panelSize.width, height: height)
    }

    private init() {}

    func show(url: URL, on screen: NSScreen? = nil) {
        cancelScheduledDismiss(for: url)
        items.removeAll { $0 == url }
        items.append(url)
        while items.count > Self.maxItems {
            let evicted = items.removeFirst()
            cancelScheduledDismiss(for: evicted)
        }
        targetScreen = screen

        if panel == nil {
            createPanel()
        }

        positionPanel()
        panel?.orderFront(nil)

        scheduleDismiss(for: url)
    }

    func remove(_ url: URL) {
        cancelScheduledDismiss(for: url)
        items.removeAll { $0 == url }
        if items.isEmpty {
            dismiss()
        } else {
            positionPanel()
        }
    }

    func dismiss() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()

        panel?.orderOut(nil)
        panel = nil
        items.removeAll()
    }

    func cancelScheduledDismiss(for url: URL) {
        dismissTasks.removeValue(forKey: url)?.cancel()
    }

    // MARK: - Panel Setup

    func openAnnotateEditor(for url: URL) {
        remove(url)
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

        let hostingView = NSHostingView(rootView: PreviewDeckView(overlay: self))
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
        let panelSize = panelSize

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

    private func scheduleDismiss(for url: URL) {
        guard AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay) else { return }
        dismissTasks[url] = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            remove(url)
        }
    }
}

// MARK: - Preview Deck SwiftUI View

struct PreviewDeckView: View {
    let overlay: PreviewOverlay

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if overlay.items.count > 1 {
                Button("Clear All") { overlay.dismiss() }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .buttonStyle(.plain)
            }
            ForEach(overlay.items, id: \.self) { url in
                PreviewCardView(overlay: overlay, url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .frame(width: overlay.panelSize.width, height: overlay.panelSize.height)
    }
}

// MARK: - Preview Card SwiftUI View

struct PreviewCardView: View {
    let overlay: PreviewOverlay
    let url: URL
    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    // Read fresh each time a card is shown rather than cached: `dismiss()`
    // always nils the panel and `show()` always rebuilds it, so a size change
    // in Settings takes effect on the next capture without any extra wiring.
    private var cardSize: CGSize { AppPreferences.overlayCardSize.thumbnailSize }

    private var isVideo: Bool { Self.isVideo(url) }

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
                    overlay.openAnnotateEditor(for: url)
                }
                .onDrag {
                    if let provider = NSItemProvider(contentsOf: url) {
                        provider.suggestedName = url.lastPathComponent
                        return provider
                    }
                    return NSItemProvider(object: image)
                }
            } else {
                Color.clear.frame(width: cardSize.width, height: cardSize.height)
            }
        }
        .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
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
            await MainActor.run { thumbnail = image }
        }
    }

    @ViewBuilder
    private func hoverOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    overlay.openAnnotateEditor(for: url)
                }

            // Corner actions
            VStack {
                HStack {
                    // Delete
                    cornerButton("trash.circle.fill") {
                        if let record = HistoryStore.shared.record(matching: url) {
                            HistoryStore.shared.deleteRecord(record)
                        } else {
                            try? FileManager.default.removeItem(at: url)
                        }
                        overlay.remove(url)
                    }
                    Spacer()
                    // Dismiss
                    cornerButton("xmark.circle.fill") {
                        overlay.remove(url)
                    }
                }

                Spacer()

                HStack {
                    // Annotate (pen icon)
                    cornerButton("pencil.circle.fill") {
                        overlay.openAnnotateEditor(for: url)
                    }
                    Spacer()
                    // Pin screenshot
                    cornerButton("pin.circle.fill") {
                        PinnedScreenshotController.shared.pin(url: url)
                        overlay.remove(url)
                    }
                }
            }
            .padding(6)

            // Center pill actions
            HStack(spacing: 6) {
                pillButton("Copy") {
                    // Copy the capture itself, not the card's thumbnail.
                    do {
                        if Self.isVideo(url) {
                            try VideoFileActions.copyToClipboard(from: url)
                        } else {
                            try ScreenshotFileActions.copyImageToClipboard(from: url)
                        }
                        overlay.remove(url)
                    } catch {
                        // Reading the file can fail if the capture moved or was deleted
                        // between the shot and the click. The card stays up so the copy
                        // can be retried, or the capture dragged out instead.
                        overlay.cancelScheduledDismiss(for: url)
                        ToastWindow.shared.show(
                            title: "Copy Failed",
                            message: error.localizedDescription,
                            systemIcon: "exclamationmark.triangle",
                            on: overlay.currentScreen
                        )
                    }
                }
                pillButton("Save") {
                    overlay.remove(url)
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
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
