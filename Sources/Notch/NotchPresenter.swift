import AppKit
import DynamicNotchKit
import SwiftUI

/// One presentation surface; capture, staging and transfers keep their existing owners.
@MainActor
@Observable
final class NotchPresenter {
    static let shared = NotchPresenter()

    private(set) var expanded = true
    private(set) var captureSuspended = false
    var countdown: Int?
    @ObservationIgnored private var enabledSession = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var isHovering = false
    @ObservationIgnored var menuTrackingCount = 0
    var ocrText: String?
    var colorHex: String?
    var captureIssue: (title: String, message: String)?
    var transfers: [UUID: TransferStatusCard] = [:]
    var transferOrder: [UUID] = []
    var script: TeleprompterOverlayModel?
    private(set) var screen: NSScreen?
    @ObservationIgnored private var notch: DynamicNotch<NotchContent, NotchCompactLeading, NotchCompactTrailing>?

    var window: NSWindow? { notch?.windowController?.window }
    var contentFrame: CGRect? {
        guard let window, let notch else { return nil }
        let rect = notch.contentFrame
        return CGRect(x: window.frame.minX + rect.minX, y: window.frame.maxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }
    var isVisible: Bool { window?.isVisible == true }
    var hasContent: Bool {
        RecordingBarPresenter.shared.isVisible || PreviewOverlay.shared.isPresented ||
            captureIssue != nil || !transfers.isEmpty || script != nil || ocrText != nil || colorHex != nil
    }

    private init() { observeHoldIndicator() }

    private func observeHoldIndicator() {
        withObservationTracking {
            let active = NotchVoiceCapture.shared.holdIndicatorActive
            notch?.outlineColor = active ? .green : .clear
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeHoldIndicator() }
        }
    }

    func show(on screen: NSScreen? = nil) {
        if AppPreferences.presentationMode == .notch { enabledSession = true }
        self.screen = screen ?? self.screen ?? ActiveDisplayResolver.screenForScreenshotCapture()
        expanded = true
        refresh(collapseIfEmpty: false)
    }

    func refresh(collapseIfEmpty: Bool = true) {
        guard AppPreferences.presentationMode == .notch, (!captureSuspended || countdown != nil), hasContent || enabledSession else {
            notch?.dismissImmediately()
            return
        }
        if collapseIfEmpty && !hasContent && countdown == nil { expanded = false }
        guard let screen = NSScreen.screens.first(where: { $0 == self.screen }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        self.screen = screen
        if notch == nil {
            let notch = DynamicNotch(hoverBehavior: [], style: .auto) {
                NotchContent()
            } compactLeading: {
                NotchCompactLeading()
            } compactTrailing: {
                NotchCompactTrailing()
            }
            notch.onHoverChanged = { [weak self] in self?.updateHoverState($0) }
            notch.configureWindow = { panel in
                panel.identifier = NSUserInterfaceItemIdentifier("BetterShot.Notch")
                panel.title = "BetterShot notch"
                panel.level = .statusBar
                panel.appearance = NSAppearance(named: .darkAqua)
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                PreviewWindowCaptureExclusion.shared.register(window: panel)
            }
            self.notch = notch
        }
        notch?.outlineColor = NotchVoiceCapture.shared.holdIndicatorActive ? .green : .clear
        notch?.presentImmediately(on: screen, expanded: expanded, animated: true)
    }

    func collapse() {
        hoverTask?.cancel()
        guard expanded else { return }
        expanded = false
        refresh()
    }

    func suspendForCapture() {
        captureIssue = nil
        hoverTask?.cancel()
        isHovering = false
        menuTrackingCount = 0
        captureSuspended = true
        notch?.dismissImmediately()
    }

    func resumeAfterCapture() {
        captureSuspended = false
        refresh()
    }

    func refreshMode() {
        NotchShelfStore.shared.refreshMonitoring()
        NotchVoiceCapture.shared.refreshGesture()
        ToastWindow.shared.dismiss(animated: false)
        hoverTask?.cancel()
        isHovering = false
        menuTrackingCount = 0
        enabledSession = AppPreferences.presentationMode == .notch
        notch?.dismissImmediately()
        RecordingBarPresenter.shared.refreshPresentation()
        PreviewOverlay.shared.refreshSettings()
        PreviewOverlay.shared.refreshPresentation()
        TeleprompterOverlayPresenter.shared.refreshPresentation()
        refresh()
    }

    func updateHoverState(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        guard AppPreferences.presentationMode == .notch, !captureSuspended, !NotchVoiceCapture.shared.drawingSession else { return }
        if hovering {
            if !expanded { show() }
            return
        }
        // Adapted from ContentView.handleHover in TheBoredTeam/boring.notch
        // (99c26e418323d10e48886469fc9bd83900194bec), GPL-3.0.
        // Keep BetterShot's native menu/sheet and capture-suspension guards.
        // See Resources/Licenses/NOTICE.md and BoringNotch.txt.
        // Measure from the pointer event, not from when SwiftUI layout lets the task start.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(100))
        hoverTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self,
                  !self.isHovering, self.canCollapseAfterHover else { return }
            self.collapse()
        }
    }

    private var canCollapseAfterHover: Bool {
        let bar = RecordingBarPresenter.shared
        return countdown == nil && !bar.showsRecordingOptions && bar.recordingConfirmation == nil
            && menuTrackingCount == 0 && NSApp.modalWindow == nil && window?.attachedSheet == nil
            && !(window?.childWindows?.contains(where: \.isVisible) ?? false)
    }

    func resumeHoverDismissal() {
        if !isHovering { updateHoverState(false) }
    }

    func runCountdown(seconds: Int, on screen: NSScreen?) async {
        guard seconds > 0 else { return }
        countdown = seconds
        show(on: screen)
        for value in stride(from: seconds, through: 1, by: -1) {
            countdown = value
            try? await Task.sleep(for: .seconds(1))
        }
        countdown = nil
        refresh()
    }

    func updateTransfer(_ card: TransferStatusCard?, id: UUID, on screen: NSScreen?) {
        if let card {
            // Representable updates can repeat without a progress change. Publishing
            // the same card feeds that update straight back into the editor graph.
            guard transfers[id]?.status != card.status else { return }
            let isNew = transfers[id] == nil
            transfers[id] = card
            if isNew { transferOrder.append(id); show(on: screen) }
        } else {
            guard transfers[id] != nil else { return }
            transfers.removeValue(forKey: id)
            transferOrder.removeAll { $0 == id }
            refresh()
        }
    }
}

struct NotchContent: View {
    @State private var presenter = NotchPresenter.shared
    @State private var bar = RecordingBarPresenter.shared
    @State private var overlay = PreviewOverlay.shared
    @State private var shelfStore = NotchShelfStore.shared
    @State private var filter: NotchShelfFilter

    init(filter: NotchShelfFilter = .all) {
        _filter = State(initialValue: filter)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.hidden)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: min(560, (presenter.screen?.visibleFrame.width ?? 624) - 64))
        .frame(maxHeight: max(240, (presenter.screen?.visibleFrame.height ?? 800) - 120))
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            presenter.menuTrackingCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            presenter.menuTrackingCount = max(0, presenter.menuTrackingCount - 1)
            presenter.resumeHoverDismissal()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            presenter.resumeHoverDismissal()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { _ in
            presenter.resumeHoverDismissal()
        }
        .onChange(of: bar.showsRecordingOptions) { _, open in
            if !open { presenter.resumeHoverDismissal() }
        }
        .onChange(of: bar.recordingConfirmation) { _, action in
            if action == nil { presenter.resumeHoverDismissal() }
        }
        .onChange(of: presenter.countdown) { _, countdown in
            if countdown == nil { presenter.resumeHoverDismissal() }
        }
        .onChange(of: presenter.captureSuspended) { _, suspended in
            if !suspended { filter = .all }
        }
        .onChange(of: overlay.items) { filter = .all }
        .onChange(of: presenter.ocrText) { filter = .all }
        .onChange(of: presenter.colorHex) { filter = .all }
        .popover(isPresented: $bar.showsRecordingOptions, arrowEdge: .top) { RecordingOptionsView() }
        .onExitCommand {
            if bar.isVisible && bar.mode == .picker {
                bar.dismiss()
                Task { await CameraRecordingManager.shared.stopPreview() }
            }
            presenter.collapse()
        }
        .onKeyPress("a") {
            guard !ScreenRecordingManager.shared.isActive else { return .ignored }
            bar.captureLastRegion()
            return .handled
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(NotchShelfFilter.allCases) { tab in
                    Button { filter = tab } label: {
                        Text(tab.rawValue).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 9).frame(height: 28)
                            .foregroundStyle(filter == tab ? .black : .white.opacity(0.65))
                            .background(filter == tab ? Color.white : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(tab.rawValue.lowercased())")
                    .accessibilityAddTraits(filter == tab ? .isSelected : [])
                }
                Spacer(minLength: 4)
                if NotchVoiceCapture.shared.holdIndicatorActive {
                    Circle().fill(.green).frame(width: 7, height: 7)
                        .accessibilityLabel("Capture active")
                }
                Menu {
                    Button(ShortcutService.shared.help("Copy Text from Screen", for: .ocr), systemImage: "doc.text.viewfinder") {
                        Task { await CaptureOrchestrator.shared.performCapture(.ocr, on: presenter.screen) }
                    }
                    Button(ShortcutService.shared.help("Pick Color", for: .colorPicker), systemImage: "eyedropper") {
                        Task { await CaptureOrchestrator.shared.performCapture(.colorPicker, on: presenter.screen) }
                    }
                    Divider()
                    Button("Open Gallery", systemImage: "folder") {
                        MediaGalleryWindowController.shared.open(on: presenter.screen)
                    }
                    if !overlay.items.isEmpty {
                        Divider()
                        Button("Save All Captures") { overlay.saveAll() }
                        Button("Dismiss All Captures") { overlay.clearAll() }
                    }
                } label: {
                    Image(systemName: "folder").frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Library and capture actions").help("Library and capture actions")
                BoringNotchHoverButton(title: "Settings", icon: "gearshape") {
                    SettingsWindowController.shared.open(section: .general)
                }
            }
            if let issue = presenter.captureIssue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.title).font(.subheadline.weight(.medium))
                        Text(issue.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    BoringNotchHoverButton(title: "Dismiss error", icon: "xmark") {
                        presenter.captureIssue = nil
                        presenter.refresh()
                    }
                }
            }
            if let countdown = presenter.countdown {
                Label("Starting in \(countdown)", systemImage: "timer")
                    .font(.title2.monospacedDigit()).padding()
            } else {
                if ScreenRecordingManager.shared.isActive {
                    RecordingSessionControls().frame(height: BarMetrics.recordingHeight)
                }
                if let script = presenter.script {
                    TeleprompterOverlayView(model: script).textArea
                        .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 8))
                }
                shelf
                if let error = shelfStore.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let id = presenter.transferOrder.last, let card = presenter.transfers[id] { card }

            }
        }
        .padding(.top, 8)
    }

    private var shelf: some View {
        let media = NotchRecentCaptures.mediaURLs(pending: overlay.items, filter: filter)
        let saved = shelfStore.entries.filter {
            filter == .all || (filter == .colors && $0.isColor == true) || (filter == .text && $0.isColor != true)
        }
        let hasText = (filter == .all || filter == .text) && presenter.ocrText != nil
            && !saved.contains { $0.text == presenter.ocrText }
        let hasColor = (filter == .all || filter == .colors) && presenter.colorHex != nil
            && !saved.contains { $0.text == presenter.colorHex }
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                if hasColor, let hex = presenter.colorHex {
                    NotchTextResult(title: "Color", value: hex, isColor: true) {
                        presenter.colorHex = nil
                        presenter.refresh()
                    }.id(hex)
                }
                if hasText, let text = presenter.ocrText {
                    NotchTextResult(title: "Text", value: text, isColor: false) {
                        presenter.ocrText = nil
                        presenter.refresh()
                    }.id(text)
                }
                ForEach(saved) { entry in
                    NotchTextResult(title: entry.isColor == true ? "Color" : entry.imageURL == nil ? "Text" : "Voice note",
                        value: entry.text, isColor: entry.isColor == true, imageURL: entry.imageURL) {
                        shelfStore.remove(entry.id)
                    }
                }
                ForEach(media, id: \.self) { url in
                    NotchMediaCard(url: url)
                }
                if media.isEmpty && !hasText && !hasColor && saved.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: filter.symbol).font(.title2).foregroundStyle(.secondary)
                        Text(filter == .all ? "Your captures, together" : "No \(filter.rawValue.lowercased()) yet")
                            .font(.headline)
                        Text(NotchVoiceCapture.drawsOnHold ? "Hold \(NotchVoiceCapture.captureHoldKey.title) briefly, draw on screen, then release to save. Find OCR and Pick Color in the folder menu." : "Hold \(NotchVoiceCapture.captureHoldKey.title) and drag an area to capture. Find OCR and Pick Color in the folder menu.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(20).frame(height: 160)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 164)
        .id(filter)
    }
}

/// Copy feedback stays on the action; session results remain until dismissed.
private struct NotchTextResult: View {
    let title: String
    let value: String
    let isColor: Bool
    var imageURL: URL? = nil
    var dismiss: () -> Void
    @State private var copyFailed = false
    @State private var copied = false

    private var ink: Color {
        guard isColor, let color = NSColor(annoHex: value.trimmingCharacters(in: .whitespacesAndNewlines)).usingColorSpace(.sRGB) else { return .white }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        return luminance > 0.179 ? .black : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                    .onDrag { NSItemProvider(object: value as NSString) }
                Spacer()
                Button("Dismiss \(title.lowercased())", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
            }
            if isColor {
                Spacer(minLength: 0)
                Text(value).font(.system(.body, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .onDrag { NSItemProvider(object: value as NSString) }
                    .help("Drag the color code into another app")
            } else {
                ScrollView {
                    Text(value).font(.system(size: 13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onDrag { NSItemProvider(object: value as NSString) }
                        .help("Drag this text into another app")
                }.scrollIndicators(.hidden)
            }
            if let imageURL {
                Button("Open image", systemImage: "photo") { NotchQuickEditor.shared.open(imageURL) }
                    .buttonStyle(.plain).font(.caption)
            }
            Button {
                if let imageURL {
                    copyFailed = (try? NotchShelfStore.copy(.init(text: value, imageURL: imageURL))) != true
                } else { copyFailed = !CaptureOrchestrator.copyText(value) }
                copied = !copyFailed
                if copied { NotchPresenter.shared.captureIssue = nil }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain).padding(.vertical, 5)
            .background(ink.opacity(0.12), in: Capsule())
            .accessibilityLabel(imageURL != nil ? "Copy image and transcript" : isColor ? "Copy color code" : "Copy text")
            .accessibilityValue(copied ? "Copied to clipboard" : "")
            .task(id: copied) {
                guard copied else { return }
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                copied = false
            }
            if copyFailed { Text("Couldn’t copy. Try again.").font(.caption) }
        }
        .padding(14).frame(width: 160, height: 160)
        .foregroundStyle(ink)
        .background {
            if isColor {
                Color(nsColor: NSColor(annoHex: value.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else { Color.white.opacity(0.09) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .contextMenu {
            if imageURL != nil {
                Button("Copy transcript", systemImage: "text.quote") {
                    copyFailed = !CaptureOrchestrator.copyText(value)
                    copied = !copyFailed
                }
            }
        }
    }
}

struct NotchCompactLeading: View {
    var body: some View {
        Button { NotchPresenter.shared.show() } label: {
            Image(nsImage: NSImage(named: "MenuBarIcon") ?? NSImage()).resizable().renderingMode(.template)
                .scaledToFit().frame(width: 18, height: 18)
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("BetterShot — open shelf")
        .help("BetterShot — saved captures, text, and colors")
    }
}

struct NotchCompactTrailing: View {
    @State private var editorIsOpen = false

    private var status: (title: String, symbol: String) {
        if editorIsOpen { return ("Editor open", "pencil.and.outline") }
        if PreviewOverlay.shared.isPresented || NotchPresenter.shared.ocrText != nil || NotchPresenter.shared.colorHex != nil {
            return ("Capture ready", "checkmark")
        }
        return ("Ready to capture", "circle.fill")
    }

    var body: some View {
        Button { NotchPresenter.shared.show() } label: {
            if NotchVoiceCapture.shared.holdIndicatorActive {
                Circle().fill(.green).frame(width: 7, height: 7).frame(width: 28, height: 22)
                    .accessibilityLabel("Capture active")
            } else if ScreenRecordingManager.shared.isActive {
                Label(ScreenRecordingManager.shared.formattedElapsedTime, systemImage: "record.circle.fill")
                    .monospacedDigit().foregroundStyle(.red)
            } else {
                Image(systemName: status.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue).frame(width: 28, height: 22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NotchVoiceCapture.shared.holdIndicatorActive ? "Capture active" : ScreenRecordingManager.shared.isActive ? "Expand recording controls" : status.title)
        .help(ScreenRecordingManager.shared.isActive ? "Recording in progress" : status.title)
        .onAppear { refreshEditors() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshEditors() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            refreshEditors(excluding: notification.object as? NSWindow)
        }
    }

    private func refreshEditors(excluding closing: NSWindow? = nil) {
        editorIsOpen = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.delegate is EditorCloseGuard
        }
    }
}
