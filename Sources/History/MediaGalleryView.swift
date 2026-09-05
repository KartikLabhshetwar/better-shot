import AppKit
import SwiftUI

struct MediaGalleryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case all = "All Media"
        case images = "Images"
        case videos = "Videos"
        case projects = "Projects"
        var id: Self { self }
        var icon: String {
            switch self {
            case .all: "square.grid.2x2"
            case .images: "photo"
            case .videos: "film"
            case .projects: "folder"
            }
        }
    }
    @State private var selection: Section = .all

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(180)
            .listStyle(.sidebar)
        } detail: {
            if selection == .projects {
                RecordingProjectsView()
            } else {
                CaptureLibraryTab(
                    kind: selection == .images
                        ? .screenshot : selection == .videos ? .recording : nil
                )
                .id(selection)
            }
        }
        .frame(minWidth: 900, minHeight: 580)
    }
}

// MARK: - Library

struct CaptureLibraryTab: View {
    let kind: CaptureKind?
    @State private var searchText = ""
    @State private var deletingRecord: CaptureRecord?

    private enum LibraryScope {
        case local
        case cloud
    }

    @State private var scope: LibraryScope = .local
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var isConfirmingClear = false
    @State private var isConfirmingCloudClear = false
    @State private var isClearingCloud = false
    @State private var cloudError: String?

    private var records: [CaptureRecord] {
        HistoryStore.shared.records.filter {
            (kind == nil || $0.kind == kind)
                && (searchText.isEmpty || $0.filename.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var cloudItems: [ScreenshotHistoryItem] {
        ScreenshotHistoryStore.shared.items.filter {
            $0.cloudURL != nil && (kind == nil || $0.isVideo == (kind == .recording))
                && (searchText.isEmpty || $0.fileName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search media", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Search media")
                Spacer()
                Picker("Library", selection: $scope) {
                    Text("On This Mac").tag(LibraryScope.local)
                    Text("Shared Links").tag(LibraryScope.cloud)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)

            switch scope {
            case .local:
                if records.isEmpty {
                    emptyState
                } else {
                    list
                }
            case .cloud:
                if cloudItems.isEmpty {
                    cloudEmptyState
                } else {
                    cloudList
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let cloudError {
                Text(cloudError).foregroundStyle(.red).font(.callout).padding()
            }
        }
        .onAppear {
            if kind != .screenshot {
                HistoryStore.shared.syncRecordingsFromDisk()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "Remove this capture from the gallery?",
            isPresented: Binding(
                get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let record = deletingRecord {
                    thumbnails.removeValue(forKey: record.id.uuidString)
                    HistoryStore.shared.deleteRecord(record)
                }
                deletingRecord = nil
            }
            Button("Cancel", role: .cancel) { deletingRecord = nil }
        } message: {
            Text("BetterShot's library copy is removed. Files in your save folder are kept.")
        }
        .alert(
            "Remove \(records.count) \(records.count == 1 ? noun : plural) from the Library?",
            isPresented: $isConfirmingClear
        ) {
            Button("Remove", role: .destructive) {
                thumbnails.removeAll()
                records.forEach { HistoryStore.shared.deleteRecord($0) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This clears the copies BetterShot keeps. The files already in your save folder stay where they are."
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "No Media Yet" : "No Matching Media", systemImage: icon)
        } description: {
            Text("Your screenshots and recordings appear here, ready to reopen and edit.")
        } actions: {
            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
            } else {
                Button(
                    kind == .recording ? "Start Recording" : "Capture a Region",
                    action: startCapture
                )
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cloudEmptyState: some View {
        ContentUnavailableView {
            Label("No Share Links Yet", systemImage: "icloud")
        } description: {
            Text(
                R2CredentialStore.shared.isConfigured
                    ? "Share a \(noun) from the editor and its link shows up here."
                    : "Share links need your own Cloudflare R2 bucket. Set it up once under Sharing."
            )
        } actions: {
            if !R2CredentialStore.shared.isConfigured {
                Button("Set Up Sharing") { SettingsWindowController.shared.open(section: .sharing) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cloudList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(cloudItems) { item in
                    cloudRow(item)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("\(cloudItems.count) shared \(cloudItems.count == 1 ? noun : plural)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isClearingCloud {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Delete From Cloud\u{2026}", role: .destructive) {
                        isConfirmingCloudClear = true
                    }
                    .controlSize(.small)
                    .disabled(!R2CredentialStore.shared.isConfigured)
                    .help("Delete these uploads from your R2 bucket")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .alert(
            "Delete \(cloudItems.count) shared \(cloudItems.count == 1 ? noun : plural) from your cloud storage?",
            isPresented: $isConfirmingCloudClear
        ) {
            Button("Delete", role: .destructive) {
                clearCloudUploads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This deletes the uploaded copies from your R2 bucket, so their share links stop working. Local copies stay on this Mac."
            )
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(records) { record in
                        row(record)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Text("\(records.count) \(records.count == 1 ? noun : plural)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Clear \(plural.capitalized)\u{2026}", role: .destructive) {
                    isConfirmingClear = true
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func row(_ record: CaptureRecord) -> some View {
        Button {
            open(record)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail(record)
                    .overlay(alignment: .bottomTrailing) {
                        Label(
                            record.kind == .recording ? "Video" : "Image",
                            systemImage: record.kind == .recording ? "play.fill" : "photo"
                        )
                        .font(.caption2)
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                    }
                Text(record.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(
                    "\(record.pixelWidth) × \(record.pixelHeight) · \(record.createdAt.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .background(
                Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(record.filename)")
        .contextMenu {
            Button("Open in Editor") { edit(record) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    HistoryStore.shared.displayURLForRecord(record)
                ])
            }
            Divider()
            Button("Remove from Gallery…", role: .destructive) { deletingRecord = record }
        }
    }

    private func edit(_ record: CaptureRecord) {
        let url = HistoryStore.shared.displayURLForRecord(record)
        if record.kind == .screenshot {
            PreviewPanelPresenter.shared.onAnnotate?(url)
        } else {
            PreviewPanelPresenter.shared.onEditVideo?(HistoryStore.shared.urlForRecord(record))
        }
    }

    @ViewBuilder
    private func cloudRow(_ item: ScreenshotHistoryItem) -> some View {
        if let link = item.cloudURL, let shareURL = URL(string: link) {
            HStack(spacing: 14) {
                itemThumbnail(item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fileName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(link)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                    ToastWindow.shared.show(title: "Link Copied", message: link, systemIcon: "link")
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.borderless)
                .help("Copy the share link")
                .accessibilityLabel("Copy link for \(item.fileName)")

                Button {
                    NSWorkspace.shared.open(shareURL)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open the share page")
                .accessibilityLabel("Open share page for \(item.fileName)")
            }
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private func thumbnail(_ record: CaptureRecord) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let thumb = thumbnails[record.id.uuidString] {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .onAppear { loadThumbnail(for: record) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color.primary.opacity(0.04))
        .onDisappear { thumbnails.removeValue(forKey: record.id.uuidString) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var noun: String {
        kind == nil ? "capture" : kind == .screenshot ? "screenshot" : "recording"
    }
    private var plural: String { noun + "s" }
    private var icon: String { kind == .screenshot ? "photo.on.rectangle.angled" : "film" }

    private func open(_ record: CaptureRecord) {
        if record.kind == .screenshot {
            PreviewPanelPresenter.shared.onAnnotate?(
                HistoryStore.shared.displayURLForRecord(record))
        } else {
            PreviewPanelPresenter.shared.onEditVideo?(HistoryStore.shared.urlForRecord(record))
        }
    }

    private func clearCloudUploads() {
        let credentials = R2CredentialStore.shared.snapshot()
        let items = cloudItems
        cloudError = nil
        isClearingCloud = true
        Task {
            var failures = 0
            for item in items {
                guard let link = item.cloudURL, let slug = R2Uploader.slug(fromShareLink: link)
                else {
                    continue
                }
                do {
                    try await R2Uploader.deleteShare(slug: slug, credentials: credentials)
                    ScreenshotHistoryStore.shared.clearCloudURL(for: item.url)
                } catch {
                    failures += 1
                }
            }
            isClearingCloud = false
            if failures > 0 {
                cloudError =
                    "\(failures) uploads could not be deleted. Check Sharing settings and try again."
                ToastWindow.shared.show(
                    title: "Cloud Delete Failed",
                    message: "\(failures) of \(items.count) uploads could not be deleted.",
                    systemIcon: "exclamationmark.icloud"
                )
            } else {
                ToastWindow.shared.show(
                    title: "Cloud \(plural.capitalized) Deleted",
                    message: "The share links no longer work.",
                    systemIcon: "icloud.slash"
                )
            }
        }
    }

    private func startCapture() {
        let screen = NSApp.keyWindow?.screen
        SettingsWindowController.shared.close()
        if kind != .recording {
            Task { await CaptureOrchestrator.shared.performCapture(.region, on: screen) }
        } else {
            RecordingBarPresenter.shared.showPicker()
        }
    }

    private func loadThumbnail(for record: CaptureRecord) {
        let source = HistoryStore.shared.thumbnailSource(for: record)
        Task.detached {
            let thumb = HistoryStore.decodeThumbnail(source, maxSize: 480)
            await MainActor.run {
                if let thumb {
                    thumbnails[record.id.uuidString] = thumb
                }
            }
        }
    }

    @ViewBuilder
    private func itemThumbnail(_ item: ScreenshotHistoryItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let thumb = thumbnails[item.id.uuidString] {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .onAppear { loadItemThumbnail(for: item) }
            }
        }
        .frame(width: 72, height: 48)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func loadItemThumbnail(for item: ScreenshotHistoryItem) {
        let source = HistoryStore.ThumbnailSource(
            url: item.url,
            kind: item.isVideo ? .recording : .screenshot
        )
        Task.detached {
            let thumb = HistoryStore.decodeThumbnail(source, maxSize: 96)
            await MainActor.run {
                if let thumb {
                    thumbnails[item.id.uuidString] = thumb
                }
            }
        }
    }
}
