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

    private(set) var mode: Mode = .picker

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

        mode = .picker
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

        let panel = panel ?? makePanel()
        let isMorphing = panel.isVisible && mode == .picker
        mode = .recording
        reposition(panel, on: screen, keepingCurrentPosition: isMorphing, animated: isMorphing)
        panel.orderFrontRegardless()

        if let rect = ScreenRecordingManager.shared.activeRegionRect {
            RecordingAreaHighlightPresenter.shared.show(rect: rect, on: screen)
        }
        RecordingBarPresentation.shared.isPresented = true
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        RecordingBarHoverView.endActiveHover()
        RecordingAreaHighlightPresenter.shared.hide()
        RecordingBarPresentation.shared.isPresented = false

        let panel = panel
        hideTask = Task { @MainActor [weak self] in
            let nanoseconds: UInt64 = RecordingMotion.reduceMotion ? 0 : 220_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            self?.mode = .picker
            self?.hideTask = nil
        }
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
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        let origin: NSPoint
        if keepingCurrentPosition {
            let current = panel.frame
            origin = NSPoint(x: current.midX - size.width / 2, y: current.minY)
        } else {
            origin = resolvedOrigin(for: size, preferredScreen: screen)
        }
        let frame = NSRect(origin: origin, size: size)
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

    private func resolvedOrigin(for panelSize: NSSize, preferredScreen: NSScreen?) -> NSPoint {
        if let saved = RecordingBarPositionStore.load() {
            let savedFrame = NSRect(origin: saved, size: panelSize)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(savedFrame) }) {
                return saved
            }
        }
        let screen = preferredScreen ?? ActiveDisplayResolver.activeScreen(preferPointer: false) ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + RecordingBarMetrics.bottomInset
        )
    }

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
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .animation(RecordingMotion.modeChange, value: presenter.mode)
        .frame(height: RecordingBarMetrics.height)
        .fixedSize()
        .recordingBarSurface(isInteractive: true)
        .scaleEffect(presentation.isPresented ? 1 : 0.92, anchor: .bottom)
        .opacity(presentation.isPresented ? 1 : 0)
        .animation(RecordingMotion.showHideSpring, value: presentation.isPresented)
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
