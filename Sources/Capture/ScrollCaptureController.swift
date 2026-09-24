import Cocoa
import ScreenCaptureKit

@MainActor
final class ScrollCaptureController {

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

    var excludedWindowIDs: [CGWindowID] = []

    private var maxScrollHeight: Int = 30000
    private var frozenDetectionEnabled: Bool = true

    private let captureRect: NSRect
    private let screen: NSScreen
    private let backingScale: CGFloat

    private let captureQueue = DispatchQueue(label: "bettershot.scrollcapture", qos: .userInitiated)

    private var shotA: CGImage?
    private var mergedImage: CGImage?
    private var headerHeight: Int = 0
    private var headerDetectionDone: Bool = false
    private var headerDetectionSamples: Int = 0

    private var rightMarginPx: Int = 0
    private var rightMarginDetected: Bool = false

    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal: Any?

    private let manualCaptureInterval: TimeInterval = 0.15
    private var lastCaptureTime: TimeInterval = 0
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

        cachedContentFilter = nil

        // Mark the session active before the first awaited frame so Stop can
        // cancel a capture that is still settling.
        isActive = true

        guard let firstFrame = await captureSettledFrame() else {
            if !isCancelled { finishSession(with: nil) }
            return
        }
        guard isActive, !isCancelled else { return }
        shotA = firstFrame
        mergedImage = firstFrame
        headerHeight = 0
        headerDetectionDone = false
        headerDetectionSamples = 0
        rightMarginPx = 0
        rightMarginDetected = false
        frozenTopHeight = 0
        stripCount = 1

        stitchedImage = firstFrame
        stitchedPixelSize = CGSize(width: CGFloat(firstFrame.width), height: CGFloat(firstFrame.height))
        emitPreview()
        onStripAdded?(stripCount)

        startManualScrollMonitors()
    }

    func stopSession() {
        guard isActive, !isStopping else { return }
        isStopping = true
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
                return cg
            }

            previousTIFF = currentTIFF
            previousCG = cg
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        return previousCG
    }

    private func captureAndCompare() async -> Bool {
        guard let currentFrame = await captureSettledFrame(), isActive else { return false }
        return processFrame(currentFrame)
    }

    @discardableResult
    private func processFrame(_ currentFrame: CGImage) -> Bool {
        guard let previousFrame = shotA else { return false }

        if !rightMarginDetected {
            detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        guard let offsetPx = Self.matchedScrollOffset(
            previous: previousFrame, current: currentFrame,
            excludedTop: headerDetectionDone ? headerHeight : 0,
            excludedRight: rightMarginPx
        ) else {
            return false
        }

        if frozenDetectionEnabled && !headerDetectionDone {
            detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        guard mergeNewContent(currentFrame: currentFrame, offsetPx: offsetPx) else {
            if hasReachedMaximumHeight { stopSession() }
            return false
        }

        shotA = currentFrame
        stripCount += 1

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
            offsetPx: offsetPx,
            rowsToAppend: newRows
        ) else { return false }
        mergedImage = merged
        stitchedImage = merged
        stitchedPixelSize = CGSize(width: CGFloat(merged.width), height: CGFloat(merged.height))
        return true
    }

    static func mergedImage(
        existing: CGImage,
        currentFrame: CGImage,
        offsetPx: Int,
        rowsToAppend: Int? = nil
    ) -> CGImage? {
        let newRows = rowsToAppend ?? offsetPx
        guard existing.width == currentFrame.width,
              offsetPx > 0, offsetPx <= currentFrame.height,
              newRows > 0, newRows <= offsetPx else { return nil }

        let width = currentFrame.width
        let totalHeight = existing.height + newRows
        let colorSpace = existing.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: nil, width: width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        context.draw(existing, in: CGRect(x: 0, y: newRows, width: width, height: existing.height))
        let stripY = currentFrame.height - offsetPx
        guard let strip = currentFrame.cropping(to: CGRect(
            x: 0, y: stripY, width: width, height: newRows
        )) else { return nil }
        context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: newRows))
        return context.makeImage()
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
        guard isActive, !isStopping else { return }

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
        guard isActive, !isStopping, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let currentFrame = await captureFrame() else { return }
        guard isActive else { return }
        processFrame(currentFrame)
    }

    private func settledCapture(final: Bool = false) async {
        while isActive && isCapturing {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard isActive, (final || !isStopping) else { return }
        isCapturing = true
        defer { isCapturing = false }

        _ = await captureAndCompare()
    }

    /// A scrolling frame overlaps the previous one at current[y] == previous[y + offset].
    /// Compare only pixels that changed at the same screen location, so fixed
    /// toolbars and empty backgrounds cannot vote for a false zero shift.
    static func validatedScrollOffset(
        previous: CGImage, current: CGImage, candidate: Int,
        excludedTop: Int, excludedRight: Int
    ) -> Int? {
        guard let match = ScrollMatch(previous: previous, current: current,
                                      excludedTop: excludedTop, excludedRight: excludedRight),
              let score = match.score(candidate), score.isConfident else { return nil }
        return candidate
    }

    static func matchedScrollOffset(
        previous: CGImage, current: CGImage,
        excludedTop: Int, excludedRight: Int
    ) -> Int? {
        guard let match = ScrollMatch(previous: previous, current: current,
                                      excludedTop: excludedTop, excludedRight: excludedRight) else { return nil }
        let minimum = max(2, current.height / 50)
        let maximum = min(current.height * 4 / 5,
                          current.height - match.top - max(12, current.height / 5))
        guard minimum <= maximum else { return nil }

        let step = max(1, current.height / 500)
        var coarse: [(offset: Int, score: ScrollMatch.Score)] = []
        for offset in stride(from: minimum, through: maximum, by: step) {
            if let score = match.score(offset) { coarse.append((offset, score)) }
        }
        let likely = coarse.sorted { $0.score.error < $1.score.error }.prefix(24)
        var candidates: [Int: ScrollMatch.Score] = [:]
        for entry in coarse where entry.score.isConfident {
            candidates[entry.offset] = entry.score
        }
        for entry in likely {
            for offset in max(minimum, entry.offset - step)...min(maximum, entry.offset + step) {
                guard let score = match.score(offset), score.isConfident else { continue }
                candidates[offset] = score
            }
        }
        let ranked = candidates.sorted { $0.value.error < $1.value.error }
        guard let best = ranked.first else { return nil }
        // Repeated rows can match at several offsets. Wait for another frame
        // rather than permanently joining it at an arbitrary repeated row.
        if let runnerUp = ranked.first(where: { abs($0.key - best.key) > max(1, step) }),
           runnerUp.value.error - best.value.error <= max(2, best.value.error * 0.5) {
            return nil
        }
        return best.key
    }

    private struct ScrollMatch {
        struct Score {
            let error: Double
            let relativeError: Double
            let support: Int

            var isConfident: Bool {
                support >= 20 && error <= 8 && relativeError <= 0.12
            }
        }

        let previous: Data
        let current: Data
        let width: Int
        let height: Int
        let top: Int
        let right: Int

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
        }

        func score(_ offset: Int) -> Score? {
            let overlapEnd = height - offset
            guard offset > 0, overlapEnd - top >= max(12, height / 5) else { return nil }
            let sampledWidth = width - right
            let xStep = max(1, sampledWidth / 96)
            let yStep = max(1, (overlapEnd - top) / 64)
            let rowBytes = width * 4
            return previous.withUnsafeBytes { previousRaw in
                current.withUnsafeBytes { currentRaw in
                    let old = previousRaw.bindMemory(to: UInt8.self)
                    let new = currentRaw.bindMemory(to: UInt8.self)
                    var changed = 0
                    var unchangedPositionError = 0
                    var alignedError = 0
                    for y in stride(from: top, to: overlapEnd, by: yStep) {
                        for x in stride(from: 0, to: sampledWidth, by: xStep) {
                            let currentIndex = y * rowBytes + x * 4
                            let sameIndex = currentIndex
                            let shiftedIndex = (y + offset) * rowBytes + x * 4
                            let same = abs(Int(old[sameIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[sameIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[sameIndex + 2]) - Int(new[currentIndex + 2]))
                            guard same >= 36 else { continue }
                            let aligned = abs(Int(old[shiftedIndex]) - Int(new[currentIndex]))
                                + abs(Int(old[shiftedIndex + 1]) - Int(new[currentIndex + 1]))
                                + abs(Int(old[shiftedIndex + 2]) - Int(new[currentIndex + 2]))
                            changed += 1
                            unchangedPositionError += same
                            alignedError += aligned
                        }
                    }
                    guard changed >= 20, unchangedPositionError > 0 else { return nil }
                    return Score(error: Double(alignedError) / Double(changed * 3),
                                 relativeError: Double(alignedError) / Double(unchangedPositionError),
                                 support: changed)
                }
            }
        }
    }

    private static func normalizedPixelData(for image: CGImage) -> Data? {
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
        guard let curData = Self.normalizedPixelData(for: current),
              let prevData = Self.normalizedPixelData(for: previous) else { return }
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

        guard let curData = Self.normalizedPixelData(for: current),
              let prevData = Self.normalizedPixelData(for: previous) else { return }

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
            headerHeight = 0
            frozenTopHeight = 0
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
