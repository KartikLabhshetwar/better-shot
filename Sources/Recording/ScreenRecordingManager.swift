import ScreenCaptureKit
import AVFoundation
import AppKit

nonisolated final class ScreenCaptureStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _stream: SCStream?
    private var _hasAudio = false
    private var _hasMicrophone = false

    private let videoQueue = DispatchQueue(label: "com.bettershot.recording.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.bettershot.recording.audio", qos: .userInteractive)
    private let micQueue = DispatchQueue(label: "com.bettershot.recording.microphone", qos: .userInteractive)

    struct Handlers {
        var video: (@Sendable (CMSampleBuffer) -> Void)?
        var audio: (@Sendable (CMSampleBuffer) -> Void)?
        var microphone: (@Sendable (CMSampleBuffer) -> Void)?
        var error: (@Sendable (Error) -> Void)?
    }

    private var _handlers = Handlers()

    private var handlers: Handlers { lock.withLock { _handlers } }

    func setHandlers(_ handlers: Handlers) {
        lock.withLock { _handlers = handlers }
    }

    static var supportsMicrophoneCapture: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    static func availableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func makeStream(filter: SCContentFilter, configuration: SCStreamConfiguration, includeSystemAudio: Bool) throws -> SCStream {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        let hasAudio = includeSystemAudio
        if hasAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        var hasMicrophone = false
        if #available(macOS 15.0, *), configuration.captureMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQueue)
            hasMicrophone = true
        }
        lock.withLock {
            _stream = stream
            _hasAudio = hasAudio
            _hasMicrophone = hasMicrophone
        }
        return stream
    }

    func stop() async {
        let (stream, hasAudio, hasMicrophone): (SCStream?, Bool, Bool) = lock.withLock {
            let s = _stream
            _stream = nil
            return (s, _hasAudio, _hasMicrophone)
        }
        guard let stream else { return }
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
        if hasAudio {
            try? stream.removeStreamOutput(self, type: .audio)
        }
        if hasMicrophone, #available(macOS 15.0, *) {
            try? stream.removeStreamOutput(self, type: .microphone)
        }
    }

    func detachHandlers() {
        lock.withLock { _handlers = Handlers() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .screen:
            if let status = Self.frameStatus(for: sampleBuffer),
               status == .blank || status == .suspended || status == .stopped {
                return
            }
            handlers.video?(sampleBuffer)
        case .audio:
            handlers.audio?(sampleBuffer)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                handlers.microphone?(sampleBuffer)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        handlers.error?(error)
    }

    private static func frameStatus(for sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawValue = attachments.first?[SCStreamFrameInfo.status] as? Int else {
            return nil
        }
        return SCFrameStatus(rawValue: rawValue)
    }
}

enum RecordingSource {
    case fullScreen
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    case area(RegionSelection)
}

@MainActor
@Observable
final class ScreenRecordingManager {
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

    private let capture = ScreenCaptureStream()
    private var session: RecordingSession?
    private var outputURL: URL?
    private var timer: Timer?
    private var elapsedAnchor: ContinuousClock.Instant?
    private var elapsedBeforePause: Duration = .zero
    private let pointerCapture = PointerCaptureRecorder()
    private let keystrokeCapture = KeystrokeRecorder()
    private(set) var activeRegionRect: CGRect?
    private(set) var isRestarting = false
    private var lastSource: RecordingSource?

    private init() {}

    var isRecording: Bool { state == .recording || state == .paused }

    /// Spans the gap a restart opens between tearing the old session down and the new one reaching `.preparing`, so the floating bar does not fall back to its picker.
    var isSessionActive: Bool { state != .idle || isRestarting }

    // MARK: - Start

    func startRecording() async throws -> Bool {
        try await startFullScreenRecording()
    }

    func restartRecording() async throws -> Bool {
        guard !isRestarting else { return false }
        isRestarting = true
        defer { isRestarting = false }
        await cancelRecording()

        switch lastSource {
        case .fullScreen, .none:
            return try await startFullScreenRecording()
        case .display(let displayID):
            return try await startDisplayRecording(displayID: displayID)
        case .window(let windowID):
            return try await startWindowRecording(windowID: windowID)
        case .area(let selection):
            return try await beginAreaCapture(selection: selection)
        }
    }

    func startFullScreenRecording() async throws -> Bool {
        guard state == .idle else { return false }
        guard Self.ensureScreenRecordingPermission() else { return false }
        state = .preparing

        let targetDisplayID = ActiveDisplayResolver.activeDisplayID() ?? CGMainDisplayID()

        do {
            let content = try await ScreenCaptureStream.availableContent()
            guard let display = Self.display(matching: targetDisplayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content)
            let scale = max(1, CGFloat(filter.pointPixelScale))
            let (width, height) = Self.pixelSize(
                points: CGSize(width: CGFloat(display.width), height: CGFloat(display.height)),
                scale: scale
            )

            activeRegionRect = nil
            lastSource = .fullScreen
            return try await beginCapture(
                filter: filter,
                width: width,
                height: height,
                pointerCaptureRect: CGDisplayBounds(display.displayID)
            )
        } catch {
            state = .idle
            throw error
        }
    }

    func startAreaRecording(afterSelection: (() async -> Void)? = nil) async throws -> Bool {
        guard state == .idle else { return false }

        let overlay = RegionSelectionOverlay()
        guard let selection = await overlay.selectRegion() else { return false }

        await afterSelection?()
        return try await beginAreaCapture(selection: selection)
    }

    private func beginAreaCapture(selection: RegionSelection) async throws -> Bool {
        guard state == .idle else { return false }
        guard Self.ensureScreenRecordingPermission() else { return false }
        state = .preparing

        do {
            let content = try await ScreenCaptureStream.availableContent()
            let targetDisplayID = selection.displayID
            guard let display = Self.display(matching: targetDisplayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content)
            let sourceRect = Self.sourceRect(
                forGlobalQuartzRect: selection.pointsRect,
                displayID: display.displayID,
                contentRect: filter.contentRect
            )
            guard sourceRect.width >= 1, sourceRect.height >= 1 else {
                state = .idle
                return false
            }

            let scale = max(1, CGFloat(filter.pointPixelScale))
            let (width, height) = Self.pixelSize(points: sourceRect.size, scale: scale)

            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            activeRegionRect = CGRect(
                x: selection.pointsRect.minX,
                y: primaryHeight - selection.pointsRect.maxY,
                width: selection.pointsRect.width,
                height: selection.pointsRect.height
            )

            lastSource = .area(selection)
            return try await beginCapture(
                filter: filter,
                width: width,
                height: height,
                sourceRect: sourceRect,
                pointerCaptureRect: selection.pointsRect
            )
        } catch {
            state = .idle
            throw error
        }
    }

    func startWindowRecording(windowID: CGWindowID) async throws -> Bool {
        guard state == .idle else { return false }
        guard Self.ensureScreenRecordingPermission() else { return false }
        state = .preparing

        do {
            let content = try await ScreenCaptureStream.availableContent()
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                state = .idle
                return false
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = max(1, CGFloat(filter.pointPixelScale))
            let (width, height) = Self.pixelSize(points: filter.contentRect.size, scale: scale)

            activeRegionRect = nil
            lastSource = .window(windowID)
            return try await beginCapture(
                filter: filter,
                width: width,
                height: height,
                pointerCaptureRect: window.frame
            )
        } catch {
            state = .idle
            throw error
        }
    }

    func startDisplayRecording(displayID: CGDirectDisplayID) async throws -> Bool {
        guard state == .idle else { return false }
        guard Self.ensureScreenRecordingPermission() else { return false }
        state = .preparing

        do {
            let content = try await ScreenCaptureStream.availableContent()
            guard let display = Self.display(matching: displayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content)
            let scale = max(1, CGFloat(filter.pointPixelScale))
            let (width, height) = Self.pixelSize(
                points: CGSize(width: CGFloat(display.width), height: CGFloat(display.height)),
                scale: scale
            )

            activeRegionRect = nil
            lastSource = .display(displayID)
            return try await beginCapture(
                filter: filter,
                width: width,
                height: height,
                pointerCaptureRect: CGDisplayBounds(display.displayID)
            )
        } catch {
            state = .idle
            throw error
        }
    }

    // MARK: - Capture targeting

    private static func display(matching displayID: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == displayID } ?? content.displays.first
    }

    /// Excludes every BetterShot window, the camera bubble included: the bubble records to its own file so the editor can move it afterwards.
    private static func displayFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
    }

    private static func pixelSize(points: CGSize, scale: CGFloat) -> (Int, Int) {
        let width = max(2, Int((points.width * scale).rounded(.toNearestOrAwayFromZero)) & ~1)
        let height = max(2, Int((points.height * scale).rounded(.toNearestOrAwayFromZero)) & ~1)
        return (width, height)
    }

    static func sourceRect(
        forGlobalQuartzRect selectionRect: CGRect,
        displayID: CGDirectDisplayID,
        contentRect: CGRect
    ) -> CGRect {
        sourceRect(
            forGlobalQuartzRect: selectionRect,
            displayBounds: CGDisplayBounds(displayID),
            contentRect: contentRect
        )
    }

    static func sourceRect(
        forGlobalQuartzRect selectionRect: CGRect,
        displayBounds: CGRect,
        contentRect: CGRect
    ) -> CGRect {
        guard displayBounds.width > 0, displayBounds.height > 0,
              contentRect.width > 0, contentRect.height > 0 else {
            return clamped(selectionRect, to: contentRect)
        }

        let scaleX = contentRect.width / displayBounds.width
        let scaleY = contentRect.height / displayBounds.height

        let minLocalX = min(max(selectionRect.minX - displayBounds.minX, 0), displayBounds.width)
        let maxLocalX = min(max(selectionRect.maxX - displayBounds.minX, 0), displayBounds.width)
        let minLocalY = min(max(selectionRect.minY - displayBounds.minY, 0), displayBounds.height)
        let maxLocalY = min(max(selectionRect.maxY - displayBounds.minY, 0), displayBounds.height)

        let rect = CGRect(
            x: contentRect.minX + minLocalX * scaleX,
            y: contentRect.minY + minLocalY * scaleY,
            width: max(1, (maxLocalX - minLocalX) * scaleX),
            height: max(1, (maxLocalY - minLocalY) * scaleY)
        )
        return clamped(rect, to: contentRect)
    }

    private static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(max(rect.width, 1), bounds.width)
        let height = min(max(rect.height, 1), bounds.height)
        let minX = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let minY = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Preflights Screen Recording TCC before touching ScreenCaptureKit, since a missing grant otherwise fails the stream silently.
    private static func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        ToastWindow.shared.show(
            title: "Screen Recording Permission Needed",
            message: "Allow BetterShot in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.",
            systemIcon: "exclamationmark.triangle"
        )
        return false
    }

    // MARK: - Stream lifecycle

    private func beginCapture(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        sourceRect: CGRect? = nil,
        pointerCaptureRect: CGRect
    ) async throws -> Bool {
        let microphoneRequested = AppPreferences.recordingCaptureMicrophone
        let microphoneAuthorized = microphoneRequested ? await AVCaptureDevice.requestAccess(for: .audio) : false
        let microphoneDevice = microphoneRequested && ScreenCaptureStream.supportsMicrophoneCapture && microphoneAuthorized
            ? MicrophoneCatalog.preferred(savedID: AppPreferences.recordingMicrophoneDeviceID)
            : nil
        let captureMicrophone = microphoneDevice != nil
        if microphoneRequested, !captureMicrophone {
            let reason: String
            if !ScreenCaptureStream.supportsMicrophoneCapture {
                reason = "Microphone capture needs macOS 15 or later."
            } else if !microphoneAuthorized {
                reason = "Allow BetterShot in System Settings > Privacy & Security > Microphone."
            } else {
                reason = "No microphone is available on this Mac."
            }
            ToastWindow.shared.show(
                title: "Recording Without Microphone",
                message: reason,
                systemIcon: "mic.slash"
            )
        }
        let audio = RecordingAudioPlan(
            systemAudio: AppPreferences.recordingCaptureAudio,
            microphone: captureMicrophone
        )
        let fps = AppPreferences.recordingFPS

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect { config.sourceRect = sourceRect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = AppPreferences.recordingShowCursor
        if audio.capturesAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }
        if let microphoneDevice, #available(macOS 15.0, *) {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = microphoneDevice.uniqueID
        }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = RecordingStagingDirectory.url.appendingPathComponent("bettershot_\(stamp).mp4")
        outputURL = url

        let recordingSession = try RecordingSession(
            outputURL: url,
            width: width,
            height: height,
            fps: fps,
            includeAudio: audio.systemAudio,
            includeMicrophone: audio.microphone
        )

        guard recordingSession.startWriting() else {
            state = .idle
            outputURL = nil
            return false
        }

        session = recordingSession

        capture.setHandlers(ScreenCaptureStream.Handlers(
            video: { [recordingSession] buffer in
                recordingSession.appendVideoSample(buffer)
            },
            audio: { [recordingSession] buffer in
                recordingSession.appendAudioSample(buffer)
            },
            microphone: { [recordingSession] buffer in
                recordingSession.appendAudioSample(buffer, isMicrophone: true)
            },
            error: { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    _ = await self.stopRecording()
                }
            }
        ))

        do {
            let stream = try capture.makeStream(filter: filter, configuration: config, includeSystemAudio: audio.systemAudio)
            try await stream.startCapture()
            pointerCapture.start(captureRect: pointerCaptureRect)
            if AppPreferences.recordingCaptureKeystrokes { keystrokeCapture.start() }
        } catch {
            capture.detachHandlers()
            recordingSession.cancelWriting()
            session = nil
            try? FileManager.default.removeItem(at: url)
            outputURL = nil
            activeRegionRect = nil
            state = .idle
            throw error
        }

        recordingSession.isCapturing = true
        CameraBubbleController.shared.beginRecording(to: Self.cameraSidecarURL(for: url))
        state = .recording
        resetElapsed()
        startTimer()
        return true
    }

    static func cameraSidecarURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("camera.mov")
    }

    // MARK: - Stop

    func stopRecording() async -> URL? {
        guard isRecording, state != .stopping else { return nil }
        state = .stopping
        stopTimer()

        session?.isCapturing = false
        await capture.stop()
        capture.detachHandlers()

        session?.finishInputs()
        let wroteFootage = await session?.finishWriting() ?? false
        session = nil
        let cameraURL = await CameraBubbleController.shared.finishRecording()
        let capturedPointerData = pointerCapture.stop()
        let capturedKeystrokes = keystrokeCapture.stop()
        activeRegionRect = nil

        state = .idle
        resetElapsed()

        let url = outputURL
        outputURL = nil

        guard wroteFootage, let url else {
            if let url { try? FileManager.default.removeItem(at: url) }
            if let cameraURL { try? FileManager.default.removeItem(at: cameraURL) }
            return nil
        }
        writePointerSidecar(capturedPointerData, alongside: url)
        writeKeystrokeSidecar(capturedKeystrokes, alongside: url)
        if let cameraURL, cameraURL != Self.cameraSidecarURL(for: url) {
            try? FileManager.default.removeItem(at: cameraURL)
        }
        return url
    }

    private func writePointerSidecar(_ capture: PointerCaptureFile, alongside url: URL) {
        guard !capture.travel.isEmpty || !capture.presses.isEmpty else { return }
        var stamped = capture
        stamped.systemCursorVisible = AppPreferences.recordingShowCursor
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        try? data.write(to: url.deletingPathExtension().appendingPathExtension("pointer.json"))
    }

    private func writeKeystrokeSidecar(_ capture: KeystrokeCaptureFile, alongside url: URL) {
        guard !capture.presses.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(capture) else { return }
        try? data.write(to: url.deletingPathExtension().appendingPathExtension("keys.json"))
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard state == .recording else { return }
        session?.pause()
        CameraBubbleController.shared.pauseRecording()
        pointerCapture.pause()
        keystrokeCapture.pause()
        state = .paused
        stopTimer()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        session?.resume()
        CameraBubbleController.shared.resumeRecording()
        pointerCapture.resume()
        keystrokeCapture.resume()
        state = .recording
        startTimer()
    }

    func togglePause() {
        if state == .recording { pauseRecording() }
        else if state == .paused { resumeRecording() }
    }

    // MARK: - Cancel

    func cancelRecording() async {
        guard isRecording || state == .preparing, state != .stopping else { return }
        stopTimer()

        session?.isCapturing = false
        await capture.stop()
        capture.detachHandlers()

        session?.cancelWriting()
        session = nil
        await CameraBubbleController.shared.discardRecording()
        _ = pointerCapture.stop()
        _ = keystrokeCapture.stop()
        activeRegionRect = nil

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil

        state = .idle
        resetElapsed()
    }

    // MARK: - Timer

    /// Ticks faster than 1Hz but only publishes on a whole-second change, so the label never lags a resume by up to a second.
    private func startTimer() {
        stopTimer()
        elapsedAnchor = ContinuousClock.now
        syncElapsed()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncElapsed() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        if let elapsedAnchor {
            elapsedBeforePause += ContinuousClock.now - elapsedAnchor
        }
        elapsedAnchor = nil
        timer?.invalidate()
        timer = nil
        syncElapsed()
    }

    private func resetElapsed() {
        elapsedAnchor = nil
        elapsedBeforePause = .zero
        elapsedSeconds = 0
    }

    /// Derived from a monotonic anchor rather than accumulated ticks, so a dropped tick under encoder load never loses a second.
    private func syncElapsed() {
        var total = elapsedBeforePause
        if let elapsedAnchor {
            total += ContinuousClock.now - elapsedAnchor
        }
        let seconds = Int(total.components.seconds)
        if seconds != elapsedSeconds {
            elapsedSeconds = seconds
        }
    }
}
