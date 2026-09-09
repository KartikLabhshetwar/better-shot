import AppKit
import SwiftUI

struct MediaGalleryItem: Identifiable {
    let id: String
    let title: String
    let createdAt: Date
    let kind: CaptureKind
    let localURL: URL
    let editorURL: URL
    let cloudURL: URL?
    var modifiedAt: Date?

    var hasLocalFile: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    static func cloudLink(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    @MainActor
    static func collect(history: HistoryStore, edits: [ScreenshotHistoryItem],
                        projects: [RecordingProjectSummary]) -> [Self] {
        var result: [Self] = []
        var representedPaths = Set<String>()
        for item in edits {
            let session = item.recordingSession
            let local = FileManager.default.fileExists(atPath: item.url.path)
                ? item.url : item.sourceCapturePath.map { URL(fileURLWithPath: $0) } ?? item.url
            result.append(Self(id: item.id.uuidString,
                title: session?.displayName ?? item.fileName, createdAt: item.createdAt,
                kind: item.isVideo ? .recording : .screenshot, localURL: local,
                editorURL: local == item.url ? item.editorURL : local,
                cloudURL: cloudLink(item.cloudURL), modifiedAt: item.updatedAt))
            representedPaths.insert(item.url.standardizedFileURL.path)
            if let source = item.sourceCapturePath {
                representedPaths.insert(URL(fileURLWithPath: source).standardizedFileURL.path)
            }
            if let session { representedPaths.insert(session.screenURL.standardizedFileURL.path) }
        }
        for record in history.records {
            let raw = history.urlForRecord(record)
            let display = history.displayURLForRecord(record)
            guard !representedPaths.contains(raw.standardizedFileURL.path),
                  !representedPaths.contains(display.standardizedFileURL.path),
                  !representedPaths.contains(record.beautifiedPath.map {
                      URL(fileURLWithPath: $0).standardizedFileURL.path
                  } ?? "") else { continue }
            representedPaths.insert(raw.standardizedFileURL.path)
            result.append(Self(id: record.id.uuidString, title: record.filename,
                createdAt: record.createdAt, kind: record.kind, localURL: display,
                editorURL: record.kind == .recording
                    ? ScreenshotHistoryStore.shared.editorURL(for: display)
                    : ScreenshotHistoryStore.shared.annotationEditorURL(for: display),
                cloudURL: cloudLink(record.shareURL),
                modifiedAt: try? display.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate))
        }
        for project in projects where !representedPaths.contains(project.session.screenURL.standardizedFileURL.path) {
            result.append(Self(id: project.id.path, title: project.displayName,
                createdAt: project.createdAt, kind: .recording,
                localURL: project.session.deliverableURL, editorURL: project.session.directoryURL,
                cloudURL: nil,
                modifiedAt: try? project.session.deliverableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate))
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    static func filtered(_ items: [Self], kind: CaptureKind?, cloud: Bool, search: String) -> [Self] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            (kind == nil || $0.kind == kind)
                && (cloud ? $0.cloudURL != nil : $0.hasLocalFile)
                && (query.isEmpty || $0.title.localizedStandardContains(query))
        }
    }
}

struct MediaGallery: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Media Gallery").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            MediaGalleryContent(items: MediaGalleryItem.collect(history: HistoryStore.shared,
                edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects),
                refresh: refresh)
        }
        .frame(width: 740, height: 580)
        .task { refresh() }
    }

    private func refresh() {
        ScreenshotHistoryStore.shared.reload()
        RecordingProjectStore.shared.reload()
    }
}

struct MediaGalleryContent: View {
    let items: [MediaGalleryItem]
    var refresh: () -> Void = {}
    @State private var kind: CaptureKind?
    @State private var cloud = false
    @State private var search = ""

    var body: some View {
        let visible = MediaGalleryItem.filtered(items, kind: kind, cloud: cloud, search: search)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Storage", selection: $cloud) {
                    Text("Local").tag(false)
                    Text("Cloud").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
            }
            HStack {
                Picker("Media type", selection: $kind) {
                    Text("All Media").tag(nil as CaptureKind?)
                    Text("Screenshots").tag(CaptureKind.screenshot as CaptureKind?)
                    Text("Videos").tag(CaptureKind.recording as CaptureKind?)
                }
                .labelsHidden()
                TextField("Search media", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            Text(cloud ? "Shares saved on this Mac. Open a cloud copy or copy its link."
                 : "Saved screenshots and videos on this Mac. Open a capture to preview it or choose Edit.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if visible.isEmpty {
                ContentUnavailableView(search.isEmpty ? (cloud ? "No cloud shares yet" : "No saved media yet") : "No matching media",
                    systemImage: cloud ? "icloud" : "photo.on.rectangle",
                    description: Text(cloud ? "Share a screenshot or video from its editor to see its link here."
                        : "Save a screenshot or finish a recording, then refresh the gallery."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                        ForEach(visible) { item in MediaGalleryCard(item: item, cloud: cloud) }
                    }
                    .padding(2)
                }
                .scrollIndicators(.hidden)
            }
            Text("\(visible.count) \(visible.count == 1 ? "item" : "items")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding([.horizontal, .bottom])
    }
}

struct MediaGalleryCard: View {
    let item: MediaGalleryItem
    let cloud: Bool
    @State private var thumbnail: NSImage?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Label(item.kind == .recording ? "Video" : "Screenshot",
                              systemImage: item.kind == .recording ? "video" : "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120).clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(cloud ? "cloud copy of " : "")\(item.title)")
            Text(item.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                .help(item.title)
            HStack {
                Label(item.kind == .recording ? "Video" : "Screenshot",
                      systemImage: item.kind == .recording ? "video" : "photo")
                Spacer()
                Text(item.createdAt, style: .date)
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(cloud ? "Open Cloud" : "Open", action: open)
                if cloud, let url = item.cloudURL {
                    Button(copied ? "Copied" : "Copy Link") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        error = copied ? nil : "Couldn’t copy the link. Try again."
                    }
                } else {
                    Button("Edit") {
                        guard available() else { return }
                        if item.kind == .recording {
                            PreviewPanelPresenter.shared.onEditVideo?(item.editorURL)
                        } else {
                            PreviewPanelPresenter.shared.onAnnotate?(item.editorURL)
                        }
                    }
                    Button("Reveal", systemImage: "folder") {
                        guard available() else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([item.localURL])
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .controlSize(.small)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        .task(id: [item.localURL.path, String(describing: item.modifiedAt)]) {
            let source = HistoryStore.ThumbnailSource(url: item.localURL, kind: item.kind)
            let decoded = await Task.detached(priority: .utility) {
                HistoryStore.decodeThumbnail(source, maxSize: 480)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded
        }
    }

    private func available() -> Bool {
        error = item.hasLocalFile ? nil : "This file was moved or deleted. Refresh the gallery."
        return error == nil
    }

    private func open() {
        if cloud, let url = item.cloudURL {
            error = NSWorkspace.shared.open(url) ? nil : "Couldn’t open the link. Try again or copy it."
        } else if available() {
            PreviewOverlay.shared.show(url: item.localURL, automaticallyDismiss: false)
        }
    }
}
