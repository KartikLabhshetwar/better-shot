import SwiftUI

struct RecordingStatusBarView: View {
    @State private var recorder = ScreenRecordingManager.shared
    @State private var isPulsing = false

    private var isPaused: Bool { recorder.state == .paused }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (isPaused ? Color.orange : Color.red).opacity(0.5), radius: isPulsing ? 4 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                Text(formatTime(recorder.elapsedSeconds))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: recorder.elapsedSeconds)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 18)

            HStack(spacing: 2) {
                iconButton(icon: isPaused ? "play.fill" : "pause.fill") {
                    recorder.togglePause()
                }

                iconButton(icon: "stop.fill", tint: .red) {
                    Task {
                        RecordingStatusBarController.shared.dismiss()
                        if let url = await recorder.stopRecording() {
                            let record = HistoryStore.shared.importCapture(from: url, deleteSource: true, kind: .recording)
                            if let record {
                                let storeURL = HistoryStore.shared.urlForRecord(record)
                                PreviewOverlay.shared.show(url: storeURL)
                            }
                        }
                    }
                }

                iconButton(icon: "arrow.counterclockwise") {
                    Task {
                        await recorder.cancelRecording()
                        let started = try? await recorder.startRecording()
                        if started != true {
                            RecordingStatusBarController.shared.dismiss()
                        }
                    }
                }

                iconButton(icon: "xmark") {
                    Task {
                        RecordingStatusBarController.shared.dismiss()
                        await recorder.cancelRecording()
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
        }
        .fixedSize()
        .frame(height: 40)
        .background(
            Capsule()
                .fill(Color(white: 0.1))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        )
    }

    private func iconButton(icon: String, tint: Color = Color.white.opacity(0.85), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(RecordingIconButtonStyle())
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct RecordingIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { isHovered = $0 }
    }
}

@MainActor
final class RecordingStatusBarController {
    static let shared = RecordingStatusBarController()
    private var panel: NSPanel?

    private init() {}

    func show(on preferredScreen: NSScreen? = nil) {
        if panel == nil {
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
            self.panel = panel
        }

        let screen = preferredScreen ?? NSScreen.main
        guard let panel, let screen else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
