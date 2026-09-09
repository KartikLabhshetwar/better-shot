//
//  RecordingControlPresenter.swift
//  BetterShot
//
//  Created by Codex on 01/05/26.
//
//  The in-session mode of the floating bar: elapsed time and the transport
//  controls for the recording that's running. It shares its panel and chrome
//  with the pre-record picker (RecordingPickerBar), so starting a recording
//  morphs one into the other instead of swapping windows.
//

import AppKit
import SwiftUI

/// Retained as the entry point callers already use; the bar itself is owned
/// by RecordingBarPresenter.
@MainActor
enum RecordingControlPresenter {
    static var shared: RecordingBarPresenter { RecordingBarPresenter.shared }
}

extension RecordingBarPresenter {
    func show(displayID: CGDirectDisplayID?) {
        showRecording(displayID: displayID)
    }
}

// MARK: - Controls

struct RecordingSessionControls: View {
    @State private var manager = ScreenRecordingManager.shared
    @State private var confirmsRestart = false
    @State private var confirmsDiscard = false

    private var isPaused: Bool {
        manager.state == .paused
    }

    /// Starting and finishing are both moments where the transport can't
    /// safely be driven - the capture graph is being wired up or torn down.
    private var isSettling: Bool {
        manager.state == .starting || manager.state == .finishing
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { manager.stopRecording() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.circle").font(.system(size: 20))
                    Text(manager.formattedElapsedTime)
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .frame(minWidth: 48, alignment: .leading)
                }
                .foregroundStyle(BarMetrics.recordTint)
                .padding(.horizontal, 12)
                .frame(height: BarMetrics.recordingHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(BarButtonStyle())
            .disabled(isSettling)
            .help("Stop and save the recording")
            .accessibilityLabel("Stop and save recording, \(manager.formattedElapsedTime) elapsed")

            separator
            BarActionButton(
                id: .pauseResume,
                title: isPaused ? "Resume recording" : "Pause recording",
                systemImage: isPaused ? "play.circle" : "pause.circle"
            ) {
                if isPaused { manager.resumeRecording() }
                else { manager.pauseRecording() }
            }
            .frame(width: 48)
            .disabled(isSettling)

            separator
            BarActionButton(id: .restart, title: "Start over", systemImage: "arrow.counterclockwise") {
                confirmsRestart = true
            }
            .frame(width: 48)
            .disabled(isSettling)

            separator
            BarActionButton(id: .discard, title: "Discard recording", systemImage: "trash") {
                confirmsDiscard = true
            }
            .frame(width: 48)
            .disabled(isSettling)
        }
        .alert("Start a new recording?", isPresented: $confirmsRestart) {
            Button("Start Over", role: .destructive) { manager.restartRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be discarded and recording will start again.")
        }
        .alert("Discard this recording?", isPresented: $confirmsDiscard) {
            Button("Discard", role: .destructive) { manager.deleteRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be deleted without saving.")
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(BarMetrics.edge)
            .frame(width: 1, height: BarMetrics.recordingHeight)
    }
}
