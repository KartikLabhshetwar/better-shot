import SwiftUI

enum NotchShelfFilter: String, CaseIterable, Identifiable {
    case all = "All", text = "Text", images = "Images", videos = "Videos", colors = "Colors"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "doc.text.viewfinder"
        case .images: return "photo"
        case .videos: return "video"
        case .colors: return "eyedropper"
        }
    }
}

/// Keep the gallery's project resolution and ordering; pending captures lead the shelf.
enum NotchRecentCaptures {
    static func items(kind: CaptureKind? = nil) -> [MediaGalleryItem] {
        let all = MediaGalleryItem.collect(history: HistoryStore.shared,
            edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects)
        return Array(MediaGalleryItem.filtered(all, kind: kind, cloud: false, search: "").prefix(4))
    }

    static func mediaURLs(pending: [URL], filter: NotchShelfFilter) -> [URL] {
        guard filter != .text, filter != .colors else { return [] }
        let kind: CaptureKind? = filter == .images ? .screenshot : filter == .videos ? .recording : nil
        var seen = Set<URL>()
        return (Array(pending.reversed()) + items(kind: kind).map(\.previewURL)).filter { url in
            guard seen.insert(url.standardizedFileURL).inserted else { return false }
            return kind == nil || PreviewOverlay.isVideo(url) == (kind == .recording)
        }
    }
}

struct NotchMediaCard: View {
    let url: URL
    @State private var overlay = PreviewOverlay.shared

    private var busy: Bool { overlay.savingItems.contains(url) || overlay.transferStatus(for: url) != nil }
    private var pending: Bool { overlay.items.contains(url) }

    var body: some View {
        VStack(spacing: 0) {
            PreviewCardView(overlay: overlay, url: url, usesNotchActions: true,
                            notchCardSize: CGSize(width: 184, height: 120))
            HStack(spacing: 4) {
                Text(PreviewOverlay.isVideo(url) ? "Video" : "Image")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Copy", systemImage: "doc.on.doc") { overlay.perform(.copy, for: url) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(width: 28, height: 28).help("Copy capture")
                Button("Save", systemImage: "square.and.arrow.down") { overlay.perform(.save, for: url) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(width: 28, height: 28).help("Save capture")
                Menu {
                    if !PreviewOverlay.isVideo(url) {
                        Button("Quick Edit", systemImage: "slider.horizontal.3") { NotchQuickEditor.shared.open(url) }
                    }
                    ForEach([OverlayTool.edit, .copy, .save, .share, .pin]) { tool in
                        Button(tool.title, systemImage: tool.symbol) { overlay.perform(tool, for: url) }
                    }
                    if pending {
                        Divider()
                        Button("Dismiss", systemImage: "xmark") { overlay.perform(.dismiss, for: url) }
                    }
                } label: { Label("Capture actions", systemImage: "ellipsis") }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .disabled(busy)
        }
        .frame(width: 184, height: 160)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .help("Open \(url.lastPathComponent) in the editor. Drag the preview into another app, or use the buttons to copy and save.")
    }
}
