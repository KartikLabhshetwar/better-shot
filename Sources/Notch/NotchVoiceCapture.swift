import AppKit
import AVFoundation
import Observation

@MainActor @Observable
final class NotchVoiceCapture {
    static let shared = NotchVoiceCapture()
    static let gestureKey = "bs_notchHoldOption"
    static let controlKey = "bs_notchControlCapture"
    static let actionKey = "bs_notchHoldAction"
    static var drawsOnHold: Bool { UserDefaults.standard.string(forKey: actionKey) != "area" }
    private(set) var drawingSession = false
    private var drawTask: Task<Void, Never>?
    private var drawingPointerDown = false
    private var pendingStroke: [(CGEventType, CGPoint)] = []
    var holdIndicatorActive: Bool { controlGesture.armed || holdActive || drawingSession }
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
        drawTask?.cancel()
        pendingStroke.removeAll()
        drawingSession = false
        drawingPointerDown = false
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
        let mouseEvent = [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(type)
        if mouseEvent, drawingSession || (!pendingStroke.isEmpty) ||
            (type == .leftMouseDown && Self.drawsOnHold && controlGesture.armed && (drawTask != nil || isPreparing)) {
            if type == .leftMouseDown { drawingPointerDown = true; swallowMouseUp = true }
            if type == .leftMouseUp { drawingPointerDown = false; swallowMouseUp = false }
            if drawingSession {
                drawStrokeEvent(type, at: Self.appKitPoint(event.location))
                if !controlGesture.armed && !drawingPointerDown { finishDrawing() }
            } else {
                pendingStroke.append((type, Self.appKitPoint(event.location)))
            }
            return true
        }
        if drawingSession {
            if !NotchQuickEditor.shared.isOpen {
                drawingSession = false
                drawingPointerDown = false
            } else {
                if type == .flagsChanged {
                    _ = controlGesture.update(flags: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                        modifierChanged: true, holdKey: Self.captureHoldKey)
                }
                if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                    drawingSession = false
                    controlGesture = NotchControlGesture()
                    return false // The editor offers its normal discard confirmation.
                }
                if !controlGesture.armed && !drawingPointerDown { finishDrawing() }
                return false
            }
        }
        if type == .leftMouseUp && swallowMouseUp {
            drawingPointerDown = false
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
        if !Self.drawsOnHold && type == .leftMouseDown && controlGesture.armed {
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
        if Self.drawsOnHold && type == .leftMouseDragged {
            // A drag that began in another app stays with that app.
            drawTask?.cancel()
            controlGesture = NotchControlGesture()
        }
        if type == .flagsChanged || type == .keyDown || type == .rightMouseDown {
            let wasArmed = controlGesture.armed
            _ = controlGesture.update(flags: flags, modifierChanged: type == .flagsChanged, holdKey: Self.captureHoldKey)
            if !controlGesture.armed { drawTask?.cancel(); pendingStroke.removeAll() }
            if Self.drawsOnHold && controlGesture.armed && !wasArmed,
               !NotchQuickEditor.shared.isOpen, !ScreenRecordingManager.shared.isActive,
               !CaptureOrchestrator.shared.captureInProgress, !ScreenCapture.shared.isCapturing {
                drawTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    guard let self, self.controlGesture.armed else { return }
                    await self.capture(whileHolding: true, includeVoice: false)
                    self.drawTask = nil
                    self.pendingStroke.removeAll()
                }
            }
        }
        return false
    }

    func beginDrawingSession() {
        guard NotchQuickEditor.shared.isOpen else { return }
        drawingSession = true
        for (type, point) in pendingStroke { drawStrokeEvent(type, at: point) }
        pendingStroke.removeAll()
    }

    private func finishDrawing() {
        drawingSession = false
        Task { await NotchQuickEditor.shared.finish() }
    }

    private func drawStrokeEvent(_ type: CGEventType, at point: CGPoint) {
        let editor = NotchQuickEditor.shared
        guard let panel = editor.panel else { return }
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        let frame = editor.model.displayCanvasFrame(in: panel.frame.size)
        switch type {
        case .leftMouseDown:
            editor.model.beginInteraction(at: local, imageFrame: frame, boundaryFrame: frame)
        case .leftMouseDragged:
            editor.model.updateInteraction(to: local, imageFrame: frame, boundaryFrame: frame)
        case .leftMouseUp:
            editor.model.endInteraction(at: local, imageFrame: frame, boundaryFrame: frame)
        default: break
        }
    }

    private static func appKitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }

    func capture(whileHolding: Bool = false, includeVoice: Bool = true) async {
        guard AppPreferences.presentationMode == .notch, !isPreparing, !ScreenCapture.shared.isCapturing, !CaptureOrchestrator.shared.captureInProgress,
              !ScreenRecordingManager.shared.isActive, !NotchQuickEditor.shared.isOpen else { return }
        isPreparing = true
        defer { isPreparing = false }
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        let notch = NotchPresenter.shared
        if includeVoice, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            notch.captureIssue = ("Microphone access needed", "Allow BetterShot in System Settings → Privacy & Security → Microphone, then try Voice again.")
            notch.show(on: screen)
            return
        }
        guard !whileHolding || (includeVoice ? holdActive : controlGesture.armed) else { return }
        notch.suspendForCapture()
        defer { notch.resumeAfterCapture() }
        await RecordingBarPresenter.shared.hidePickerForCapture()
        do {
            guard let url = try await ScreenCapture.shared.captureFullscreen(on: screen) else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            guard !whileHolding || (includeVoice ? holdActive : controlGesture.armed) else { return }
            ScreenCapture.shared.playShutterSound()
            let retained = ScreenshotHistoryStore.shared.importScreenshot(from: url)
            guard retained != url else { throw CocoaError(.fileWriteUnknown) }
            PreviewOverlay.shared.show(url: retained, on: screen, automaticallyDismiss: false)
            NotchQuickEditor.shared.open(retained, on: screen, fullScreen: whileHolding)
            gestureSession = whileHolding && includeVoice
            if whileHolding && !includeVoice { beginDrawingSession() }
            if includeVoice { await NotchQuickEditor.shared.startVoice() }
            if whileHolding && !(includeVoice ? holdActive : controlGesture.armed) {
                gestureSession = false
                Task { await NotchQuickEditor.shared.finish() }
            }
        } catch {
            notch.captureIssue = (includeVoice ? "Couldn’t start voice capture" : "Couldn’t start annotation", error.localizedDescription)
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
