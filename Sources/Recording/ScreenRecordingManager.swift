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

    var onVideoFrame: ((CMSampleBuffer) -> Void)?
    var onAudioSample: ((CMSampleBuffer) -> Void)?
    var onMicrophoneSample: ((CMSampleBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    static var supportsMicrophoneCapture: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    static func availableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func makeStream(filter: SCContentFilter, configuration: SCStreamConfiguration) throws -> SCStream {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        let hasAudio = configuration.capturesAudio
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
        onVideoFrame = nil
        onAudioSample = nil
        onMicrophoneSample = nil
        onError = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .screen:
            if let status = Self.frameStatus(for: sampleBuffer),
               status == .blank || status == .suspended || status == .stopped {
                return
            }
            onVideoFrame?(sampleBuffer)
        case .audio:
            onAudioSample?(sampleBuffer)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                onMicrophoneSample?(sampleBuffer)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError?(error)
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
    private let pointerCapture = PointerCaptureRecorder()
    private(set) var activeRegionRect: CGRect?
    private var lastSource: RecordingSource?

    private init() {}

    var isRecording: Bool { state == .recording || state == .paused }

    // MARK: - Start

    func startRecording() async throws -> Bool {
        try await startFullScreenRecording()
    }

    func restartRecording() async throws -> Bool {
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
        state = .preparing

        let targetDisplayID = ActiveDisplayResolver.activeDisplayID() ?? CGMainDisplayID()

        do {
            let content = try await ScreenCaptureStream.availableContent()
            guard let display = Self.display(matching: targetDisplayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content, cameraWindowID: CameraBubbleController.shared.windowID)
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
        state = .preparing

        do {
            let content = try await ScreenCaptureStream.availableContent()
            let targetDisplayID = selection.displayID
            guard let display = Self.display(matching: targetDisplayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content, cameraWindowID: CameraBubbleController.shared.windowID)
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
        state = .preparing

        do {
            let content = try await ScreenCaptureStream.availableContent()
            guard let display = Self.display(matching: displayID, in: content) else {
                state = .idle
                return false
            }

            let filter = Self.displayFilter(display: display, content: content, cameraWindowID: CameraBubbleController.shared.windowID)
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

    private static func displayFilter(display: SCDisplay, content: SCShareableContent, cameraWindowID: CGWindowID?) -> SCContentFilter {
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let cameraWindows = cameraWindowID.flatMap { id in
            content.windows.first { $0.windowID == id }
        }.map { [$0] } ?? []
        return SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: cameraWindows)
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

    // MARK: - Stream lifecycle

    private func beginCapture(
        filter: SCContentFilter,
        width: Int,
        height: Int,
        sourceRect: CGRect? = nil,
        pointerCaptureRect: CGRect
    ) async throws -> Bool {
        let captureAudio = AppPreferences.recordingCaptureAudio
        let captureMicrophone = AppPreferences.recordingCaptureMicrophone
            && ScreenCaptureStream.supportsMicrophoneCapture
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let fps = AppPreferences.recordingFPS

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect { config.sourceRect = sourceRect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = AppPreferences.recordingShowCursor
        if captureAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }
        if captureMicrophone, #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }

        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(fileURLWithPath: "\(dir)/bettershot_\(stamp).mp4")
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
            outputURL = nil
            return false
        }

        session = recordingSession

        capture.onVideoFrame = { [recordingSession] buffer in
            recordingSession.appendVideoSample(buffer)
        }
        capture.onAudioSample = { [recordingSession] buffer in
            recordingSession.appendAudioSample(buffer)
        }
        capture.onMicrophoneSample = { [recordingSession] buffer in
            recordingSession.appendAudioSample(buffer, isMicrophone: true)
        }
        capture.onError = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                _ = await self.stopRecording()
            }
        }

        do {
            let stream = try capture.makeStream(filter: filter, configuration: config)
            try await stream.startCapture()
            pointerCapture.start(captureRect: pointerCaptureRect)
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
        await capture.stop()
        capture.detachHandlers()

        session?.finishInputs()
        let wroteFootage = await session?.finishWriting() ?? false
        session = nil
        let capturedPointerData = pointerCapture.stop()
        activeRegionRect = nil

        state = .idle
        elapsedSeconds = 0

        let url = outputURL
        outputURL = nil

        guard wroteFootage, let url else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        writePointerSidecar(capturedPointerData, alongside: url)
        return url
    }

    private func writePointerSidecar(_ capture: PointerCaptureFile, alongside url: URL) {
        guard !capture.travel.isEmpty || !capture.presses.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(capture) else { return }
        try? data.write(to: url.deletingPathExtension().appendingPathExtension("pointer.json"))
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard state == .recording else { return }
        session?.pause()
        pointerCapture.pause()
        state = .paused
        stopTimer()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        session?.resume()
        pointerCapture.resume()
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
        _ = pointerCapture.stop()
        activeRegionRect = nil

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
