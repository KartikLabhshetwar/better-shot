import AppKit
import SwiftUI

struct MediaGalleryItem: Identifiable {
    let id: String
    let title: String
    let createdAt: Date
    let kind: CaptureKind
    let localURL: URL
    let editorURL: URL
    var cloudURL: URL?
    var historyID: UUID?
    var captureIDs: [UUID] = []
    var deletionURLs: [URL] = []
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
        var representedPaths: [String: Int] = [:]
        for item in edits {
            let session = item.recordingSession
            let local = FileManager.default.fileExists(atPath: item.url.path)
                ? item.url : item.sourceCapturePath.map { URL(fileURLWithPath: $0) } ?? item.url
            result.append(Self(id: item.id.uuidString,
                title: session?.displayName ?? item.fileName, createdAt: item.createdAt,
                kind: item.isVideo ? .recording : .screenshot, localURL: local,
                editorURL: local == item.url ? item.editorURL : local,
                cloudURL: cloudLink(item.cloudURL), historyID: item.id,
                deletionURLs: localFiles(for: item.url, kind: item.isVideo ? .recording : .screenshot),
                modifiedAt: item.updatedAt))
            representedPaths[item.url.standardizedFileURL.path] = result.count - 1
            if let source = item.sourceCapturePath {
                representedPaths[URL(fileURLWithPath: source).standardizedFileURL.path] = result.count - 1
                result[result.count - 1].deletionURLs += localFiles(for: URL(fileURLWithPath: source), kind: item.isVideo ? .recording : .screenshot)
            }
            if let session { representedPaths[session.screenURL.standardizedFileURL.path] = result.count - 1 }
        }
        for record in history.records {
            let raw = history.urlForRecord(record)
            let display = history.displayURLForRecord(record)
            let paths = [raw.path, display.path] + [record.beautifiedPath].compactMap { $0 }
            let files = paths.flatMap { localFiles(for: URL(fileURLWithPath: $0), kind: record.kind) }
            if let index = paths.compactMap({ representedPaths[URL(fileURLWithPath: $0).standardizedFileURL.path] }).first {
                result[index].captureIDs.append(record.id)
                result[index].deletionURLs += files
                if result[index].cloudURL == nil { result[index].cloudURL = cloudLink(record.shareURL) }
                continue
            }
            representedPaths[raw.standardizedFileURL.path] = result.count
            result.append(Self(id: record.id.uuidString, title: record.filename,
                createdAt: record.createdAt, kind: record.kind, localURL: display,
                editorURL: record.kind == .recording
                    ? ScreenshotHistoryStore.shared.editorURL(for: display)
                    : ScreenshotHistoryStore.shared.annotationEditorURL(for: display),
                cloudURL: cloudLink(record.shareURL), captureIDs: [record.id], deletionURLs: files,
                modifiedAt: try? display.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate))
        }
        for project in projects where representedPaths[project.session.screenURL.standardizedFileURL.path] == nil {
            result.append(Self(id: project.id.path, title: project.displayName,
                createdAt: project.createdAt, kind: .recording,
                localURL: project.session.deliverableURL, editorURL: project.session.directoryURL,
                cloudURL: nil, deletionURLs: [project.session.directoryURL],
                modifiedAt: try? project.session.deliverableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate))
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    static func localFiles(for url: URL, kind: CaptureKind) -> [URL] {
        if kind == .recording {
            return [RecordingSession.sessionDirectory(containing: url) ?? url]
        }
        return [url, ScreenshotHistoryStore.editDocumentURL(for: url),
                ScreenshotHistoryStore.baseImageURL(for: url), CaptureOrchestrator.baseImageURL(for: url)]
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

@MainActor
final class MediaGalleryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MediaGalleryWindowController(window: nil)

    func open(on screen: NSScreen? = nil) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MediaGallery()))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.title = "Media Gallery"
            window.setContentSize(NSSize(width: 1080, height: 740))
            window.minSize = NSSize(width: 780, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let screen = screen ?? NSScreen.main {
                window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                    y: screen.visibleFrame.midY - window.frame.height / 2))
            }
            self.window = window
            AppActivationPolicy.enter()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivationPolicy.leave()
    }
}

struct MediaGallery: View {
    var body: some View {
        MediaGalleryContent(items: MediaGalleryItem.collect(history: HistoryStore.shared,
            edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects),
            refresh: refresh)
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
    @State private var newestFirst = true
    @State private var deletionMessage: String?

    private var title: String {
        switch kind {
        case .screenshot: "Screenshots"
        case .recording: "Videos"
        case nil: "All media"
        }
    }

    var body: some View {
        let filtered = MediaGalleryItem.filtered(items, kind: kind, cloud: cloud, search: search)
        let visible = filtered.sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Label("Your media", systemImage: "photo.on.rectangle")
                    .font(.headline).padding(.top, 12)
                VStack(alignment: .leading, spacing: 4) {
                    sidebarButton("All Media", icon: "square.grid.2x2", selected: kind == nil) { kind = nil }
                    sidebarButton("Screenshots", icon: "photo", selected: kind == .screenshot) { kind = .screenshot }
                    sidebarButton("Videos", icon: "video", selected: kind == .recording) { kind = .recording }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("STORAGE").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.bottom, 8)
                    sidebarButton("On this Mac", icon: "internaldrive", selected: !cloud) { cloud = false }
                    sidebarButton("Cloud", icon: "icloud", selected: cloud) { cloud = true }
                }
                Spacer()
                Text(cloud ? "Cloud links saved on this Mac." : "Saved captures and editable projects.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(width: 184).frame(maxHeight: .infinity)
            .studioGlass(cornerRadius: 0)
            Divider()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        Text("\(title) (\(visible.count))").font(.title3.bold()).monospacedDigit()
                        Spacer(minLength: 0)
                        TextField("Search by name", text: $search)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    }
                    HStack {
                        Picker("Sort", selection: $newestFirst) {
                            Text("Newest first").tag(true)
                            Text("Oldest first").tag(false)
                        }
                        .labelsHidden().fixedSize()
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                            .buttonStyle(EditorButtonStyle())
                    }
                }
                .padding(24).background(EditorChrome.panel)
                Divider()
                if let deletionMessage {
                    HStack(alignment: .top) {
                        Text(deletionMessage + " Refresh to review remaining items; local files already moved can be restored from Trash.")
                            .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        Button("Dismiss") { self.deletionMessage = nil }
                    }
                    .padding(16)
                }
                if visible.isEmpty {
                    ContentUnavailableView(search.isEmpty ? (cloud ? "No cloud shares yet" : "No saved media yet") : "No matching media",
                        systemImage: cloud ? "icloud" : "photo.on.rectangle",
                        description: Text(search.isEmpty
                            ? (cloud ? "Share a screenshot or video from its editor to see it here." : "Save a screenshot or finish a recording, then refresh.")
                            : "Try another name or media type."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], alignment: .leading, spacing: 24) {
                            ForEach(visible) { item in
                                MediaGalleryCard(item: item, cloud: cloud, onDeleteFailure: { deletionMessage = $0 })
                            }
                        }
                        .padding(24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EditorChrome.workspace)
        }
        .tint(EditorChrome.accent)
    }

    private func sidebarButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(EditorButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MediaGalleryCard: View {
    let item: MediaGalleryItem
    let cloud: Bool
    var onDeleteFailure: (String) -> Void = { _ in }
    @State private var thumbnail: NSImage?
    @State private var error: String?
    @State private var deletionError: String?
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var deleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Image(systemName: item.kind == .recording ? "video" : "photo")
                            .font(.largeTitle).foregroundStyle(.secondary)
                    }
                    if item.kind == .recording {
                        Image(systemName: "play.circle.fill").font(.system(size: 44))
                            .symbolRenderingMode(.palette).foregroundStyle(.blue, .white)
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(cloud ? "cloud copy of " : "")\(item.title)")
            HStack(spacing: 4) {
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle).help(item.title)
                Spacer(minLength: 0)
                Button("Edit", systemImage: "pencil", action: edit)
                    .buttonStyle(EditorButtonStyle(horizontalPadding: 6))
                    .disabled(!item.hasLocalFile)
                    .help(item.hasLocalFile ? "Edit local source" : "The local source is unavailable. Restore it to edit.")
            }
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !item.hasLocalFile {
                Text("Local source unavailable for editing.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(cloud ? "Delete Cloud Share" : "Move to Trash", systemImage: "trash").foregroundStyle(.red)
                }
                .help(cloud ? "Delete cloud share" : "Move local files to Trash")
                Spacer()
                if item.hasLocalFile {
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.localURL])
                    }
                    .help("Reveal in Finder")
                }
                if let url = item.cloudURL {
                    Button(copied ? "Link copied" : "Copy Link", systemImage: copied ? "checkmark" : "link") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        error = copied ? nil : "Couldn’t copy the link. Try again."
                    }
                    .help(copied ? "Link copied" : "Copy Link")
                    Button("Open Cloud", systemImage: "arrow.up.right.square") { openCloud(url) }
                        .help("Open cloud share")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(EditorButtonStyle(horizontalPadding: 6))
            if deleting { ProgressView("Deleting…").controlSize(.small) }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let deletionError {
                Text(deletionError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { confirmingDelete = true }.controlSize(.small)
            }
        }
        .padding(14)
        .background(EditorChrome.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(EditorChrome.border, lineWidth: 0.5))
        .disabled(deleting)
        .alert(cloud ? "Delete this cloud share?" : "Move this capture to Trash?", isPresented: $confirmingDelete) {
            Button(cloud ? "Delete Cloud Share" : "Move to Trash", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cloud
                ? "The shared copy of “\(item.title)” will be permanently deleted and its link will stop working. Local files stay on your Mac."
                : "“\(item.title)” and its local source and edit files will move to Trash. Close its editor first. Existing cloud shares stay online.")
        }
        .task(id: [item.localURL.path, String(describing: item.modifiedAt)]) {
            let source = HistoryStore.ThumbnailSource(url: item.localURL, kind: item.kind)
            let decoded = await Task.detached(priority: .utility) {
                HistoryStore.decodeThumbnail(source, maxSize: 640)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded
        }
    }

    private func edit() {
        guard available() else { return }
        if item.kind == .recording { PreviewPanelPresenter.shared.onEditVideo?(item.editorURL) }
        else { PreviewPanelPresenter.shared.onAnnotate?(item.editorURL) }
    }

    private func delete() {
        deleting = true
        deletionError = nil
        Task { @MainActor in
            defer { deleting = false }
            do {
                if cloud { try await item.deleteCloud() }
                else { try item.deleteLocal() }
            } catch {
                deletionError = error.localizedDescription
                onDeleteFailure(error.localizedDescription)
            }
        }
    }

    private func available() -> Bool {
        error = item.hasLocalFile ? nil : "This file was moved or deleted. Refresh the gallery."
        return error == nil
    }

    private func openCloud(_ url: URL) {
        error = NSWorkspace.shared.open(url) ? nil : "Couldn’t open the link. Try again or copy it."
    }

    private func open() {
        if cloud, let url = item.cloudURL { openCloud(url) }
        else if available() { PreviewOverlay.shared.show(url: item.localURL, automaticallyDismiss: false) }
    }
}
