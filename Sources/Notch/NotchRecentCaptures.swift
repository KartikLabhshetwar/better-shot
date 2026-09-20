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
    struct Media: Identifiable {
        let url: URL
        let date: Date
        var id: URL { url.standardizedFileURL }
    }

    enum ShelfItem: Identifiable {
        case result(NotchShelfStore.Entry)
        case media(Media)

        var id: String {
            switch self {
            case .result(let entry): "result-\(entry.id)"
            case .media(let media): "media-\(media.id.path)"
            }
        }

        var date: Date {
            switch self {
            case .result(let entry): entry.date
            case .media(let media): media.date
            }
        }
    }

    static func items(kind: CaptureKind? = nil) -> [MediaGalleryItem] {
        let all = MediaGalleryItem.collect(history: HistoryStore.shared,
            edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects)
        return Array(MediaGalleryItem.filtered(all, kind: kind, cloud: false, search: "").prefix(4))
    }

    static func media(pending: [URL], filter: NotchShelfFilter) -> [Media] {
        guard filter != .text, filter != .colors else { return [] }
        let kind: CaptureKind? = filter == .images ? .screenshot : filter == .videos ? .recording : nil
        var seen = Set<URL>()
        var result: [Media] = []
        for (index, url) in pending.reversed().enumerated() {
            guard (kind == nil || PreviewOverlay.isVideo(url) == (kind == .recording)),
                  seen.insert(url.standardizedFileURL).inserted else { continue }
            result.append(Media(url: url, date: .distantFuture.addingTimeInterval(-Double(index))))
        }
        for item in items(kind: kind) {
            let url = item.previewURL
            guard seen.insert(url.standardizedFileURL).inserted else { continue }
            result.append(Media(url: url, date: item.createdAt))
        }
        return result
    }

    static func mediaURLs(pending: [URL], filter: NotchShelfFilter) -> [URL] {
        media(pending: pending, filter: filter).map(\.url)
    }

    static func shelfItems(pending: [URL], entries: [NotchShelfStore.Entry], filter: NotchShelfFilter) -> [ShelfItem] {
        let results = entries.filter {
            filter == .all || (filter == .colors && $0.isColor == true) || (filter == .text && $0.isColor != true)
        }.map(ShelfItem.result)
        return (media(pending: pending, filter: filter).map(ShelfItem.media) + results)
            .sorted { $0.date > $1.date }
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
