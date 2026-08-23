import SwiftUI

struct RecordingStatusBarView: View {
    @State private var recorder = ScreenRecordingManager.shared
    @State private var presentation = RecordingBarPresentation.shared
    @State private var isPulsing = false

    private var isPaused: Bool { recorder.state == .paused }

    var body: some View {
        HStack(spacing: 0) {
            elapsed
            RecordingBarDivider()
            controls
        }
        .fixedSize()
        .frame(height: RecordingBarMetrics.height)
        .background(barBackground)
        .scaleEffect(presentation.isPresented ? 1 : 0.92, anchor: .bottom)
        .opacity(presentation.isPresented ? 1 : 0)
        .animation(RecordingMotion.showHideSpring, value: presentation.isPresented)
    }

    private var elapsed: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .frame(width: 8, height: 8)
                .opacity(isPaused ? 0.4 : 1)
                .shadow(color: .red.opacity(isPaused ? 0 : 0.5), radius: isPulsing ? 4 : 1)
                .onAppear { isPulsing = true }
                .animation(
                    RecordingMotion.reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text(formatTime(recorder.elapsedSeconds))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .contentTransition(.numericText())
                .animation(.default, value: recorder.elapsedSeconds)
                .frame(minWidth: 40, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused
                ? "Recording paused at \(formatTime(recorder.elapsedSeconds))"
                : "Recording, \(formatTime(recorder.elapsedSeconds)) elapsed"
        )
    }

    private var controls: some View {
        HStack(spacing: RecordingBarMetrics.itemSpacing) {
            RecordingBarIconButton(
                systemImage: isPaused ? "play.fill" : "pause.fill",
                accessibilityLabel: isPaused ? "Resume recording" : "Pause recording"
            ) {
                recorder.togglePause()
            }

            RecordingBarIconButton(
                systemImage: "stop.fill",
                tint: Color(nsColor: .systemRed),
                accessibilityLabel: "Stop and save recording"
            ) {
                Task {
                    RecordingStatusBarController.shared.dismiss()
                    if let url = await recorder.stopRecording() {
                        let record = HistoryStore.shared.referenceCapture(at: url, kind: .recording)
                        if let record {
                            let storeURL = HistoryStore.shared.urlForRecord(record)
                            PreviewOverlay.shared.show(url: storeURL)
                        }
                    }
                }
            }

            RecordingBarIconButton(
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Restart recording"
            ) {
                Task {
                    await recorder.cancelRecording()
                    let started = try? await recorder.startRecording()
                    if started != true {
                        RecordingStatusBarController.shared.dismiss()
                    }
                }
            }

            RecordingBarIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Discard recording"
            ) {
                Task {
                    RecordingStatusBarController.shared.dismiss()
                    await recorder.cancelRecording()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }

    private var barBackground: some View {
        RecordingBarMaterial()
            .clipShape(RoundedRectangle(cornerRadius: RecordingBarMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RecordingBarMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(RecordingBarMetrics.edge, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(RecordingBarMetrics.shadowOpacity), radius: RecordingBarMetrics.shadowRadius, y: RecordingBarMetrics.shadowY)
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct RecordingBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(RecordingBarMetrics.edge)
            .frame(width: 1, height: 18)
    }
}

@MainActor
final class RecordingStatusBarController {
    static let shared = RecordingStatusBarController()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(on preferredScreen: NSScreen? = nil) {
        hideTask?.cancel()
        hideTask = nil

        let panel = panel ?? makePanel()
        panel.setFrameOrigin(resolvedOrigin(for: panel.frame.size, preferredScreen: preferredScreen))
        panel.orderFrontRegardless()

        if let rect = ScreenRecordingManager.shared.activeRegionRect {
            RecordingAreaHighlightPresenter.shared.show(rect: rect, on: preferredScreen)
        }
        RecordingBarPresentation.shared.isPresented = true
    }

    func dismiss() {
        RecordingAreaHighlightPresenter.shared.hide()
        RecordingBarPresentation.shared.isPresented = false

        let panel = panel
        hideTask = Task { @MainActor [weak self] in
            let nanoseconds: UInt64 = RecordingMotion.reduceMotion ? 0 : 220_000_000
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            self?.hideTask = nil
        }
    }

    private func makePanel() -> NSPanel {
        let rootView = RecordingStatusBarView()
            .environment(\.colorScheme, .dark)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = NSPanel(
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
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            RecordingBarPositionStore.save(window.frame.origin)
        }

        self.panel = panel
        return panel
    }

    private func resolvedOrigin(for panelSize: NSSize, preferredScreen: NSScreen?) -> NSPoint {
        if let saved = RecordingBarPositionStore.load() {
            let savedFrame = NSRect(origin: saved, size: panelSize)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) {
                return saved
            }
        }
        let screen = preferredScreen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 16
        )
    }
}

/// Remembers the bar's dragged position across launches.
private enum RecordingBarPositionStore {
    private static let xKey = "bs_recbar_x"
    private static let yKey = "bs_recbar_y"

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
