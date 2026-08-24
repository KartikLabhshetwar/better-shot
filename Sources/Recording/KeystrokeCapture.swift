import AppKit
import CoreGraphics
import Foundation

/// Records what was typed while the screen was captured, so the editor can show the keys instead of leaving viewers guessing.
final class KeystrokeRecorder: @unchecked Sendable {
    private static let specialKeys: [UInt16: String] = [
        36: "Return",
        76: "Return",
        48: "Tab",
        49: "Space",
        51: "Backspace",
        53: "Escape",
        115: "Home",
        116: "PageUp",
        117: "Delete",
        119: "End",
        121: "PageDown",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up",
    ]

    private let lock = NSLock()
    private var presses: [KeyPress] = []
    private var startUptime: TimeInterval = 0
    private var isPaused = false
    private var monitor: Any?

    /// Listening to the keyboard from outside our own windows is Input Monitoring, which the user grants once in System Settings.
    static var isPermitted: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    @MainActor
    func start() {
        stopMonitor()
        lock.withLock {
            startUptime = ProcessInfo.processInfo.systemUptime
            isPaused = false
            presses = []
        }

        let handler: @Sendable (NSEvent) -> Void = { [weak self] event in
            guard let key = KeystrokeRecorder.name(for: event) else { return }
            self?.append(key: key, modifiers: KeystrokeRecorder.modifiers(for: event))
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handler)
    }

    @MainActor
    func stop() -> KeystrokeCaptureFile {
        stopMonitor()
        return lock.withLock { KeystrokeCaptureFile(presses: presses) }
    }

    func pause() {
        lock.withLock { isPaused = true }
    }

    func resume() {
        lock.withLock { isPaused = false }
    }

    @MainActor
    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func append(key: String, modifiers: KeyModifiers) {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        let time = ProcessInfo.processInfo.systemUptime - startUptime
        guard time >= 0 else { return }
        presses.append(KeyPress(time: time, key: key, modifiers: modifiers))
    }

    private nonisolated static func name(for event: NSEvent) -> String? {
        if let special = specialKeys[event.keyCode] { return special }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else { return nil }
        return characters
    }

    private nonisolated static func modifiers(for event: NSEvent) -> KeyModifiers {
        let flags = event.modifierFlags
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
