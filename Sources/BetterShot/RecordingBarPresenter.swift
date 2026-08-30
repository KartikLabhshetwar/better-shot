//
//  RecordingBarPresenter.swift
//  BetterShot
//
//  One floating bar, two modes. Before recording it picks the source and the
//  capture inputs; during recording it drives the session. They share a
//  single panel so the handoff is a morph - the bar's rounded rect animates
//  to the new width while the controls cross-fade - rather than one window
//  vanishing and another appearing somewhere near it.
//
//  RecordingPickerPresenter and RecordingControlPresenter are the entry
//  points callers still use; both forward here.
//

import AppKit
import SwiftUI

@Observable
@MainActor
final class RecordingBarPresenter {
    static let shared = RecordingBarPresenter()

    enum Mode: Equatable {
        case picker
        case recording
    }

    private(set) var mode: Mode = .picker

    /// The bar's frame inside the panel's content view, reported by SwiftUI.
    /// The panel is deliberately much larger than the bar, so this is what
    /// tells the hosting view which part of itself is real and satellite
    /// windows where to anchor.
    var barFrameInPanel: CGRect = .zero

    @ObservationIgnored private var panel: NSPanel?
    /// The app that had focus before the picker activated BetterShot, so
    /// closing the bar (or starting a recording) hands the keyboard back.
    @ObservationIgnored private var previousApp: NSRunningApplication?

    private init() {}

    // MARK: Picker

    func togglePicker() {
        if let panel, panel.isVisible, mode == .picker {
            hide()
        } else {
            showPicker()
        }
    }

    func showPicker() {
        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        Task {
            await RecordingSourceCatalog.shared.refresh()
        }
        mode = .picker
        position(panel, displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: false))
        panel.orderFrontRegardless()
        // The picker is driven from the keyboard too (Esc, A for the last
        // region), and key events only reach the panel while BetterShot is
        // the active app. Focus is handed back when the picker leaves.
        previousApp = NSApp.isActive ? nil : NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        LastRegionGhostPresenter.shared.show()
        warmCameraPreviewIfEnabled()
    }

    /// The remembered region, captured without going through the selection
    /// overlay. The ghost on screen is what the user is confirming.
    func captureLastRegion() {
        guard mode == .picker, AppPreferences.lastRegionRect != nil else { return }
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        hide()
        Task {
            await CameraRecordingManager.shared.stopPreview()
            await CaptureOrchestrator.shared.captureLastRegion(on: screen)
        }
    }

    private func restoreFocus() {
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: Recording

    /// Called once capture is actually starting. If the bar is already up on
    /// the recording's display it morphs in place; otherwise it has to move,
    /// and there's nothing to morph from.
    func showRecording(displayID: CGDirectDisplayID?) {
        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        TeleprompterComposerPresenter.shared.hide()
        LastRegionGhostPresenter.shared.hide()
        restoreFocus()

        let isMorphing = panel.isVisible && isPositioned(panel, onDisplayID: displayID)
        if isMorphing {
            withAnimation(BarMetrics.modeChange) {
                mode = .recording
            }
        } else {
            mode = .recording
            position(panel, displayID: displayID)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        // `orderOut` sends no exit events, so a hover that's live when the
        // bar hides has to be ended by hand - it holds the pointing hand.
        BarControlHoverView.endActiveHover()
        panel?.orderOut(nil)
        LastRegionGhostPresenter.shared.hide()
        // The composer only makes sense floating above the bar.
        TeleprompterComposerPresenter.shared.hide()
        // Next appearance should always start as the picker, and without
        // animating out of a mode nobody can see.
        mode = .picker
    }

    /// The user backed out of the picker: hide it and give the keyboard
    /// back. `hide()` alone keeps BetterShot active, which the selection
    /// overlays that follow it (area recording, region capture) rely on:
    /// their cursor and Esc only hold while this app is frontmost.
    func dismiss() {
        hide()
        restoreFocus()
    }

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard let barFrame, panel?.isVisible == true else { return false }
        return barFrame.contains(point)
    }

    // MARK: Geometry

    /// Where the bar currently sits on screen, so satellite windows (the
    /// teleprompter composer) can anchor to it even after the user drags it
    /// around. This is the visible bar, not the panel: the panel is padded
    /// out with transparent slack for the tooltips and shadows, and anchoring
    /// to that would leave satellites floating clear of the bar.
    var barFrame: CGRect? {
        guard let panel, panel.isVisible, barFrameInPanel != .zero else { return nil }
        // SwiftUI reports a top-left origin; screen coordinates are bottom-up.
        return CGRect(
            x: panel.frame.minX + barFrameInPanel.minX,
            y: panel.frame.maxY - barFrameInPanel.maxY,
            width: barFrameInPanel.width,
            height: barFrameInPanel.height
        )
    }

    private func isPositioned(_ panel: NSPanel, onDisplayID displayID: CGDirectDisplayID?) -> Bool {
        guard let target = ActiveDisplayResolver.screen(for: displayID) else { return true }
        return target.frame.intersects(panel.frame)
    }

    private func position(_ panel: NSPanel, displayID: CGDirectDisplayID?) {
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: BarMetrics.panelWidth, height: BarMetrics.panelHeight)
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            // Dropped by the bottom slack so the bar - not the panel - lands
            // 48pt above the visible frame.
            y: visibleFrame.minY + 48 - BarMetrics.shadowSlack
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// The bar's hosting view is created once and just reordered in/out on
    /// every show/hide, so its SwiftUI `.task` never reruns after the first
    /// appearance. Reading the camera preference here - on every real
    /// `showPicker()` - is what makes a camera left on from a previous
    /// session warm up immediately instead of needing an off/on toggle.
    private func warmCameraPreviewIfEnabled() {
        let cameraID = BetterShotPreferences.recordingCameraDeviceID
        guard !cameraID.isEmpty else { return }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        Task {
            await CameraRecordingManager.shared.startPreview(deviceID: cameraID, displayID: displayID)
        }
    }

    private func makePanel() -> NSPanel {
        let size = CGSize(width: BarMetrics.panelWidth, height: BarMetrics.panelHeight)
        let panel = RecordingBarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Shadows are drawn in SwiftUI, not by AppKit. The window shadow is
        // derived from the window's alpha silhouette and recomputed lazily,
        // so anything that fades or resizes inside the panel - the tooltip,
        // the morph - leaves its shadow outline hanging for a frame or two
        // after the fill has moved on. The panel reserves slack on all four
        // sides so SwiftUI's shadows aren't clipped by the panel edge, which
        // was the original reason for using the AppKit one.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        // The controls track hover themselves so they still highlight while
        // BetterShot is in the background, which is the whole time a recording
        // is running. Their tracking areas need the moved events.
        panel.acceptsMouseMovedEvents = true
        // Nothing in the bar wants a cursor other than the pointing hand its
        // controls push. Left on, AppKit's own cursor rectangles reset the
        // pointer to an arrow on every mouse move the moment BetterShot is
        // the active app - which it is whenever the picker is opened from
        // inside the app.
        panel.disableCursorRects()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        PreviewWindowCaptureExclusion.shared.register(window: panel)

        let hostingView = RecordingBarHostingView(rootView: RecordingBarView())
        hostingView.frame = CGRect(origin: .zero, size: size)
        // The panel is sized explicitly and the bar inside it animates its own
        // width during a morph. Left to bridge its ideal size onto the
        // window, the hosting view and the window fight over sizing every
        // frame until AppKit's constraint watchdog kills the app.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.layer?.isOpaque = false

        self.panel = panel
        return panel
    }
}

private final class RecordingBarPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        guard RecordingBarPresenter.shared.mode == .picker,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              event.charactersIgnoringModifiers?.lowercased() == "a" else {
            super.keyDown(with: event)
            return
        }
        RecordingBarPresenter.shared.captureLastRegion()
    }

    override func cancelOperation(_ sender: Any?) {
        // Escape backs out of picking a source; it must not abandon a
        // recording that's already running.
        guard RecordingBarPresenter.shared.mode == .picker else { return }
        RecordingBarPresenter.shared.dismiss()
        Task { await CameraRecordingManager.shared.stopPreview() }
    }
}

private final class RecordingBarHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    /// The panel is much larger than the bar - fixed size, so a morph never
    /// resizes the window, plus slack for tooltips and shadows. AppKit
    /// hit-tests by view bounds, not alpha, so without this all that empty
    /// space would silently swallow clicks meant for whatever is behind it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let bar = RecordingBarPresenter.shared.barFrameInPanel
        guard bar != .zero else { return nil }
        // SwiftUI reports a top-left origin, and NSHostingView is flipped, so
        // the two agree without conversion.
        guard bar.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - Bar

private struct RecordingBarView: View {
    @State private var presenter = RecordingBarPresenter.shared
    @State private var tooltip = BarTooltipModel()

    var body: some View {
        bar
            // The panel is a fixed size both modes sit inside, so a morph only
            // ever changes the bar's own width - never the window's. The bar
            // sits at the bottom: the slack above it is the tooltip's room,
            // the slack below is the shadow's.
            .padding(.bottom, BarMetrics.shadowSlack)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .coordinateSpace(.named(BarCoordinateSpace.panel))
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
        // The outgoing controls leave instantly so the bar starts narrowing
        // immediately; a fading-out set would hold its layout width and the
        // bar would visibly bulge to fit both before collapsing.
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .padding(.horizontal, BarMetrics.horizontalPadding)
        .frame(height: BarMetrics.height)
        // Clipped to the same shape the glass takes, so a morph reveals and
        // hides the controls behind the narrowing edge instead of letting
        // them spill past it.
        .clipShape(barShape)
        .glassEffect(.regular, in: barShape)
        .overlay {
            barShape.strokeBorder(BarMetrics.edge, lineWidth: 0.5)
        }
        .coordinateSpace(.named(BarCoordinateSpace.bar))
        .overlay(tooltipLayer)
        // What the hosting view hit-tests against and what satellite windows
        // anchor to - the bar, not the panel it floats in.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(BarCoordinateSpace.panel))
        } action: {
            presenter.barFrameInPanel = $0
        }
    }

    /// Positioned off the hovered control's measured frame rather than a
    /// hardcoded index, so it keeps tracking when the bar's contents change -
    /// a mode swap, or the display picker becoming a menu on a second monitor.
    private var tooltipLayer: some View {
        GeometryReader { _ in
            if let target = tooltip.visible {
                BarTooltipPill(text: target.text)
                    .position(
                        x: target.frame.midX,
                        y: -(BarTooltip.gap + BarTooltip.pillHeight / 2)
                    )
            }
        }
        .allowsHitTesting(false)
        // Keyed on the id as well as the text so sliding the pointer along
        // the bar glides the pill from control to control rather than
        // cross-fading it in place.
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.id)
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.text)
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BarMetrics.cornerRadius, style: .continuous)
    }
}
