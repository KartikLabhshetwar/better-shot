import SwiftUI

/// Dashboard shown first in Settings: quick captures, recent captures, and setup status.
struct SettingsHomeTab: View {
    var navigate: (SettingsSection) -> Void = { _ in }
    @State private var permissions = OnboardingPermissions()

    private static let captures: [(action: ShortcutService.Action, title: String, symbol: String)] = [
        (.region, "Region", "rectangle.dashed"),
        (.fullscreen, "Screen", "desktopcomputer"),
        (.window, "Window", "macwindow"),
        (.scrollCapture, "Scrolling", "rectangle.expand.vertical"),
        (.recordingOptions, "Record", "record.circle"),
        (.ocr, "Text", "doc.text.viewfinder"),
    ]

    private static let setupPermissions: [OnboardingPermission] = [.screen, .accessibility, .microphone, .camera]

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeader(title: "Capture") {
                    SettingsPageLink(title: "Shortcuts") { navigate(.shortcuts) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(Self.captures, id: \.action) { item in
                        CaptureTile(title: item.title, symbol: item.symbol, action: item.action) { run(item.action) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeader(title: "Recent") {
                    SettingsPageLink(title: "Media Gallery", action: openGallery)
                }
                RecentCaptures()
            }
            SettingsGroup("Setup") {
                ForEach(Array(Self.setupPermissions.enumerated()), id: \.element) { index, permission in
                    if index > 0 { SettingsDivider() }
                    SettingsPermissionRow(permission: permission, permissions: permissions)
                }
            }
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func run(_ action: ShortcutService.Action) {
        let screen = ActiveDisplayResolver.screenForScreenshotCapture()
        SettingsWindowController.shared.close()
        if action == .recordingOptions {
            RecordingBarPresenter.shared.showPicker(recordingOptions: true)
            return
        }
        Task { await CaptureOrchestrator.shared.performCapture(action, on: screen) }
    }

    private func openGallery() {
        MediaGalleryWindowController.shared.open()
    }
}

private struct CaptureTile: View {
    let title: String
    let symbol: String
    let action: ShortcutService.Action
    let perform: () -> Void
    @State private var isHovered = false

    private var shortcut: ShortcutService.Shortcut? {
        ShortcutService.shared.effectiveShortcut(for: action)
    }

    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(shortcut?.displayString ?? "No shortcut")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(isHovered ? 0.05 : 0), in: .rect(cornerRadius: 12, style: .continuous))
            .background(Color.settingsCardFill, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.settingsCardStroke))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(ShortcutService.shared.help(title, for: action))
    }
}

private struct RecentCaptures: View {
    @State private var error: String?

    private var records: [CaptureRecord] { Array(HistoryStore.shared.records.prefix(5)) }

    var body: some View {
        if records.isEmpty {
            SettingsCard(padding: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.tertiary)
                    Text("No captures yet").font(.headline)
                    Text("Screenshots and recordings you take appear here.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SettingsCard(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Divider().padding(.leading, 64) }
                            RecentCaptureRow(record: record) { open(record) }
                        }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func open(_ record: CaptureRecord) {
        let url = HistoryStore.shared.displayURLForRecord(record)
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "“\(record.displayName)” was moved or deleted. Open the Media Gallery to find your other captures."
            return
        }
        error = nil
        PreviewOverlay.shared.show(url: url, automaticallyDismiss: false)
    }
}

private struct RecentCaptureRow: View {
    let record: CaptureRecord
    let open: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Image(systemName: record.kind == .recording ? "video" : "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayName).lineLimit(1).truncationMode(.middle)
                    Text(record.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: record.kind == .recording ? "video" : "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("Open \(record.displayName)")
        .task(id: record.id) {
            let source = HistoryStore.shared.thumbnailSource(for: record)
            let decoded = await Task.detached(priority: .utility) {
                HistoryStore.decodeThumbnail(source, maxSize: 96)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded
        }
    }
}
