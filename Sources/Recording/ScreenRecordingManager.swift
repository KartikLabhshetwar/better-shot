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
    var isMicMuted: Bool = false

    private var stream: SCStream?
    private var session: RecordingSession?
    private var outputURL: URL?
    private var timer: Timer?
    private var micCapture: MicrophoneCapture?
    nonisolated(unsafe) private var _streamSession: RecordingSession?

    private let videoQueue = DispatchQueue(label: "com.bettershot.recording.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.bettershot.recording.audio", qos: .userInteractive)

    private override init() { super.init() }

    var isRecording: Bool { state == .recording || state == .paused }

    // MARK: - Start

    func startRecording() async throws -> Bool {
        return try await startFullScreenRecording()
    }

    func startFullScreenRecording() async throws -> Bool {
        guard state == .idle else { return false }
        state = .preparing

        let captureAudio = AppPreferences.recordingCaptureAudio
        
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.screens.first
        let targetDisplayID = targetScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first { $0.displayID == targetDisplayID } ?? content.displays.first
        
        guard let display = display else {
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

    func startAreaRecording() async throws -> Bool {
        guard state == .idle else { return false }

        let overlay = RegionSelectionOverlay()
        guard let selection = await overlay.selectRegion() else { return false }

        state = .preparing
        let captureAudio = AppPreferences.recordingCaptureAudio
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first { $0.displayID == selection.displayID } ?? content.displays.first
        guard let display = display else {
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

        let targetScreen = NSScreen.screens.first { screen in
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return screenID == display.displayID
        } ?? NSScreen.screens.first

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let targetScreenFrame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        let targetScreenQuartzFrame = CGRect(
            x: targetScreenFrame.origin.x,
            y: primaryHeight - targetScreenFrame.origin.y - targetScreenFrame.height,
            width: targetScreenFrame.width,
            height: targetScreenFrame.height
        )

        let selRect = selection.pointsRect
        let clampedX = max(selRect.minX, targetScreenQuartzFrame.minX)
        let clampedY = max(selRect.minY, targetScreenQuartzFrame.minY)
        let clampedMaxX = min(selRect.maxX, targetScreenQuartzFrame.maxX)
        let clampedMaxY = min(selRect.maxY, targetScreenQuartzFrame.maxY)

        let localX = clampedX - targetScreenQuartzFrame.minX
        let localY = clampedY - targetScreenQuartzFrame.minY
        let localW = clampedMaxX - clampedX
        let localH = clampedMaxY - clampedY

        let scaleX = contentRect.width / targetScreenFrame.width
        let scaleY = contentRect.height / targetScreenFrame.height

        let sourceX = contentRect.minX + localX * scaleX
        let sourceY = contentRect.minY + localY * scaleY
        let sourceW = localW * scaleX
        let sourceH = localH * scaleY

        let mappedSourceRect = CGRect(x: sourceX, y: sourceY, width: sourceW, height: sourceH)

        let scale = CGFloat(pointPixelScale)
        let captureWidth = Int(sourceW * scale)
        let captureHeight = Int(sourceH * scale)

        return try await beginCapture(
            filter: filter,
            width: captureWidth,
            height: captureHeight,
            captureAudio: captureAudio,
            sourceRect: mappedSourceRect
        )
    }

    private func beginCapture(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        captureAudio: Bool,
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

        let captureMic = AppPreferences.recordingCaptureMicrophone
        if captureMic {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
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
            includeMic: captureMic
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

        if captureMic {
            let mic = MicrophoneCapture()
            mic.onAudioSample = { [weak self] sampleBuffer in
                guard let self = self else { return }
                if self.isMicMuted {
                    self.silenceAudioBuffer(sampleBuffer)
                }
                self._streamSession?.appendMicSample(sampleBuffer)
            }
            mic.start()
            self.micCapture = mic
        }

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

        micCapture?.stop()
        micCapture = nil
        isMicMuted = false

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
        guard (isRecording || state == .preparing) && state != .stopping else { return }
        stopTimer()
        session?.isCapturing = false

        micCapture?.stop()
        micCapture = nil
        isMicMuted = false

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

    private func silenceAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        _ = CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length)
    }

    func toggleMicMute() {
        isMicMuted.toggle()
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
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - MicrophoneCapture Helper

final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let sampleQueue = DispatchQueue(label: "com.bettershot.recording.mic", qos: .userInteractive)

    var onAudioSample: ((CMSampleBuffer) -> Void)?

    func start() {
        let session = AVCaptureSession()

        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic) else { return }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureAudioDataOutput()
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000.0,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        output.audioSettings = audioSettings
        
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        self.captureSession = session
        self.audioOutput = output

        session.startRunning()
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onAudioSample?(sampleBuffer)
    }
}
