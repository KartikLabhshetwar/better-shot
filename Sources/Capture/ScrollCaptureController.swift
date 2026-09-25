import Cocoa
import Vision

// Scroll registration, settlement and auto-scroll adapted from MacShot (GPLv3).
// See Resources/Licenses/MacShot.txt.

@MainActor
final class ScrollCaptureController {

    private(set) var stripCount = 0
    private(set) var stitchedImage: CGImage?
    private(set) var isActive = false
    private(set) var autoScrollActive = false
    private(set) var frozenTopHeight: CGFloat = 0
    private var isCancelled = false
    private var isStopping = false
    private var didFinishSession = false

    var stitchedPixelSize: CGSize {
        stitchedImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    var onStripAdded: ((Int) -> Void)?
    var onSessionDone: ((NSImage?) -> Void)?
    var onPreviewUpdated: ((NSImage) -> Void)?
    var onAutoScrollChanged: ((Bool) -> Void)?
    var onStatusMessage: ((String?) -> Void)?

    /// Frames include only windows below this one, so BetterShot's session panels never appear in them.
    var captureBelowWindowID: CGWindowID = kCGNullWindowID

    private var autoScrollSpeed = 3
    private var maxScrollHeight = 30_000
    private var frozenDetectionEnabled = true

    private let captureRect: NSRect
    private let captureRectCG: CGRect
    private let backingScale: CGFloat
    private let captureQueue = DispatchQueue(label: "bettershot.scrollcapture", qos: .userInitiated)

    private var shotA: CGImage?
    private var headerHeight = 0
    private var headerDetectionDone = false
    private var rightMarginPx = 0
    private var rightMarginDetected = false

    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal: Any?
    private var autoScrollTask: Task<Void, Never>?
    private var targetAppPID: pid_t = 0

    private let manualCaptureInterval: TimeInterval = 0.15
    private var lastCaptureTime: TimeInterval = 0
    private var settlementTimer: Timer?
    private let settlementInterval: TimeInterval = 0.25
    private let maxMatchNotFound = 8

    private var isCapturing = false

    private enum Step { case appended, unchanged, tooSmall, unmatched }

    private typealias WindowListCreateImage = @convention(c) (
        CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` is hidden from Swift at this deployment target but still ships; it is several times faster than ScreenCaptureKit for single frames.
    private static let createWindowListImage: WindowListCreateImage? =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")
            .map { unsafeBitCast($0, to: WindowListCreateImage.self) }

    init(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.backingScale = screen.backingScaleFactor
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        captureRectCG = CGRect(x: captureRect.minX, y: primaryHeight - captureRect.maxY,
                               width: captureRect.width, height: captureRect.height)
    }

    func startSession() async {
        guard !isActive, !isCancelled, !didFinishSession else { return }

        let ud = UserDefaults.standard
        autoScrollSpeed = min(4, max(1, ud.object(forKey: "scrollAutoScrollSpeed") as? Int ?? 3))
        maxScrollHeight = ud.object(forKey: "scrollMaxHeight") as? Int ?? 30_000
        frozenDetectionEnabled = ud.object(forKey: "scrollFrozenDetection") as? Bool ?? true
        resolveTargetApp()

        isActive = true
        isCapturing = true
        defer { isCapturing = false }

        guard let firstFrame = await captureSettledFrame() else {
            if !isCancelled { finishSession(with: nil) }
            return
        }
        guard isActive, !isCancelled else { return }
        shotA = firstFrame
        stitchedImage = firstFrame
        stripCount = 1
        emitPreview()
        onStripAdded?(stripCount)

        guard !isStopping else { return }
        startManualScrollMonitors()
        if ud.bool(forKey: "scrollAutoScrollEnabled") { toggleAutoScroll() }
    }

    func stopSession() {
        guard isActive, !isStopping else { return }
        isStopping = true
        stopAutoScroll()
        removeManualScrollMonitors()
        Task {
            await settledCapture(final: true)
            if isActive { finishSession(with: stitchedImage) }
        }
    }

    func cancelSession() {
        isCancelled = true
        endSession()
    }

    private func finishSession(with image: CGImage?) {
        guard !didFinishSession else { return }
        didFinishSession = true
        endSession()
        onSessionDone?(image.map { NSImage(cgImage: $0, size: pointSize(of: $0)) })
    }

    private func endSession() {
        isActive = false
        stopAutoScroll()
        removeManualScrollMonitors()
    }

    private func pointSize(of image: CGImage) -> CGSize {
        CGSize(width: CGFloat(image.width) / backingScale, height: CGFloat(image.height) / backingScale)
    }

    private func resolveTargetApp() {
        let point = CGPoint(x: captureRectCG.midX, y: captureRectCG.midY)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] else { return }
        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier else { continue }
            targetAppPID = pid
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            return
        }
    }

    private func captureFrame() -> CGImage? {
        let options: CGWindowListOption = captureBelowWindowID == kCGNullWindowID
            ? .optionOnScreenOnly : .optionOnScreenBelowWindow
        return Self.createWindowListImage?(captureRectCG, options, captureBelowWindowID,
                                           .boundsIgnoreFraming)?.takeRetainedValue()
    }

    /// Grabs frames until two consecutive TIFF representations match byte for byte, returning the last frame if the content keeps animating.
    private func captureSettledFrame() async -> CGImage? {
        var previousTIFF: Data?
        var previousFrame: CGImage?
        var waitNs: UInt64 = 10_000_000

        for _ in 0..<12 {
            guard !isCancelled, !Task.isCancelled else { return nil }
            guard let frame = captureFrame() else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }
            let tiff = await onCaptureQueue { NSBitmapImageRep(cgImage: frame).tiffRepresentation }
            guard !isCancelled, !Task.isCancelled else { return nil }
            if let tiff, tiff == previousTIFF { return frame }
            previousTIFF = tiff
            previousFrame = frame
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }
        return previousFrame
    }

    private func onCaptureQueue<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            captureQueue.async { continuation.resume(returning: work()) }
        }
    }

    @discardableResult
    private func process(_ frame: CGImage, final: Bool = false) async -> Step {
        guard let previous = shotA else {
            shotA = frame
            return .unmatched
        }
        if !rightMarginDetected { detectRightMargin(current: frame, previous: previous) }

        let excludedTop = headerDetectionDone ? headerHeight : 0
        let excludedRight = rightMarginPx
        let offset = await onCaptureQueue {
            Self.visionScrollOffset(previous: previous, current: frame,
                                    excludedTop: excludedTop, excludedRight: excludedRight)
        }
        guard isActive, !isCancelled, !Task.isCancelled, let offset else { return .unmatched }
        guard offset != 0 else {
            shotA = frame
            return .unchanged
        }
        guard offset > 0 else { return .unmatched }
        guard final || offset >= frame.height / 10 else { return .tooSmall }

        if frozenDetectionEnabled && !headerDetectionDone {
            detectHeader(current: frame, previous: previous, shiftPx: offset)
        }
        guard let existing = stitchedImage else { return .unmatched }
        let header = headerDetectionDone ? headerHeight : 0
        let merged = await onCaptureQueue {
            Self.mergedImage(existing: existing, currentFrame: frame, offsetPx: offset, headerHeight: header)
        }
        guard isActive, !isCancelled, !Task.isCancelled, let merged else { return .unmatched }

        stitchedImage = merged
        shotA = frame
        stripCount += 1
        emitPreview()
        onStripAdded?(stripCount)
        if maxScrollHeight > 0 && merged.height >= maxScrollHeight { stopSession() }
        return .appended
    }

    /// Vertical content shift in pixels between two frames, measured by Vision with the header and scrollbar cropped out.
    nonisolated static func visionScrollOffset(previous: CGImage, current: CGImage,
                                               excludedTop: Int, excludedRight: Int) -> Int? {
        guard previous.width == current.width, previous.height == current.height else { return nil }
        let top = min(max(0, excludedTop), current.height / 5)
        let crop = CGRect(x: 0, y: top, width: current.width - max(0, excludedRight), height: current.height - top)
        guard crop.width > 20, crop.height > 20,
              let old = previous.cropping(to: crop), let new = current.cropping(to: crop) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: old)
        guard (try? VNImageRequestHandler(cgImage: new, options: [:]).perform([request])) != nil,
              let result = request.results?.first as? VNImageTranslationAlignmentObservation,
              let shift = ScrollFrameAnalyzer.validatedVerticalShift(result.alignmentTransform.ty,
                                                                     frameHeight: old.height) else { return nil }
        return Int(shift.rounded())
    }

    /// Appends `offsetPx` new rows; without a pinned header the whole newer frame overwrites the overlap so pinned footers appear once, at the end.
    nonisolated static func mergedImage(existing: CGImage, currentFrame: CGImage,
                                        offsetPx: Int, headerHeight: Int = 0) -> CGImage? {
        guard existing.width == currentFrame.width, offsetPx > 0, offsetPx <= currentFrame.height,
              currentFrame.height <= existing.height + offsetPx else { return nil }
        let width = currentFrame.width
        let totalHeight = existing.height + offsetPx
        let colorSpace = existing.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        context.draw(existing, in: CGRect(x: 0, y: offsetPx, width: width, height: existing.height))
        if headerHeight > 0 {
            guard let strip = currentFrame.cropping(to: CGRect(x: 0, y: currentFrame.height - offsetPx,
                                                               width: width, height: offsetPx)) else { return nil }
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: offsetPx))
        } else {
            context.draw(currentFrame, in: CGRect(x: 0, y: 0, width: width, height: currentFrame.height))
        }
        return context.makeImage()
    }

    func toggleAutoScroll() {
        guard isActive, !isStopping, stitchedImage != nil else { return }
        if autoScrollActive {
            stopAutoScroll()
            return
        }
        guard ShortcutService.hasAccessibilityPermission else {
            onStatusMessage?("Allow Accessibility in Settings, then retry Auto Scroll.")
            ShortcutService.requestAccessibilityPermission()
            return
        }
        guard targetAppPID != 0 else {
            onStatusMessage?("No target app found. Cancel and reselect the area.")
            return
        }
        onStatusMessage?(nil)
        settlementTimer?.invalidate()
        settlementTimer = nil
        autoScrollActive = true
        onAutoScrollChanged?(true)

        let point = CGPoint(x: captureRectCG.midX, y: captureRectCG.midY)
        CGWarpMouseCursorPosition(point)
        NSRunningApplication(processIdentifier: targetAppPID)?.activate(options: [])
        let step = Int32(max(1, captureRect.height * CGFloat(autoScrollSpeed) / 8))
        autoScrollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.autoScrollLoop(point: point, step: step)
        }
    }

    /// Posts continuous pixel scrolls, which scroll utilities such as Mac Mouse Fix pass through without reversing or smoothing them.
    private func autoScrollLoop(point: CGPoint, step: Int32) async {
        var failures = 0
        while isActive && autoScrollActive && !Task.isCancelled {
            if isCapturing {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetAppPID else {
                stopAutoScroll()
                return
            }
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: -step, wheel2: 0, wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
            isCapturing = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            var step = Step.unmatched
            if let frame = await captureSettledFrame(), isActive, !Task.isCancelled {
                step = await process(frame)
            }
            isCapturing = false
            guard isActive, autoScrollActive, !Task.isCancelled else { return }
            if step == .appended {
                failures = 0
            } else {
                failures += 1
                if failures >= maxMatchNotFound {
                    stopSession()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        guard autoScrollActive else { return }
        autoScrollActive = false
        onAutoScrollChanged?(false)
    }

    private func startManualScrollMonitors() {
        scrollMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.onManualScrollEvent()
        }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onManualScrollEvent()
            return event
        }
    }

    private func removeManualScrollMonitors() {
        settlementTimer?.invalidate()
        settlementTimer = nil
        if let monitor = scrollMonitorGlobal { NSEvent.removeMonitor(monitor) }
        if let monitor = scrollMonitorLocal { NSEvent.removeMonitor(monitor) }
        scrollMonitorGlobal = nil
        scrollMonitorLocal = nil
    }

    private func onManualScrollEvent() {
        guard isActive, !isStopping, !autoScrollActive, captureRect.contains(NSEvent.mouseLocation) else { return }

        settlementTimer?.invalidate()
        settlementTimer = Timer.scheduledTimer(withTimeInterval: settlementInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.settledCapture() }
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= manualCaptureInterval else { return }
        lastCaptureTime = now
        Task { await grabAndProcess() }
    }

    private func grabAndProcess() async {
        guard isActive, !isStopping, !isCapturing, let frame = captureFrame() else { return }
        isCapturing = true
        defer { isCapturing = false }
        await process(frame)
    }

    private func settledCapture(final: Bool = false) async {
        while isActive && isCapturing {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard isActive, final || (!isStopping && !autoScrollActive) else { return }
        isCapturing = true
        defer { isCapturing = false }
        guard let frame = await captureSettledFrame(), isActive else { return }
        await process(frame, final: final)
    }

    private func detectRightMargin(current: CGImage, previous: CGImage) {
        guard let scrollbarWidth = ScrollFrameAnalyzer.scrollbarWidth(current: current, previous: previous) else { return }
        rightMarginDetected = true
        if scrollbarWidth >= 3 && scrollbarWidth <= 40 {
            rightMarginPx = scrollbarWidth + 4
        }
    }

    private func detectHeader(current: CGImage, previous: CGImage, shiftPx: Int) {
        guard shiftPx > 5,
              let frozenRows = ScrollFrameAnalyzer.frozenTopRows(
                current: current, previous: previous, rightMarginPx: rightMarginPx),
              frozenRows < current.height else { return }
        if frozenRows >= 10 && frozenRows < current.height * 6 / 10 {
            headerHeight = frozenRows
            frozenTopHeight = CGFloat(headerHeight) / backingScale
            headerDetectionDone = true
        } else if frozenRows < 10 {
            headerDetectionDone = true
        }
    }

    private func emitPreview() {
        guard let image = stitchedImage, let onPreviewUpdated else { return }
        onPreviewUpdated(NSImage(cgImage: image, size: pointSize(of: image)))
    }
}
