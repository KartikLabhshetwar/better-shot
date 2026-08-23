import SwiftUI

/// The in-session half of the recording bar: elapsed time plus pause/stop/restart/discard. Hosted by `RecordingBarPresenter` once a recording starts.
struct RecordingSessionControls: View {
    @State private var recorder = ScreenRecordingManager.shared
    @State private var isPulsing = false

    private var isPaused: Bool { recorder.state == .paused }
    private var isSettling: Bool { recorder.state == .preparing || recorder.state == .stopping }

    var body: some View {
        HStack(spacing: 0) {
            elapsed
            RecordingBarDivider()
            controls
        }
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
            .disabled(isSettling)

            RecordingBarIconButton(
                systemImage: "stop.fill",
                tint: Color(nsColor: .systemRed),
                accessibilityLabel: "Stop and save recording"
            ) {
                Task {
                    RecordingBarPresenter.shared.hide()
                    if let url = await recorder.stopRecording() {
                        let record = HistoryStore.shared.referenceCapture(at: url, kind: .recording)
                        if let record {
                            let storeURL = HistoryStore.shared.urlForRecord(record)
                            PreviewOverlay.shared.show(url: storeURL)
                        }
                    }
                }
            }
            .disabled(isSettling)

            RecordingBarIconButton(
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Restart recording"
            ) {
                Task {
                    await recorder.cancelRecording()
                    let started = try? await recorder.restartRecording()
                    if started != true {
                        RecordingBarPresenter.shared.hide()
                    }
                }
            }
            .disabled(isSettling)

            RecordingBarIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Discard recording"
            ) {
                Task {
                    RecordingBarPresenter.shared.hide()
                    await recorder.cancelRecording()
                }
            }
            .disabled(recorder.state == .preparing)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
