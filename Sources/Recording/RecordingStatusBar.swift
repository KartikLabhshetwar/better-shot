import SwiftUI

/// The in-session half of the recording bar: elapsed time plus pause/stop/restart/discard. Hosted by `RecordingBarPresenter` once a recording starts.
struct RecordingSessionControls: View {
    @State private var recorder = ScreenRecordingManager.shared

    private var isPaused: Bool { recorder.state == .paused }
    private var isSettling: Bool { recorder.state == .preparing || recorder.state == .stopping }

    var body: some View {
        HStack(spacing: 0) {
            elapsed
            RecordingBarDivider()
            controls
        }
        .padding(.horizontal, RecordingBarMetrics.horizontalPadding)
    }

    private var elapsed: some View {
        HStack(spacing: 8) {
            RecordingLiveDot(isPaused: isPaused)

            Text(formatTime(recorder.elapsedSeconds))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .contentTransition(.numericText(countsDown: false))
                .animation(.easeOut(duration: 0.18), value: recorder.elapsedSeconds)
                .frame(width: timeWidth, alignment: .leading)
        }
        .padding(.trailing, 2)
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
                id: "pauseResume",
                title: isPaused ? "Resume recording" : "Pause recording",
                systemImage: isPaused ? "play.fill" : "pause.fill",
                accessibilityLabel: isPaused ? "Resume recording" : "Pause recording"
            ) {
                recorder.togglePause()
            }
            .disabled(isSettling)

            RecordingBarIconButton(
                id: "stop",
                title: "Stop and save",
                systemImage: "stop.fill",
                tint: Color(nsColor: .systemRed),
                accessibilityLabel: "Stop and save recording"
            ) {
                Task {
                    CameraBubbleController.shared.suspend()
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
                id: "restart",
                title: "Start over",
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Restart recording"
            ) {
                Task {
                    let started = try? await recorder.restartRecording()
                    if started != true {
                        RecordingBarPresenter.shared.hide()
                    }
                }
            }
            .disabled(isSettling)

            RecordingBarIconButton(
                id: "discard",
                title: "Discard recording",
                systemImage: "xmark",
                accessibilityLabel: "Discard recording"
            ) {
                Task {
                    CameraBubbleController.shared.suspend()
                    RecordingBarPresenter.shared.hide()
                    await recorder.cancelRecording()
                }
            }
            .disabled(recorder.state == .preparing)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }

    /// Fixed rather than intrinsic, so the controls beside it do not shift every time a digit changes width.
    private var timeWidth: CGFloat {
        recorder.elapsedSeconds >= 3600 ? 66 : 44
    }

    private func formatTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}

/// Pulses only while actually recording: a paused session shows a steady dimmed dot, and reduced motion gets no pulse at all.
private struct RecordingLiveDot: View {
    let isPaused: Bool

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color(nsColor: .systemRed))
            .frame(width: 8, height: 8)
            .opacity(isPaused ? 0.4 : (isPulsing ? 0.55 : 1))
            .shadow(color: .red.opacity(isPaused ? 0 : 0.55), radius: isPulsing ? 4 : 1)
            .animation(pulse, value: isPulsing)
            .onAppear { isPulsing = !isPaused && !RecordingMotion.reduceMotion }
            .onChange(of: isPaused) { _, paused in
                isPulsing = !paused && !RecordingMotion.reduceMotion
            }
    }

    private var pulse: Animation? {
        guard isPulsing else { return .easeOut(duration: 0.2) }
        return .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }
}
