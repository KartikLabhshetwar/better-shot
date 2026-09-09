//
//  RecordingPickerBar.swift
//  BetterShot
//
//  The pre-record mode of the floating bar. "Record" anywhere in the app
//  brings the bar up at the bottom of the active screen; it picks the source
//  (display / window / area) and toggles the capture inputs (camera,
//  microphone, system audio) for the next recording, then hands off to
//  CaptureCoordinator - at which point the same bar morphs into the in-session
//  controls (RecordingControlPresenter). Clicks and keystrokes are always
//  logged to the session sidecar; whether they appear is decided later in
//  Studio.
//
//  The panel, the chrome and the morph live in RecordingBarPresenter.
//

import AppKit
import ScreenCaptureKit
import SwiftUI

/// Retained as the entry point callers already use; the bar itself is owned
/// by RecordingBarPresenter.
@MainActor
enum RecordingPickerPresenter {
    static var shared: RecordingBarPresenter { RecordingBarPresenter.shared }
}

extension RecordingBarPresenter {
    func toggle() {
        togglePicker()
    }

    func show() {
        showPicker()
    }
}

// MARK: - Controls

struct RecordingPickerControls: View {
    @State private var sources = RecordingSourceCatalog.shared
    @AppStorage(BetterShotPreferences.recordingCameraDeviceIDKey) private var cameraID = ""
    @AppStorage(BetterShotPreferences.recordingMicrophoneDeviceIDKey) private var microphoneID = ""
    @AppStorage(BetterShotPreferences.recordingSystemAudioKey) private var systemAudio = false
    @AppStorage(BetterShotPreferences.recordingStartDelaySecondsKey) private var startDelaySeconds = 0
    @AppStorage(BetterShotPreferences.recordingTeleprompterEnabledKey) private var teleprompterEnabled = false

    @State private var showsRecordingOptions = false

    private static let timerOptions = [0, 1, 3, 5]

    var body: some View {
        HStack(spacing: 4) {
            screenshotGroup
            BarDivider()
            timerMenu
            Button { showsRecordingOptions.toggle() } label: {
                BarActionLabel(id: .recording, title: "Recording options", systemImage: "video",
                               caption: "Recording")
            }
            .buttonStyle(BarButtonStyle())
            .accessibilityLabel("Recording options")
            .popover(isPresented: $showsRecordingOptions, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording").font(.headline)
                    Text("Choose a source to start recording.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if sources.isLoading {
                        ProgressView("Loading recording sources…")
                    }
                    if let error = sources.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Try Again") { Task { await sources.refresh() } }
                    }
                    recordingOptions.disabled(sources.isLoading)
                }
                .padding(20)
                .task { await sources.refresh() }
            }
            BarActionButton(id: .close, title: "Close", systemImage: "xmark",
                            accessibility: "Close capture bar — Esc") {
                dismissPicker()
            }
        }
    }

    private var recordingOptions: some View {
        HStack(spacing: 8) {
            displaySource
            windowSource
            BarActionButton(
                id: .area,
                title: "Drag to select a region",
                systemImage: "rectangle.dashed", caption: "Area",
                accessibility: "Area - drag to select the region to record"
            ) {
                startAreaRecording()
            }

            BarDivider()

            inputToggle(
                id: .camera,
                caption: "Camera",
                title: cameraID.isEmpty ? "Camera off" : "Camera on",
                isOn: !cameraID.isEmpty,
                onIcon: "video.fill",
                offIcon: "video.slash",
                accessibility: cameraAccessibilityLabel
            ) {
                toggleCamera()
            }
            .contextMenu {
                cameraDeviceMenu
            }

            microphonePicker

            inputToggle(
                id: .systemAudio,
                caption: "Audio",
                title: systemAudio ? "System audio on" : "System audio off",
                isOn: systemAudio,
                onIcon: "speaker.wave.2.fill",
                offIcon: "speaker.slash",
                accessibility: systemAudio
                    ? "System audio on - click to stop capturing what you hear"
                    : "System audio off - click to capture what you hear"
            ) {
                systemAudio.toggle()
            }

            inputToggle(
                id: .teleprompter,
                caption: "Script",
                title: teleprompterEnabled ? "Teleprompter on" : "Teleprompter off",
                isOn: teleprompterEnabled,
                onIcon: "text.pad.header",
                offIcon: "text.pad.header",
                accessibility: teleprompterEnabled
                    ? "Teleprompter on - click to edit the script"
                    : "Teleprompter off - click to write a script"
            ) {
                TeleprompterComposerPresenter.shared.toggle()
            }

        }
    }

    // MARK: Screenshots

    private static let screenshotActions: [(BarTooltipID, ShortcutService.Action, String, String)] = [
        (.screenshotRegion, .region, "Area", "viewfinder"),
        (.screenshotFullscreen, .fullscreen, "Fullscreen", "desktopcomputer"),
        (.screenshotWindow, .window, "Window", "macwindow"),
        (.ocr, .ocr, "OCR", "textformat"),
        (.colorPicker, .colorPicker, "Color", "eyedropper"),
    ]

    private var screenshotGroup: some View {
        ForEach(Self.screenshotActions, id: \.0) { id, action, title, icon in
            BarActionButton(id: id, title: title, systemImage: icon, caption: title) {
                captureScreenshot(action)
            }
        }
    }

    private func captureScreenshot(_ action: ShortcutService.Action) {
        showsRecordingOptions = false
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        Task { await CaptureOrchestrator.shared.performCapture(action, on: screen) }
    }

    // MARK: Sources

    @ViewBuilder
    private var displaySource: some View {
        if sources.displays.count > 1 {
            Menu {
                ForEach(Array(sources.displays.enumerated()), id: \.element.displayID) { index, display in
                    Button(RecordingSourceCatalog.displayTitle(display, index: index)) {
                        startRecording {
                            RecordingCaptureEntry.recordFullscreen(display)
                        }
                    }
                }
            } label: {
                BarActionLabel(
                    id: .display,
                    title: "Pick a screen to record",
                    systemImage: "menubar.rectangle", caption: "Display"
                )
            }
            .menuStyle(.button)
            .buttonStyle(BarButtonStyle())
            .menuIndicator(.hidden)
            .accessibilityLabel("Display - choose which screen to record")
        } else {
            BarActionButton(
                id: .display,
                title: "Record the whole screen",
                systemImage: "menubar.rectangle", caption: "Display",
                accessibility: "Display - record the whole screen"
            ) {
                guard let display = sources.displays.first else { return }
                startRecording {
                    RecordingCaptureEntry.recordFullscreen(display)
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
                    startRecording {
                        RecordingCaptureEntry.recordWindow(window)
                    }
                }
            }

            Divider()

            Button("Refresh Windows") {
                Task {
                    await sources.refresh()
                }
            }
        } label: {
            BarActionLabel(
                id: .window,
                title: "Pick an app window",
                systemImage: "macwindow", caption: "Window"
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel("Window - choose an app window to record")
    }

    private func startAreaRecording() {
        showsRecordingOptions = false
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        guard let display = sources.displays.first(where: { $0.displayID == displayID })
            ?? sources.displays.first else { return }
        // Area is the one source that can't morph: the bar has to get out of
        // the way of the selection overlay, so it leaves and comes back as the
        // session controls.
        RecordingBarPresenter.shared.hide()
        RecordingCaptureEntry.recordArea(display)
    }

    /// Leaves the bar on screen: it stays as the picker through any start
    /// delay, then morphs into the session controls the moment capture
    /// actually begins. The warm camera preview (if any) is left running so it
    /// flows straight into the recording instead of restarting and refading.
    private func startRecording(_ start: () -> Void) {
        showsRecordingOptions = false
        TeleprompterComposerPresenter.shared.hide()
        start()
    }

    /// Backs out of the picker without recording: stop any warm camera
    /// preview so it doesn't keep running in the background.
    private func dismissPicker() {
        RecordingBarPresenter.shared.dismiss()
        Task { await CameraRecordingManager.shared.stopPreview() }
    }

    // MARK: Input toggles

    private func toggleCamera() {
        if cameraID.isEmpty {
            selectCamera(RecordingDeviceCatalog.cameras().first?.uniqueID)
        } else {
            cameraID = ""
            Task { await CameraRecordingManager.shared.stopPreview() }
        }
    }

    private var cameraAccessibilityLabel: String {
        guard !cameraID.isEmpty else {
            return "Camera off - click to record your camera, right-click to pick one"
        }
        guard let camera = RecordingDeviceCatalog.cameras().first(where: { $0.uniqueID == cameraID }) else {
            return "Camera unavailable - right-click to choose another camera"
        }
        return "Camera on - \(camera.localizedName), right-click to switch"
    }

    /// The pill only has room for the state, so an attached-but-missing
    /// device is worth calling out there - it's the one case where the icon
    /// alone is misleading.
    private var microphoneTooltip: String {
        guard !microphoneID.isEmpty else { return "Microphone off" }
        guard RecordingDeviceCatalog.microphone(withID: microphoneID) != nil else {
            return "Microphone unavailable"
        }
        return "Microphone on"
    }

    private var microphoneAccessibilityLabel: String {
        guard !microphoneID.isEmpty else {
            return "Microphone off - click to choose an input"
        }
        guard let microphone = RecordingDeviceCatalog.microphone(withID: microphoneID) else {
            return "Microphone unavailable - choose another input"
        }
        return "Microphone on - \(microphone.localizedName)"
    }

    @ViewBuilder
    private var cameraDeviceMenu: some View {
        ForEach(RecordingDeviceCatalog.cameras(), id: \.uniqueID) { device in
            Toggle(isOn: Binding(
                get: { cameraID == device.uniqueID },
                set: { selected in
                    if selected {
                        selectCamera(device.uniqueID)
                    } else {
                        cameraID = ""
                        Task { await CameraRecordingManager.shared.stopPreview() }
                    }
                }
            )) {
                Text(device.localizedName)
            }
        }
    }

    private var microphonePicker: some View {
        Menu {
            Button {
                microphoneID = ""
            } label: {
                menuSelectionLabel("Off", isSelected: microphoneID.isEmpty)
            }

            Divider()

            ForEach(RecordingDeviceCatalog.microphones(), id: \.uniqueID) { device in
                Button {
                    selectMicrophone(device.uniqueID)
                } label: {
                    menuSelectionLabel(
                        device.localizedName,
                        isSelected: microphoneID == device.uniqueID
                    )
                }
            }
        } label: {
            BarActionLabel(
                id: .microphone,
                title: microphoneTooltip,
                systemImage: microphoneID.isEmpty ? "mic.slash" : "mic.fill",
                tint: microphoneID.isEmpty ? BarMetrics.inactiveTint : BarMetrics.activeTint,
                caption: "Mic"
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel(microphoneAccessibilityLabel)
    }

    /// Replaces the old gear button that opened Settings: a self-contained
    /// menu for options that only matter for the next recording, starting
    /// with a start-delay timer.
    private var timerMenu: some View {
        Menu {
            Section("Screenshot timer") {
                ForEach(SelfTimerDelay.allCases, id: \.rawValue) { delay in
                    Button {
                        AppPreferences.selfTimerDelay = delay
                    } label: {
                        menuSelectionLabel(delay.label, isSelected: AppPreferences.selfTimerDelay == delay)
                    }
                }
            }
            Section("Recording timer") {
                ForEach(Self.timerOptions, id: \.self) { seconds in
                    Button {
                        startDelaySeconds = seconds
                    } label: {
                        menuSelectionLabel(timerLabel(seconds), isSelected: startDelaySeconds == seconds)
                    }
                }
            }
        } label: {
            BarActionLabel(
                id: .timer,
                title: timerTooltip,
                systemImage: "timer",
                tint: BarMetrics.activeTint,
                caption: "Timer"
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel("Screenshot and recording timers")
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds == 0 ? "None" : "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    private var timerTooltip: String {
        startDelaySeconds == 0 ? "Timer off" : "Timer \(startDelaySeconds)s"
    }

    @ViewBuilder
    private func menuSelectionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func selectCamera(_ deviceID: String?) {
        guard let deviceID else { return }
        Task { @MainActor in
            let authorized = await RecordingInputAuthorization.ensureAccess(for: .camera)
            cameraID = authorized ? deviceID : ""
            if authorized {
                await warmCameraPreview()
            }
        }
    }

    /// Starts the camera session (and its floating preview) ahead of "Start
    /// Recording", so its exposure/white-balance ramp - the fade-in macOS
    /// shows whenever a capture session starts cold - finishes before
    /// anything is actually being recorded.
    private func warmCameraPreview() async {
        guard !cameraID.isEmpty else { return }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        await CameraRecordingManager.shared.startPreview(deviceID: cameraID, displayID: displayID)
    }

    private func selectMicrophone(_ deviceID: String?) {
        guard let deviceID else { return }
        Task { @MainActor in
            microphoneID = await RecordingInputAuthorization.ensureAccess(for: .microphone) ? deviceID : ""
        }
    }

    // MARK: Pieces

    /// An input toggle is the same control as a source button - the "off"
    /// state is carried by dimming the tint, not by shrinking the target.
    private func inputToggle(
        id: BarTooltipID,
        caption: String,
        title: String,
        isOn: Bool,
        onIcon: String,
        offIcon: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        BarActionButton(
            id: id,
            title: title,
            systemImage: isOn ? onIcon : offIcon,
            tint: isOn ? BarMetrics.activeTint : BarMetrics.inactiveTint,
            caption: caption,
            accessibility: accessibility,
            action: action
        )
    }
}
