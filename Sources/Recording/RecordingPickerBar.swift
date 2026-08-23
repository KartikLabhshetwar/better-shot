import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// The pre-recording half of the recording bar: pick a source, toggle audio inputs, set a start delay. Ported from screendrop's RecordingPickerBar (github.com/fayazara/screendrop, CC0-1.0), trimmed to BetterShot's chrome and capture APIs.
struct RecordingPickerControls: View {
    private static let delayOptions = [0, 1, 3, 5]

    @State private var sources = RecordingSourceCatalog.shared
    @State private var captureMicrophone = AppPreferences.recordingCaptureMicrophone
    @State private var captureSystemAudio = AppPreferences.recordingCaptureAudio
    @State private var startDelaySeconds = AppPreferences.recordingStartDelaySeconds
    @State private var camera = CameraBubbleController.shared

    private func toggleMicrophone() {
        guard !captureMicrophone else {
            captureMicrophone = false
            AppPreferences.recordingCaptureMicrophone = false
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                captureMicrophone = granted
                AppPreferences.recordingCaptureMicrophone = granted
                if !granted {
                    ToastWindow.shared.show(
                        title: "Microphone Blocked",
                        message: "Allow BetterShot in System Settings > Privacy & Security > Microphone.",
                        systemIcon: "mic.slash"
                    )
                }
            }
        }
    }

    var body: some View {
        HStack(spacing: RecordingBarMetrics.itemSpacing) {
            displaySource
            windowSource

            RecordingBarIconButton(systemImage: "rectangle.dashed", accessibilityLabel: "Area, drag to select the region to record") {
                startAreaRecording()
            }

            RecordingBarDivider()

            if ScreenCaptureStream.supportsMicrophoneCapture {
                RecordingBarIconButton(
                    systemImage: captureMicrophone ? "mic.fill" : "mic.slash",
                    tint: captureMicrophone ? RecordingBarMetrics.activeTint : RecordingBarMetrics.inactiveTint,
                    accessibilityLabel: captureMicrophone ? "Microphone on" : "Microphone off"
                ) {
                    toggleMicrophone()
                }
            }

            if camera.hasCamera {
                RecordingBarIconButton(
                    systemImage: camera.isEnabled ? "video.fill" : "video.slash",
                    tint: camera.isEnabled ? RecordingBarMetrics.activeTint : RecordingBarMetrics.inactiveTint,
                    accessibilityLabel: camera.isEnabled ? "Face cam on" : "Face cam off"
                ) {
                    camera.toggle()
                }
                .disabled(camera.isStarting)
                .contextMenu {
                    ForEach(CameraBubbleController.Size.allCases) { size in
                        Button(size.label) { camera.resize(to: size) }
                    }
                }
            }

            RecordingBarIconButton(
                systemImage: captureSystemAudio ? "speaker.wave.2.fill" : "speaker.slash",
                tint: captureSystemAudio ? RecordingBarMetrics.activeTint : RecordingBarMetrics.inactiveTint,
                accessibilityLabel: captureSystemAudio ? "System audio on" : "System audio off"
            ) {
                captureSystemAudio.toggle()
                AppPreferences.recordingCaptureAudio = captureSystemAudio
            }

            delayMenu

            RecordingBarIconButton(systemImage: "xmark", accessibilityLabel: "Close the recorder") {
                camera.suspend()
                RecordingBarPresenter.shared.hide()
            }
        }
        .padding(.horizontal, RecordingBarMetrics.horizontalPadding)
    }

    @ViewBuilder
    private var displaySource: some View {
        if sources.displays.count > 1 {
            Menu {
                ForEach(Array(sources.displays.enumerated()), id: \.element.displayID) { index, display in
                    Button(RecordingSourceCatalog.displayTitle(display, index: index)) {
                        beginRecording(on: ActiveDisplayResolver.screen(for: display.displayID)) {
                            try await ScreenRecordingManager.shared.startDisplayRecording(displayID: display.displayID)
                        }
                    }
                }
            } label: {
                RecordingBarIconLabel(systemImage: "menubar.rectangle", accessibilityLabel: "Display, choose which screen to record")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        } else {
            RecordingBarIconButton(systemImage: "menubar.rectangle", accessibilityLabel: "Display, record the whole screen") {
                guard let display = sources.displays.first else { return }
                beginRecording(on: ActiveDisplayResolver.screen(for: display.displayID)) {
                    try await ScreenRecordingManager.shared.startDisplayRecording(displayID: display.displayID)
                }
            }
        }
    }

    private var windowSource: some View {
        Menu {
            if sources.windows.isEmpty {
                Text("No app windows found")
            }
            ForEach(sources.windows, id: \.windowID) { window in
                Button(RecordingSourceCatalog.windowTitle(window)) {
                    beginRecording(on: nil) {
                        try await ScreenRecordingManager.shared.startWindowRecording(windowID: window.windowID)
                    }
                }
            }
            Divider()
            Button("Refresh Windows") {
                Task { await sources.refresh() }
            }
        } label: {
            RecordingBarIconLabel(systemImage: "macwindow", accessibilityLabel: "Window, choose an app window to record")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var delayMenu: some View {
        Menu {
            ForEach(Self.delayOptions, id: \.self) { seconds in
                Button {
                    startDelaySeconds = seconds
                    AppPreferences.recordingStartDelaySeconds = seconds
                } label: {
                    if startDelaySeconds == seconds {
                        Label(delayLabel(seconds), systemImage: "checkmark")
                    } else {
                        Text(delayLabel(seconds))
                    }
                }
            }
        } label: {
            RecordingBarIconLabel(
                systemImage: "timer",
                tint: startDelaySeconds == 0 ? RecordingBarMetrics.inactiveTint : RecordingBarMetrics.activeTint,
                accessibilityLabel: startDelaySeconds == 0 ? "Start delay off" : "Start delay \(startDelaySeconds) seconds"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func delayLabel(_ seconds: Int) -> String {
        seconds == 0 ? "No delay" : "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    private func startAreaRecording() {
        RecordingBarPresenter.shared.hide()
        Task {
            let started = (try? await ScreenRecordingManager.shared.startAreaRecording(afterSelection: runStartDelay)) ?? false
            if started {
                RecordingBarPresenter.shared.showRecording()
            }
        }
    }

    private func beginRecording(on screen: NSScreen?, _ start: @escaping () async throws -> Bool) {
        Task {
            await runStartDelay()
            let started = (try? await start()) ?? false
            if started {
                RecordingBarPresenter.shared.showRecording(on: screen)
            }
        }
    }

    private func runStartDelay() async {
        let delay = AppPreferences.recordingStartDelaySeconds
        guard delay > 0 else { return }
        await CountdownOverlay.shared.showCountdown(seconds: delay)
    }
}
