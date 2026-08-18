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
    private let microphoneQueue = DispatchQueue(label: "com.bettershot.recording.microphone", qos: .userInteractive)

    private override init() { super.init() }

    var isRecording: Bool { state == .recording || state == .paused }

    // MARK: - Start

    func startRecording() async throws -> Bool {
        return try await startFullScreenRecording()
    }

    func startFullScreenRecording() async throws -> Bool {
        guard state == .idle else { return false }

        let captureAudio = AppPreferences.recordingCaptureAudio
        let captureMicrophone = await resolveMicrophoneCapture()
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
            captureAudio: captureAudio,
            captureMicrophone: captureMicrophone
        )
    }

    func startAreaRecording() async throws -> Bool {
        guard state == .idle else { return false }

        let overlay = RegionSelectionOverlay()
        guard let selection = await overlay.selectRegion() else { return false }

        let captureAudio = AppPreferences.recordingCaptureAudio
        let captureMicrophone = await resolveMicrophoneCapture()
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

        let contentRect = try await filter.contentRect
        let pointPixelScale = try await filter.pointPixelScale

        let screenFrame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))

        let selRect = selection.pointsRect
        let clampedX = max(selRect.minX, screenFrame.minX)
        let clampedY = max(selRect.minY, 0)
        let clampedMaxX = min(selRect.maxX, screenFrame.maxX)
        let clampedMaxY = min(selRect.maxY, screenFrame.height)

        let scaleX = contentRect.width / screenFrame.width
        let scaleY = contentRect.height / screenFrame.height

        let sourceX = contentRect.minX + (clampedX - screenFrame.minX) * scaleX
        let sourceY = contentRect.minY + clampedY * scaleY
        let sourceW = (clampedMaxX - clampedX) * scaleX
        let sourceH = (clampedMaxY - clampedY) * scaleY

        let mappedSourceRect = CGRect(x: sourceX, y: sourceY, width: sourceW, height: sourceH)

        let scale = CGFloat(pointPixelScale)
        let captureWidth = Int(sourceW * scale)
        let captureHeight = Int(sourceH * scale)

        return try await beginCapture(
            filter: filter,
            width: captureWidth,
            height: captureHeight,
            captureAudio: captureAudio,
            captureMicrophone: captureMicrophone,
            sourceRect: mappedSourceRect
        )
    }

    /// Resolves the microphone toggle against OS support and the privacy grant, so a
    /// blocked mic degrades to a silent-voice recording with a visible reason rather
    /// than a stream that fails to start.
    private func resolveMicrophoneCapture() async -> Bool {
        guard AppPreferences.recordingCaptureMicrophone,
              AppPreferences.microphoneCaptureSupported else { return false }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return true }
            showMicrophoneBlockedToast()
            return false
        default:
            showMicrophoneBlockedToast()
            return false
        }
    }

    private func showMicrophoneBlockedToast() {
        ToastWindow.shared.show(
            title: "Microphone blocked",
            message: "Recording without voice. Allow BetterShot under Privacy & Security > Microphone.",
            systemIcon: "mic.slash",
            duration: 4
        )
    }

    private func beginCapture(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        captureAudio: Bool,
        captureMicrophone: Bool,
        sourceRect: CGRect? = nil
    ) async throws -> Bool {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height

        if let sourceRect {
            config.sourceRect = sourceRect
        }
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

        if captureMicrophone, #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }

        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(dir)/bettershot_\(stamp).mp4"
        let url = URL(fileURLWithPath: path)
        outputURL = url

        let recordingSession = try RecordingSession(
            outputURL: url,
            width: width,
            height: height,
            fps: fps,
            includeAudio: captureAudio,
            includeMicrophone: captureMicrophone
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
        if captureMicrophone, #available(macOS 15.0, *) {
            try scStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneQueue)
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
        guard isRecording, state != .stopping else { return nil }
        state = .stopping
        stopTimer()

        session?.isCapturing = false

        if let stream {
            try? stream.removeStreamOutput(self, type: .screen)
            try? stream.removeStreamOutput(self, type: .audio)
            if #available(macOS 15.0, *) {
                try? stream.removeStreamOutput(self, type: .microphone)
            }
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
        guard (isRecording || state == .preparing) && state != .stopping else { return }
        stopTimer()
        session?.isCapturing = false

        if let stream {
            try? stream.removeStreamOutput(self, type: .screen)
            try? stream.removeStreamOutput(self, type: .audio)
            if #available(macOS 15.0, *) {
                try? stream.removeStreamOutput(self, type: .microphone)
            }
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
        default:
            if #available(macOS 15.0, *), type == .microphone {
                _streamSession?.appendMicrophoneSample(sampleBuffer)
            }
        }
    }
}
