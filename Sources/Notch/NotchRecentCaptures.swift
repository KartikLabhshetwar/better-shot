import SwiftUI

/// Reuse the gallery's project resolution, thumbnails, and capture actions.
struct NotchRecentCaptures: View {
    @State private var kind: CaptureKind?
    @State private var error: String?

    static func items(kind: CaptureKind? = nil) -> [MediaGalleryItem] {
        let all = MediaGalleryItem.collect(history: HistoryStore.shared,
            edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects)
        return Array(MediaGalleryItem.filtered(all, kind: kind, cloud: false, search: "").prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Captures").font(.subheadline.weight(.medium))
                Spacer()
                Button("Open Gallery", systemImage: "photo.on.rectangle") {
                    MediaGalleryWindowController.shared.open(on: NotchPresenter.shared.screen)
                }
            }
            Picker("Recent capture type", selection: $kind) {
                Text("All").tag(Optional<CaptureKind>.none)
                Text("Screenshots").tag(Optional(CaptureKind.screenshot))
                Text("Videos").tag(Optional(CaptureKind.recording))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let recent = Self.items(kind: kind)
            if recent.isEmpty {
                Text("Your recent screenshots and videos will appear here.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recent) { item in
                        MediaGalleryCard(item: item, cloud: false,
                            onSelect: { error = item.open(cloud: false) },
                            onDeleteFailure: { error = $0 })
                            .frame(width: 142)
                            .focusable()
                            .help("Open \(item.title). Right-click for more actions.")
                    }
                    Spacer(minLength: 0)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
