import AppKit
import CoreGraphics
import Foundation

nonisolated struct PointerTravelSample: Codable, Sendable {
    var time: TimeInterval
    var x: Double
    var y: Double
}

nonisolated struct PointerPressEvent: Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case down
    }

    var time: TimeInterval
    var x: Double
    var y: Double
    var phase: Phase
}

nonisolated struct PointerCaptureFile: Codable, Sendable {
    var travel: [PointerTravelSample] = []
    var presses: [PointerPressEvent] = []
}

final class PointerCaptureRecorder: @unchecked Sendable {
    private static let sampleInterval: TimeInterval = 1.0 / 30.0

    private let lock = NSLock()
    private var travel: [PointerTravelSample] = []
    private var presses: [PointerPressEvent] = []
    private var captureRect: CGRect = .zero
    private var startUptime: TimeInterval = 0
    private var isPaused = false

    private var timer: DispatchSourceTimer?
    private var pressMonitor: Any?

    @MainActor
    func start(captureRect: CGRect) {
        stopMonitors()
        lock.withLock {
            self.captureRect = captureRect
            self.startUptime = ProcessInfo.processInfo.systemUptime
            self.isPaused = false
            self.travel = []
            self.presses = []
        }

        let queue = DispatchQueue(label: "com.bettershot.recording.pointer", qos: .utility)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: Self.sampleInterval)
        let sampleHandler: @Sendable () -> Void = { [weak self] in
            self?.sampleTravel()
        }
        source.setEventHandler(handler: sampleHandler)
        source.resume()
        timer = source

        let pressHandler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            self?.recordPress()
        }
        pressMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: pressHandler)
    }

    @MainActor
    func stop() -> PointerCaptureFile {
        stopMonitors()
        return lock.withLock { PointerCaptureFile(travel: travel, presses: presses) }
    }

    func pause() {
        lock.withLock { isPaused = true }
    }

    func resume() {
        lock.withLock { isPaused = false }
    }

    @MainActor
    private func stopMonitors() {
        timer?.cancel()
        timer = nil
        if let pressMonitor {
            NSEvent.removeMonitor(pressMonitor)
        }
        pressMonitor = nil
    }

    private func sampleTravel() {
        guard let location = CGEvent(source: nil)?.location else { return }
        appendTravel(location: location)
    }

    private func recordPress() {
        guard let location = CGEvent(source: nil)?.location else { return }
        appendPress(location: location)
    }

    private func appendTravel(location: CGPoint) {
        guard let normalized = normalizedPoint(for: location) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        let time = ProcessInfo.processInfo.systemUptime - startUptime
        guard time >= 0 else { return }
        travel.append(PointerTravelSample(time: time, x: normalized.x, y: normalized.y))
    }

    private func appendPress(location: CGPoint) {
        guard let normalized = normalizedPoint(for: location) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        let time = ProcessInfo.processInfo.systemUptime - startUptime
        guard time >= 0 else { return }
        presses.append(PointerPressEvent(time: time, x: normalized.x, y: normalized.y, phase: .down))
    }

    private func normalizedPoint(for location: CGPoint) -> CGPoint? {
        lock.lock()
        let rect = captureRect
        lock.unlock()
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = (location.x - rect.minX) / rect.width
        let y = (location.y - rect.minY) / rect.height
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
