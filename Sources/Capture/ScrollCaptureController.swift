import Cocoa
import ScreenCaptureKit
import Vision

@MainActor
final class ScrollCaptureController {

    private(set) var stripCount: Int = 0
    private(set) var stitchedImage: CGImage?
    private(set) var stitchedPixelSize: CGSize = .zero
    private(set) var isActive: Bool = false
    private(set) var frozenTopHeight: CGFloat = 0
    private var isCancelled: Bool = false
    private var didFinishSession: Bool = false

    var estimatedTotalHeight: CGFloat {
        guard let merged = mergedImage else { return 0 }
        return CGFloat(merged.height) / backingScale
    }

    var onStripAdded: ((Int) -> Void)?
    var onSessionDone: ((NSImage?) -> Void)?
    var onAutoScrollStarted: (() -> Void)?
    var onPreviewUpdated: ((NSImage) -> Void)?

    var excludedWindowIDs: [CGWindowID] = []

    private var autoScrollEnabled: Bool = false
    private var autoScrollSpeed: Int = 3
    private var maxScrollHeight: Int = 30000
    private var frozenDetectionEnabled: Bool = true

    private let captureRect: NSRect
    private let screen: NSScreen
    private let backingScale: CGFloat

    private let captureQueue = DispatchQueue(label: "bettershot.scrollcapture", qos: .userInitiated)

    private var shotA: CGImage?
    private var shotB: CGImage?
    private var lastComparedTIFF: Data?
    private var mergedImage: CGImage?
    private var headerHeight: Int = 0
    private var headerDetectionDone: Bool = false
    private var headerDetectionSamples: Int = 0

    private var rightMarginPx: Int = 0
    private var rightMarginDetected: Bool = false

    private var matchNotFoundCount: Int = 0
    private let maxMatchNotFound: Int = 8
    private var didReportFirstMatch: Bool = false
    private var hasScrolledOnce: Bool = false
    private var consecutiveZeroShifts: Int = 0
    private let maxZeroShiftsBeforeStop: Int = 6

    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal: Any?

    private(set) var autoScrollActive: Bool = false
    private var autoScrollTask: Task<Void, Never>?

    private let manualCaptureInterval: TimeInterval = 0.15
    private var lastCaptureTime: TimeInterval = 0
    private var pendingCaptureTask: Task<Void, Never>?
    private var settlementTimer: Timer?
    private let settlementInterval: TimeInterval = 0.25

    private var isCapturing: Bool = false

    private var targetAppPID: pid_t = 0

    private var targetWindowID: CGWindowID = kCGNullWindowID
    private var captureRectCG: CGRect = .zero
    private var cachedContentFilter: SCContentFilter?

    init(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.screen = screen
        self.backingScale = screen.backingScaleFactor
    }

    func startSession() async {
        guard !isActive, !isCancelled, !didFinishSession else { return }

        let ud = UserDefaults.standard
        autoScrollEnabled = ud.object(forKey: "scrollAutoScrollEnabled") as? Bool ?? false
        autoScrollSpeed = ud.object(forKey: "scrollAutoScrollSpeed") as? Int ?? 3
        maxScrollHeight = ud.object(forKey: "scrollMaxHeight") as? Int ?? 30000
        frozenDetectionEnabled = ud.object(forKey: "scrollFrozenDetection") as? Bool ?? true

        let primaryScreenH = CGDisplayBounds(CGMainDisplayID()).height
        captureRectCG = CGRect(
            x: captureRect.origin.x,
            y: primaryScreenH - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )

        cachedContentFilter = nil
        resolveTargetWindow()
        resolveTargetApp()

        // Mark the session active before the first awaited frame so Stop can
        // cancel a capture that is still settling.
        isActive = true

        guard let firstFrame = await captureSettledFrame() else {
            if !isCancelled { finishSession(with: nil) }
            return
        }
        guard isActive, !isCancelled else { return }
        shotA = nil
        shotB = nil
        lastComparedTIFF = nil
        mergedImage = firstFrame
        headerHeight = 0
        headerDetectionDone = false
        headerDetectionSamples = 0
        rightMarginPx = 0
        rightMarginDetected = false
        matchNotFoundCount = 0
        didReportFirstMatch = false
        hasScrolledOnce = false
        consecutiveZeroShifts = 0
        frozenTopHeight = 0
        stripCount = 1

        stitchedImage = firstFrame
        stitchedPixelSize = CGSize(width: CGFloat(firstFrame.width), height: CGFloat(firstFrame.height))
        emitPreview()
        onStripAdded?(stripCount)

        if autoScrollEnabled {
            startAutoScroll()
        } else {
            startManualScrollMonitors()
        }
    }

    func stopSession() {
        guard isActive else { return }
        finishSession(with: mergedImage)
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
        autoScrollTask?.cancel(); autoScrollTask = nil
        settlementTimer?.invalidate(); settlementTimer = nil
        pendingCaptureTask?.cancel(); pendingCaptureTask = nil
        if let monitor = scrollMonitorGlobal { NSEvent.removeMonitor(monitor); scrollMonitorGlobal = nil }
        if let monitor = scrollMonitorLocal { NSEvent.removeMonitor(monitor); scrollMonitorLocal = nil }
        autoScrollActive = false
    }

    private func resolveTargetWindow() {
        let centerX = captureRectCG.midX
        let centerY = captureRectCG.midY

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let excluded = Set(excludedWindowIDs)
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let winID = info[kCGWindowNumber as String] as? Int,
                  !excluded.contains(CGWindowID(winID))
            else { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            let cgRect = CGRect(x: x, y: y, width: w, height: h)

            if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                targetWindowID = CGWindowID(winID)
                return
            }
        }
    }

    private func resolveTargetApp() {
        let centerX = captureRectCG.midX
        let centerY = captureRectCG.midY

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let excluded = Set(excludedWindowIDs)
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let winID = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  !excluded.contains(CGWindowID(winID))
            else { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            let cgRect = CGRect(x: x, y: y, width: w, height: h)

            if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                targetAppPID = pid
                return
            }
        }
    }

    private func activateTargetApp() {
        guard targetAppPID != 0 else { return }
        NSRunningApplication(processIdentifier: targetAppPID)?.activate(options: [])
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
        let excludedWindows = content.windows.filter { excluded.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
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
            guard !isCancelled else { return nil }
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
            guard !isCancelled else { return nil }
            guard let currentTIFF = tiffData else {
                try? await Task.sleep(nanoseconds: waitNs)
                waitNs = min(waitNs * 3 / 2, 80_000_000)
                continue
            }

            if let prevTIFF = previousTIFF, currentTIFF == prevTIFF {
                lastComparedTIFF = currentTIFF
                return cg
            }

            previousTIFF = currentTIFF
            previousCG = cg
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        return previousCG
    }

    private func startAutoScroll() {
        autoScrollActive = true
        onAutoScrollStarted?()

        let primaryScreenH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cursorX = captureRect.midX
        let cursorY = primaryScreenH - captureRect.midY
        CGWarpMouseCursorPosition(CGPoint(x: cursorX, y: cursorY))

        activateTargetApp()

        let linesPerTick: Int32
        switch autoScrollSpeed {
        case 1: linesPerTick = 1
        case 2: linesPerTick = 1
        case 4: linesPerTick = 2
        default: linesPerTick = 1
        }

        let burstCount: Int
        switch autoScrollSpeed {
        case 1: burstCount = 1
        case 2: burstCount = 2
        case 4: burstCount = 4
        default: burstCount = 3
        }

        autoScrollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self = self, self.isActive, self.autoScrollActive else { return }
            await self.autoScrollLoop(linesPerTick: linesPerTick, burstCount: burstCount)
        }
    }

    private func autoScrollLoop(linesPerTick: Int32, burstCount: Int) async {
        while isActive && autoScrollActive {
            if hasReachedMaximumHeight {
                stopSession()
                return
            }
            for _ in 0..<burstCount {
                if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                       wheel1: -linesPerTick, wheel2: 0, wheel3: 0) {
                    event.post(tap: .cghidEventTap)
                }
            }

            let success = await captureAndCompare()

            if !success {
                matchNotFoundCount += 1
                if matchNotFoundCount >= maxMatchNotFound {
                    stopSession()
                    return
                }
            } else {
                matchNotFoundCount = 0
            }

            if let merged = mergedImage, maxScrollHeight > 0 {
                if merged.height >= maxScrollHeight {
                    stopSession()
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func captureAndCompare() async -> Bool {
        try? await Task.sleep(nanoseconds: 50_000_000)

        var previousTIFF: Data? = nil
        var settledCG: CGImage? = nil
        var waitNs: UInt64 = 12_000_000

        for _ in 0..<30 {
            guard isActive else { return false }

            guard let cg = await captureFrame() else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }
            guard isActive else { return false }

            let tiffData: Data? = await withCheckedContinuation { cont in
                captureQueue.async {
                    let bitmapRep = NSBitmapImageRep(cgImage: cg)
                    cont.resume(returning: bitmapRep.tiffRepresentation)
                }
            }
            guard isActive else { return false }
            guard let currentTIFF = tiffData else {
                try? await Task.sleep(nanoseconds: waitNs)
                waitNs = min(waitNs * 3 / 2, 80_000_000)
                continue
            }

            if let prevTIFF = previousTIFF, currentTIFF == prevTIFF {
                settledCG = cg
                lastComparedTIFF = currentTIFF
                break
            }

            previousTIFF = currentTIFF
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        guard let currentFrame = settledCG else { return false }
        guard let previousFrame = shotA ?? mergedImage?.cropping(to: CGRect(
            x: 0, y: 0, width: currentFrame.width, height: currentFrame.height
        )) else {
            shotA = currentFrame
            return false
        }

        if !rightMarginDetected {
            detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        guard let offset = visionShift(current: currentFrame, previous: previousFrame) else {
            shotA = currentFrame
            consecutiveZeroShifts += 1
            if hasScrolledOnce && consecutiveZeroShifts >= maxZeroShiftsBeforeStop {
                stopSession()
            }
            return false
        }

        let offsetPx = Int(round(offset))
        guard offsetPx > 0 else {
            shotA = currentFrame
            return false
        }

        let minShift = currentFrame.height / 10
        if offsetPx < minShift {
            return false
        }

        consecutiveZeroShifts = 0
        hasScrolledOnce = true

        if frozenDetectionEnabled && !headerDetectionDone {
            detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        let safeOffset = max(1, offsetPx - 1)

        guard mergeNewContent(currentFrame: currentFrame, offsetPx: safeOffset) else {
            if hasReachedMaximumHeight { stopSession() }
            return false
        }

        shotA = currentFrame
        stripCount += 1
        didReportFirstMatch = true

        emitPreview()
        onStripAdded?(stripCount)

        return true
    }

    private var hasReachedMaximumHeight: Bool {
        maxScrollHeight > 0 && (mergedImage?.height ?? 0) >= maxScrollHeight
    }

    @discardableResult
    private func mergeNewContent(currentFrame: CGImage, offsetPx: Int) -> Bool {
        guard let existing = mergedImage else {
            mergedImage = currentFrame
            return true
        }

        let newRows = maxScrollHeight > 0
            ? min(offsetPx, max(0, maxScrollHeight - existing.height))
            : offsetPx
        guard newRows > 0, newRows <= currentFrame.height else { return false }
        guard let merged = Self.mergedImage(
            existing: existing,
            currentFrame: currentFrame,
            offsetPx: newRows
        ) else { return false }
        mergedImage = merged
        stitchedImage = merged
        stitchedPixelSize = CGSize(width: CGFloat(merged.width), height: CGFloat(merged.height))
        return true
    }

    static func mergedImage(
        existing: CGImage,
        currentFrame: CGImage,
        offsetPx: Int
    ) -> CGImage? {
        guard existing.width == currentFrame.width,
              offsetPx > 0, offsetPx <= currentFrame.height else { return nil }

        let width = currentFrame.width
        let totalHeight = existing.height + offsetPx
        let colorSpace = existing.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        context.draw(existing, in: CGRect(x: 0, y: offsetPx, width: width, height: existing.height))
        let stripY = currentFrame.height - offsetPx
        guard let strip = currentFrame.cropping(to: CGRect(
            x: 0, y: stripY, width: width, height: offsetPx
        )) else { return nil }
        context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: offsetPx))
        return context.makeImage()
    }

    private func stopAutoScroll() {
        autoScrollActive = false
        autoScrollTask?.cancel(); autoScrollTask = nil
    }

    func toggleAutoScroll() {
        if autoScrollActive {
            stopAutoScroll()
            startManualScrollMonitors()
        } else {
            if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m); scrollMonitorGlobal = nil }
            if let m = scrollMonitorLocal { NSEvent.removeMonitor(m); scrollMonitorLocal = nil }
            settlementTimer?.invalidate(); settlementTimer = nil
            startAutoScroll()
        }
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

    private func onManualScrollEvent() {
        guard isActive else { return }

        settlementTimer?.invalidate()
        settlementTimer = Timer.scheduledTimer(withTimeInterval: settlementInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.settledCapture() }
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= manualCaptureInterval else { return }
        lastCaptureTime = now

        Task { @MainActor in await self.grabAndProcess() }
    }

    private func grabAndProcess() async {
        guard isActive, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let currentFrame = await captureFrame() else { return }
        guard isActive else { return }
        guard let previousFrame = shotA else {
            shotA = currentFrame
            return
        }

        if !rightMarginDetected {
            detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        guard let offset = visionShift(current: currentFrame, previous: previousFrame) else {
            shotA = currentFrame
            return
        }

        let offsetPx = Int(round(offset))
        guard offsetPx > 0 else {
            shotA = currentFrame
            return
        }

        let minShift = currentFrame.height / 10
        if offsetPx < minShift { return }

        hasScrolledOnce = true
        consecutiveZeroShifts = 0

        if frozenDetectionEnabled && !headerDetectionDone {
            detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        let safeOffset = max(1, offsetPx - 1)
        guard mergeNewContent(currentFrame: currentFrame, offsetPx: safeOffset) else {
            if hasReachedMaximumHeight { stopSession() }
            return
        }

        shotA = currentFrame
        stripCount += 1
        didReportFirstMatch = true

        emitPreview()
        onStripAdded?(stripCount)
    }

    private func settledCapture() async {
        guard isActive, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let _ = await captureAndCompare()
    }

    private func visionShift(current: CGImage, previous: CGImage) -> CGFloat? {
        var curImg = current
        var prevImg = previous
        let maxCropY = current.height / 5
        let cropY = headerDetectionDone ? min(headerHeight, maxCropY) : 0
        let cropW = current.width - rightMarginPx
        let cropH = current.height - cropY
        if cropY > 0 || rightMarginPx > 0 {
            guard cropH > 20 && cropW > 20 else { return nil }
            let cropRect = CGRect(x: 0, y: cropY, width: cropW, height: cropH)
            guard let cc = current.cropping(to: cropRect),
                  let pc = previous.cropping(to: cropRect) else { return nil }
            curImg = cc
            prevImg = pc
        }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: prevImg)
        let handler = VNImageRequestHandler(cgImage: curImg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first as? VNImageTranslationAlignmentObservation else { return nil }
        return obs.alignmentTransform.ty
    }

    private func normalizedPixelData(for image: CGImage) -> Data? {
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
        guard current.width == previous.width, current.height == previous.height else { return }
        guard let curData = normalizedPixelData(for: current),
              let prevData = normalizedPixelData(for: previous) else { return }
        rightMarginDetected = true

        let w = current.width
        let h = current.height
        let bytesPerRow = w * 4

        let rowStart = h * 2 / 10
        let rowEnd = h * 8 / 10
        let rowStep = max(1, (rowEnd - rowStart) / 40)

        var scrollbarWidth = 0
        let maxScanCols = min(50, w / 8)

        for colOffset in 0..<maxScanCols {
            let col = w - 1 - colOffset
            var sad: UInt64 = 0
            var samples: Int = 0

            for row in stride(from: rowStart, to: rowEnd, by: rowStep) {
                let idx = row * bytesPerRow + col * 4
                guard idx + 2 < h * bytesPerRow else { continue }
                sad += UInt64(abs(Int(curData[idx]) - Int(prevData[idx]))
                            + abs(Int(curData[idx + 1]) - Int(prevData[idx + 1]))
                            + abs(Int(curData[idx + 2]) - Int(prevData[idx + 2])))
                samples += 1
            }
            guard samples > 0 else { continue }
            let avgSAD = sad / UInt64(samples)

            if avgSAD > 8 {
                scrollbarWidth = colOffset + 1
            } else if scrollbarWidth > 0 {
                break
            }
        }

        if scrollbarWidth >= 3 && scrollbarWidth <= 40 {
            rightMarginPx = scrollbarWidth + 4
        }
    }

    private func detectHeader(current: CGImage, previous: CGImage, shiftPx: Int) {
        guard current.width == previous.width, current.height == previous.height else { return }
        guard shiftPx > 5 else { return }

        let w = current.width
        let h = current.height

        guard let curData = normalizedPixelData(for: current),
              let prevData = normalizedPixelData(for: previous) else { return }

        let bytesPerRow = w * 4
        let compareBytes = max(4, (w - rightMarginPx)) * 4
        let colStep = 4

        var frozenRows = 0
        for row in 0..<h {
            var rowSAD: UInt64 = 0
            var samples: Int = 0
            let offset = row * bytesPerRow
            for col in stride(from: 0, to: compareBytes, by: colStep * 4) {
                let cR = Int(curData[offset + col])
                let cG = Int(curData[offset + col + 1])
                let cB = Int(curData[offset + col + 2])
                let pR = Int(prevData[offset + col])
                let pG = Int(prevData[offset + col + 1])
                let pB = Int(prevData[offset + col + 2])
                rowSAD += UInt64(abs(cR - pR) + abs(cG - pG) + abs(cB - pB))
                samples += 1
            }
            let avg = samples > 0 ? rowSAD / UInt64(samples) : 999
            if avg > 8 {
                frozenRows = row
                break
            }
            if row == h - 1 { return }
        }

        if frozenRows >= 10 && frozenRows < (h * 6 / 10) {
            headerDetectionSamples += 1

            if headerDetectionSamples == 1 {
                headerHeight = frozenRows
                frozenTopHeight = CGFloat(headerHeight) / backingScale
                headerDetectionDone = true
            } else {
                if abs(frozenRows - headerHeight) <= 5 {
                    headerHeight = min(headerHeight, frozenRows)
                    frozenTopHeight = CGFloat(headerHeight) / backingScale
                } else {
                    headerHeight = 0
                    frozenTopHeight = 0
                }
                headerDetectionDone = true
            }
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
