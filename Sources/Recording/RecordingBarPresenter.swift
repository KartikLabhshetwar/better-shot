import AppKit
import SwiftUI

/// Owns the single floating panel that starts as the source picker and morphs in place into the in-session controls. Ported from screendrop's RecordingBarPresenter (github.com/fayazara/screendrop, CC0-1.0), adapted to BetterShot's NSVisualEffectView chrome and ScreenRecordingManager API.
@Observable
@MainActor
final class RecordingBarPresenter {
    static let shared = RecordingBarPresenter()

    enum Mode: Equatable {
        case picker
        case recording
    }

    /// Derived from the recorder rather than set by hand, so the bar cannot show picker controls over a live session no matter which path started it.
    var mode: Mode {
        if let frozenMode { return frozenMode }
        return ScreenRecordingManager.shared.isSessionActive ? .recording : .picker
    }

    /// Held only while the bar animates out, so the contents do not swap back to the picker mid-fade when the recording ends.
    private var frozenMode: Mode?
    @ObservationIgnored private var contentSize: NSSize?

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var showTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingFrame = false

    private init() {}

    func togglePicker(on screen: NSScreen? = nil) {
        if let panel, panel.isVisible, mode == .picker {
            hide()
        } else {
            showPicker(on: screen)
        }
    }

    func showPicker(on screen: NSScreen? = nil) {
        hideTask?.cancel()
        hideTask = nil
        frozenMode = nil
        showTask?.cancel()

        if AppPreferences.recordingShowCamera {
            CameraBubbleController.shared.enable()
        }
        let panel = panel ?? makePanel()
        applyFrame(to: panel, on: screen, keepingCurrentPosition: false, animated: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        RecordingBarPresentation.shared.isPresented = true

        // Enumerating displays and windows takes long enough to be felt, so the bar goes up first and its source menus fill in behind it.
        showTask = Task { @MainActor [weak self] in
            await RecordingSourceCatalog.shared.refresh()
            guard let self, !Task.isCancelled else { return }
            self.reposition(panel, on: screen, keepingCurrentPosition: true, animated: true)
            self.showTask = nil
        }
    }

    func showRecording(on screen: NSScreen? = nil) {
        hideTask?.cancel()
        hideTask = nil
        showTask?.cancel()
        showTask = nil
        frozenMode = nil

        let panel = panel ?? makePanel()
        let wasVisible = panel.isVisible
        reposition(panel, on: screen, keepingCurrentPosition: wasVisible, animated: false)
        panel.orderFrontRegardless()

        if let rect = ScreenRecordingManager.shared.activeRegionRect {
            RecordingAreaHighlightPresenter.shared.show(rect: rect, on: screen)
        }
        RecordingBarPresentation.shared.isPresented = true
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        frozenMode = mode
        RecordingBarHoverView.endActiveHover()
        RecordingAreaHighlightPresenter.shared.hide()
        RecordingBarPresentation.shared.isPresented = false

        let panel = panel
        hideTask = Task { @MainActor [weak self] in
            let nanoseconds: UInt64 = RecordingMotion.reduceMotion ? 0 : 220_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            self?.frozenMode = nil
            self?.hideTask = nil
        }
    }

    /// SwiftUI reports what the bar actually measures, so the panel tracks a mode swap or a widening timecode instead of keeping whatever it fitted to first.
    func barContentSizeChanged(_ size: CGSize) {
        let measured = NSSize(
            width: size.width.rounded(.up),
            height: size.height.rounded(.up) + RecordingBarMetrics.tooltipReservedHeight
        )
        guard measured.width > 1, measured != contentSize else { return }
        let hadSize = contentSize != nil
        contentSize = measured
        guard hadSize, let panel, panel.isVisible else { return }
        applyFrame(to: panel, on: nil, keepingCurrentPosition: true, animated: false)
    }

    private func reposition(_ panel: NSPanel, on screen: NSScreen?, keepingCurrentPosition: Bool, animated: Bool) {
        if panel.isVisible {
            Task { @MainActor [weak self] in
                self?.applyFrame(to: panel, on: screen, keepingCurrentPosition: keepingCurrentPosition, animated: animated)
            }
        } else {
            applyFrame(to: panel, on: screen, keepingCurrentPosition: keepingCurrentPosition, animated: animated)
        }
    }

    private func applyFrame(to panel: NSPanel, on screen: NSScreen?, keepingCurrentPosition: Bool, animated: Bool) {
        guard let contentView = panel.contentView else { return }
        let size = measuredSize(of: contentView)
        let frame = resolvedFrame(for: size, panel: panel, screen: screen, keepingCurrentPosition: keepingCurrentPosition)
        guard frame != panel.frame else { return }

        isApplyingFrame = true
        if animated, !RecordingMotion.reduceMotion {
            // Held across the animation, not just the call: `didMove` fires per animation step and would otherwise save a position the user never chose.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated { self.isApplyingFrame = false }
            }
        } else {
            panel.setFrame(frame, display: true)
            isApplyingFrame = false
        }
    }

    private func measuredSize(of contentView: NSView) -> NSSize {
        if let contentSize { return contentSize }
        contentView.layoutSubtreeIfNeeded()
        return contentView.fittingSize
    }

    private func resolvedFrame(for size: NSSize, panel: NSPanel, screen: NSScreen?, keepingCurrentPosition: Bool) -> NSRect {
        if keepingCurrentPosition {
            let visible = (panel.screen ?? screen)?.visibleFrame ?? Self.fallbackVisibleFrame
            return RecordingBarFrame.resized(panel.frame, to: size, in: visible)
        }
        if let saved = RecordingBarPositionStore.load(),
           let savedScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(saved) }) {
            return RecordingBarFrame.clamped(NSRect(origin: saved, size: size), in: savedScreen.visibleFrame)
        }
        let target = screen ?? ActiveDisplayResolver.activeScreen(preferPointer: false) ?? NSScreen.main
        return RecordingBarFrame.centered(
            size: size,
            in: target?.visibleFrame ?? Self.fallbackVisibleFrame,
            bottomInset: RecordingBarMetrics.bottomInset
        )
    }

    private static let fallbackVisibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 948)

    private func makePanel() -> NSPanel {
        let rootView = RecordingBarRootView()
            .environment(\.colorScheme, .dark)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = RecordingBarPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        // The controls track hover themselves so they still highlight, and claim the pointing-hand cursor, while BetterShot is in the background - which is the whole time a recording is running.
        panel.acceptsMouseMovedEvents = true
        panel.disableCursorRects()
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let self, !self.isApplyingFrame else { return }
                RecordingBarPositionStore.save(window.frame.origin)
            }
        }

        self.panel = panel
        return panel
    }
}

/// Borderless panel that can still become key (so its `Menu`s and Escape-to-dismiss work) without activating BetterShot.
private final class RecordingBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        guard RecordingBarPresenter.shared.mode == .picker else { return }
        RecordingBarPresenter.shared.hide()
    }
}

private struct RecordingBarRootView: View {
    @State private var presenter = RecordingBarPresenter.shared
    @State private var presentation = RecordingBarPresentation.shared
    @State private var tooltip = RecordingBarTooltipModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(width: 1, height: RecordingBarMetrics.height + RecordingBarMetrics.tooltipReservedHeight)
                .allowsHitTesting(false)
            bar
            tooltipLayer
        }
        .coordinateSpace(.named(RecordingBarCoordinateSpace.bar))
        .environment(tooltip)
    }

    private var bar: some View {
        Group {
            switch presenter.mode {
            case .picker:
                RecordingPickerControls()
            case .recording:
                RecordingSessionControls()
            }
        }
        .frame(height: RecordingBarMetrics.height)
        .fixedSize()
        .background(sizeReader)
        .recordingBarSurface(isInteractive: true)
        .scaleEffect(presentation.isPresented ? 1 : 0.92, anchor: .bottom)
        .opacity(presentation.isPresented ? 1 : 0)
        .animation(RecordingMotion.showHideSpring, value: presentation.isPresented)
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size, initial: true) { _, size in
                    presenter.barContentSizeChanged(size)
                }
        }
    }

    /// Positioned off the hovered control's measured frame rather than a hardcoded index, so it keeps tracking when the bar's contents change - a mode swap, or a menu label swapping in.
    private var tooltipLayer: some View {
        GeometryReader { _ in
            if let target = tooltip.visible {
                RecordingBarTooltipPill(text: target.text)
                    .position(
                        x: target.frame.midX,
                        y: target.frame.minY - RecordingBarMetrics.tooltipGap - RecordingBarMetrics.tooltipPillHeight / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.id)
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.text)
    }
}

/// Remembers the bar's dragged position across launches.
private enum RecordingBarPositionStore {
    private static let xKey = "bs_recbar_origin_x_v2"
    private static let yKey = "bs_recbar_origin_y_v2"

    static func save(_ origin: NSPoint) {
        UserDefaults.standard.set(Double(origin.x), forKey: xKey)
        UserDefaults.standard.set(Double(origin.y), forKey: yKey)
    }

    static func load() -> NSPoint? {
        guard UserDefaults.standard.object(forKey: xKey) != nil,
              UserDefaults.standard.object(forKey: yKey) != nil else { return nil }
        return NSPoint(
            x: UserDefaults.standard.double(forKey: xKey),
            y: UserDefaults.standard.double(forKey: yKey)
        )
    }
}
