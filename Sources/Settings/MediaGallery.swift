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

    var previewURL: URL {
        RecordingSession.isSessionDirectory(editorURL)
            ? RecordingSession(directoryURL: editorURL).deliverableURL : localURL
    }

    var kindLabel: String { kind == .recording ? "Video" : "Screenshot" }

    var hasLocalFile: Bool { FileManager.default.fileExists(atPath: previewURL.path) }

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
                ?? RecordingSession.sessionDirectory(containing: item.url).map { RecordingSession(directoryURL: $0) }
            let local = session?.deliverableURL ?? (FileManager.default.fileExists(atPath: item.url.path)
                ? item.url : item.sourceCapturePath.map { URL(fileURLWithPath: $0) } ?? item.url)
            result.append(Self(id: item.id.uuidString,
                title: session?.displayName ?? item.fileName, createdAt: item.createdAt,
                kind: item.isVideo ? .recording : .screenshot, localURL: local,
                editorURL: session?.directoryURL ?? (local == item.url ? item.editorURL : local),
                cloudURL: cloudLink(item.cloudURL), historyID: item.id,
                deletionURLs: localFiles(for: item.url, kind: item.isVideo ? .recording : .screenshot),
                modifiedAt: item.updatedAt))
            representedPaths[item.url.standardizedFileURL.path] = result.count - 1
            if let source = item.sourceCapturePath {
                representedPaths[URL(fileURLWithPath: source).standardizedFileURL.path] = result.count - 1
                result[result.count - 1].deletionURLs += localFiles(for: URL(fileURLWithPath: source), kind: item.isVideo ? .recording : .screenshot)
            }
            if let session {
                for url in [session.screenURL] + VideoExportContainer.allCases.map({ session.finalURL(for: $0) }) {
                    representedPaths[url.standardizedFileURL.path] = result.count - 1
                }
            }
        }
        for record in history.records {
            let raw = history.urlForRecord(record)
            let session = RecordingSession.sessionDirectory(containing: raw).map { RecordingSession(directoryURL: $0) }
            let display = session?.deliverableURL ?? history.displayURLForRecord(record)
            let paths = [raw.path, display.path] + [record.beautifiedPath].compactMap { $0 }
            let files = paths.flatMap { localFiles(for: URL(fileURLWithPath: $0), kind: record.kind) }
            if let index = paths.compactMap({ representedPaths[URL(fileURLWithPath: $0).standardizedFileURL.path] }).first {
                result[index].captureIDs.append(record.id)
                result[index].deletionURLs += files
                if result[index].cloudURL == nil { result[index].cloudURL = cloudLink(record.shareURL) }
                continue
            }
            for path in paths { representedPaths[URL(fileURLWithPath: path).standardizedFileURL.path] = result.count }
            if let session { representedPaths[session.screenURL.standardizedFileURL.path] = result.count }
            result.append(Self(id: record.id.uuidString, title: record.displayName,
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
            let window = NSWindow(contentViewController: NSHostingController(rootView: MediaGallery { [weak self] in
                self?.window?.title = $0.title
            }))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.title = MediaGalleryCategory.all.title
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
    var onCategoryChange: (MediaGalleryCategory) -> Void = { _ in }

    var body: some View {
        MediaGalleryContent(items: MediaGalleryItem.collect(history: HistoryStore.shared,
            edits: ScreenshotHistoryStore.shared.items, projects: RecordingProjectStore.shared.projects),
            refresh: refresh, onCategoryChange: onCategoryChange)
            .task { refresh() }
    }

    private func refresh() {
        ScreenshotHistoryStore.shared.reload()
        RecordingProjectStore.shared.reload()
    }
}

enum MediaGalleryCategory: String, CaseIterable, Identifiable {
    case all, screenshots, videos, cloudAll, cloudScreenshots, cloudVideos
    var id: Self { self }
    static let local: [Self] = [.all, .screenshots, .videos]
    static let shared: [Self] = [.cloudAll, .cloudScreenshots, .cloudVideos]
    var cloud: Bool { Self.shared.contains(self) }
    var title: String {
        switch self {
        case .all, .cloudAll: "All Media"
        case .screenshots, .cloudScreenshots: "Screenshots"
        case .videos, .cloudVideos: "Videos"
        }
    }
    var icon: String {
        switch self {
        case .all: "folder"
        case .cloudAll: "icloud"
        case .screenshots, .cloudScreenshots: "photo"
        case .videos, .cloudVideos: "film"
        }
    }
    var kind: CaptureKind? {
        switch self {
        case .all, .cloudAll: nil
        case .screenshots, .cloudScreenshots: .screenshot
        case .videos, .cloudVideos: .recording
        }
    }
}

struct MediaGalleryContent: View {
    let items: [MediaGalleryItem]
    var refresh: () -> Void = {}
    var onCategoryChange: (MediaGalleryCategory) -> Void = { _ in }
    @State var listView = false
    @State var category = MediaGalleryCategory.all
    private var cloud: Bool { category.cloud }
    @State private var search = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var sortOrder = [KeyPathComparator(\MediaGalleryItem.createdAt, order: .reverse)]
    @State private var selection: String?
    @FocusState private var focusedItem: String?
    @State private var actionMessage: String?

    var body: some View {
        let filtered = MediaGalleryItem.filtered(items, kind: category.kind, cloud: cloud, search: search)
        let visible = filtered.sorted(using: sortOrder)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $category) {
                Section("On this Mac") {
                    ForEach(MediaGalleryCategory.local, content: sidebarRow)
                }
                Section("Cloud Shares") {
                    ForEach(MediaGalleryCategory.shared, content: sidebarRow)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Toggle Sidebar", systemImage: "sidebar.left") {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                    .help("Show or hide the sidebar")
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if let actionMessage {
                    HStack(alignment: .top) {
                        Text(actionMessage)
                            .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        Button("Dismiss") { self.actionMessage = nil }
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
                } else if listView {
                    Table(visible, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.title) { item in
                            card(item)
                        }
                        .width(min: 160, ideal: 200, max: .infinity)
                        TableColumn("Date Created", value: \.createdAt) { item in
                            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                                .help(item.createdAt.formatted(date: .complete, time: .standard))
                        }
                        .width(140)
                        TableColumn("Kind", value: \.kindLabel)
                            .width(76)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                    .onKeyPress(keys: [.return, .space]) { _ in
                        guard let item = visible.first(where: { $0.id == selection }) else { return .ignored }
                        actionMessage = item.open(cloud: cloud)
                        return .handled
                    }
                } else {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 16)], spacing: 24) {
                                    ForEach(visible) { item in
                                        card(item)
                                            .focusable()
                                            .focusEffectDisabled()
                                            .focused($focusedItem, equals: item.id)
                                            .id(item.id)
                                    }
                                }
                                .padding(24)
                            }
                            .onMoveCommand { direction in
                                let columns = max(1, Int((geometry.size.width - 48 + 16) / 128))
                                let index = visible.firstIndex { $0.id == selection } ?? 0
                                let offset: Int
                                switch direction {
                                case .left: offset = -1
                                case .right: offset = 1
                                case .up: offset = -columns
                                case .down: offset = columns
                                @unknown default: return
                                }
                                let target = visible[min(max(index + offset, 0), visible.count - 1)].id
                                selection = target
                                focusedItem = target
                                proxy.scrollTo(target)
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: cloud ? "icloud" : "internaldrive")
                    Text(cloud ? "Cloud Shares" : "On this Mac").fixedSize()
                    Image(systemName: "chevron.right").font(.caption2)
                    Text(category.title).lineLimit(1)
                    if let selected = visible.first(where: { $0.id == selection }) {
                        Image(systemName: "chevron.right").font(.caption2)
                        Text(selected.title).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text("\(visible.count) items").monospacedDigit().fixedSize()
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(.bar)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(category.title)
            .toolbar {
                ToolbarItem {
                    Picker("View", selection: $listView) {
                        Label("Icons", systemImage: "square.grid.2x2").tag(false)
                        Label("List", systemImage: "list.bullet").tag(true)
                    }
                    .pickerStyle(.segmented).labelStyle(.iconOnly)
                    .help("Gallery view")
                }
                ToolbarItem {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            Text("Name").tag([KeyPathComparator(\MediaGalleryItem.title)])
                            Text("Kind").tag([KeyPathComparator(\MediaGalleryItem.kindLabel)])
                            Text("Newest First").tag([KeyPathComparator(\MediaGalleryItem.createdAt, order: .reverse)])
                            Text("Oldest First").tag([KeyPathComparator(\MediaGalleryItem.createdAt)])
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort media")
                }
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                        .help("Refresh media")
                }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search media")
        }
        .navigationSplitViewStyle(.balanced)
        .scrollIndicators(.hidden)
        .tint(EditorChrome.accent)
        .onChange(of: category) { _, category in onCategoryChange(category) }
        .onChange(of: focusedItem) { if let focusedItem { selection = focusedItem } }
        .onChange(of: visible.map(\.id)) {
            if !visible.contains(where: { $0.id == selection }) { selection = nil }
        }
    }

    private func sidebarRow(_ category: MediaGalleryCategory) -> some View {
        Label {
            Text(category.title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: category.icon)
                .symbolRenderingMode(.hierarchical)
        }
        .badge(MediaGalleryItem.filtered(items, kind: category.kind, cloud: category.cloud, search: "").count)
        .tag(category)
        .accessibilityLabel("\(category.cloud ? "Cloud" : "Local") \(category.title)")
    }

    private func card(_ item: MediaGalleryItem) -> some View {
        MediaGalleryCard(item: item, cloud: cloud, listView: listView, selected: selection == item.id,
            onSelect: { selection = item.id; if !listView { focusedItem = item.id } },
            onDeleteFailure: { actionMessage = $0 + " Refresh to review remaining items; local files already moved can be restored from Trash." })
    }
}

struct MediaGalleryCard: View {
    let item: MediaGalleryItem
    let cloud: Bool
    var listView = false
    var selected = false
    var onSelect: () -> Void = {}
    var onDeleteFailure: (String) -> Void = { _ in }
    @State private var thumbnail: NSImage?
    @State private var error: String?
    @State private var deletionError: String?
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 6) {
            if listView {
                HStack(spacing: 12) {
                    artwork.frame(width: 24, height: 24)
                    Text(item.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    actionMenu
                }
                .padding(.vertical, 3)
            } else {
                artwork
                    .frame(width: 64, height: 64)
                    .padding(10)
                    .frame(height: 84)
                    .background(selected ? Color.primary.opacity(0.09) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if selected { actionMenu.padding(3) }
                    }
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(2).truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? EditorChrome.accent : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                    .frame(height: 36, alignment: .top)
            }
            if deleting { ProgressView("Deleting…").controlSize(.small) }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let deletionError {
                Text(deletionError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { confirmingDelete = true }.controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: open)
        .onTapGesture(perform: onSelect)
        .onKeyPress(.return) { open(); return .handled }
        .onKeyPress(.space) { open(); return .handled }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.hasLocalFile ? (item.kind == .recording ? "Video" : "Screenshot") : "Local source unavailable")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open", open)
        .accessibilityAction(named: "Select", onSelect)
        .help(item.title + (item.hasLocalFile ? " — Double-click to open. Right-click for actions." : " — Local source unavailable for editing."))
        .disabled(deleting)
        .alert(cloud ? "Delete this cloud share?" : "Move this capture to Trash?", isPresented: $confirmingDelete) {
            Button(cloud ? "Delete Cloud Share" : "Move to Trash", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cloud
                ? "The shared copy of “\(item.title)” will be permanently deleted and its link will stop working. Local files stay on your Mac."
                : "“\(item.title)” and its local source and edit files will move to Trash. Close its editor first. Existing cloud shares stay online.")
        }
        .task(id: [item.previewURL.path, String(describing: item.modifiedAt)]) {
            let source = HistoryStore.ThumbnailSource(url: item.previewURL, kind: item.kind)
            let decoded = await Task.detached(priority: .utility) {
                HistoryStore.decodeThumbnail(source, maxSize: 320)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            } else {
                Image(systemName: item.kind == .recording ? "video" : "photo")
                    .font(.system(size: listView ? 24 : 40)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if item.kind == .recording {
                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
                    .font(.system(size: listView ? 12 : 18)).padding(2)
            }
        }
    }

    private var actionMenu: some View {
        Menu { actions } label: {
            Label("Actions for \(item.title)", systemImage: "ellipsis.circle")
        }
        .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
        .help("Media actions")
    }

    @ViewBuilder private var actions: some View {
        Button("Open", systemImage: "arrow.up.right.square", action: open)
        Button("Edit", systemImage: "pencil", action: edit).disabled(!item.hasLocalFile)
        if item.hasLocalFile {
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.previewURL])
            }
        }
        if let url = item.cloudURL {
            Divider()
            Button(copied ? "Link Copied" : "Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
                error = copied ? nil : "Couldn’t copy the link. Try again."
            }
            Button("Open Cloud", systemImage: "icloud") { openCloud(url) }
        }
        Divider()
        Button(cloud ? "Delete Cloud Share…" : "Move to Trash…", systemImage: "trash", role: .destructive) {
            confirmingDelete = true
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
        error = item.open(cloud: cloud)
    }
}
