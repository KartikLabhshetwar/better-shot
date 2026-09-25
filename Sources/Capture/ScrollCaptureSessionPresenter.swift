import AppKit
import SwiftUI

/// Keeps the capture controls visible while the selected content is scrolled.
@MainActor
final class ScrollCaptureSessionPresenter {
    static let shared = ScrollCaptureSessionPresenter()

    enum Result {
        case completed(CGImage)
        case cancelled
        case failed
    }

    private var controller: ScrollCaptureController?
    private var panel: NSPanel?
    private var previewPanel: ScrollCapturePreviewPanel?
    private var selectionPanel: NSPanel?
    private var keyMonitorGlobal: Any?
    private var keyMonitorLocal: Any?
    private var mouseMoveTap: CFMachPort?
    private var mouseMoveTapSource: CFRunLoopSource?
    private var continuation: CheckedContinuation<Result, Never>?

    private init() {}

    var isActive: Bool { continuation != nil }

    func stop() {
        controller?.stopSession()
    }

    func capture(rect: CGRect, on screen: NSScreen) async -> Result {
        guard continuation == nil else { return .cancelled }

        let controller = ScrollCaptureController(captureRect: rect, screen: screen)
        let model = ScrollCaptureSessionModel()
        self.controller = controller
        controller.onStripAdded = { [weak self, weak controller] _ in
            guard self?.continuation != nil, let controller else { return }
            model.isStarting = false
            let pixels = controller.stitchedPixelSize
            model.pointSize = CGSize(width: pixels.width / screen.backingScaleFactor,
                                     height: pixels.height / screen.backingScaleFactor)
        }
        controller.onSessionDone = { [weak self, weak controller] image in
            guard let self else { return }
            if image != nil, let pixels = controller?.stitchedImage {
                self.finish(.completed(pixels))
            } else {
                self.finish(.failed)
            }
        }

        let outline = NSPanel(contentRect: rect.insetBy(dx: -1, dy: -1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        outline.isOpaque = false
        outline.backgroundColor = .clear
        outline.hasShadow = false
        outline.level = .floating
        outline.sharingType = .none
        outline.hidesOnDeactivate = false
        outline.ignoresMouseEvents = true
        outline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        outline.contentView = NSHostingView(rootView: Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 2).accessibilityHidden(true))
        outline.orderFrontRegardless()
        selectionPanel = outline
        controller.onAutoScrollChanged = { active in model.isAutoScrolling = active }
        controller.onStatusMessage = { message in model.statusMessage = message }
        let preview = ScrollCapturePreviewPanel(captureRect: rect, screen: screen)
        previewPanel = preview
        controller.onPreviewUpdated = { [weak preview] image in
            preview?.updatePreview(image: image)
        }
        preview?.orderFrontRegardless()
        present(model: model, rect: rect, on: screen)
        controller.captureBelowWindowID = CGWindowID(outline.windowNumber)
        if ShortcutService.hasAccessibilityPermission { installMouseMoveSuppression() }
        keyMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }
        keyMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { await controller.startSession() }
        }
    }

    private func cancel() {
        controller?.cancelSession()
        finish(.cancelled)
    }

    /// Swallows mouse-moved events while capturing so hover effects in the target app don't change the frames being stitched.
    private func installMouseMoveSuppression() {
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
            callback: { _, _, _, _ in nil }, userInfo: nil) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mouseMoveTap = tap
        mouseMoveTapSource = source
    }

    private func removeMouseMoveSuppression() {
        if let mouseMoveTap {
            CGEvent.tapEnable(tap: mouseMoveTap, enable: false)
            CFMachPortInvalidate(mouseMoveTap)
        }
        if let mouseMoveTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseMoveTapSource, .commonModes) }
        mouseMoveTap = nil
        mouseMoveTapSource = nil
    }

    // MacShot's selection-relative HUD placement, including the notch-safe fallback.
    static func panelFrame(size: NSSize, selection: NSRect, screenFrame: NSRect,
                           visibleFrame: NSRect, topInset: CGFloat) -> NSRect {
        var y = selection.minY - size.height - 6
        if y < visibleFrame.minY + 4 { y = selection.maxY + 6 }
        let topLimit = min(visibleFrame.maxY, screenFrame.maxY - topInset) - 4
        y = max(visibleFrame.minY + 4, min(y, topLimit - size.height))
        let x = max(visibleFrame.minX + 4,
            min(selection.midX - size.width / 2, visibleFrame.maxX - size.width - 4))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func present(model: ScrollCaptureSessionModel, rect: NSRect, on screen: NSScreen) {
        let view = ScrollCaptureSessionView(model: model,
            stop: { [weak self] in self?.stop() },
            cancel: { [weak self] in self?.cancel() },
            toggleAutoScroll: { [weak self] in self?.controller?.toggleAutoScroll() })
        let hostingView = NSHostingView(rootView: view)
        let size = ScrollCaptureSessionView.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("BetterShot.ScrollCaptureControls")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        panel.setFrame(Self.panelFrame(size: size, selection: rect,
            screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            topInset: screen.safeAreaInsets.top), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func finish(_ result: Result) {
        guard let continuation else { return }
        self.continuation = nil
        controller?.onStripAdded = nil
        controller?.onSessionDone = nil
        controller?.onAutoScrollChanged = nil
        controller?.onStatusMessage = nil
        controller?.onPreviewUpdated = nil
        if let keyMonitorGlobal { NSEvent.removeMonitor(keyMonitorGlobal) }
        if let keyMonitorLocal { NSEvent.removeMonitor(keyMonitorLocal) }
        keyMonitorGlobal = nil
        keyMonitorLocal = nil
        removeMouseMoveSuppression()
        previewPanel?.orderOut(nil)
        previewPanel = nil
        selectionPanel?.orderOut(nil)
        selectionPanel = nil
        panel?.orderOut(nil)
        panel = nil
        controller = nil
        continuation.resume(returning: result)
    }
}

@MainActor
@Observable
final class ScrollCaptureSessionModel {
    var statusMessage: String?
    var isStarting = true
    var isAutoScrolling = false
    var pointSize: CGSize = .zero
}

struct ScrollCaptureSessionView: View {
    static let size = NSSize(width: 400, height: 36)

    @State var model: ScrollCaptureSessionModel
    let stop: () -> Void
    let cancel: () -> Void
    var toggleAutoScroll: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BarMetrics.activeTint.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel Scrolling Capture")
            .accessibilityIdentifier("scrollCaptureCancel")

            status
                .frame(maxWidth: .infinity, alignment: .leading)

            pillButton(model.isAutoScrolling ? "Scrolling…" : "Auto Scroll",
                       tint: model.isAutoScrolling ? .orange : .blue, width: 90, action: toggleAutoScroll)
                .disabled(model.isStarting)
                .opacity(model.isStarting ? 0.7 : 1)
                .accessibilityLabel(model.isAutoScrolling ? "Pause Automatic Scrolling" : "Start Automatic Scrolling")
                .accessibilityIdentifier("scrollCaptureAutoScroll")

            pillButton("Stop", tint: .red, width: 56, action: stop)
                .accessibilityLabel("Stop Scrolling Capture")
                .accessibilityIdentifier("scrollCaptureStop")
        }
        .padding(.horizontal, 8)
        .frame(width: Self.size.width, height: Self.size.height)
        .glassSurface(cornerRadius: 12, depth: .raised)
    }

    @ViewBuilder private var status: some View {
        if let message = model.statusMessage {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(BarMetrics.activeTint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.pointSize.width > 0 && model.pointSize.height > 0 {
            let width = Int(model.pointSize.width)
            let height = Int(model.pointSize.height)
            Text("Scroll Capture  ·  \(width)×\(height)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(BarMetrics.activeTint)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("Scroll Capture, \(width) by \(height) points")
        } else {
            Text("Scroll Capture")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BarMetrics.activeTint)
                .lineLimit(1)
        }
    }

    private func pillButton(_ title: String, tint: Color, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width, height: 24)
                .background(tint.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
