//
//  CameraRecordingManager.swift
//  BetterShot
//
//  Captures the webcam alongside a screen recording. The camera is written
//  to its own camera.mov inside the recording session (never burned into
//  the screen video) so the studio editor can restyle, reposition, or drop
//  the bubble in post. A floating circular preview shows the user what the
//  camera sees while recording; the preview panel is excluded from capture.
//
//  Sync: AVCaptureSession stamps buffers with the same host clock
//  ScreenCaptureKit uses, so the first camera frame's PTS minus the screen
//  writer's session start gives an exact timeline offset for the editor.
//

import AppKit
import AVFoundation
@preconcurrency import CoreMedia
import Observation

nonisolated struct CameraRecordingResult: Sendable {
    /// Host-clock seconds of the first written camera frame.
    let firstFrameUptime: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated enum RecordingDeviceCatalog {
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func camera(withID uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return cameras().first { $0.uniqueID == uniqueID }
    }

    static func microphone(withID uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return microphones().first { $0.uniqueID == uniqueID }
    }
}

@MainActor
final class CameraRecordingManager {
    static let shared = CameraRecordingManager()

    private let engine = CameraCaptureEngine()
    private var previewPanel: NSPanel?
    private var activePreviewDisplayID: CGDirectDisplayID?
    private(set) var isRunning = false
    /// True once frames are actually being written to a `camera.mov`, as
    /// opposed to just warming the sensor for the floating preview.
    private(set) var isWriting = false
    private var activeDeviceID: String?

    private init() {}

    /// Starts the capture session and shows the floating preview, without
    /// writing anything to disk yet. Call this as soon as the camera is
    /// enabled in the pre-record picker (or whenever it's re-shown with the
    /// camera already on) so the sensor's exposure/white-balance ramp - the
    /// visible fade-in macOS shows whenever a capture session starts cold -
    /// finishes before "Start Recording", instead of showing up live and at
    /// the start of the recorded footage.
    @discardableResult
    func startPreview(deviceID: String, displayID: CGDirectDisplayID?) async -> Bool {
        guard !isWriting else { return true }
        if isRunning {
            if activeDeviceID == deviceID {
                showPreview(displayID: displayID)
                return true
            }
            await stopPreview()
        }
        guard let device = RecordingDeviceCatalog.camera(withID: deviceID) else { return false }

        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { return false }

        do {
            try await engine.startSession(device: device)
        } catch {
            print("Camera preview failed to start: \(error)")
            return false
        }

        isRunning = true
        activeDeviceID = deviceID
        showPreview(displayID: displayID)
        return true
    }

    /// Tears down a warm preview that never turned into a recording - the
    /// camera was toggled off, or the pre-record picker was dismissed
    /// without starting. No-op while an actual recording is using the camera.
    func stopPreview() async {
        guard isRunning, !isWriting else { return }
        isRunning = false
        activeDeviceID = nil
        hidePreview()
        await engine.stopSessionOnly()
    }

    /// Starts writing camera frames to `outputURL`. Reuses an already-warm
    /// preview session for the same device when one is running - so
    /// recording never re-triggers the startup ramp - otherwise it starts a
    /// fresh session (e.g. a recording started without the picker bar).
    /// Returns false (without throwing) when the camera can't start -
    /// a missing device or denied permission should never abort the
    /// screen recording itself.
    func start(outputURL: URL, deviceID: String, displayID: CGDirectDisplayID?) async -> Bool {
        guard !isWriting else { return true }

        if !isRunning || activeDeviceID != deviceID {
            guard await startPreview(deviceID: deviceID, displayID: displayID) else { return false }
        } else {
            showPreview(displayID: displayID)
        }

        do {
            try await engine.beginWriting(outputURL: outputURL)
        } catch {
            print("Camera recording failed to start: \(error)")
            isRunning = false
            activeDeviceID = nil
            hidePreview()
            await engine.stopSessionOnly()
            return false
        }

        isWriting = true
        return true
    }

    func pause() {
        guard isWriting else { return }
        engine.pause()
    }

    func resume() {
        guard isWriting else { return }
        engine.resume()
    }

    func stop() async -> CameraRecordingResult? {
        guard isWriting else { return nil }
        isRunning = false
        isWriting = false
        activeDeviceID = nil
        hidePreview()
        return await engine.finish()
    }

    func cancel() async {
        guard isRunning else { return }
        isRunning = false
        isWriting = false
        activeDeviceID = nil
        hidePreview()
        await engine.cancel()
    }

    private func showPreview(displayID: CGDirectDisplayID?) {
        // Already showing in the right place: the session (and its exposure)
        // is untouched, so recreating the panel here would only cost a
        // pointless layer swap.
        if previewPanel != nil, activePreviewDisplayID == displayID {
            return
        }
        hidePreview()

        let diameter: CGFloat = 160
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CGPoint(
            x: visibleFrame.maxX - diameter - 24,
            y: visibleFrame.minY + 24
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        PreviewWindowCaptureExclusion.shared.register(window: panel)

        let container = NSView(frame: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
        container.wantsLayer = true
        container.layer?.cornerRadius = diameter / 2
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        container.layer?.borderWidth = 1

        let previewLayer = engine.makePreviewLayer()
        previewLayer.frame = container.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.videoGravity = .resizeAspectFill
        container.layer?.addSublayer(previewLayer)

        panel.contentView = container
        panel.orderFrontRegardless()
        previewPanel = panel
        activePreviewDisplayID = displayID
    }

    private func hidePreview() {
        previewPanel?.orderOut(nil)
        previewPanel = nil
        activePreviewDisplayID = nil
    }
}

// MARK: - Capture engine

nonisolated private final class CameraCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.bettershot.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.bettershot.camera.video", qos: .userInitiated)
    private let writer = CameraMovieWriter()
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var activeDevice: AVCaptureDevice?

    /// Starts the capture session only - no movie is written yet. Frames
    /// reach `captureOutput` immediately (for the live preview layer), but
    /// `CameraMovieWriter.writeVideoSample` silently no-ops until
    /// `beginWriting` has run, since it has no asset writer to append to.
    func startSession(device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSession(device: device)
                    activeDevice = device
                    session.startRunning()
                    continuation.resume()
                } catch {
                    teardownSession()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sets up the movie writer for the already-running session so its
    /// frames start landing on disk.
    func beginWriting(outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                guard let activeDevice else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    return
                }
                do {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(activeDevice.activeFormat.formatDescription)
                    try writer.setup(
                        outputURL: outputURL,
                        width: Int(dimensions.width),
                        height: Int(dimensions.height)
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pause() {
        writer.pause()
    }

    func resume() {
        writer.resume()
    }

    func finish() async -> CameraRecordingResult? {
        await stopSession()
        return await writer.finish()
    }

    func cancel() async {
        await stopSession()
        await writer.cancel()
    }

    /// Tears the session down without ever having written a movie - the
    /// warm preview was toggled off or dismissed before recording began.
    func stopSessionOnly() async {
        await stopSession()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return layer
    }

    private func configureSession(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CocoaError(.featureUnsupported)
        }
        session.addInput(input)
        self.input = input

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            throw CocoaError(.featureUnsupported)
        }
        session.addOutput(output)
        self.output = output

        // Mirror the recorded video so it matches the on-screen preview -
        // the FaceTime convention users expect from a talking-head bubble.
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func stopSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                teardownSession()
                continuation.resume()
            }
        }
    }

    private func teardownSession() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        if let input {
            session.removeInput(input)
        }
        if let output {
            session.removeOutput(output)
        }
        session.commitConfiguration()
        input = nil
        output = nil
        activeDevice = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        writer.writeVideoSample(sampleBuffer)
    }
}

// MARK: - Camera movie writer

nonisolated private final class CameraMovieWriter: @unchecked Sendable {
    private let writingQueue = DispatchQueue(label: "com.bettershot.camera.writer", qos: .userInitiated)
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isSessionStarted = false
    private var sessionStartTime: CMTime?
    private var isPaused = false
    private var pauseStartTime: CMTime?
    private var totalPauseDuration: CMTime = .zero
    private var needsPauseDurationUpdate = false
    private var latestSampleTime: CMTime?
    private var pixelWidth = 0
    private var pixelHeight = 0

    func setup(outputURL: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // Fragmented movie: a crash mid-recording still leaves a playable file.
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(6_000_000, width * height * 6),
                AVVideoExpectedSourceFrameRateKey: 30
            ] as [String: Any]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }

        writingQueue.sync {
            assetWriter = writer
            videoInput = input
            self.outputURL = outputURL
            isSessionStarted = false
            sessionStartTime = nil
            isPaused = false
            pauseStartTime = nil
            totalPauseDuration = .zero
            needsPauseDurationUpdate = false
            latestSampleTime = nil
            pixelWidth = width
            pixelHeight = height
        }
    }

    func pause() {
        writingQueue.async { [weak self] in
            guard let self, !isPaused else { return }
            isPaused = true
            pauseStartTime = latestSampleTime
        }
    }

    func resume() {
        writingQueue.async { [weak self] in
            guard let self, isPaused else { return }
            isPaused = false
            needsPauseDurationUpdate = true
        }
    }

    func writeVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let sendable = SendableCameraSampleBuffer(sampleBuffer)
        // Bound retained camera buffers for the same reason as the screen
        // writer: capture should shed frames under encoder pressure instead
        // of growing an unbounded queue until the process is killed.
        writingQueue.sync { [weak self] in
            autoreleasepool {
                guard let self,
                      let assetWriter = self.assetWriter,
                      let videoInput = self.videoInput else {
                    return
                }

                let sampleBuffer = sendable.sampleBuffer
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                if self.isPaused {
                    if self.pauseStartTime == nil {
                        self.pauseStartTime = time
                    }
                    return
                }

                if self.needsPauseDurationUpdate {
                    if let pauseStartTime = self.pauseStartTime {
                        self.totalPauseDuration = CMTimeAdd(
                            self.totalPauseDuration,
                            CMTimeSubtract(time, pauseStartTime)
                        )
                        self.pauseStartTime = nil
                    }
                    self.needsPauseDurationUpdate = false
                }

                if !self.isSessionStarted {
                    self.sessionStartTime = time
                    assetWriter.startSession(atSourceTime: .zero)
                    self.isSessionStarted = true
                }

                self.latestSampleTime = time

                var adjusted = time
                if let sessionStartTime = self.sessionStartTime {
                    adjusted = CMTimeSubtract(adjusted, sessionStartTime)
                }
                if self.totalPauseDuration > .zero {
                    adjusted = CMTimeSubtract(adjusted, self.totalPauseDuration)
                }
                guard adjusted >= .zero,
                      videoInput.isReadyForMoreMediaData,
                      assetWriter.status == .writing,
                      let retimed = Self.retime(sampleBuffer, to: adjusted) else {
                    return
                }
                videoInput.append(retimed)
            }
        }
    }

    func finish() async -> CameraRecordingResult? {
        await withCheckedContinuation { continuation in
            writingQueue.async { [weak self] in
                guard let self, let assetWriter = self.assetWriter else {
                    continuation.resume(returning: nil)
                    return
                }

                let result: CameraRecordingResult? = self.sessionStartTime.map {
                    CameraRecordingResult(
                        firstFrameUptime: $0.seconds,
                        pixelWidth: self.pixelWidth,
                        pixelHeight: self.pixelHeight
                    )
                }

                self.videoInput?.markAsFinished()
                assetWriter.finishWriting {
                    let succeeded = assetWriter.status == .completed
                    if !succeeded, let outputURL = self.outputURL {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    self.reset()
                    continuation.resume(returning: succeeded ? result : nil)
                }
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                assetWriter?.cancelWriting()
                if let outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                reset()
                continuation.resume()
            }
        }
    }

    private func reset() {
        assetWriter = nil
        videoInput = nil
        outputURL = nil
        isSessionStarted = false
        sessionStartTime = nil
        isPaused = false
        pauseStartTime = nil
        totalPauseDuration = .zero
        needsPauseDurationUpdate = false
        latestSampleTime = nil
    }

    private static func retime(_ sampleBuffer: CMSampleBuffer, to newPTS: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        return status == noErr ? newBuffer : nil
    }
}

nonisolated private struct SendableCameraSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(_ sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}
