//
//  RecordingProjectsView.swift
//  BetterShot
//
//  Every screen recording BetterShot has kept, as reopenable projects. This
//  is the way back into an edit - History lists captures and previews them,
//  this lists projects and opens them in Studio.
//

import AppKit
import SwiftUI

struct RecordingProjectsView: View {
    private enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyOpened
        case newest
        case name
        case largest

        var id: Self { self }

        var title: String {
            switch self {
            case .recentlyOpened: "Recently Opened"
            case .newest: "Date Recorded"
            case .name: "Name"
            case .largest: "Size on Disk"
            }
        }
    }

    @State private var store = RecordingProjectStore.shared
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.recentlyOpened
    @State private var renamingProject: RecordingProjectSummary?
    @State private var renameText = ""
    @State private var deletingProject: RecordingProjectSummary?

    private let columns = [GridItem(.adaptive(minimum: 232, maximum: 320), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 480)
        .alert("Rename Project", isPresented: renameBinding) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renamingProject {
                    store.rename(renamingProject, to: renameText)
                }
                renamingProject = nil
            }
            Button("Cancel", role: .cancel) { renamingProject = nil }
        }
        .alert(
            "Delete “\(deletingProject?.displayName ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let deletingProject {
                    store.delete(deletingProject)
                }
                deletingProject = nil
            }
            Button("Cancel", role: .cancel) { deletingProject = nil }
        } message: {
            Text("The recording, its camera and audio tracks, and every edit are removed from your Mac. This can't be undone.")
        }
        .onAppear {
            store.reload()
        }
    }

    /// The window is hosted by AppKit, so the chrome lives in the view rather
    /// than in a scene toolbar - the same shape History uses.
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording Projects")
                    .font(.title3.weight(.semibold))
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Menu {
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort projects")

            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "No Recording Projects",
                    systemImage: "film.stack",
                    description: Text("Screen recordings you make are kept here so you can reopen and keep editing them.")
                )
            } else if visibleProjects.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleProjects) { project in
                            RecordingProjectCard(project: project) {
                                open(project)
                            }
                            .contextMenu {
                                Button("Open in Studio") { open(project) }
                                Button("Rename…") { beginRename(project) }
                                Button("Reveal in Finder") { store.reveal(project) }
                                Divider()
                                Button("Delete Project…", role: .destructive) {
                                    deletingProject = project
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleProjects: [RecordingProjectSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty
            ? store.projects
            : store.projects.filter { $0.displayName.localizedCaseInsensitiveContains(query) }

        switch sortOrder {
        case .recentlyOpened:
            return matched.sorted { $0.lastActivityAt > $1.lastActivityAt }
        case .newest:
            return matched.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return matched.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .largest:
            return matched.sorted { $0.sizeOnDisk > $1.sizeOnDisk }
        }
    }

    private var summaryLine: String {
        let count = store.projects.count
        guard count > 0 else { return "No projects yet" }
        let size = RecordingProjectFormatting.fileSize(store.totalSizeOnDisk)
        return "\(count) project\(count == 1 ? "" : "s") · \(size)"
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deletingProject != nil },
            set: { if !$0 { deletingProject = nil } }
        )
    }

    private func beginRename(_ project: RecordingProjectSummary) {
        renameText = project.displayName
        renamingProject = project
    }

    private func open(_ project: RecordingProjectSummary) {
        RecordingProjectOpener.shared.open(project.session)
    }
}

private struct RecordingProjectCard: View {
    let project: RecordingProjectSummary
    let onOpen: () -> Void

    @State private var poster: NSImage?
    @State private var isHovering = false

    // Outer radius sits one step above the poster's so the nesting reads
    // correctly at the corners.
    private let outerRadius: CGFloat = 14
    private let posterRadius: CGFloat = 8
    private let posterInset: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            posterView
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: posterRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if project.duration > 0 {
                        Text(RecordingProjectFormatting.duration(project.duration))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if project.hasUnsavedDraft {
                        Text("Unsaved")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
        .padding(posterInset)
        .background(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .stroke(Color.primary.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        // Single click would fight the context menu and selection; opening on
        // double click matches how Finder and Screen Studio behave.
        .onTapGesture(count: 2, perform: onOpen)
        .task {
            poster = await RecordingProjectStore.poster(for: project.session)
        }
        .help("Double-click to open in Studio")
    }

    @ViewBuilder
    private var posterView: some View {
        if let poster {
            Image(nsImage: poster)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(Color.black.opacity(0.35))
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var metaLine: String {
        var parts = [RecordingProjectFormatting.relativeDate(project.createdAt)]
        if project.pixelSize.width > 0 {
            parts.append("\(Int(project.pixelSize.width))×\(Int(project.pixelSize.height))")
        }
        parts.append(RecordingProjectFormatting.fileSize(project.sizeOnDisk))
        return parts.joined(separator: " · ")
    }
}

enum RecordingProjectFormatting {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        // Anything older than a week reads better as a real date.
        if Date().timeIntervalSince(date) > 7 * 24 * 60 * 60 {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
