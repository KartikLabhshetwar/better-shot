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

    var body: some View {
        PreviewCardView(overlay: overlay, url: url, usesNotchActions: true,
                        notchCardSize: CGSize(width: 184, height: 160))
            .help("Open \(url.lastPathComponent). Hover for actions, or drag the preview into another app.")
    }
}
