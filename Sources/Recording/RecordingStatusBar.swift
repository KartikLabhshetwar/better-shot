import SwiftUI

struct RecordingStatusBarView: View {
    let recorder = ScreenRecordingManager.shared
    @State private var isPulsing = false

    private var isPaused: Bool { recorder.state == .paused }

    var body: some View {
        HStack(spacing: 0) {
            // Recording indicator + timer
            HStack(spacing: 10) {
                Circle()
                    .fill(isPaused ? .orange : .red)
                    .frame(width: 10, height: 10)
                    .shadow(color: (isPaused ? Color.orange : Color.red).opacity(0.5), radius: isPulsing ? 6 : 2)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                Text(formatTime(recorder.elapsedSeconds))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if isPaused {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)

            // Separator
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 24)

            // Controls
            HStack(spacing: 4) {
                // Pause / Resume
                pillButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    label: isPaused ? "Resume" : "Pause",
                    color: .white
                ) {
                    recorder.togglePause()
                }

                // Stop
                pillButton(
                    icon: "stop.fill",
                    label: "Stop",
                    color: .red
                ) {
                    Task {
                        RecordingStatusBarController.shared.dismiss()
                        if let url = await recorder.stopRecording() {
                            let record = HistoryStore.shared.importCapture(from: url, deleteSource: true, kind: .recording)
                            if let record {
                                let storeURL = HistoryStore.shared.urlForRecord(record)
                                if let exportedURL = await VideoEditorModel.autoExportWithDefaults(url: storeURL) {
                                    HistoryStore.shared.setBeautifiedPath(exportedURL.path, for: record.id)
                                    PreviewOverlay.shared.show(url: exportedURL)
                                } else {
                                    PreviewOverlay.shared.show(url: storeURL)
                                }
                            }
                        }
                    }
                }

                // Discard
                pillButton(
                    icon: "trash",
                    label: "Discard",
                    color: .white.opacity(0.5)
                ) {
                    Task {
                        RecordingStatusBarController.shared.dismiss()
                        await recorder.cancelRecording()
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 48)
        .background {
            Capsule()
                .fill(.black.opacity(0.7))
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
        }
    }

    private func pillButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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

    func show(on preferredScreen: NSScreen? = nil) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
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
            panel.contentView = NSHostingView(rootView: RecordingStatusBarView())
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
    }
}
