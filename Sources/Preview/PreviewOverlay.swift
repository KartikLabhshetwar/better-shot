import AppKit
import AVFoundation
import SwiftUI

/// Shows a stack of floating preview cards after capture. Uses a borderless NSPanel.
/// Multiple screenshots taken in quick succession stack up (newest closest to the
/// screen corner) instead of replacing each other, up to `maxItems`.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    static let maxItems = 5

    /// Card size, scaled 30% larger than the original 130x98 design.
    static let cardSize = CGSize(width: 169, height: 127)
    static let itemSpacing: CGFloat = 14
    static let panelWidth: CGFloat = 260
    static let panelTrailingPadding: CGFloat = 26
    static let panelLeadingPadding: CGFloat = 26
    static let panelBottomPadding: CGFloat = 31
    static let panelTopPadding: CGFloat = 63

    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let screen: NSScreen?
    }

    private(set) var items: [Item] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private var panel: NSPanel?
    private var targetScreen: NSScreen?

    var isVisible: Bool { !items.isEmpty }

    private init() {}

    func show(url: URL, on screen: NSScreen? = nil) {
        targetScreen = screen

        if items.count >= Self.maxItems, let oldest = items.first {
            cancelDismiss(for: oldest.id)
            items.removeFirst()
        }

        let item = Item(url: url, screen: screen)
        items.append(item)

        if panel == nil {
            createPanel()
        }

        positionPanel()
        panel?.orderFront(nil)

        scheduleDismiss(for: item.id)
    }

    func dismiss(_ id: UUID) {
        cancelDismiss(for: id)
        items.removeAll { $0.id == id }

        if items.isEmpty {
            panel?.orderOut(nil)
            panel = nil
        } else {
            positionPanel()
        }
    }

    func dismissAll() {
        for id in dismissTasks.keys { dismissTasks[id]?.cancel() }
        dismissTasks.removeAll()
        items.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel Setup

    func openAnnotateEditor(for item: Item) {
        let screen = item.screen
        dismiss(item.id)
        let ext = item.url.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" {
            VideoEditorWindowController.shared.open(url: item.url, on: screen)
        } else {
            EditorWindowController.shared.open(url: item.url, on: screen)
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelTopPadding + Self.panelBottomPadding + Self.cardSize.height),
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

        let hostingView = NSHostingView(rootView: PreviewStackView(overlay: self))
        hostingView.autoresizingMask = [.width, .height]
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
        let count = max(items.count, 1)
        let height = Self.panelTopPadding + Self.panelBottomPadding
            + CGFloat(count) * Self.cardSize.height
            + CGFloat(count - 1) * Self.itemSpacing
        let width = Self.panelWidth

        let x: CGFloat
        switch AppPreferences.overlayPosition {
        case .bottomRight:
            x = screenFrame.maxX - width
        case .bottomLeft:
            x = screenFrame.minX
        }
        let y = screenFrame.minY

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: CGSize(width: width, height: height)), display: true)
    }

    private func scheduleDismiss(for id: UUID) {
        cancelDismiss(for: id)
        guard !AppPreferences.overlayNeverDismiss else { return }
        dismissTasks[id] = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            self.dismiss(id)
        }
    }

    private func cancelDismiss(for id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }
}

// MARK: - Preview Stack SwiftUI View

struct PreviewStackView: View {
    let overlay: PreviewOverlay

    private var alignment: HorizontalAlignment {
        AppPreferences.overlayPosition == .bottomLeft ? .leading : .trailing
    }

    var body: some View {
        VStack(alignment: alignment, spacing: PreviewOverlay.itemSpacing) {
            ForEach(overlay.items) { item in
                PreviewCardView(item: item, overlay: overlay)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: AppPreferences.overlayPosition == .bottomLeft ? .bottomLeading : .bottomTrailing)
        .padding(.leading, AppPreferences.overlayPosition == .bottomLeft ? PreviewOverlay.panelLeadingPadding : 0)
        .padding(.trailing, AppPreferences.overlayPosition == .bottomLeft ? 0 : PreviewOverlay.panelTrailingPadding)
        .padding(.bottom, PreviewOverlay.panelBottomPadding)
    }
}

// MARK: - Preview Card SwiftUI View

struct PreviewCardView: View {
    let item: PreviewOverlay.Item
    let overlay: PreviewOverlay
    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    init(item: PreviewOverlay.Item, overlay: PreviewOverlay) {
        self.item = item
        self.overlay = overlay
        let ext = item.url.pathExtension.lowercased()
        let isVideo = ext == "mov" || ext == "mp4"
        // Images load synchronously here; video thumbnails generate async in onAppear.
        _thumbnail = State(initialValue: isVideo ? nil : NSImage(contentsOf: item.url))
    }

    private var cardSize: CGSize { PreviewOverlay.cardSize }

    private var isVideo: Bool {
        let ext = item.url.pathExtension.lowercased()
        return ext == "mov" || ext == "mp4"
    }

    var body: some View {
        ZStack {
            if let image = thumbnail {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()

                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }

                    if isHovered {
                        hoverOverlay(image: image)
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
                    overlay.openAnnotateEditor(for: item)
                }
                .onDrag {
                    NSItemProvider(object: item.url as NSURL)
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .onAppear {
            if isVideo, thumbnail == nil {
                loadVideoThumbnail(from: item.url)
            }
        }
    }

    private func loadVideoThumbnail(from url: URL) {
        Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 338, height: 254)
            if let result = try? await generator.image(at: .zero) {
                let cgImage = result.image
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run { thumbnail = nsImage }
            }
        }
    }

    @ViewBuilder
    private func hoverOverlay(image: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    overlay.openAnnotateEditor(for: item)
                }

            // Corner actions
            VStack {
                HStack {
                    // Delete
                    cornerButton("trash.circle.fill") {
                        if let record = HistoryStore.shared.records.first(where: {
                            HistoryStore.shared.urlForRecord($0) == item.url
                        }) {
                            HistoryStore.shared.deleteRecord(record)
                        } else {
                            try? FileManager.default.removeItem(at: item.url)
                        }
                        overlay.dismiss(item.id)
                    }
                    Spacer()
                    // Dismiss
                    cornerButton("xmark.circle.fill") {
                        overlay.dismiss(item.id)
                    }
                }

                Spacer()

                HStack {
                    // Annotate (pen icon)
                    cornerButton("pencil.circle.fill") {
                        overlay.openAnnotateEditor(for: item)
                    }
                    Spacer()
                    // Pin screenshot
                    cornerButton("pin.circle.fill") {
                        PinnedScreenshotController.shared.pin(url: item.url)
                        overlay.dismiss(item.id)
                    }
                }
            }
            .padding(8)

            // Center pill actions
            HStack(spacing: 8) {
                pillButton("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    overlay.dismiss(item.id)
                }
                pillButton("Save") {
                    overlay.dismiss(item.id)
                }
            }
        }
    }

    private func cornerButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(0.25))
                .font(.system(size: 20))
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
