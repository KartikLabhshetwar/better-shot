import Cocoa
import ScreenCaptureKit
import Vision

// Scroll registration, settlement and auto-scroll adapted from MacShot (GPLv3).
// See Resources/Licenses/MacShot.txt.

@MainActor
final class ScrollCaptureController {

    nonisolated enum ScrollDirection: Sendable {
        case down, right, left

        var isHorizontal: Bool { self != .down }
        var sign: Int { self == .left ? -1 : 1 }
    }

    private(set) var stripCount: Int = 0
    private(set) var stitchedImage: CGImage?
    private(set) var stitchedPixelSize: CGSize = .zero
    private(set) var isActive: Bool = false
    private(set) var frozenTopHeight: CGFloat = 0
    private var isCancelled: Bool = false
    private var isStopping: Bool = false
    private var didFinishSession: Bool = false

    var estimatedTotalHeight: CGFloat {
        guard let merged = mergedImage else { return 0 }
        return CGFloat(merged.height) / backingScale
    }

    var onStripAdded: ((Int) -> Void)?
    var onSessionDone: ((NSImage?) -> Void)?
    var onPreviewUpdated: ((NSImage) -> Void)?
    var onTrackingChanged: ((Bool) -> Void)?

    var excludedWindowIDs: [CGWindowID] = []

    private(set) var autoScrollActive = false
    var onAutoScrollChanged: ((Bool) -> Void)?
    var onStatusMessage: ((String?) -> Void)?
    private var autoScrollTask: Task<Void, Never>?
    private var autoScrollSpeed = 3
    private var targetAppPID: pid_t = 0
    private var maxScrollHeight: Int = 30000
    private var frozenDetectionEnabled: Bool = true

    private let captureRect: NSRect
    private let screen: NSScreen
    private let backingScale: CGFloat

    private let captureQueue = DispatchQueue(label: "bettershot.scrollcapture", qos: .userInitiated)

    private var shotA: CGImage?
    private var mergedImage: CGImage?
    private var scrollDirection: ScrollDirection?
    private var prefersHorizontal = false
    var isHorizontalCapture: Bool { scrollDirection?.isHorizontal == true }
    private var headerHeight: Int = 0
    private var headerDetectionDone: Bool = false

    private var rightMarginPx: Int = 0
    private var rightMarginDetected: Bool = false

    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal: Any?

    private let manualCaptureInterval: TimeInterval = 0.15
    private var lastCaptureTime: TimeInterval = 0
    private var scrolledSinceCapture: CGFloat = 0
    private var scrolledSinceMatch: CGFloat = 0
    private var isTracking = true
    private var settlementTimer: Timer?
    private let settlementInterval: TimeInterval = 0.25

    private var isCapturing: Bool = false

    private var cachedContentFilter: SCContentFilter?

    init(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.screen = screen
        self.backingScale = screen.backingScaleFactor
    }

    func startSession() async {
        guard !isActive, !isCancelled, !didFinishSession else { return }

        let ud = UserDefaults.standard
        maxScrollHeight = ud.object(forKey: "scrollMaxHeight") as? Int ?? 30000
        frozenDetectionEnabled = ud.object(forKey: "scrollFrozenDetection") as? Bool ?? true

        autoScrollSpeed = min(4, max(1, ud.object(forKey: "scrollAutoScrollSpeed") as? Int ?? 3))
        resolveTargetApp()
        cachedContentFilter = nil

        // Mark the session active before the first awaited frame so Stop can
        // cancel a capture that is still settling.
        isActive = true
        isCapturing = true
        defer { isCapturing = false }

        guard let firstFrame = await captureSettledFrame() else {
            if !isCancelled { finishSession(with: nil) }
            return
        }
        guard isActive, !isCancelled else { return }
        shotA = firstFrame
        mergedImage = firstFrame
        scrollDirection = nil
        prefersHorizontal = false
        headerHeight = 0
        headerDetectionDone = false
        rightMarginPx = 0
        rightMarginDetected = false
        frozenTopHeight = 0
        stripCount = 1

        stitchedImage = firstFrame
        stitchedPixelSize = CGSize(width: CGFloat(firstFrame.width), height: CGFloat(firstFrame.height))
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
        settlementTimer?.invalidate(); settlementTimer = nil
        if let monitor = scrollMonitorGlobal { NSEvent.removeMonitor(monitor); scrollMonitorGlobal = nil }
        if let monitor = scrollMonitorLocal { NSEvent.removeMonitor(monitor); scrollMonitorLocal = nil }
        Task {
            await settledCapture(final: true)
            if isActive { finishSession(with: mergedImage) }
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
        guard let image else {
            onSessionDone?(nil)
            return
        }
        let ptSize = CGSize(width: CGFloat(image.width) / backingScale,
                            height: CGFloat(image.height) / backingScale)
        onSessionDone?(NSImage(cgImage: image, size: ptSize))
    }

    private func endSession() {
        isActive = false
        stopAutoScroll()
        settlementTimer?.invalidate(); settlementTimer = nil
        if let monitor = scrollMonitorGlobal { NSEvent.removeMonitor(monitor); scrollMonitorGlobal = nil }
        if let monitor = scrollMonitorLocal { NSEvent.removeMonitor(monitor); scrollMonitorLocal = nil }
    }

    private func resolveContentFilter() async -> SCContentFilter? {
        if let cachedContentFilter { return cachedContentFilter }
        guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { return nil }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ), let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        let excluded = Set(excludedWindowIDs)
        let filter = PreviewWindowCaptureExclusion.includesAppWindowsInCaptures
            ? SCContentFilter(display: display, excludingWindows: content.windows.filter { excluded.contains($0.windowID) })
            : ScreenRecordingCapture.displayFilter(display: display, content: content, includesAppWindows: false)
        cachedContentFilter = filter
        return filter
    }

    private func captureFrame() async -> CGImage? {
        guard let filter = await resolveContentFilter() else { return nil }

        let sourceRect = sourceRect(in: filter.contentRect)
        guard sourceRect.width > 1, sourceRect.height > 1 else { return nil }

        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = max(2, Int((sourceRect.width * scale).rounded()))
        config.height = max(2, Int((sourceRect.height * scale).rounded()))
        config.showsCursor = false

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Converts the global AppKit selection into this display's ScreenCaptureKit
    /// coordinates. Displays can have negative origins and do not share a single
    /// AppKit-to-Quartz Y origin.
    private func sourceRect(in contentRect: CGRect) -> CGRect {
        guard screen.frame.width > 0, screen.frame.height > 0,
              contentRect.width > 0, contentRect.height > 0 else { return .zero }

        let localMinX = min(max(captureRect.minX - screen.frame.minX, 0), screen.frame.width)
        let localMaxX = min(max(captureRect.maxX - screen.frame.minX, 0), screen.frame.width)
        let localMinY = min(max(captureRect.minY - screen.frame.minY, 0), screen.frame.height)
        let localMaxY = min(max(captureRect.maxY - screen.frame.minY, 0), screen.frame.height)
        let scaleX = contentRect.width / screen.frame.width
        let scaleY = contentRect.height / screen.frame.height
        let rect = CGRect(
            x: contentRect.minX + localMinX * scaleX,
            y: contentRect.minY + (screen.frame.height - localMaxY) * scaleY,
            width: (localMaxX - localMinX) * scaleX,
            height: (localMaxY - localMinY) * scaleY
        )
        return rect.intersection(contentRect)
    }

    private func captureSettledFrame() async -> CGImage? {
        var previousTIFF: Data? = nil
        var previousCG: CGImage? = nil
        var waitNs: UInt64 = 10_000_000

        for _ in 0..<30 {
            guard !isCancelled, !Task.isCancelled else { return nil }
            guard let cg = await captureFrame() else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }

            let tiffData: Data? = await withCheckedContinuation { cont in
                captureQueue.async {
                    let bitmapRep = NSBitmapImageRep(cgImage: cg)
                    cont.resume(returning: bitmapRep.tiffRepresentation)
                }
            }
            guard !isCancelled, !Task.isCancelled else { return nil }
            guard let currentTIFF = tiffData else {
                try? await Task.sleep(nanoseconds: waitNs)
                waitNs = min(waitNs * 3 / 2, 80_000_000)
                continue
            }

            if let prevTIFF = previousTIFF, currentTIFF == prevTIFF {
                return cg
            }

            previousTIFF = currentTIFF
            previousCG = cg
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        return previousCG
    }

    @discardableResult
    private func processFrame(_ currentFrame: CGImage,
                              allowAxisFallback: Bool = false) async -> Bool {
        guard let previousFrame = shotA else { return false }

        if !rightMarginDetected {
            detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        let directionGroups: [[ScrollDirection]]
        if let scrollDirection {
            directionGroups = [[scrollDirection]]
        } else if prefersHorizontal {
            directionGroups = allowAxisFallback ? [[.right, .left], [.down]] : [[.right, .left]]
        } else {
            directionGroups = allowAxisFallback ? [[.down], [.right, .left]] : [[.down]]
        }
        let excludedTop = headerDetectionDone ? headerHeight : 0
        let excludedRight = rightMarginPx
        let chosen: (ScrollDirection, Int)? = await withCheckedContinuation { continuation in
            captureQueue.async {
                for directions in directionGroups {
                    let matches = directions.compactMap { direction -> (ScrollDirection, Int, ScrollMatch.Score)? in
                        guard let match = Self.matchedScroll(previous: previousFrame, current: currentFrame,
                            excludedTop: excludedTop, excludedRight: excludedRight, direction: direction) else { return nil }
                        return (direction, match.offset, match.score)
                    }.sorted { $0.2.error < $1.2.error }
                    guard let best = matches.first else { continue }
                    if matches.count > 1,
                       matches[1].2.error - best.2.error <= max(2, best.2.error * 0.5) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: (best.0, best.1))
                    return
                }
                continuation.resume(returning: nil)
            }
        }
        guard isActive, !isCancelled, !Task.isCancelled else { return false }
        guard let (direction, offsetPx) = chosen else { return false }

        if direction == .down && frozenDetectionEnabled && !headerDetectionDone {
            detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        guard mergeNewContent(currentFrame: currentFrame, offsetPx: offsetPx,
                              direction: direction) else {
            if hasReachedMaximumDimension(for: direction) { stopSession() }
            return false
        }

        scrollDirection = direction
        shotA = currentFrame
        stripCount += 1
        scrolledSinceMatch = 0
        setTracking(true)

        emitPreview()
        onStripAdded?(stripCount)
        if hasReachedMaximumDimension(for: direction) { stopSession() }

        return true
    }

    private func hasReachedMaximumDimension(for direction: ScrollDirection) -> Bool {
        guard let mergedImage else { return false }
        let length = direction.isHorizontal ? mergedImage.width : mergedImage.height
        return maxScrollHeight > 0 && length >= maxScrollHeight
    }

    @discardableResult
    private func mergeNewContent(currentFrame: CGImage, offsetPx: Int,
                                 direction: ScrollDirection) -> Bool {
        guard let existing = mergedImage else {
            mergedImage = currentFrame
            return true
        }

        let existingLength = direction.isHorizontal ? existing.width : existing.height
        let newPixels = maxScrollHeight > 0
            ? min(abs(offsetPx), max(0, maxScrollHeight - existingLength))
            : abs(offsetPx)
        guard newPixels > 0 else { return false }
        let frameLength = direction.isHorizontal ? currentFrame.width : currentFrame.height
        let leadingFixedLength = max(frameLength / 5, direction.isHorizontal ? 0 : headerHeight)
        let refreshedPixels = max(0, min(frameLength / 2,
                                         frameLength - abs(offsetPx) - leadingFixedLength))
        let merged: CGImage?
        if direction.isHorizontal {
            merged = Self.mergedHorizontalImage(existing: existing, currentFrame: currentFrame,
                                                offsetPx: offsetPx, columnsToAppend: newPixels,
                                                refreshedColumns: refreshedPixels)
        } else {
            merged = Self.mergedImage(existing: existing, currentFrame: currentFrame,
                                      offsetPx: offsetPx, rowsToAppend: newPixels,
                                      refreshedRows: refreshedPixels)
        }
        guard let merged else { return false }
        mergedImage = merged
        stitchedImage = merged
        stitchedPixelSize = CGSize(width: CGFloat(merged.width), height: CGFloat(merged.height))
        return true
    }

    /// Appends new rows and redraws the trailing `refreshedRows` so pinned overlays appear once.
    static func mergedImage(
        existing: CGImage,
        currentFrame: CGImage,
        offsetPx: Int,
        rowsToAppend: Int? = nil,
        refreshedRows: Int = 0
    ) -> CGImage? {
        let newRows = rowsToAppend ?? offsetPx
        guard existing.width == currentFrame.width,
              offsetPx > 0, refreshedRows >= 0, refreshedRows <= existing.height,
              offsetPx + refreshedRows <= currentFrame.height,
              newRows > 0, newRows <= offsetPx else { return nil }

        let width = currentFrame.width
        let totalHeight = existing.height + newRows
        let colorSpace = existing.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        context.draw(existing, in: CGRect(x: 0, y: newRows, width: width, height: existing.height))
        let stripY = currentFrame.height - offsetPx - refreshedRows
        let stripHeight = refreshedRows + newRows
        guard let strip = currentFrame.cropping(to: CGRect(
            x: 0, y: stripY, width: width, height: stripHeight
        )) else { return nil }
        context.setBlendMode(.copy)
        context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: stripHeight))
        return context.makeImage()
    }

    static func mergedHorizontalImage(
        existing: CGImage, currentFrame: CGImage,
        offsetPx: Int, columnsToAppend: Int? = nil,
        refreshedColumns: Int = 0
    ) -> CGImage? {
        let newColumns = columnsToAppend ?? abs(offsetPx)
        guard existing.height == currentFrame.height,
              offsetPx != 0, refreshedColumns >= 0, refreshedColumns <= existing.width,
              abs(offsetPx) + refreshedColumns <= currentFrame.width,
              newColumns > 0, newColumns <= abs(offsetPx) else { return nil }

        let height = currentFrame.height
        let colorSpace = existing.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: existing.width + newColumns,
                                      height: height, bitsPerComponent: 8,
                                      bytesPerRow: (existing.width + newColumns) * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        let stripWidth = newColumns + refreshedColumns
        let stripX = offsetPx > 0 ? currentFrame.width - offsetPx - refreshedColumns : -offsetPx - newColumns
        guard let strip = currentFrame.cropping(to: CGRect(
            x: stripX, y: 0, width: stripWidth, height: height
        )) else { return nil }
        if offsetPx > 0 {
            context.draw(existing, in: CGRect(x: 0, y: 0,
                                               width: existing.width, height: height))
            context.setBlendMode(.copy)
            context.draw(strip, in: CGRect(x: existing.width - refreshedColumns, y: 0,
                                            width: stripWidth, height: height))
        } else {
            context.draw(existing, in: CGRect(x: newColumns, y: 0,
                                               width: existing.width, height: height))
            context.setBlendMode(.copy)
            context.draw(strip, in: CGRect(x: 0, y: 0,
                                            width: stripWidth, height: height))
        }
        return context.makeImage()
    }

    private func resolveTargetApp() {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let point = CGPoint(x: captureRect.midX, y: primaryHeight - captureRect.midY)
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

    func toggleAutoScroll() {
        guard isActive, !isStopping, stitchedImage != nil else { return }
        if autoScrollActive {
            stopAutoScroll()
            return
        }
        guard !isHorizontalCapture else { return }
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
        let point = CGPoint(x: captureRect.midX,
            y: CGDisplayBounds(CGMainDisplayID()).height - captureRect.midY)
        CGWarpMouseCursorPosition(point)
        NSRunningApplication(processIdentifier: targetAppPID)?.activate(options: [])
        let lines: Int32 = autoScrollSpeed == 4 ? 2 : 1
        let bursts = autoScrollSpeed
        autoScrollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            var failures = 0
            var unchanged = 0
            while self.isActive && self.autoScrollActive && !Task.isCancelled {
                if self.isCapturing {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }
                // Pause if the user switches apps; never scroll an unrelated window.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == self.targetAppPID else {
                    self.stopAutoScroll()
                    return
                }
                self.isCapturing = true
                for _ in 0..<bursts {
                    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                        wheel1: -lines, wheel2: 0, wheel3: 0)
                    event?.location = point
                    event?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                let frame = await self.captureSettledFrame()
                guard self.isActive, self.autoScrollActive, !Task.isCancelled else {
                    self.isCapturing = false
                    return
                }
                let previousFrame = self.shotA
                let matched = if let frame { await self.processFrame(frame) } else { false }
                self.isCapturing = false
                if matched {
                    failures = 0
                    unchanged = 0
                } else if let frame, let previousFrame,
                          Self.framesEqual(frame, previousFrame) {
                    unchanged += 1
                    if unchanged >= 6 { self.stopSession(); return }
                } else {
                    failures += 1
                    if failures >= 8 {
                        self.stopAutoScroll()
                        self.setTracking(false)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
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
        scrollMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onManualScrollEvent(event)
        }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onManualScrollEvent(event)
            return event
        }
    }

    private func onManualScrollEvent(_ event: NSEvent) {
        guard isActive, !isStopping, !autoScrollActive, captureRect.contains(NSEvent.mouseLocation) else { return }
        if event.modifierFlags.contains(.shift)
            || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            prefersHorizontal = true
        } else if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            prefersHorizontal = false
        }

        let delta = prefersHorizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        let distance = event.hasPreciseScrollingDeltas ? delta : delta * 10
        scrolledSinceCapture += abs(distance)
        scrolledSinceMatch += distance

        settlementTimer?.invalidate()
        settlementTimer = Timer.scheduledTimer(withTimeInterval: settlementInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.settledCapture() }
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard !isCapturing, now - lastCaptureTime >= manualCaptureInterval
                || scrolledSinceCapture >= scrollLength / 3 else { return }
        lastCaptureTime = now
        scrolledSinceCapture = 0

        Task { @MainActor in await self.grabAndProcess() }
    }

    private func grabAndProcess() async {
        guard isActive, !isStopping, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let currentFrame = await captureFrame() else { return }
        guard isActive else { return }
        await processFrame(currentFrame)
    }

    private func settledCapture(final: Bool = false) async {
        while isActive && isCapturing {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard isActive, (final || (!isStopping && !autoScrollActive)) else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let frame = await captureSettledFrame(), isActive else { return }
        let matched = await processFrame(frame, allowAxisFallback: true)
        if !final, !matched, abs(scrolledSinceMatch) >= scrollLength / 20,
           let previous = shotA, !Self.framesEqual(frame, previous) {
            setTracking(false)
        }
    }

    private var scrollLength: CGFloat {
        (scrollDirection?.isHorizontal ?? prefersHorizontal) ? captureRect.width : captureRect.height
    }

    private func setTracking(_ tracking: Bool) {
        guard tracking != isTracking else { return }
        isTracking = tracking
        onTrackingChanged?(tracking)
    }

    /// MacShot's Vision registration, cropped to moving content. Keep exact pixel
    /// offsets: subtracting a row on every strip progressively shortens the page.
    nonisolated static func visionScrollOffset(
        previous: CGImage, current: CGImage, excludedTop: Int, excludedRight: Int,
        excludedBottom: Int = 0, direction: ScrollDirection = .down
    ) -> Int? {
        guard previous.width == current.width, previous.height == current.height else { return nil }
        let crop = CGRect(x: 0, y: max(0, excludedTop),
            width: current.width - max(0, excludedRight),
            height: current.height - max(0, excludedTop) - max(0, excludedBottom))
        guard crop.width > 20, crop.height > 20,
              let old = previous.cropping(to: crop), let new = current.cropping(to: crop) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: old)
        let handler = VNImageRequestHandler(cgImage: new, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first as? VNImageTranslationAlignmentObservation else { return nil }
        let transform = result.alignmentTransform
        // Vision's image Y axis points up; horizontal translation has the opposite sign.
        let shift = direction.isHorizontal ? -transform.tx : transform.ty
        let crossAxis = direction.isHorizontal ? transform.ty : transform.tx
        let length = direction.isHorizontal ? old.width : old.height
        guard crossAxis.isFinite,
              let valid = ScrollFrameAnalyzer.validatedVerticalShift(shift, frameHeight: length) else { return nil }
        let offset = Int(valid.rounded())
        return offset * direction.sign > 0 ? offset : nil
    }

    /// Compare only pixels that changed at the same screen location, so fixed
    /// toolbars and empty backgrounds cannot vote for a false shift.
    nonisolated static func validatedScrollOffset(
        previous: CGImage, current: CGImage, candidate: Int,
        excludedTop: Int, excludedRight: Int,
        direction: ScrollDirection = .down
    ) -> Int? {
        guard let match = ScrollMatch(previous: previous, current: current,
                                      excludedTop: excludedTop, excludedRight: excludedRight),
              candidate * direction.sign > 0,
              let score = match.score(candidate, direction: direction),
              score.isConfident else { return nil }
        return candidate
    }

    nonisolated static func matchedScrollOffset(
        previous: CGImage, current: CGImage,
        excludedTop: Int, excludedRight: Int,
        direction: ScrollDirection = .down
    ) -> Int? {
        matchedScroll(previous: previous, current: current,
                      excludedTop: excludedTop, excludedRight: excludedRight,
                      direction: direction)?.offset
    }

    private nonisolated static func matchedScroll(
        previous: CGImage, current: CGImage,
        excludedTop: Int, excludedRight: Int,
        direction: ScrollDirection
    ) -> (offset: Int, score: ScrollMatch.Score)? {
        guard let match = ScrollMatch(previous: previous, current: current,
                                      excludedTop: excludedTop, excludedRight: excludedRight) else { return nil }
        guard match.previous != match.current else { return nil }
        let length = direction.isHorizontal ? current.width : current.height
        let visionCandidate = visionScrollOffset(previous: previous, current: current,
            excludedTop: max(match.top, ScrollFrameAnalyzer.frozenTopRows(current: current,
                previous: previous, rightMarginPx: match.right).flatMap { $0 < current.height / 2 ? $0 : nil } ?? 0),
            excludedRight: match.right, excludedBottom: match.bottom, direction: direction)
        if let candidate = visionCandidate,
           let score = match.score(candidate, direction: direction), score.isConfident {
            // A sparse ambiguity scan keeps repeated rows safe without running the
            // full pixel search after every successful Vision registration.
            let ambiguous = (2...max(2, length * 4 / 5)).contains { distance in
                guard abs(distance - abs(candidate)) > 2,
                      let other = match.score(distance * direction.sign, direction: direction, sampleLimit: 16),
                      other.isConfident else { return false }
                return other.error <= score.error + max(2, score.error * 0.5)
                    && other.relativeError <= score.relativeError * 1.5 + 0.05
            }
            if !ambiguous { return (candidate, score) }
        }
        let minimum = max(2, length / 50)
        let maximum = min(length * 4 / 5,
                          length - (direction.isHorizontal ? 0 : match.top)
                              - max(12, length / 5))
        guard minimum <= maximum else { return nil }

        let step = max(1, length / 500)
        var coarse: [(offset: Int, score: ScrollMatch.Score)] = []
        for distance in stride(from: minimum, through: maximum, by: step) {
            let offset = distance * direction.sign
            if let score = match.score(offset, direction: direction) {
                coarse.append((offset, score))
            }
        }
        if let candidate = visionCandidate, (minimum...maximum).contains(abs(candidate)),
           let score = match.score(candidate, direction: direction) {
            coarse.append((candidate, score))
        }
        let likely = coarse.sorted { $0.score.error < $1.score.error }.prefix(24)
        let seeds = Set(likely.map(\.offset) + coarse.filter(\.score.isConfident).map(\.offset))
        var candidates: [Int: ScrollMatch.Score] = [:]
        var refined = Set<Int>()
        for seed in seeds {
            for distance in max(minimum, abs(seed) - step)...min(maximum, abs(seed) + step)
            where refined.insert(distance).inserted {
                let offset = distance * direction.sign
                guard let score = match.score(offset, direction: direction),
                      score.isConfident else { continue }
                candidates[offset] = score
            }
        }
        var basins: [(offset: Int, score: ScrollMatch.Score)] = []
        var previousOffset: Int?
        for offset in candidates.keys.sorted() {
            let score = candidates[offset]!
            if let previousOffset, offset - previousOffset <= step, let last = basins.last {
                if score.error < last.score.error { basins[basins.count - 1] = (offset, score) }
            } else {
                basins.append((offset, score))
            }
            previousOffset = offset
        }
        guard let best = basins.min(by: { $0.score.error < $1.score.error }) else { return nil }
        let rivals = basins
            .filter { $0.score.error - best.score.error <= max(2, best.score.error * 0.5)
                && $0.score.relativeError <= best.score.relativeError * 1.5 + 0.05 }
            .sorted { $0.score.evidence > $1.score.evidence }
        // Repeated content can match at several offsets. Wait for another frame
        // rather than permanently joining at an arbitrary row or column.
        guard rivals.count == 1 || rivals[0].score.evidence >= rivals[1].score.evidence * 2 else { return nil }
        return rivals[0]
    }

    private nonisolated struct ScrollMatch {
        struct Score {
            let error: Double
            let trimmedError: Double
            let relativeError: Double
            let evidence: Int

            /// Scores aligned differences, ignoring the worst half so fading or animated content cannot hide a true match.
            init?(alignedHistogram histogram: [Int], unchangedPositionError: Int, stride: Int) {
                let changed = histogram.reduce(0, +)
                guard changed >= 20 else { return nil }
                let kept = changed - changed / 2
                var remaining = kept
                var trimmedSum = 0
                var alignedSum = 0
                for (value, count) in histogram.enumerated() {
                    let taken = min(count, remaining)
                    trimmedSum += value * taken
                    remaining -= taken
                    alignedSum += value * count
                }
                error = Double(alignedSum) / Double(changed * 3)
                trimmedError = Double(trimmedSum) / Double(kept * 3)
                relativeError = Double(alignedSum) / Double(unchangedPositionError)
                evidence = histogram[..<36].reduce(0, +) * stride
            }

            var isConfident: Bool {
                trimmedError <= 1.5 && error <= 32 && relativeError <= 0.35
            }
        }

        let previous: Data
        let current: Data
        let width: Int
        let height: Int
        let top: Int
        let right: Int
        let bottom: Int

        init?(previous: CGImage, current: CGImage, excludedTop: Int, excludedRight: Int) {
            guard previous.width == current.width, previous.height == current.height,
                  previous.width > 20, previous.height > 20,
                  let previousPixels = ScrollCaptureController.normalizedPixelData(for: previous),
                  let currentPixels = ScrollCaptureController.normalizedPixelData(for: current) else { return nil }
            self.previous = previousPixels
            self.current = currentPixels
            width = current.width
            height = current.height
            top = min(max(0, excludedTop), height / 5)
            right = min(max(0, excludedRight), width / 5)
            bottom = Self.pinnedBottomRows(previous: previousPixels, current: currentPixels,
                                           width: width, height: height, sampledWidth: width - right)
        }

        /// Counts trailing rows that stay unchanged between frames, such as a pinned footer or composer.
        private static func pinnedBottomRows(previous: Data, current: Data,
                                             width: Int, height: Int, sampledWidth: Int) -> Int {
            let xStep = max(1, sampledWidth / 96)
            let rowBytes = width * 4
            return previous.withUnsafeBytes { previousRaw in
                current.withUnsafeBytes { currentRaw in
                    let old = previousRaw.bindMemory(to: UInt8.self)
                    let new = currentRaw.bindMemory(to: UInt8.self)
                    var rows = 0
                    while rows < height / 3 {
                        let rowStart = (height - 1 - rows) * rowBytes
                        var samples = 0
                        var moved = 0
                        for x in stride(from: 0, to: sampledWidth, by: xStep) {
                            let index = rowStart + x * 4
                            samples += 1
                            if abs(Int(old[index]) - Int(new[index]))
                                + abs(Int(old[index + 1]) - Int(new[index + 1]))
                                + abs(Int(old[index + 2]) - Int(new[index + 2])) >= 36 {
                                moved += 1
                            }
                        }
                        guard moved * 10 <= samples else { break }
                        rows += 1
                    }
                    return rows >= 10 && rows < height / 3 ? rows : 0
                }
            }
        }

        func score(_ offset: Int, direction: ScrollDirection, sampleLimit: Int = 96) -> Score? {
            if direction.isHorizontal { return scoreHorizontal(offset, sampleLimit: sampleLimit) }
            let overlapEnd = height - offset - bottom
            guard offset > 0, overlapEnd - top >= max(12, height / 5) else { return nil }
            let sampledWidth = width - right
            let xStep = max(1, sampledWidth / sampleLimit)
            let yStep = max(1, (overlapEnd - top) / min(64, sampleLimit))
            let rowBytes = width * 4
            return previous.withUnsafeBytes { previousRaw in
                current.withUnsafeBytes { currentRaw in
                    let old = previousRaw.bindMemory(to: UInt8.self)
                    let new = currentRaw.bindMemory(to: UInt8.self)
                    var histogram = [Int](repeating: 0, count: 766)
                    var unchangedPositionError = 0
                    for y in stride(from: top, to: overlapEnd, by: yStep) {
                        for x in stride(from: 0, to: sampledWidth, by: xStep) {
                            let currentIndex = y * rowBytes + x * 4
                            let sameIndex = currentIndex
                            let shiftedIndex = (y + offset) * rowBytes + x * 4
                            let same = abs(Int(old[sameIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[sameIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[sameIndex + 2]) - Int(new[currentIndex + 2]))
                            guard same >= 8 else { continue }
                            let aligned = abs(Int(old[shiftedIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[shiftedIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[shiftedIndex + 2]) - Int(new[currentIndex + 2]))
                            histogram[aligned] += 1
                            unchangedPositionError += same
                        }
                    }
                    return Score(alignedHistogram: histogram,
                                 unchangedPositionError: unchangedPositionError, stride: yStep)
                }
            }
        }

        private func scoreHorizontal(_ offset: Int, sampleLimit: Int) -> Score? {
            let overlapStart = max(0, -offset)
            // Keep the right margin out of both frames after alignment.
            let overlapEnd = min(width - right, width - right - offset)
            guard offset != 0,
                  overlapEnd - overlapStart >= max(12, width / 5) else { return nil }
            let xStep = max(1, (overlapEnd - overlapStart) / min(64, sampleLimit))
            let yStep = max(1, (height - top) / sampleLimit)
            let rowBytes = width * 4
            return previous.withUnsafeBytes { previousRaw in
                current.withUnsafeBytes { currentRaw in
                    let old = previousRaw.bindMemory(to: UInt8.self)
                    let new = currentRaw.bindMemory(to: UInt8.self)
                    var histogram = [Int](repeating: 0, count: 766)
                    var unchangedPositionError = 0
                    for y in stride(from: top, to: height, by: yStep) {
                        for x in stride(from: overlapStart, to: overlapEnd, by: xStep) {
                            let currentIndex = y * rowBytes + x * 4
                            let shiftedIndex = y * rowBytes + (x + offset) * 4
                            let same = abs(Int(old[currentIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[currentIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[currentIndex + 2]) - Int(new[currentIndex + 2]))
                            guard same >= 8 else { continue }
                            let aligned = abs(Int(old[shiftedIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[shiftedIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[shiftedIndex + 2]) - Int(new[currentIndex + 2]))
                            histogram[aligned] += 1
                            unchangedPositionError += same
                        }
                    }
                    return Score(alignedHistogram: histogram,
                                 unchangedPositionError: unchangedPositionError, stride: xStep)
                }
            }
        }
    }

    // ScreenCaptureKit can pad pixel rows with changing unused bytes. Compare
    // rendered pixels, not the provider buffer, when deciding that scrolling ended.
    nonisolated static func framesEqual(_ first: CGImage, _ second: CGImage) -> Bool {
        guard first.width == second.width, first.height == second.height,
              let firstPixels = normalizedPixelData(for: first),
              let secondPixels = normalizedPixelData(for: second) else { return false }
        return firstPixels == secondPixels
    }

    private nonisolated static func normalizedPixelData(for image: CGImage) -> Data? {
        let bytesPerRow = image.width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        return Data(bytes: data, count: bytesPerRow * image.height)
    }

    private func detectRightMargin(current: CGImage, previous: CGImage) {
        // Only mark detection as done once a comparable pair actually arrived.
        // Setting it up front let one odd pair (a resize mid-session, say)
        // disable scrollbar exclusion for the rest of the capture.
        guard let scrollbarWidth = ScrollFrameAnalyzer.scrollbarWidth(current: current, previous: previous) else { return }
        rightMarginDetected = true

        if scrollbarWidth >= 3 && scrollbarWidth <= 40 {
            rightMarginPx = scrollbarWidth + 4
        }
    }

    // MARK: - Header (frozen region) detection

    private func detectHeader(current: CGImage, previous: CGImage, shiftPx: Int) {
        guard shiftPx > 5 else { return }
        guard let frozenRows = ScrollFrameAnalyzer.frozenTopRows(
            current: current, previous: previous, rightMarginPx: rightMarginPx) else { return }

        let h = current.height
        // Nothing changed anywhere: this pair says nothing about a header, so
        // leave detection open for the next frame instead of freezing the
        // whole capture area.
        guard frozenRows < h else { return }

        if frozenRows >= 10 && frozenRows < (h * 6 / 10) {
            headerHeight = frozenRows
            frozenTopHeight = CGFloat(headerHeight) / backingScale
            headerDetectionDone = true
        } else if frozenRows < 10 {
            headerDetectionDone = true
        }
    }

    private func emitPreview() {
        guard let cg = mergedImage, let callback = onPreviewUpdated else { return }
        let ptSize = CGSize(width: CGFloat(cg.width) / backingScale,
                            height: CGFloat(cg.height) / backingScale)
        callback(NSImage(cgImage: cg, size: ptSize))
    }
}
