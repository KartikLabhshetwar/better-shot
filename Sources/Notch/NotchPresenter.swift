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
    @ObservationIgnored private var hoverDismissTimer: Timer?
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
                panel.isOpaque = false
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                PreviewWindowCaptureExclusion.shared.register(window: panel)
            }
            self.notch = notch
        }
        notch?.presentImmediately(on: screen, expanded: expanded)
    }

    func collapse() {
        hoverDismissTimer?.invalidate()
        guard expanded else { return }
        expanded = false
        refresh()
    }

    func suspendForCapture() {
        hoverDismissTimer?.invalidate()
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
        hoverDismissTimer?.invalidate()
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
        hoverDismissTimer?.invalidate()
        guard AppPreferences.presentationMode == .notch, !captureSuspended else { return }
        if hovering {
            if !expanded { show() }
            return
        }
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isHovering, self.canCollapseAfterHover else { return }
                self.collapse()
            }
        }
        hoverDismissTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        .onChange(of: overlay.items) { selectedURL = overlay.items.last }
        .onExitCommand {
            if bar.isVisible && bar.mode == .picker {
                bar.dismiss()
                Task { await CameraRecordingManager.shared.stopPreview() }
            } else { presenter.collapse() }
        }
        .onKeyPress("a") {
            guard bar.isVisible, bar.mode == .picker else { return .ignored }
            bar.captureLastRegion()
            return .handled
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack {
                Image("MenuBarIcon").resizable().scaledToFit().frame(width: 18, height: 18)
                Text("BetterShot").font(.headline)
                Spacer()
                if !bar.isVisible && !ScreenRecordingManager.shared.isActive {
                    Button("New Capture", systemImage: "viewfinder") { bar.showPicker() }
                }
                Button("Collapse notch", systemImage: "chevron.up") { presenter.collapse() }
                    .labelStyle(.iconOnly)
            }
            if let countdown = presenter.countdown {
                Label("Starting in \(countdown)", systemImage: "timer")
                    .font(.title2.monospacedDigit()).padding()
            } else {
                if bar.isVisible {
                    if bar.mode == .recording {
                        RecordingSessionControls().frame(height: BarMetrics.recordingHeight)
                    } else {
                        RecordingPickerControls().frame(height: BarMetrics.height)
                    }
                }
                if let script = presenter.script {
                    TeleprompterOverlayView(model: script).textArea
                        .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 8))
                }
                if overlay.isPresented, let url = selected {
                    Divider()
                    HStack {
                        Text(PreviewOverlay.isVideo(url) ? "Recording" : "Screenshot").font(.subheadline)
                        Spacer()
                        if overlay.items.count > 1 {
                            Button("Previous capture", systemImage: "chevron.left") { moveSelection(-1) }
                                .labelStyle(.iconOnly)
                            Text("\((overlay.items.firstIndex(of: url) ?? 0) + 1) / \(overlay.items.count)")
                                .monospacedDigit()
                            Button("Next capture", systemImage: "chevron.right") { moveSelection(1) }
                                .labelStyle(.iconOnly)
                            Button("Save All") { overlay.saveAll() }
                            Button("Clear All") { overlay.clearAll() }
                        }
                    }
                    PreviewCardView(overlay: overlay, url: url, usesNotchActions: true)
                        .id(url)
                    HStack(spacing: 16) {
                        ForEach(OverlayTool.allCases) { tool in
                            Button { overlay.perform(tool, for: url) } label: {
                                Label(tool.title, systemImage: tool.symbol)
                            }
                            .disabled(overlay.savingItems.contains(url) || overlay.transferStatus(for: url) != nil)
                        }
                    }
                    .controlSize(.small)
                    .onHover { hovering in
                        if hovering { overlay.cancelScheduledDismiss(for: url) }
                        else { overlay.scheduleDismiss(for: url) }
                    }
                }
                Divider()
                NotchRecentCaptures()
                if let id = presenter.transferOrder.last, let card = presenter.transfers[id] { card }
                if let notification = presenter.notification { notification }
            }
        }
        .padding(.top, 8)
    }

    private func moveSelection(_ delta: Int) {
        guard let selected, let index = overlay.items.firstIndex(of: selected), !overlay.items.isEmpty else { return }
        selectedURL = overlay.items[(index + delta + overlay.items.count) % overlay.items.count]
    }
}

struct NotchCompactLeading: View {
    var body: some View {
        Button { NotchPresenter.shared.show() } label: {
            if (NotchPresenter.shared.screen?.safeAreaInsets.top ?? 0) == 0 {
                Text("BetterShot").font(.caption)
            } else {
                Color.clear.frame(width: 1, height: 18)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand BetterShot notch")
    }
}

struct NotchCompactTrailing: View {
    var body: some View {
        if ScreenRecordingManager.shared.isActive {
            Button { NotchPresenter.shared.show() } label: {
                Label(ScreenRecordingManager.shared.formattedElapsedTime, systemImage: "record.circle")
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand recording controls")
        }
    }
}
