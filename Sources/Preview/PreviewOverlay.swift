import AppKit
import SwiftUI

/// Shows a floating deck of preview cards after capture. Uses a borderless NSPanel.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    static let maxItems = 5
    private static let cardSpacing: CGFloat = 10
    private static let clearAllHeight: CGFloat = 26

    private(set) var items: [URL] = []
    private(set) var savingItems: Set<URL> = []
    private var panel: NSPanel?
    private var dismissTasks: [URL: Task<Void, Never>] = [:]
    private var targetScreen: NSScreen?
    private(set) var shareStatuses: [URL: TransferStatus] = [:]
    private var shareIDs: [URL: UUID] = [:]
    private var shareTasks: [URL: Task<Void, Never>] = [:]
    var toastURL: URL?
    private(set) var cardSize = AppPreferences.overlayCardSize
    private(set) var edgeMargin = AppPreferences.overlayEdgeMargin
    private(set) var position = AppPreferences.overlayPosition

    var currentScreen: NSScreen? { targetScreen }

    var panelSize: CGSize {
        let size = cardSize
        let base = size.panelSize(margin: edgeMargin)
        let extraCards = CGFloat(max(items.count - 1, 0))
        let height = base.height
            + extraCards * (size.thumbnailSize.height + Self.cardSpacing)
            + (items.count > 1 ? Self.clearAllHeight : 0)
        return CGSize(width: base.width, height: height)
    }

    private init() {}

    func show(url: URL, on screen: NSScreen? = nil, automaticallyDismiss: Bool = true) {
        refreshSettings()
        cancelScheduledDismiss(for: url)
        items.removeAll { $0 == url }
        items.append(url)
        while items.count > Self.maxItems {
            // Keep active transfers in the deck; evict the oldest idle card.
            guard let evicted = items.first(where: { shareIDs[$0] == nil }) else { break }
            remove(evicted)
        }
        targetScreen = screen

        if panel == nil {
            createPanel()
        }

        positionPanel()
        panel?.orderFrontRegardless()

        if automaticallyDismiss { scheduleDismiss(for: url) }
    }

    func remove(_ url: URL) {
        cancelShare(for: url)
        shareStatuses.removeValue(forKey: url)
        if toastURL == url { toastURL = nil }
        cancelScheduledDismiss(for: url)
        DeckStaging.discard(url)
        items.removeAll { $0 == url }
        if items.isEmpty {
            dismiss()
        } else {
            positionPanel()
        }
    }

    func dismiss() {
        for url in Array(shareIDs.keys) { cancelShare(for: url) }
        shareStatuses.removeAll()
        toastURL = nil
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()

        panel?.orderOut(nil)
        panel = nil
        items.removeAll()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggleVisibility() {
        guard !items.isEmpty else { return }
        if panel?.isVisible == true { hide() }
        else {
            if panel == nil { createPanel() }
            positionPanel()
            panel?.orderFrontRegardless()
        }
    }

    func clearAll() {
        items.forEach(DeckStaging.discard)
        dismiss()
    }

    func saveAll() {
        var savedCount = 0
        let snapshot = items
        for url in snapshot where shareIDs[url] == nil {
            if Self.isVideo(url) {
                save(url)
            } else if DeckStaging.isStaged(url) {
                guard !DeckStaging.isStaged(DeckStaging.promote(url)) else {
                    showSaveFailure(for: url)
                    continue
                }
                savedCount += 1
                remove(url)
            } else {
                remove(url)
            }
        }
        showSavedToast(count: savedCount)
    }

    func save(_ url: URL) {
        guard !savingItems.contains(url) else { return }
        if Self.isVideo(url) {
            savingItems.insert(url)
            cancelScheduledDismiss(for: url)
            let screen = targetScreen
            Task {
                defer { savingItems.remove(url) }
                do {
                    _ = try await RecordingDeliverable.saveToDefaultLocation(for: url)
                    guard items.contains(url) else { return }
                    remove(url)
                    ToastWindow.shared.show(message: "Recording saved!", on: screen)
                } catch {
                    ToastWindow.shared.show(
                        title: "Couldn't save recording",
                        message: error.localizedDescription,
                        systemIcon: "exclamationmark.triangle",
                        on: screen
                    )
                }
            }
            return
        }
        if DeckStaging.isStaged(url) {
            guard !DeckStaging.isStaged(DeckStaging.promote(url)) else {
                showSaveFailure(for: url)
                return
            }
            showSavedToast(count: 1)
        }
        remove(url)
    }

    fileprivate func showSaveFailure(for url: URL) {
        cancelScheduledDismiss(for: url)
        ToastWindow.shared.show(title: "Couldn’t save capture", message: "The capture is still in the deck. Check the save folder in General settings and try Save again.", systemIcon: "exclamationmark.triangle", on: targetScreen)
    }

    var hasStagedItems: Bool { items.contains { DeckStaging.isStaged($0) || Self.isVideo($0) } }

    static func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "mp4"
    }

    private func showSavedToast(count: Int) {
        guard count > 0 else { return }
        ToastWindow.shared.show(
            message: count == 1 ? "Screenshot saved!" : "\(count) screenshots saved!",
            icon: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage,
            on: targetScreen
        )
    }

    func cancelScheduledDismiss(for url: URL) {
        dismissTasks.removeValue(forKey: url)?.cancel()
    }

    func refreshSettings() {
        cardSize = AppPreferences.overlayCardSize
        edgeMargin = AppPreferences.overlayEdgeMargin
        position = AppPreferences.overlayPosition
        positionPanel()
        for url in items {
            cancelScheduledDismiss(for: url)
            scheduleDismiss(for: url)
        }
    }

    func transferStatus(for url: URL) -> TransferStatus? {
        if let id = shareIDs[url], let progress = CloudUploader.shared.uploadProgress[id] {
            return .working(stage: .uploading, progress: progress)
        }
        return shareStatuses[url]
    }

    func share(_ url: URL) {
        guard items.contains(url), shareIDs[url] == nil else { return }
        cancelScheduledDismiss(for: url)
        toastURL = url
        guard CloudUploader.shared.isConfigured else {
            shareStatuses[url] = .failed(headline: "Set up cloud sharing",
                message: "Add your cloud account in Settings → Sharing, then try again.", canRetry: true)
            return
        }
        let savedURL = DeckStaging.promote(url)
        guard !DeckStaging.isStaged(savedURL) else {
            shareStatuses[url] = .failed(headline: "Couldn’t save capture",
                message: "Check the save folder in General settings, then retry.", canRetry: true)
            return
        }
        let id = UUID()
        shareIDs[url] = id
        shareStatuses[url] = .working(stage: .processing, progress: nil)
        shareTasks[url] = Task {
            do {
                let uploadURL = try await RecordingDeliverable.resolve(for: savedURL)
                try Task.checkCancellation()
                let result = try await CloudUploader.shared.upload(itemID: id, fileURL: uploadURL)
                // Persist a completed upload even if the card is dismissed during the metadata write.
                if let session = RecordingDeliverable.session(for: savedURL) {
                    await ScreenshotHistoryStore.shared.importRecordingSession(session)
                    ScreenshotHistoryStore.shared.setCloudURL(forSession: session, cloudURL: result.url)
                } else {
                    await ScreenshotHistoryStore.shared.setCloudURL(for: savedURL, cloudURL: result.url)
                }
                try Task.checkCancellation()
                guard shareIDs[url] == id, let link = URL(string: result.url) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url, forType: .string)
                shareStatuses[url] = .linkReady(url: link)
            } catch {
                guard shareIDs[url] == id else { return }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    shareStatuses.removeValue(forKey: url)
                } else {
                    shareStatuses[url] = .failed(headline: "Upload failed",
                        message: error.localizedDescription, canRetry: true)
                }
            }
            guard shareIDs[url] == id else { return }
            shareIDs.removeValue(forKey: url)
            shareTasks.removeValue(forKey: url)
            scheduleDismiss(for: url)
        }
    }

    func dismissShareStatus(for url: URL) {
        cancelShare(for: url)
        shareStatuses.removeValue(forKey: url)
        scheduleDismiss(for: url)
    }

    func cancelShare(for url: URL) {
        shareTasks.removeValue(forKey: url)?.cancel()
        if let id = shareIDs.removeValue(forKey: url) {
            CloudUploader.shared.cancelUpload(for: id)
            shareStatuses.removeValue(forKey: url)
        }
        if toastURL == url { toastURL = nil }
        scheduleDismiss(for: url)
    }

    // MARK: - Panel Setup

    func openAnnotateEditor(for url: URL) {
        let savedURL = DeckStaging.promote(url)
        remove(url)
        PreviewPanelPresenter.shared.openEditor(for: savedURL)
    }

    private func createPanel() {
        let panel = PreviewDeckPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 130),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("BetterShot.CaptureOverlay")
        panel.title = "Capture overlay"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: PreviewDeckView(overlay: self))
        panel.contentView = hostingView

        self.panel = panel
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let panel, let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panelSize

        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottomRight:
            x = screenFrame.maxX - panelSize.width
            y = screenFrame.minY
        case .bottomLeft:
            x = screenFrame.minX
            y = screenFrame.minY
        }

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
    }

    func scheduleDismiss(for url: URL) {
        cancelScheduledDismiss(for: url)
        guard items.contains(url) else { return }
        guard AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay),
              !DeckStaging.isStaged(url), shareStatuses[url] == nil else { return }
        dismissTasks[url] = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            remove(url)
        }
    }
}

private final class PreviewDeckPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Preview Deck SwiftUI View

struct PreviewDeckView: View {
    let overlay: PreviewOverlay

    private var pinnedLeft: Bool { overlay.position == .bottomLeft }

    var body: some View {
        VStack(alignment: pinnedLeft ? .leading : .trailing, spacing: 10) {
            if overlay.items.count > 1 {
                HStack(spacing: 6) {
                    if overlay.hasStagedItems {
                        deckButton("Save All") { overlay.saveAll() }
                    }
                    deckButton("Clear All") { overlay.clearAll() }
                }
            }
            ForEach(overlay.items, id: \.self) { url in
                PreviewCardView(overlay: overlay, url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pinnedLeft ? .bottomLeading : .bottomTrailing)
        .padding(pinnedLeft ? [.leading, .bottom] : [.trailing, .bottom], overlay.edgeMargin)
        .frame(width: overlay.panelSize.width, height: overlay.panelSize.height)
        .background {
            if let url = overlay.toastURL {
                TransferToast(status: overlay.transferStatus(for: url),
                    onCancel: { overlay.cancelShare(for: url) },
                    onRetry: { overlay.share(url) }, onDismiss: { overlay.toastURL = nil })
            }
        }
    }

    private func deckButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .buttonStyle(.plain)
    }
}

// MARK: - Preview Card SwiftUI View

struct PreviewCardView: View {
    let overlay: PreviewOverlay
    let url: URL
    @State private var isHovered = false
    @FocusState private var hasFocus: Bool
    @FocusState private var focusedAction: String?
    @AppStorage(AppPreferences.overlayToolLayoutKey) private var layoutData = Data()
    @AppStorage(AppPreferences.overlayAlwaysShowActionsKey) private var alwaysShowActions = false

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = true

    init(overlay: PreviewOverlay, url: URL, thumbnail: NSImage? = nil) {
        self.overlay = overlay
        self.url = url
        _thumbnail = State(initialValue: thumbnail)
    }

    private var size: OverlayCardSize { overlay.cardSize }
    private var cardSize: CGSize { size.thumbnailSize }
    private var controlScale: CGFloat { size.controlScale }

    private var isVideo: Bool { PreviewOverlay.isVideo(url) }

    var body: some View {
        Group {
            if let status = overlay.transferStatus(for: url) {
                TransferStatusCard(status: status,
                    onCancel: { overlay.cancelShare(for: url) },
                    onRetry: { overlay.share(url) },
                    onDismiss: { overlay.dismissShareStatus(for: url) }, compactSize: cardSize,
                    onSettings: CloudUploader.shared.isConfigured ? nil : {
                        SettingsWindowController.shared.open(section: .sharing)
                    })
            } else if let image = thumbnail {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()

                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28 * controlScale))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }

                    hoverOverlay()
                        .opacity(isHovered || alwaysShowActions || hasFocus || focusedAction != nil ? 1 : 0)
                        .allowsHitTesting(isHovered || alwaysShowActions || hasFocus || focusedAction != nil)

                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .onHover { hovering in
                    isHovered = hovering
                    if hovering { overlay.cancelScheduledDismiss(for: url) }
                    else if !hasFocus && focusedAction == nil { overlay.scheduleDismiss(for: url) }
                }
                .onTapGesture {
                    overlay.openAnnotateEditor(for: url)
                }
                .onDrag {
                    DeckStaging.promote(url)
                    if let provider = NSItemProvider(contentsOf: url) {
                        provider.suggestedName = url.lastPathComponent
                        return provider
                    }
                    return NSItemProvider(object: image)
                }
            } else {
                Button {
                    overlay.openAnnotateEditor(for: url)
                } label: {
                    VStack(spacing: 8) {
                        if isLoadingThumbnail {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: isVideo ? "play.rectangle" : "photo")
                                .font(.title2)
                        }
                        Text(isLoadingThumbnail ? "Loading preview…" : "Open \(isVideo ? "recording" : "image")")
                            .font(.caption)
                    }
                    .frame(width: cardSize.width, height: cardSize.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVideo ? "Open recording editor" : "Open image editor")
            }
        }
        .focusable()
        .focused($hasFocus)
        .onChange(of: hasFocus) {
            if hasFocus { overlay.cancelScheduledDismiss(for: url) }
            else if !isHovered { overlay.scheduleDismiss(for: url) }
        }
        .onChange(of: focusedAction) {
            if focusedAction != nil { overlay.cancelScheduledDismiss(for: url) }
            else if !isHovered && !hasFocus { overlay.scheduleDismiss(for: url) }
        }
        .onKeyPress(.return) {
            guard overlay.transferStatus(for: url) == nil else { return .ignored }
            overlay.openAnnotateEditor(for: url)
            return .handled
        }
        .accessibilityLabel(isVideo ? "Recording preview" : "Screenshot preview")
        .task(id: url) { await loadThumbnail() }
        .disabled(overlay.savingItems.contains(url))
        .allowsHitTesting(!overlay.savingItems.contains(url))
        .overlay {
            if overlay.savingItems.contains(url) {
                ProgressView("Saving…")
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func loadThumbnail() async {
        // Both kinds go through the history store's decoder: it samples a bounded
        // thumbnail rather than the full bitmap, and it is nonisolated, so the
        // decode runs off the main actor instead of on the tick that just
        // finished rendering the capture.
        let source = HistoryStore.ThumbnailSource(
            url: url,
            kind: PreviewOverlay.isVideo(url) ? .recording : .screenshot
        )
        let sampleSize = max(cardSize.width, cardSize.height) * 2 // retina headroom at the current card size
        isLoadingThumbnail = true
        let task = Task.detached(priority: .userInitiated) {
            HistoryStore.decodeThumbnail(source, maxSize: sampleSize)
        }
        let image = await task.value
        guard !Task.isCancelled else { return }
        thumbnail = image
        isLoadingThumbnail = false
    }

    private func hoverOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { overlay.openAnnotateEditor(for: url) }
            OverlayToolArrangement(scale: controlScale) { slot in
                if let tool = OverlayToolLayout(data: layoutData).assignments[slot] {
                    Button { perform(tool) } label: {
                        OverlayToolLabel(tool: tool, slot: slot, scale: controlScale)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: tool.rawValue)
                    .accessibilityLabel(tool.title)
                    .help(tool.title)
                }
            }
        }
    }

    private func perform(_ tool: OverlayTool) {
        switch tool {
        case .pin:
            let savedURL = DeckStaging.promote(url)
            guard !DeckStaging.isStaged(savedURL) else {
                overlay.showSaveFailure(for: url)
                return
            }
            PinnedScreenshotController.shared.pin(url: savedURL, on: overlay.currentScreen)
            overlay.remove(url)
        case .dismiss:
            overlay.remove(url)
        case .edit:
            overlay.openAnnotateEditor(for: url)
        case .share:
            overlay.share(url)
        case .save:
            overlay.save(url)
        case .copy:
            do {
                if isVideo { try VideoFileActions.copyToClipboard(from: url) }
                else { try ScreenshotFileActions.copyImageToClipboard(from: url) }
                overlay.remove(url)
            } catch {
                overlay.cancelScheduledDismiss(for: url)
                ToastWindow.shared.show(title: "Copy Failed", message: error.localizedDescription,
                    systemIcon: "exclamationmark.triangle", on: overlay.currentScreen)
            }
        }
    }
}
