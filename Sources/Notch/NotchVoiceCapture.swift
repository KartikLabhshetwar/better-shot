import AppKit
import AVFoundation
import Observation

@MainActor @Observable
final class NotchVoiceCapture {
    static let shared = NotchVoiceCapture()
    static let gestureKey = "bs_notchHoldOption"
    static let controlKey = "bs_notchControlCapture"
    static let holdKey = "bs_notchCaptureHoldKey"
    static var captureHoldKey: NotchCaptureHoldKey {
        NotchCaptureHoldKey(rawValue: UserDefaults.standard.string(forKey: holdKey) ?? "") ?? .control
    }
    static var optionUsedForCapture: Bool { controlEnabled && captureHoldKey == .option }
    var controlGesture = NotchControlGesture()
    static var controlEnabled: Bool { UserDefaults.standard.object(forKey: controlKey) as? Bool ?? true }
    private(set) var isPreparing = false
    private var controlOverlay: RegionSelectionOverlay?
    private var swallowMouseUp = false
    private var previousControlApp: NSRunningApplication?
    private var holdActive = false
    private var gestureSession = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var holdTask: Task<Void, Never>?

    func refreshGesture() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        holdTask?.cancel()
        holdActive = false
        controlGesture = NotchControlGesture()
        controlOverlay?.cancelControlDrag()
        guard AppPreferences.presentationMode == .notch,
              UserDefaults.standard.bool(forKey: Self.gestureKey), !Self.optionUsedForCapture,
              ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        // Observe modifier state only; never retain characters or ordinary typing.
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
    }

    private func handle(_ event: NSEvent) {
        guard AppPreferences.presentationMode == .notch, !ShortcutService.shared.isRecordingShortcut else {
            controlGesture = NotchControlGesture()
            return
        }
        guard UserDefaults.standard.bool(forKey: Self.gestureKey), !Self.optionUsedForCapture else { return }
        let optionOnly = event.modifierFlags.intersection([.option, .command, .control, .shift]) == .option
        if event.type != .flagsChanged {
            holdTask?.cancel() // Option+letter shortcuts and accented typing remain untouched.
            return
        }
        if optionOnly && !holdActive {
            holdActive = true
            holdTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await self?.capture(whileHolding: true)
            }
        } else if !optionOnly {
            let wasHeld = holdActive
            holdActive = false
            holdTask?.cancel()
            if wasHeld && gestureSession {
                gestureSession = false
                Task { await NotchQuickEditor.shared.finish() }
            }
        }
    }

    func handleControlEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .leftMouseUp && swallowMouseUp {
            swallowMouseUp = false
            controlOverlay?.updateControlDrag(at: Self.appKitPoint(event.location), ended: true)
            return true
        }
        guard AppPreferences.presentationMode == .notch, Self.controlEnabled,
              !ShortcutService.shared.isRecordingShortcut else {
            controlOverlay?.cancelControlDrag()
            controlGesture = NotchControlGesture()
            return false
        }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        if let overlay = controlOverlay {
            if type == .leftMouseDragged {
                overlay.updateControlDrag(at: Self.appKitPoint(event.location))
                return true
            }
            if type == .keyDown || (type == .flagsChanged && flags.intersection([.control, .option, .command, .shift]) != Self.captureHoldKey.modifier) {
                overlay.cancelControlDrag()
                controlGesture = NotchControlGesture()
                return type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53
            }
            return false
        }
        if type == .leftMouseDown && controlGesture.armed {
            guard !isPreparing, !NotchQuickEditor.shared.isOpen, !ScreenRecordingManager.shared.isActive,
                  !CaptureOrchestrator.shared.captureInProgress, !ScreenCapture.shared.isCapturing else { return false }
            let point = Self.appKitPoint(event.location)
            let screen = NSScreen.screens.first { $0.frame.contains(point) }
            let overlay = RegionSelectionOverlay()
            controlOverlay = overlay
            swallowMouseUp = true
            previousControlApp = NSWorkspace.shared.frontmostApplication
            overlay.beginControlDrag(at: point) { [weak self] outcome in
                guard let self else { return }
                self.controlOverlay = nil
                self.controlGesture = NotchControlGesture()
                let previousApp = self.previousControlApp
                self.previousControlApp = nil
                if case .region = outcome {
                    Task {
                        await CaptureOrchestrator.shared.captureLastRegion(on: screen)
                        previousApp?.activate()
                    }
                }
            }
            return true
        }
        if type == .flagsChanged || type == .keyDown || type == .rightMouseDown {
            _ = controlGesture.update(flags: flags, modifierChanged: type == .flagsChanged, holdKey: Self.captureHoldKey)
        }
        return false
    }

    private static func appKitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }

    func capture(whileHolding: Bool = false) async {
        guard AppPreferences.presentationMode == .notch, !isPreparing, !ScreenCapture.shared.isCapturing, !CaptureOrchestrator.shared.captureInProgress,
              !ScreenRecordingManager.shared.isActive, !NotchQuickEditor.shared.isOpen else { return }
        isPreparing = true
        defer { isPreparing = false }
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        let notch = NotchPresenter.shared
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            notch.captureIssue = ("Microphone access needed", "Allow BetterShot in System Settings → Privacy & Security → Microphone, then try Voice again.")
            notch.show(on: screen)
            return
        }
        guard !whileHolding || holdActive else { return }
        notch.suspendForCapture()
        defer { notch.resumeAfterCapture() }
        await RecordingBarPresenter.shared.hidePickerForCapture()
        do {
            guard let url = try await ScreenCapture.shared.captureFullscreen(on: screen) else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            guard !whileHolding || holdActive else { return }
            ScreenCapture.shared.playShutterSound()
            let retained = ScreenshotHistoryStore.shared.importScreenshot(from: url)
            guard retained != url else { throw CocoaError(.fileWriteUnknown) }
            PreviewOverlay.shared.show(url: retained, on: screen, automaticallyDismiss: false)
            NotchQuickEditor.shared.open(retained, on: screen, fullScreen: whileHolding)
            gestureSession = whileHolding
            await NotchQuickEditor.shared.startVoice()
            if whileHolding && !holdActive {
                gestureSession = false
                Task { await NotchQuickEditor.shared.finish() }
            }
        } catch {
            notch.captureIssue = ("Couldn’t start voice capture", error.localizedDescription)
            notch.show(on: screen)
        }
    }
}

enum NotchCaptureHoldKey: String, CaseIterable, Identifiable {
    case control, option, shift, command
    var id: Self { self }
    var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }
    var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
    var modifier: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }
}

/// The chosen modifier alone arms selection; keyboard chords cancel it before a drag.
struct NotchControlGesture: Equatable {
    private(set) var armed = false
    private var tracking = false

    mutating func update(flags: NSEvent.ModifierFlags, modifierChanged: Bool, holdKey: NotchCaptureHoldKey = .control) -> Bool {
        let modifiers = flags.intersection([.control, .option, .command, .shift])
        if modifiers.isEmpty {
            let capture = armed && modifierChanged
            armed = false
            tracking = false
            return capture
        }
        if !modifierChanged || modifiers != holdKey.modifier { armed = false }
        else if !tracking { armed = true }
        tracking = true
        return false
    }
}
