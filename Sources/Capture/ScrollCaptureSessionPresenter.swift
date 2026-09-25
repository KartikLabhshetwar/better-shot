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
        controller.onStripAdded = { [weak self, weak controller] count in
            guard self?.continuation != nil, let controller else { return }
            model.isStarting = false
            model.stripCount = count
            model.isHorizontal = controller.isHorizontalCapture
            model.pixelLength = Int(model.isHorizontal
                ? controller.stitchedPixelSize.width : controller.stitchedPixelSize.height)
        }
        controller.onTrackingChanged = { [weak self] isTracking in
            guard self?.continuation != nil else { return }
            model.isLost = !isTracking
            if !isTracking {
                AccessibilityNotification.Announcement(ScrollCaptureSessionView.lostMessage).post()
            }
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
        controller.excludedWindowIDs = [panel, previewPanel, selectionPanel].compactMap { $0.map { CGWindowID($0.windowNumber) } }
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
        let size = NSSize(width: 312, height: 148)
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
        controller?.onTrackingChanged = nil
        controller?.onAutoScrollChanged = nil
        controller?.onStatusMessage = nil
        controller?.onPreviewUpdated = nil
        if let keyMonitorGlobal { NSEvent.removeMonitor(keyMonitorGlobal) }
        if let keyMonitorLocal { NSEvent.removeMonitor(keyMonitorLocal) }
        keyMonitorGlobal = nil
        keyMonitorLocal = nil
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
    var isHorizontal = false
    var isLost = false
    var stripCount = 0
    var pixelLength = 0
}

struct ScrollCaptureSessionView: View {
    static let lostMessage = "Lost track. Scroll back a little, then slower."

    @State var model: ScrollCaptureSessionModel
    let stop: () -> Void
    let cancel: () -> Void
    var toggleAutoScroll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: model.isLost ? "exclamationmark.triangle.fill"
                      : model.isHorizontal ? "arrow.right.to.line" : "arrow.down.to.line")
                    .foregroundStyle(model.isLost ? Color.orange : BarMetrics.activeTint.opacity(0.75))
                Text("Scrolling Capture")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BarMetrics.activeTint)
                Spacer()
            }

            Text(model.statusMessage ?? (model.isStarting ? "Preparing area…"
                 : model.isLost ? Self.lostMessage : model.isAutoScrolling ? "Scrolling automatically…" : "Scroll the area, then Stop."))
                .font(.system(size: 11))
                .foregroundStyle(BarMetrics.activeTint.opacity(model.isLost ? 1 : 0.75))
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("\(model.stripCount) strips · \(model.pixelLength) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BarMetrics.activeTint.opacity(0.75))
                    .lineLimit(1)
                    .accessibilityLabel("\(model.stripCount) captured frames, \(model.pixelLength) pixels \(model.isHorizontal ? "wide" : "high")")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(model.isAutoScrolling ? "Pause Scroll" : "Auto Scroll", action: toggleAutoScroll)
                    .disabled(model.isStarting || model.isHorizontal)
                    .accessibilityLabel(model.isAutoScrolling ? "Pause Automatic Scrolling" : "Start Automatic Scrolling")
                    .accessibilityIdentifier("scrollCaptureAutoScroll")
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .accessibilityLabel("Cancel Scrolling Capture")
                    .accessibilityIdentifier("scrollCaptureCancel")
                Button("Stop", action: stop)
                    .disabled(model.isStarting)
                    .opacity(model.isStarting ? 0.45 : 1)
                    .accessibilityLabel("Stop Scrolling Capture")
                    .accessibilityIdentifier("scrollCaptureStop")
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 312, height: 148)
        .glassSurface(cornerRadius: 12, depth: .raised)
    }

}
