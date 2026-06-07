import ScreenCaptureKit
import AVFoundation
import AppKit

@MainActor
@Observable
final class ScreenRecordingManager: NSObject {
    static let shared = ScreenRecordingManager()

    enum State: Equatable {
        case idle
        case preparing
        case recording
        case paused
        case stopping
    }

    private(set) var state: State = .idle
    private(set) var elapsedSeconds: Int = 0

    private var stream: SCStream?
    private var session: RecordingSession?
    private var outputURL: URL?
    private var timer: Timer?
    nonisolated(unsafe) private var _streamSession: RecordingSession?

    private let videoQueue = DispatchQueue(label: "com.bettershot.recording.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.bettershot.recording.audio", qos: .userInteractive)

    private override init() { super.init() }

    var isRecording: Bool { state == .recording || state == .paused }

    // MARK: - Start

    func startRecording() async throws -> Bool {
        return try await startRecording(
            captureAudio: AppPreferences.recordingCaptureAudio
        )
    }

    func startRecording(captureAudio: Bool) async throws -> Bool {
        guard state == .idle else { return false }
        state = .preparing

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            state = .idle
            return false
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let captureWidth = display.width * 2
        let captureHeight = display.height * 2

        return try await beginCapture(
            filter: filter,
            width: captureWidth,
            height: captureHeight,
            captureAudio: captureAudio
        )
    }

    func startWindowRecording() async throws -> Bool {
        guard state == .idle else { return false }
        state = .preparing

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let eligibleWindows = content.windows.filter {
            $0.isOnScreen
            && $0.owningApplication?.bundleIdentifier != ownBundleID
            && $0.frame.width > 0 && $0.frame.height > 0
        }

        guard !eligibleWindows.isEmpty else {
            state = .idle
            return false
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let picker = WindowPickerOverlay(windows: eligibleWindows)
        guard let selectedWindow = await picker.pickWindow() else {
            NSApp.setActivationPolicy(.accessory)
            state = .idle
            return false
        }

        NSApp.setActivationPolicy(.accessory)

        let filter = SCContentFilter(desktopIndependentWindow: selectedWindow)
        let captureWidth = Int(selectedWindow.frame.width) * 2
        let captureHeight = Int(selectedWindow.frame.height) * 2

        return try await beginCapture(
            filter: filter,
            width: captureWidth,
            height: captureHeight,
            captureAudio: AppPreferences.recordingCaptureAudio
        )
    }

    private func beginCapture(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        captureAudio: Bool
    ) async throws -> Bool {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        let fps = AppPreferences.recordingFPS
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5
        config.showsCursor = AppPreferences.recordingShowCursor

        if captureAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(dir)/bettershot_\(stamp).mov"
        let url = URL(fileURLWithPath: path)
        outputURL = url

        let recordingSession = try RecordingSession(
            outputURL: url,
            width: width,
            height: height,
            fps: fps,
            includeAudio: captureAudio
        )

        guard recordingSession.startWriting() else {
            state = .idle
            return false
        }

        self.session = recordingSession
        self._streamSession = recordingSession

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if captureAudio {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        self.stream = scStream

        try await scStream.startCapture()
        recordingSession.isCapturing = true

        state = .recording
        elapsedSeconds = 0
        startTimer()

        return true
    }

    // MARK: - Stop

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        state = .stopping
        stopTimer()

        session?.isCapturing = false

        if let stream {
            try? stream.removeStreamOutput(self, type: .screen)
            try? stream.removeStreamOutput(self, type: .audio)
            try? await stream.stopCapture()
        }
        stream = nil

        session?.finishInputs()
        await session?.finishWriting()
        session = nil
        _streamSession = nil

        state = .idle
        elapsedSeconds = 0

        let url = outputURL
        outputURL = nil
        return url
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard state == .recording else { return }
        session?.isCapturing = false
        state = .paused
        stopTimer()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        session?.isCapturing = true
        state = .recording
        startTimer()
    }

    func togglePause() {
        if state == .recording { pauseRecording() }
        else if state == .paused { resumeRecording() }
    }

    // MARK: - Cancel

    func cancelRecording() async {
        guard isRecording || state == .preparing else { return }
        stopTimer()
        session?.isCapturing = false

        if let stream {
            try? stream.removeStreamOutput(self, type: .screen)
            try? stream.removeStreamOutput(self, type: .audio)
            try? await stream.stopCapture()
        }
        stream = nil

        session?.cancelWriting()
        session = nil
        _streamSession = nil

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil

        state = .idle
        elapsedSeconds = 0
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecordingManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            if self.isRecording {
                _ = await self.stopRecording()
            }
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenRecordingManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard sampleBuffer.isValid else { return }
            _streamSession?.appendVideoSample(sampleBuffer)
        case .audio:
            _streamSession?.appendAudioSample(sampleBuffer)
        @unknown default:
            break
        }
    }
}
