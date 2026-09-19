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
    var notification: AnyView?
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
            notification != nil || !transfers.isEmpty || script != nil
    }

    private init() {}

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
        notch?.presentImmediately(on: screen, expanded: expanded, animated: true)
    }

    func collapse() {
        hoverTask?.cancel()
        guard expanded else { return }
        expanded = false
        refresh()
    }

    func suspendForCapture() {
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
        guard AppPreferences.presentationMode == .notch, !captureSuspended else { return }
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
    @State private var selectedURL: URL?
    @State private var showsRecent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(showsRecent: Bool = false) {
        _showsRecent = State(initialValue: showsRecent)
    }

    private var selected: URL? {
        selectedURL.flatMap { overlay.items.contains($0) ? $0 : nil } ?? overlay.items.last
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.hidden)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: 620)
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
        .onChange(of: overlay.items) {
            selectedURL = overlay.items.last
            if !overlay.items.isEmpty { showsRecent = false }
        }
        .onExitCommand {
            if bar.isVisible && bar.mode == .picker {
                bar.dismiss()
                Task { await CameraRecordingManager.shared.stopPreview() }
            }
            presenter.collapse()
        }
        .onKeyPress("a") {
            guard !showsRecent, !ScreenRecordingManager.shared.isActive else { return .ignored }
            bar.captureLastRegion()
            return .handled
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: "MenuBarIcon") ?? NSImage()).resizable().renderingMode(.template)
                    .scaledToFit().frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("BetterShot").font(.headline)
                Spacer()
                Picker("Notch section", selection: $showsRecent) {
                    Text("Capture").tag(false)
                    Text("Recents").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                BoringNotchHoverButton(title: "Settings", icon: "gearshape") {
                    SettingsWindowController.shared.open(section: .general)
                }
                BoringNotchHoverButton(title: "Collapse notch — Esc", icon: "chevron.up") {
                    presenter.collapse()
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
                Group {
                    if showsRecent {
                        NotchRecentCaptures()
                    } else {
                        captureContent
                    }
                }
                .transition(.opacity)
                if let id = presenter.transferOrder.last, let card = presenter.transfers[id] { card }
                if let notification = presenter.notification { notification }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsRecent)
        .padding(.top, 8)
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !ScreenRecordingManager.shared.isActive {
                RecordingPickerControls(showsCloseButton: false)
                    .frame(maxWidth: .infinity).frame(height: BarMetrics.height)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            if overlay.isPresented, let url = selected {
                HStack {
                    Label(PreviewOverlay.isVideo(url) ? "Recording" : "Screenshot",
                          systemImage: PreviewOverlay.isVideo(url) ? "video" : "photo")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if overlay.items.count > 1 {
                        Button("Previous capture", systemImage: "chevron.left") { moveSelection(-1) }
                            .labelStyle(.iconOnly)
                        Text("\((overlay.items.firstIndex(of: url) ?? 0) + 1) of \(overlay.items.count)")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Button("Next capture", systemImage: "chevron.right") { moveSelection(1) }
                            .labelStyle(.iconOnly)
                        Menu("More", systemImage: "ellipsis") {
                            Button("Save All") { overlay.saveAll() }
                            Button("Clear All") { overlay.clearAll() }
                        }.labelStyle(.iconOnly)
                    }
                }
                HStack(alignment: .center, spacing: 20) {
                    PreviewCardView(overlay: overlay, url: url, usesNotchActions: true).id(url)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ready to edit or share").font(.headline)
                        Text("Keep capturing. Your captures stay here until you dismiss them.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach([OverlayTool.edit, .copy, .save, .share, .pin, .dismiss]) { tool in
                                Button { overlay.perform(tool, for: url) } label: {
                                    Label(tool.title, systemImage: tool.symbol)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(EditorButtonStyle(bordered: true))
                                .disabled(overlay.savingItems.contains(url) || overlay.transferStatus(for: url) != nil)
                            }
                        }
                    }
                }
            } else if !ScreenRecordingManager.shared.isActive {
                VStack(spacing: 8) {
                    Image(systemName: "viewfinder").font(.system(size: 28, weight: .light))
                    Text("Ready to capture").font(.headline)
                    Text("Choose an area, display, or window above.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Browse recent captures") { showsRecent = true }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22)
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard let selected, let index = overlay.items.firstIndex(of: selected), !overlay.items.isEmpty else { return }
        selectedURL = overlay.items[(index + delta + overlay.items.count) % overlay.items.count]
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
        .accessibilityLabel("BetterShot — expand capture tools")
        .help("BetterShot — capture tools and recent media")
    }
}

struct NotchCompactTrailing: View {
    @State private var editorIsOpen = false

    private var status: (title: String, symbol: String) {
        if editorIsOpen { return ("Editor open", "pencil.and.outline") }
        if PreviewOverlay.shared.isPresented { return ("Capture ready", "checkmark") }
        return ("Ready to capture", "viewfinder")
    }

    var body: some View {
        Button { NotchPresenter.shared.show() } label: {
            if ScreenRecordingManager.shared.isActive {
                Label(ScreenRecordingManager.shared.formattedElapsedTime, systemImage: "record.circle.fill")
                    .monospacedDigit().foregroundStyle(.red)
            } else {
                Image(systemName: status.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue).frame(width: 28, height: 22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ScreenRecordingManager.shared.isActive ? "Expand recording controls" : status.title)
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
