import AppKit
@testable import BetterShot

/// Opt-in: drives the real macOS selector against a disposable, solid-color window.
@main
struct WindowCaptureIntegration {
    @MainActor static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        precondition(CGPreflightScreenCaptureAccess() && AXIsProcessTrusted(),
                     "Interactive checks require existing Screen Recording and Accessibility permission")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do {
                try await checkCapture()
                exit(0)
            } catch {
                print("FAIL window capture: \(error)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor static func checkCapture() async throws {
        AppPreferences.openEditorAfterCapture = false
        AppPreferences.copyAfterSave = false
        AppPreferences.playSound = false
        AppPreferences.selfTimerDelay = .off
        UserDefaults.standard.set(false, forKey: "afterCapture.screenshot.save")
        UserDefaults.standard.set("", forKey: BetterShotPreferences.recordingCameraDeviceIDKey)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "BetterShot window capture check"
        window.backgroundColor = .systemBlue
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            PreviewOverlay.shared.dismiss()
            RecordingBarPresenter.shared.hide()
            window.close()
            try? FileManager.default.removeItem(at: ScreenshotHistoryStore.applicationSupportDirectory)
        }
        for mode in ["normal", "notch"] {
            UserDefaults.standard.set(mode, forKey: AppPreferences.presentationModeKey)
            NotchPresenter.shared.refreshMode()
            RecordingBarPresenter.shared.showPicker(activate: false)
            NotchPresenter.shared.window?.ignoresMouseEvents = true
            for cancel in [false, true] {
                let previous = CaptureOrchestrator.shared.lastCaptureURL
                let selection = Task { @MainActor in
                    try await Task.sleep(for: .seconds(2))
                    if cancel {
                        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
                    } else {
                        let point = CGPoint(x: window.frame.midX,
                                            y: NSScreen.screens[0].frame.maxY - window.frame.midY)
                        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        try await Task.sleep(for: .milliseconds(300))
                        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    }
                }
                await CaptureOrchestrator.shared.performCapture(.window, on: window.screen)
                selection.cancel()
                precondition(!ScreenCapture.shared.isCapturing && !NotchPresenter.shared.captureSuspended)
                if cancel {
                    precondition(CaptureOrchestrator.shared.lastCaptureURL == previous)
                    precondition(PreviewOverlay.shared.items.isEmpty)
                } else {
                    guard let result = CaptureOrchestrator.shared.lastCaptureURL else {
                        preconditionFailure("Window selection must produce a screenshot")
                    }
                    precondition(result != previous && NSImage(contentsOf: result) != nil)
                    precondition(PreviewOverlay.shared.isPresented && PreviewOverlay.shared.items.contains(result))
                    if mode == "notch" {
                        precondition(NotchPresenter.shared.isVisible && NotchPresenter.shared.expanded)
                    }
                    PreviewOverlay.shared.dismiss()
                }
                print("PASS \(mode) window \(cancel ? "cancellation" : "capture and preview")")
            }
        }
    }
}
