//
//  RecordingPickerBar.swift
//  BetterShot
//
//  Shared screenshot controls and native recording setup for the bar and notch.
//  The panel, chrome, and recording handoff live in RecordingBarPresenter.

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
    var showsCloseButton = true
    @AppStorage("bs_selfTimerDelay") private var screenshotDelay = 0
    @Bindable private var presenter = RecordingBarPresenter.shared

    private static let screenshotActions: [(BarTooltipID, ShortcutService.Action, String, String)] = [
        (.screenshotRegion, .region, "Area", "viewfinder"),
        (.screenshotFullscreen, .fullscreen, "Screen", "desktopcomputer"),
        (.screenshotWindow, .window, "Window", "macwindow"),
        (.ocr, .ocr, "Text", "doc.text.viewfinder"),
        (.colorPicker, .colorPicker, "Color", "eyedropper"),
    ]

    private func capture(_ action: ShortcutService.Action) {
        presenter.showsRecordingOptions = false
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        Task { await CaptureOrchestrator.shared.performCapture(action, on: screen) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.screenshotActions.enumerated()), id: \.element.0) { index, item in
                if index == 3 { BarDivider() }
                let (id, action, caption, icon) = item
                let title = ShortcutService.shared.help(action == .ocr ? "Copy text from screen" : caption, for: action)
                BarActionButton(id: id, title: title, systemImage: icon, caption: caption) {
                    capture(action)
                }
                .help(title)
            }
            BarDivider()
            Menu {
                Picker("Screenshot delay", selection: $screenshotDelay) {
                    ForEach(SelfTimerDelay.allCases, id: \.rawValue) { delay in
                        Text(delay.label).tag(delay.rawValue)
                    }
                }
            } label: {
                BarActionLabel(id: .timer, title: "Screenshot delay", systemImage: "timer",
                    tint: screenshotDelay == 0 ? BarMetrics.activeTint : EditorChrome.accent,
                    caption: screenshotDelay == 0 ? "Timer" : "\(screenshotDelay)s")
            }
            .menuStyle(.button).buttonStyle(BarButtonStyle()).menuIndicator(.hidden)
            .accessibilityLabel("Screenshot delay")
            .accessibilityValue(AppPreferences.selfTimerDelay.label)
            .help("Screenshot delay. Set the recording delay in Record Video.")
            Button { presenter.showsRecordingOptions.toggle() } label: {
                BarActionLabel(id: .recording, title: "Set up a video recording", systemImage: "video",
                               caption: "Record")
            }
            .buttonStyle(BarButtonStyle())
            .accessibilityLabel("Record video — setup")
            .help(ShortcutService.shared.help("Record video", for: .recordingOptions))
            .popover(isPresented: $presenter.showsRecordingOptions, arrowEdge: .top) {
                RecordingOptionsView()
            }
            if showsCloseButton {
                BarActionButton(id: .close, title: "Close", systemImage: "xmark",
                                accessibility: "Close capture bar — Esc") {
                    presenter.dismiss()
                    Task { await CameraRecordingManager.shared.stopPreview() }
                }
            }
        }
    }
}

/// One native setup panel shared by the capture bar and notch.
struct RecordingOptionsView: View {
    @State private var sources = RecordingSourceCatalog.shared
    @State private var sourceMode: ScreenRecordingSourceMode = .fullscreen
    @State private var displayID: CGDirectDisplayID?
    @State private var windowID: CGWindowID?
    @State private var authorizingInput = false
    @AppStorage(BetterShotPreferences.recordingCameraDeviceIDKey) private var cameraID = ""
    @AppStorage(BetterShotPreferences.recordingMicrophoneDeviceIDKey) private var microphoneID = ""
    @AppStorage(BetterShotPreferences.recordingSystemAudioKey) private var systemAudio = false
    @AppStorage(BetterShotPreferences.recordingStartDelaySecondsKey) private var startDelaySeconds = 0
    @AppStorage(BetterShotPreferences.recordingTeleprompterEnabledKey) private var teleprompterEnabled = false

    private var canStart: Bool {
        !authorizingInput && !ScreenRecordingManager.shared.isActive
            && sources.containsSelection(sourceMode, displayID: displayID, windowID: windowID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Record Video", systemImage: "video").font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") {
                    RecordingBarPresenter.shared.showsRecordingOptions = false
                }
                .labelStyle(.iconOnly).buttonStyle(.plain).help("Close recording setup")
            }
            Picker("Recording source", selection: $sourceMode) {
                Label("Screen", systemImage: "desktopcomputer").tag(ScreenRecordingSourceMode.fullscreen)
                Label("Window", systemImage: "macwindow").tag(ScreenRecordingSourceMode.window)
                Label("Area", systemImage: "viewfinder").tag(ScreenRecordingSourceMode.area)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)

            Group {
                switch sourceMode {
                case .fullscreen:
                    Picker("Screen", selection: $displayID) {
                        Text("Choose a screen").tag(Optional<CGDirectDisplayID>.none)
                        ForEach(Array(sources.displays.enumerated()), id: \.element.displayID) { index, display in
                            Text(RecordingSourceCatalog.displayTitle(display, index: index)).tag(Optional(display.displayID))
                        }
                    }
                case .window:
                    Picker("Window", selection: $windowID) {
                        Text("Choose a window").tag(Optional<CGWindowID>.none)
                        ForEach(sources.windows, id: \.windowID) { window in
                            Text(RecordingSourceCatalog.windowTitle(window)).tag(Optional(window.windowID))
                        }
                    }
                case .area:
                    Label("Choose an area on your screen next.", systemImage: "cursorarrow.and.square.on.square.dashed")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 28)

            Form {
                Section("Include") {
                    Picker(selection: Binding(get: { cameraID }, set: selectCamera)) {
                        Text("Off").tag("")
                        let cameras = RecordingDeviceCatalog.cameras()
                        if !cameraID.isEmpty && !cameras.contains(where: { $0.uniqueID == cameraID }) {
                            Text("Camera unavailable").tag(cameraID)
                        }
                        ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    } label: { Label("Camera", systemImage: "video") }
                    .disabled(authorizingInput)
                    Picker(selection: Binding(get: { microphoneID }, set: selectMicrophone)) {
                        Text("Off").tag("")
                        let microphones = RecordingDeviceCatalog.microphones()
                        if !microphoneID.isEmpty && !microphones.contains(where: { $0.uniqueID == microphoneID }) {
                            Text("Microphone unavailable").tag(microphoneID)
                        }
                        ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    } label: { Label("Microphone", systemImage: "mic") }
                    .disabled(authorizingInput)
                    Toggle(isOn: $systemAudio) { Label("System Audio", systemImage: "speaker.wave.2") }
                        .toggleStyle(.switch)
                }
                Section {
                    Picker(selection: $startDelaySeconds) {
                        ForEach(Array(Set([0, 1, 3, 5, startDelaySeconds])).sorted(), id: \.self) { seconds in
                            Text(seconds == 0 ? "None" : seconds == 1 ? "1 second" : "\(seconds) seconds").tag(seconds)
                        }
                    } label: { Label("Start Delay", systemImage: "timer") }
                    HStack {
                        Label("Teleprompter", systemImage: "text.pad.header")
                        Spacer()
                        Text(teleprompterEnabled ? "On" : "Off").foregroundStyle(.secondary)
                        Button(teleprompterEnabled ? "Edit Script…" : "Add Script…") {
                            TeleprompterComposerPresenter.shared.toggle()
                        }
                    }
                }
            }
            .formStyle(.grouped).scrollDisabled(true).scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)

            if sources.isLoading || authorizingInput {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(authorizingInput ? "Waiting for permission…" : "Loading sources…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = sources.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Refresh Sources", systemImage: "arrow.clockwise") { Task { await refreshSources() } }
                    .disabled(sources.isLoading)
                Spacer()
                Button(sourceMode == .area ? "Choose Area…" : "Start Recording",
                       systemImage: sourceMode == .area ? "viewfinder" : "record.circle") {
                    startRecording()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canStart)
            }
        }
        .controlSize(.regular).padding(18).frame(width: 420)
        .task { await refreshSources() }
        .onChange(of: sources.displays.map(\.displayID)) { _, ids in
            if let displayID, !ids.contains(displayID) { self.displayID = nil }
        }
        .onChange(of: sources.windows.map(\.windowID)) { _, ids in
            if let windowID, !ids.contains(windowID) { self.windowID = nil }
        }
    }

    private func refreshSources() async {
        await sources.refresh()
        if displayID == nil {
            let active = RecordingBarPresenter.shared.displayID
            displayID = sources.displays.first(where: { $0.displayID == active })?.displayID ?? sources.displays.first?.displayID
        }
    }

    private func startRecording() {
        guard canStart else { return }
        RecordingBarPresenter.shared.showsRecordingOptions = false
        TeleprompterComposerPresenter.shared.hide()
        switch sourceMode {
        case .fullscreen:
            guard let display = sources.displays.first(where: { $0.displayID == displayID }) else { return }
            RecordingCaptureEntry.recordFullscreen(display)
        case .window:
            guard let window = sources.windows.first(where: { $0.windowID == windowID }) else { return }
            RecordingCaptureEntry.recordWindow(window)
        case .area:
            RecordingBarPresenter.shared.hide()
            RecordingCaptureEntry.recordArea()
        }
    }

    private func selectCamera(_ id: String) {
        guard !id.isEmpty else {
            cameraID = ""
            Task { await CameraRecordingManager.shared.stopPreview() }
            return
        }
        authorizingInput = true
        Task { @MainActor in
            defer { authorizingInput = false }
            let authorized = await RecordingInputAuthorization.ensureAccess(for: .camera)
            cameraID = authorized ? id : ""
            if authorized {
                await CameraRecordingManager.shared.startPreview(deviceID: id,
                    displayID: RecordingBarPresenter.shared.displayID)
            }
        }
    }

    private func selectMicrophone(_ id: String) {
        guard !id.isEmpty else { microphoneID = ""; return }
        authorizingInput = true
        Task { @MainActor in
            defer { authorizingInput = false }
            microphoneID = await RecordingInputAuthorization.ensureAccess(for: .microphone) ? id : ""
        }
    }
}
