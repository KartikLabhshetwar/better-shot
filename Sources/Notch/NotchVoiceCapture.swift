import AppKit
import AVFoundation
import Observation

@MainActor @Observable
final class NotchVoiceCapture {
    static let shared = NotchVoiceCapture()
    static let gestureKey = "bs_notchHoldOption"
    private(set) var isPreparing = false
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
        guard UserDefaults.standard.bool(forKey: Self.gestureKey),
              ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        // Observe modifier state only; never retain characters or ordinary typing.
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
    }

    private func handle(_ event: NSEvent) {
        let optionOnly = event.modifierFlags.intersection([.option, .command, .control, .shift]) == .option
        if event.type == .keyDown {
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

    func capture(whileHolding: Bool = false) async {
        guard !isPreparing, !ScreenCapture.shared.isCapturing, !CaptureOrchestrator.shared.captureInProgress,
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
