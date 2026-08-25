//
//  RecordingPointerCapture.swift
//  BetterShot
//
//  Captures pointer interaction independently from the cursor-free screen
//  master. Absolute input, pointer artwork, and per-frame window geometry
//  stay on the host clock until recording finishes, when they are mapped
//  onto the written source timeline and normalized into recording
//  coordinates.
//

import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Where the capture lives on screen and how large the written surface is in
/// pixels. `captureRect` is in Quartz's top-left-origin global display space -
/// the same space as `CGDisplayBounds`, `SCWindow.frame`, and ScreenCaptureKit's
/// per-frame `screenRect` - so pointer events, capture geometry, and the video
/// surface all share one origin and no axis is ever flipped twice.
nonisolated struct RecordingInputMapping: Sendable {
    let captureRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated final class PointerActivityRecorder: NSObject, @unchecked Sendable {
    private struct CapturedPointerSample {
        let uptime: TimeInterval
        let point: CGPoint
        let travelKind: PointerTravelSample.PointerTravelKind
        let artworkID: String?
    }

    private struct CapturedPressEvent {
        let uptime: TimeInterval
        let point: CGPoint
        let button: Int
        let phase: PointerPressEvent.PressPhase
        let artworkID: String?
    }

    private struct CapturedFrameGeometry {
        let uptime: TimeInterval
        let screenRect: CGRect
        let contentRect: CGRect
        let scaleFactor: Double
    }

    private struct PauseInterval {
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Mirrors RecordingKeystrokeRecorder.duplicateEventWindow: the same
    /// physical input can arrive from the event tap and the AppKit monitors.
    private static let duplicatePressWindow: TimeInterval = 0.05
    /// Cursor identities can change briefly over links, resize handles, and
    /// text. Sample near display cadence; artwork encoding still runs only when
    /// the NSCursor identity actually changes.
    private static let appearanceSampleInterval: TimeInterval = 1.0 / 30.0

    private let lock = NSLock()
    private var mapping: RecordingInputMapping?
    private var tracksDynamicGeometry = false
    private var samples: [CapturedPointerSample] = []
    private var presses: [CapturedPressEvent] = []
    private var frameGeometries: [CapturedFrameGeometry] = []
    private var capturedArtwork: [PointerArtwork] = []
    private var activeArtworkID: String?
    private var lastCursorIdentity: ObjectIdentifier?
    private var hasFrameAlignedSample = false
    private var pressedButtons = Set<Int>()
    private var pauseStartedUptime: TimeInterval?
    private var pauseIntervals: [PauseInterval] = []

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var fallbackSamplerTimer: DispatchSourceTimer?
    private var fallbackGlobalMonitor: Any?
    private var fallbackLocalMonitor: Any?
    private var cursorAppearanceTimer: Timer?

    @MainActor
    func start(
        mapping: RecordingInputMapping,
        tracksDynamicGeometry: Bool = false
    ) {
        stop()

        lock.withLock {
            self.mapping = mapping
            self.tracksDynamicGeometry = tracksDynamicGeometry
            samples = []
            presses = []
            frameGeometries = []
            capturedArtwork = []
            activeArtworkID = nil
            lastCursorIdentity = nil
            hasFrameAlignedSample = false
            pressedButtons = []
            pauseStartedUptime = nil
            pauseIntervals = []
        }

        captureActiveArtwork()
        // A session event tap is the only source that preserves native mouse
        // move/drag timing. Ask for listen access up front; when the user has
        // not granted it yet, installEventTap still fails safely into the
        // sampled fallback below.
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        let tapIsLive = installEventTap()
        // Presses are the feature users notice missing first, so the AppKit
        // monitors run even beside a live tap: they need no Input Monitoring
        // grant, and appendPress discards whichever copy of a click lands
        // second. Only the 60 Hz travel sampler is exclusive to the tap
        // being dead, since it would otherwise fight the tap's native timing.
        installPressMonitors()
        if !tapIsLive {
            installSampledTravelFallback()
        }

        let appearanceTimer = Timer(
            timeInterval: Self.appearanceSampleInterval,
            target: self,
            selector: #selector(pointerAppearanceTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(appearanceTimer, forMode: .common)
        cursorAppearanceTimer = appearanceTimer
    }

    @MainActor
    func stop() {
        fallbackSamplerTimer?.cancel()
        fallbackSamplerTimer = nil
        if let fallbackGlobalMonitor {
            NSEvent.removeMonitor(fallbackGlobalMonitor)
        }
        if let fallbackLocalMonitor {
            NSEvent.removeMonitor(fallbackLocalMonitor)
        }
        fallbackGlobalMonitor = nil
        fallbackLocalMonitor = nil

        cursorAppearanceTimer?.invalidate()
        cursorAppearanceTimer = nil

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
    }

    func pause() {
        lock.withLock {
            guard pauseStartedUptime == nil else { return }
            pauseStartedUptime = ProcessInfo.processInfo.systemUptime
            pressedButtons = []
        }
    }

    func resume() {
        lock.withLock {
            guard let pauseStartedUptime else { return }
            let resumedAt = ProcessInfo.processInfo.systemUptime
            pauseIntervals.append(PauseInterval(start: pauseStartedUptime, end: resumedAt))
            self.pauseStartedUptime = nil
        }
    }

    /// ScreenCaptureKit attaches the source's onscreen bounds and the content
    /// rectangle inside the fixed output surface to every usable video frame.
    /// Keeping changes on the same host clock as pointer samples lets window
    /// recordings remain aligned while the source moves or resizes.
    func recordFrameGeometry(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        let uptime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard uptime.isFinite else { return }
        let cursorPoint = CGEvent(source: nil)?.location
        let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]]
        let attachment = attachments?.first
        let screenRect = Self.rectValue(attachment?[.screenRect])
        let contentRect = Self.rectValue(attachment?[.contentRect])
        let scaleFactor = Self.doubleValue(attachment?[.scaleFactor]) ?? 1

        lock.withLock {
            // The event tap emits only when input changes. A source-frame
            // heartbeat guarantees a time-zero pointer sample and keeps long
            // idle stretches represented without reverting to 60 Hz polling.
            if pauseStartedUptime == nil,
               let cursorPoint,
               (!hasFrameAlignedSample
                    || samples.last.map({ uptime - $0.uptime >= 1 }) ?? true) {
                let sample = CapturedPointerSample(
                    uptime: uptime,
                    point: cursorPoint,
                    travelKind: pressedButtons.isEmpty ? .move : .drag,
                    artworkID: activeArtworkID
                )
                if hasFrameAlignedSample {
                    appendSample(sample)
                } else {
                    // Keep this even when it duplicates the pre-stream sample;
                    // that earlier event will be negative once the first frame
                    // establishes t=0 and is intentionally discarded.
                    samples.append(sample)
                }
                hasFrameAlignedSample = true
            }

            guard tracksDynamicGeometry,
                  let screenRect,
                  screenRect.width > 0,
                  screenRect.height > 0 else {
                return
            }
            let geometry = CapturedFrameGeometry(
                uptime: uptime,
                screenRect: screenRect,
                contentRect: contentRect ?? CGRect(origin: .zero, size: screenRect.size),
                scaleFactor: max(scaleFactor, 0.001)
            )
            if let last = frameGeometries.last,
               Self.nearlyEqual(last.screenRect, geometry.screenRect),
               Self.nearlyEqual(last.contentRect, geometry.contentRect),
               abs(last.scaleFactor - geometry.scaleFactor) < 0.001,
               uptime - last.uptime < 1 {
                return
            }
            frameGeometries.append(geometry)
        }
    }

    /// Converts raw host-clock samples onto the written movie timeline. Pause
    /// adjustment is calculated per sample so activity before a pause never
    /// moves backwards when later pauses are present.
    func finish(sessionStartUptime: TimeInterval, duration: TimeInterval) -> PointerCaptureFile {
        lock.withLock {
            guard let mapping else { return PointerCaptureFile() }
            var completedPauses = pauseIntervals
            if let pauseStartedUptime {
                completedPauses.append(PauseInterval(
                    start: pauseStartedUptime,
                    end: ProcessInfo.processInfo.systemUptime
                ))
            }

            var capture = PointerCaptureFile()
            capture.travel = samples.compactMap { sample in
                guard let time = videoTime(
                    for: sample.uptime,
                    sessionStartUptime: sessionStartUptime,
                    duration: duration,
                    pauseIntervals: completedPauses
                ),
                let point = normalizedPoint(
                    for: sample.point,
                    at: sample.uptime,
                    mapping: mapping
                ) else {
                    return nil
                }
                return PointerTravelSample(
                    time: time,
                    x: point.x,
                    y: point.y,
                    kind: sample.travelKind,
                    artworkID: sample.artworkID
                )
            }
            capture.presses = presses.compactMap { press in
                guard let time = videoTime(
                    for: press.uptime,
                    sessionStartUptime: sessionStartUptime,
                    duration: duration,
                    pauseIntervals: completedPauses
                ),
                let point = normalizedPoint(
                    for: press.point,
                    at: press.uptime,
                    mapping: mapping
                ) else {
                    return nil
                }
                return PointerPressEvent(
                    time: time,
                    x: point.x,
                    y: point.y,
                    button: press.button,
                    phase: press.phase,
                    artworkID: press.artworkID
                )
            }
            capture.artwork = capturedArtwork

            let sanitized = PointerStreamSanitizer.sanitize(
                capture,
                options: PointerSanitizeOptions(
                    recordingSizeInPoints: mapping.captureRect.size
                )
            ).sanitizedCapture

            samples = []
            presses = []
            frameGeometries = []
            capturedArtwork = []
            hasFrameAlignedSample = false
            pauseIntervals = []
            self.pauseStartedUptime = nil
            pressedButtons = []
            return sanitized
        }
    }

    // MARK: - Primary event tap

    @MainActor
    private func installEventTap() -> Bool {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<PointerActivityRecorder>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = recorder.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            } else {
                recorder.record(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            NSLog("[BetterShot] Pointer event tap unavailable; using sampled cursor fallback.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Without Input Monitoring, tapCreate still hands back a valid port -
        // it just never enables and silently delivers nothing. Non-nil is
        // therefore not proof of a working tap; only an enabled tap may stand
        // in for the sampled fallback.
        guard CGEvent.tapIsEnabled(tap: tap) else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
            NSLog("[BetterShot] Pointer event tap created but not enabled (Input Monitoring not granted); using sampled cursor fallback.")
            return false
        }

        eventTap = tap
        eventTapRunLoopSource = source
        return true
    }

    private func record(type: CGEventType, event: CGEvent) {
        let uptime = TimeInterval(event.timestamp) / 1_000_000_000
        guard uptime.isFinite else { return }
        let point = event.location

        lock.withLock {
            guard pauseStartedUptime == nil else { return }
            let artworkID = activeArtworkID
            switch type {
            case .mouseMoved:
                appendSample(
                    CapturedPointerSample(
                        uptime: uptime,
                        point: point,
                        travelKind: .move,
                        artworkID: artworkID
                    )
                )
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                appendSample(
                    CapturedPointerSample(
                        uptime: uptime,
                        point: point,
                        travelKind: .drag,
                        artworkID: artworkID
                    )
                )
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                let button = Self.buttonNumber(for: type, event: event)
                pressedButtons.insert(button)
                appendPress(CapturedPressEvent(
                    uptime: uptime,
                    point: point,
                    button: button,
                    phase: .down,
                    artworkID: artworkID
                ))
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                let button = Self.buttonNumber(for: type, event: event)
                pressedButtons.remove(button)
                appendPress(CapturedPressEvent(
                    uptime: uptime,
                    point: point,
                    button: button,
                    phase: .up,
                    artworkID: artworkID
                ))
            default:
                break
            }
        }
    }

    // MARK: - Degraded fallback

    /// AppKit press monitors, which unlike an event tap need no Input
    /// Monitoring grant. They always run so a missing or silently dead tap
    /// can never cost the recording its clicks.
    @MainActor
    private func installPressMonitors() {
        let clickMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
            self?.handleFallbackPress(event)
        }
        fallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            self?.handleFallbackPress(event)
            return event
        }
    }

    @MainActor
    private func installSampledTravelFallback() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(
            label: "com.bettershot.recording.pointer-capture",
            qos: .utility
        ))
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.sampleFallbackPointer()
        }
        timer.resume()
        fallbackSamplerTimer = timer
    }

    private func sampleFallbackPointer() {
        guard let event = CGEvent(source: nil) else { return }
        let point = event.location
        let uptime = ProcessInfo.processInfo.systemUptime

        lock.withLock {
            guard pauseStartedUptime == nil else { return }
            appendSample(CapturedPointerSample(
                uptime: uptime,
                point: point,
                travelKind: pressedButtons.isEmpty ? .move : .drag,
                artworkID: activeArtworkID
            ))
        }
    }

    private func handleFallbackPress(_ event: NSEvent) {
        guard let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location else { return }
        let uptime = event.timestamp > 0
            ? event.timestamp
            : ProcessInfo.processInfo.systemUptime
        let phase: PointerPressEvent.PressPhase
        let button: Int
        switch event.type {
        case .leftMouseDown:
            phase = .down
            button = 0
        case .leftMouseUp:
            phase = .up
            button = 0
        case .rightMouseDown:
            phase = .down
            button = 1
        case .rightMouseUp:
            phase = .up
            button = 1
        case .otherMouseDown:
            phase = .down
            button = max(2, event.buttonNumber)
        case .otherMouseUp:
            phase = .up
            button = max(2, event.buttonNumber)
        default:
            return
        }

        lock.withLock {
            guard pauseStartedUptime == nil else { return }
            if phase == .down {
                pressedButtons.insert(button)
            } else {
                pressedButtons.remove(button)
            }
            appendPress(CapturedPressEvent(
                uptime: uptime,
                point: point,
                button: button,
                phase: phase,
                artworkID: activeArtworkID
            ))
        }
    }

    private func appendSample(_ sample: CapturedPointerSample) {
        if let last = samples.last {
            let moved = hypot(sample.point.x - last.point.x, sample.point.y - last.point.y)
            if moved < 1,
               sample.uptime - last.uptime < 1,
               sample.travelKind == last.travelKind,
               sample.artworkID == last.artworkID {
                return
            }
        }
        samples.append(sample)
    }

    /// One physical click reaches here from both the event tap and the AppKit
    /// monitors. Matching button, phase, and location inside
    /// `duplicatePressWindow` marks a duplicate rather than a human
    /// double-click - those repeat far slower and interleave a release.
    private func appendPress(_ press: CapturedPressEvent) {
        if let last = presses.last,
           last.button == press.button,
           last.phase == press.phase,
           abs(last.uptime - press.uptime) < Self.duplicatePressWindow,
           hypot(last.point.x - press.point.x, last.point.y - press.point.y) < 1 {
            return
        }
        presses.append(press)
    }

    // MARK: - Pointer artwork

    @objc @MainActor
    private func pointerAppearanceTimer(_ timer: Timer) {
        captureActiveArtwork()
    }

    @MainActor
    private func captureActiveArtwork() {
        // This is the only public AppKit API that can expose another app's
        // current cursor separately from screen pixels. It is deprecated and
        // can be transiently nil, so retain the last valid system cursor in
        // that case rather than flashing to a different shape.
        if let currentCursor = NSCursor.currentSystem,
           captureArtwork(from: currentCursor) {
            return
        }

        let hasCapturedArtwork = lock.withLock { activeArtworkID != nil }
        guard !hasCapturedArtwork else { return }

        // At recording start (or for a legacy/unavailable cursor API), seed
        // the sidecar with AppKit's system arrow. It carries its real image,
        // anchor point, and size just like every other captured artwork.
        if captureArtwork(from: NSCursor.arrow) {
            return
        }
        clearActiveArtwork()
    }

    @MainActor
    private func captureArtwork(from cursor: NSCursor) -> Bool {
        let identity = ObjectIdentifier(cursor)
        let shouldCapture = lock.withLock { lastCursorIdentity != identity }
        guard shouldCapture else { return true }

        guard let artwork = PointerArtworkCapture.capture(
            cursor,
            id: "artwork-candidate"
        ) else {
            return false
        }

        let imageData = artwork.imageData
        let anchorPoint = artwork.anchorPoint
        let referenceSize = artwork.referenceSize
        let cursorPoint = CGEvent(source: nil)?.location
        let uptime = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            lastCursorIdentity = identity
            let artworkID: String
            if let existing = capturedArtwork.first(where: {
                $0.imageData == imageData
                    && abs($0.anchorPoint.x - anchorPoint.x) < 0.001
                    && abs($0.anchorPoint.y - anchorPoint.y) < 0.001
                    && abs($0.referenceSize.width - referenceSize.width) < 0.001
                    && abs($0.referenceSize.height - referenceSize.height) < 0.001
            }) {
                artworkID = existing.artworkID
            } else {
                artworkID = "artwork-\(capturedArtwork.count + 1)"
                capturedArtwork.append(PointerArtwork(
                    artworkID: artworkID,
                    imageData: imageData,
                    anchorPoint: anchorPoint,
                    referenceSize: referenceSize
                ))
            }

            let appearanceChanged = activeArtworkID != artworkID
            activeArtworkID = artworkID
            if appearanceChanged,
               pauseStartedUptime == nil,
               let cursorPoint {
                appendSample(CapturedPointerSample(
                    uptime: uptime,
                    point: cursorPoint,
                    travelKind: pressedButtons.isEmpty ? .move : .drag,
                    artworkID: artworkID
                ))
            }
        }
        return true
    }

    @MainActor
    private func clearActiveArtwork() {
        let cursorPoint = CGEvent(source: nil)?.location
        let uptime = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            lastCursorIdentity = nil
            guard activeArtworkID != nil else { return }
            activeArtworkID = nil
            guard pauseStartedUptime == nil, let cursorPoint else { return }
            appendSample(CapturedPointerSample(
                uptime: uptime,
                point: cursorPoint,
                travelKind: pressedButtons.isEmpty ? .move : .drag,
                artworkID: nil
            ))
        }
    }

    // MARK: - Coordinate and time mapping

    private func videoTime(
        for uptime: TimeInterval,
        sessionStartUptime: TimeInterval,
        duration: TimeInterval,
        pauseIntervals: [PauseInterval]
    ) -> TimeInterval? {
        let precedingPauseDuration = pauseIntervals.reduce(0) { total, interval in
            guard uptime > interval.start else { return total }
            return total + max(0, min(uptime, interval.end) - interval.start)
        }
        let time = uptime - sessionStartUptime - precedingPauseDuration
        guard time >= 0, time <= duration + 0.5 else { return nil }
        return min(time, duration)
    }

    private func normalizedPoint(
        for screenPoint: CGPoint,
        at uptime: TimeInterval,
        mapping: RecordingInputMapping
    ) -> (x: Double, y: Double)? {
        // Two hops, both top-left: screen point to a fraction of the source's
        // onscreen rectangle, then that fraction into the frame the source
        // occupies inside the fixed output surface. The second hop is what
        // keeps a window correct once it is resized, because ScreenCaptureKit
        // then scales the content down and pins it to the surface's top-left
        // corner instead of refitting the surface to the window.
        if tracksDynamicGeometry,
           let geometry = geometry(at: uptime),
           geometry.screenRect.width > 0,
           geometry.screenRect.height > 0,
           geometry.contentRect.width > 0,
           geometry.contentRect.height > 0 {
            let sourceX = (screenPoint.x - geometry.screenRect.minX) / geometry.screenRect.width
            let sourceY = (screenPoint.y - geometry.screenRect.minY) / geometry.screenRect.height
            let surfaceWidth = Double(mapping.pixelWidth) / geometry.scaleFactor
            let surfaceHeight = Double(mapping.pixelHeight) / geometry.scaleFactor
            guard surfaceWidth > 0, surfaceHeight > 0 else { return nil }
            return (
                x: (geometry.contentRect.minX + sourceX * geometry.contentRect.width) / surfaceWidth,
                y: (geometry.contentRect.minY + sourceY * geometry.contentRect.height) / surfaceHeight
            )
        }

        let captureRect = mapping.captureRect
        guard captureRect.width > 0, captureRect.height > 0 else { return nil }
        return (
            x: (screenPoint.x - captureRect.minX) / captureRect.width,
            y: (screenPoint.y - captureRect.minY) / captureRect.height
        )
    }

    private func geometry(at uptime: TimeInterval) -> CapturedFrameGeometry? {
        guard let first = frameGeometries.first else { return nil }
        guard uptime >= first.uptime else { return first }
        var low = 0
        var high = frameGeometries.count
        while low < high {
            let middle = (low + high) / 2
            if frameGeometries[middle].uptime <= uptime {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return frameGeometries[max(0, low - 1)]
    }

    private static func buttonNumber(for type: CGEventType, event: CGEvent) -> Int {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
        default:
            return max(2, Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        }
    }

    /// ScreenCaptureKit hands rectangle attachments over as the CFDictionary
    /// form of a CGRect, not as a boxed CGRect. Missing that left `screenRect`
    /// permanently nil, which silently disabled per-frame window tracking and
    /// pushed every window recording onto the static fallback mapping.
    private static func rectValue(_ value: Any?) -> CGRect? {
        guard let value else { return nil }
        if CFGetTypeID(value as CFTypeRef) == CFDictionaryGetTypeID(),
           let rect = CGRect(dictionaryRepresentation: value as! CFDictionary) {
            return rect
        }
        if let rect = value as? CGRect { return rect }
        if let value = value as? NSValue { return value.rectValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? CGFloat { return Double(value) }
        return nil
    }

    private static func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.01
            && abs(lhs.minY - rhs.minY) < 0.01
            && abs(lhs.width - rhs.width) < 0.01
            && abs(lhs.height - rhs.height) < 0.01
    }
}
