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

    private(set) var isPresented = false
    private(set) var items: [URL] = []
    private(set) var savingItems: Set<URL> = []
    private(set) var thumbnails: [URL: NSImage] = [:]
    private var failedSaves: Set<URL> = []
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
    private var mouseMovedGlobalMonitor: Any?
    private var mouseMovedLocalMonitor: Any?
    private var panelGeneration: UInt = 0

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

    func show(url: URL, on screen: NSScreen? = nil, automaticallyDismiss: Bool = true, thumbnail: NSImage? = nil) {
        refreshSettings()
        cancelScheduledDismiss(for: url)
        if let thumbnail { thumbnails[url] = thumbnail }
        items.removeAll { $0 == url }
        items.append(url)
        while items.count > Self.maxItems {
            // Keep active transfers in the deck; evict the oldest idle card.
            guard let evicted = items.first(where: { shareIDs[$0] == nil }) else { break }
            remove(evicted)
        }
        targetScreen = screen

        isPresented = true
        refreshPresentation()

        if automaticallyDismiss { scheduleDismiss(for: url) }
        startMouseTrackingIfNeeded()
    }

    func remove(_ url: URL) {
        failedSaves.remove(url)
        cancelShare(for: url)
        shareStatuses.removeValue(forKey: url)
        if toastURL == url { toastURL = nil }
        cancelScheduledDismiss(for: url)
        items.removeAll { $0 == url }
        thumbnails.removeValue(forKey: url)
        if items.isEmpty {
            dismiss()
        } else {
            positionPanel()
        }
        discardAfterViewUpdate([url])
    }

    func dismiss() {
        isPresented = false
        failedSaves.removeAll()
        for url in Array(shareIDs.keys) { cancelShare(for: url) }
        shareStatuses.removeAll()
        toastURL = nil
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()

        stopMouseTracking()
        let dismissedPanel = panel
        panel = nil
        items.removeAll()
        thumbnails.removeAll()
        Task { @MainActor in
            dismissedPanel?.orderOut(nil)
            NotchPresenter.shared.refresh()
        }
    }

    func hide() {
        isPresented = false
        panel?.orderOut(nil)
        NotchPresenter.shared.refresh()
    }

    func toggleVisibility() {
        guard !items.isEmpty else { return }
        if isPresented { hide() }
        else {
            isPresented = true
            refreshPresentation()
        }
    }

    func refreshPresentation() {
        let isNormal = isPresented && !items.isEmpty && AppPreferences.presentationMode != .notch
        if !isNormal || panel?.screen != (targetScreen ?? ActiveDisplayResolver.screenForScreenshotCapture()) {
            teardownPanel()
        }
        guard isPresented, !items.isEmpty else { return }
        if AppPreferences.presentationMode == .notch {
            NotchPresenter.shared.show(on: targetScreen ?? ActiveDisplayResolver.screenForScreenshotCapture())
            startMouseTrackingIfNeeded()
        } else {
            // Create on the final display to preserve hit testing across mixed DPI screens.
            if panel == nil { createPanel() }
            positionPanel()
            panel?.orderFrontRegardless()
            startMouseTrackingIfNeeded()
        }
    }

    func clearAll() {
        let discardedItems = items
        dismiss()
        discardAfterViewUpdate(discardedItems)
    }

    private func discardAfterViewUpdate(_ urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for url in urls where !items.contains(url) {
                DeckStaging.discard(url)
            }
        }
    }

    func saveAll() {
        var savedCount = 0
        let snapshot = items
        for url in snapshot where shareIDs[url] == nil {
            if Self.isVideo(url) {
                save(url)
            } else if saveScreenshot(url) {
                savedCount += 1
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
                        isError: true, title: "Couldn't save recording",
                        message: error.localizedDescription,
                        systemIcon: "exclamationmark.triangle",
                        on: screen
                    )
                }
            }
            return
        }
        guard saveScreenshot(url) else { return }
        showSavedToast(count: 1)
        remove(url)
    }

    private func saveScreenshot(_ url: URL) -> Bool {
        do {
            try ScreenshotFileActions.saveCapture(from: url)
            return true
        } catch {
            showSaveFailure(for: url)
            return false
        }
    }

    func copy(_ url: URL) {
        do {
            if Self.isVideo(url) { try VideoFileActions.copyToClipboard(from: url) }
            else { try ScreenshotFileActions.copyImageToClipboard(from: url) }
            remove(url)
        } catch {
            cancelScheduledDismiss(for: url)
            ToastWindow.shared.show(isError: true, title: "Copy Failed", message: error.localizedDescription,
                systemIcon: "exclamationmark.triangle", on: targetScreen)
        }
    }

    func showSaveFailure(for url: URL) {
        failedSaves.insert(url)
        cancelScheduledDismiss(for: url)
        ToastWindow.shared.show(isError: true, title: "Couldn’t save capture", message: "The capture is still in the deck. Check the save folder in General settings and try Save again.", systemIcon: "exclamationmark.triangle", on: targetScreen)
    }

    var hasStagedItems: Bool { items.contains { DeckStaging.isStaged($0) || Self.isVideo($0) } }

    static func isVideo(_ url: URL) -> Bool {
        CaptureKind.resolved(for: url) == .recording
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
        guard shareIDs[url] == nil else { return }
        if !items.contains(url) { show(url: url, automaticallyDismiss: false) }
        cancelScheduledDismiss(for: url)
        toastURL = url
        guard CloudUploader.shared.canShare else {
            shareStatuses[url] = R2CredentialStore.shared.isConfigured
                ? .failed(headline: "Uploads are off",
                    message: "Turn on Upload when I share in Settings \u{2192} Sharing, then try again.", canRetry: true)
                : .failed(headline: "Set up cloud sharing",
                    message: "Add your cloud account in Settings \u{2192} Sharing, then try again.", canRetry: true)
            return
        }
        let savedURL = DeckStaging.retain(url)
        guard !DeckStaging.isStaged(savedURL) else {
            shareStatuses[url] = .failed(headline: "Couldn’t prepare capture",
                message: "The screenshot is still in the deck. Check available disk space and retry.", canRetry: true)
            return
        }
        let id = UUID()
        shareIDs[url] = id
        shareStatuses[url] = .working(stage: .processing, progress: nil)
        shareTasks[url] = Task {
            do {
                let uploadURL = try await RecordingDeliverable.resolve(for: savedURL)
                try Task.checkCancellation()
                let result = try await CloudUploader.shared.upload(
                    itemID: id, fileURL: uploadURL, named: ScreenshotFileActions.captureName(for: url))
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

    private func teardownPanel() {
        stopMouseTracking()
        panel?.orderOut(nil)
        panel = nil
    }

    private func startMouseTrackingIfNeeded() {
        stopMouseTracking()
        guard AppPreferences.overlayFollowsMouse else { return }

        mouseMovedGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        mouseMovedLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
    }

    private func stopMouseTracking() {
        if let monitor = mouseMovedGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMovedGlobalMonitor = nil
        }
        if let monitor = mouseMovedLocalMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMovedLocalMonitor = nil
        }
    }

    private func handleMouseMoved() {
        let generation = panelGeneration
        guard !items.isEmpty, AppPreferences.overlayFollowsMouse else { return }
        guard let newScreen = ActiveDisplayResolver.activeScreen(preferPointer: true),
              newScreen != targetScreen else { return }
        guard panelGeneration == generation else { return }

        guard AppPreferences.presentationMode != .notch || !RecordingBarPresenter.shared.isVisible else { return }
        targetScreen = newScreen
        refreshPresentation()
    }

    // MARK: - Panel Setup

    func openAnnotateEditor(for url: URL) {
        let savedURL = DeckStaging.retain(url)
        guard !DeckStaging.isStaged(savedURL) else {
            showSaveFailure(for: url)
            return
        }
        remove(url)
        PreviewPanelPresenter.shared.openEditor(for: savedURL)
    }

    func perform(_ tool: OverlayTool, for url: URL) {
        NotchPresenter.shared.captureIssue = nil
        switch tool {
        case .pin:
            let savedURL = DeckStaging.retain(url)
            guard !DeckStaging.isStaged(savedURL) else {
                showSaveFailure(for: url)
                return
            }
            PinnedScreenshotController.shared.pin(url: savedURL, on: currentScreen)
            remove(url)
        case .dismiss:
            remove(url)
        case .edit:
            openAnnotateEditor(for: url)
        case .share:
            share(url)
        case .save:
            save(url)
        case .copy:
            copy(url)
        }
    }

    private func createPanel() {
        panelGeneration &+= 1
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
        // An explicit target (the screen a capture actually happened on)
        // always wins; only a nil target (re-showing a card with no capture
        // context, e.g. from History) falls through to the same follow-mouse
        // / pinned-display resolution a fresh capture would use.
        let screen = targetScreen ?? ActiveDisplayResolver.screenForScreenshotCapture()
        guard let panel, let screen else { return }
        targetScreen = screen // remember what we actually resolved, so live mouse-tracking can diff against it

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
        guard AppPreferences.presentationMode == .normal, items.contains(url), !failedSaves.contains(url) else { return }
        guard AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay),
              (!DeckStaging.isStaged(url) || !AppPreferences.keepInDeckUntilSaved),
              shareStatuses[url] == nil else { return }
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
                PreviewCardView(overlay: overlay, url: url, thumbnail: overlay.thumbnails[url])
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
    var usesNotchActions = false
    var notchCardSize: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var hasFocus: Bool
    @FocusState private var focusedAction: String?
    @AppStorage(AppPreferences.overlayToolLayoutKey) private var layoutData = Data()
    @AppStorage(AppPreferences.overlayAlwaysShowActionsKey) private var alwaysShowActions = false

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = true

    init(overlay: PreviewOverlay, url: URL, thumbnail: NSImage? = nil, usesNotchActions: Bool = false, notchCardSize: CGSize? = nil) {
        self.overlay = overlay
        self.url = url
        self.usesNotchActions = usesNotchActions
        self.notchCardSize = notchCardSize
        _thumbnail = State(initialValue: thumbnail)
    }

    private var size: OverlayCardSize { usesNotchActions ? .medium : overlay.cardSize }
    private var cardSize: CGSize { notchCardSize ?? size.thumbnailSize }
    private var controlScale: CGFloat { size.controlScale }

    private var isVideo: Bool { PreviewOverlay.isVideo(url) }
    private var showsActions: Bool { isHovered || alwaysShowActions || hasFocus || focusedAction != nil }

    var body: some View {
        Group {
            if let status = overlay.transferStatus(for: url) {
                TransferStatusCard(status: status,
                    onCancel: { overlay.cancelShare(for: url) },
                    onRetry: { overlay.share(url) },
                    onDismiss: { overlay.dismissShareStatus(for: url) }, compactSize: cardSize,
                    onSettings: CloudUploader.shared.canShare ? nil : {
                        SettingsWindowController.shared.open(section: .sharing)
                    })
            } else if let image = thumbnail {
                ZStack {
                    // onDrag/onTapGesture live on this base image, not on the
                    // ZStack as a whole: the hover buttons below are siblings
                    // drawn on top of it, and a drag-source recognizer
                    // spanning the whole card (buttons included) beats a
                    // physical mouse's tiny mouseDown-to-mouseUp jitter to
                    // the punch, starting a native drag under the Copy/Save
                    // buttons that snaps back on release — trackpad taps
                    // don't have enough movement to trigger it, which is why
                    // this only showed up with a mouse.
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: usesNotchActions ? .fill : .fit)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .background(Color.black.opacity(0.9))
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openEditor()
                        }
                        .onDrag {
                            let retainedURL = DeckStaging.retain(url)
                            if !DeckStaging.isStaged(retainedURL), let provider = NSItemProvider(contentsOf: retainedURL) {
                                provider.suggestedName = ScreenshotFileActions.captureFileName(
                                    for: url, extension: retainedURL.pathExtension)
                                return provider
                            }
                            return NSItemProvider(object: image)
                        }

                    if isVideo && (!usesNotchActions || !showsActions) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28 * controlScale))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    if usesNotchActions {
                        notchCaption
                            .opacity(showsActions ? 0 : 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    hoverOverlay()
                        .opacity(showsActions ? 1 : 0)
                        .allowsHitTesting(showsActions)
                        .accessibilityHidden(!showsActions)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsActions)

                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: usesNotchActions ? 18 : 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: usesNotchActions ? 18 : 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(usesNotchActions ? 0 : 0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(usesNotchActions ? 0 : 0.25), radius: 10, y: 4)
                .onHover { hovering in
                    isHovered = hovering
                    if hovering { overlay.cancelScheduledDismiss(for: url) }
                    else if !hasFocus && focusedAction == nil { overlay.scheduleDismiss(for: url) }
                }
            } else {
                Button {
                    openEditor()
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
            openEditor()
            return .handled
        }
        .accessibilityElement(children: .contain)
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

    private func openEditor() {
        overlay.openAnnotateEditor(for: url)
    }

    private func loadThumbnail() async {
        guard thumbnail == nil else {
            isLoadingThumbnail = false
            return
        }
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

    private var notchCaption: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isVideo ? "Recording" : "Screenshot")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Open in editor")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)

            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
        }
    }

    private func hoverOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.28)
                .allowsHitTesting(false)
            OverlayToolArrangement(scale: controlScale) { slot in
                if let tool = (usesNotchActions ? OverlayToolLayout.standard : OverlayToolLayout(data: layoutData)).assignments[slot],
                   tool != .dismiss || !usesNotchActions || overlay.items.contains(url) {
                    Button { overlay.perform(tool, for: url) } label: {
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

}
