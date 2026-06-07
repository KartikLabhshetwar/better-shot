import SwiftUI

struct RecordingStatusBarView: View {
    let recorder = ScreenRecordingManager.shared
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(recorder.state == .paused ? .orange : .red)
                    .frame(width: 8, height: 8)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                Text(formatTime(recorder.elapsedSeconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }

            Divider().frame(height: 14)

            Button {
                recorder.togglePause()
            } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(recorder.state == .paused ? "Resume" : "Pause")

            Button {
                Task {
                    RecordingStatusBarController.shared.dismiss()
                    if let url = await recorder.stopRecording() {
                        let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
                        ToastWindow.shared.show(
                            message: "Recording saved!",
                            icon: appIcon
                        )
                        PreviewOverlay.shared.show(url: url)
                    }
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")

            Divider().frame(height: 14)

            Button {
                Task {
                    RecordingStatusBarController.shared.dismiss()
                    await recorder.cancelRecording()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Discard Recording")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

@MainActor
final class RecordingStatusBarController {
    static let shared = RecordingStatusBarController()
    private var panel: NSPanel?

    private init() {}

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
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
            panel.contentView = NSHostingView(rootView: RecordingStatusBarView())
            self.panel = panel
        }

        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }
}
