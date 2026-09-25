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

        present(model: model, on: screen)
        controller.excludedWindowIDs = panel.map { [CGWindowID($0.windowNumber)] } ?? []

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { await controller.startSession() }
        }
    }

    private func present(model: ScrollCaptureSessionModel, on screen: NSScreen) {
        let view = ScrollCaptureSessionView(model: model,
            stop: { [weak self] in self?.stop() },
            cancel: { [weak self] in
                self?.controller?.cancelSession()
                self?.finish(.cancelled)
            })
        let hostingView = NSHostingView(rootView: view)
        let size = NSSize(width: 312, height: 116)
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
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - size.width - 16,
                                   y: screen.visibleFrame.maxY - size.height - 16))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func finish(_ result: Result) {
        guard let continuation else { return }
        self.continuation = nil
        controller?.onStripAdded = nil
        controller?.onSessionDone = nil
        controller?.onTrackingChanged = nil
        panel?.orderOut(nil)
        panel = nil
        controller = nil
        continuation.resume(returning: result)
    }
}

@MainActor
@Observable
final class ScrollCaptureSessionModel {
    var isStarting = true
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

            Text(model.isStarting ? "Preparing area…"
                 : model.isLost ? Self.lostMessage : "Scroll the area, then Stop.")
                .font(.system(size: 11))
                .foregroundStyle(BarMetrics.activeTint.opacity(model.isLost ? 1 : 0.75))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("\(model.stripCount) strips · \(model.pixelLength) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BarMetrics.activeTint.opacity(0.75))
                    .lineLimit(1)
                    .accessibilityLabel("\(model.stripCount) captured frames, \(model.pixelLength) pixels \(model.isHorizontal ? "wide" : "high")")
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
        .frame(width: 312, height: 116)
        .glassSurface(cornerRadius: 12, depth: .raised)
    }

}
