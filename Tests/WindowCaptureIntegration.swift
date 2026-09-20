import AppKit
import ScreenCaptureKit
@testable import BetterShot

/// Opt-in: validates the production window screenshot and preview pipeline.
/// The native picker and Escape must also be checked in the signed app: macOS
/// attributes standalone test executables to their terminal's capture identity.
@main
struct WindowCaptureIntegration {
    @MainActor static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        precondition(CGPreflightScreenCaptureAccess(), "Requires existing Screen Recording permission")
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
        UserDefaults.standard.set(false, forKey: "afterCapture.screenshot.save")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "BetterShot window capture check"
        window.backgroundColor = .systemBlue
        window.orderFrontRegardless()
        defer {
            PreviewOverlay.shared.dismiss()
            RecordingBarPresenter.shared.hide()
            window.close()
            try? FileManager.default.removeItem(at: ScreenshotHistoryStore.applicationSupportDirectory)
        }
        if ProcessInfo.processInfo.environment["BETTERSHOT_CHECK_CONTROL_ONLY"] != "1" {
            let sources = RecordingSourceCatalog.shared
            await sources.refresh()
            precondition(sources.errorMessage == nil)
            for display in sources.displays {
                precondition(sources.containsSelection(.fullscreen, displayID: display.displayID, windowID: nil))
            }
            for source in sources.windows {
                precondition(sources.containsSelection(.window, displayID: nil, windowID: source.windowID))
            }
            precondition(!sources.containsSelection(.window, displayID: nil, windowID: .max))
            precondition(!sources.containsSelection(.fullscreen, displayID: .max, windowID: nil))
            precondition(sources.containsSelection(.area, displayID: nil, windowID: nil) == !sources.displays.isEmpty)
            print("PASS recording source availability and missing-source rejection")
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let selected = content.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
            let filter = SCContentFilter(desktopIndependentWindow: selected)
            for mode in ["normal", "notch"] {
                UserDefaults.standard.set(mode, forKey: AppPreferences.presentationModeKey)
                NotchPresenter.shared.refreshMode()
                NotchPresenter.shared.suspendForCapture()
                let url = try await ScreenCapture.shared.windowShot(filter: filter)
                let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
                precondition(bitmap.pixelsWide == Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
                precondition(bitmap.pixelsHigh == Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
                let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
                precondition(center.blueComponent > center.redComponent + 0.3 && center.alphaComponent > 0.99,
                             "Selected window pixels must survive capture, without background windows or picker chrome")
                await CaptureOrchestrator.shared.processCapturedImage(url, action: .window)
                NotchPresenter.shared.resumeAfterCapture()
                let result = CaptureOrchestrator.shared.lastCaptureURL!
                precondition(PreviewOverlay.shared.items.contains(result) && NSImage(contentsOf: result) != nil)
                if mode == "notch" { precondition(NotchPresenter.shared.isVisible && NotchPresenter.shared.expanded) }
                PreviewOverlay.shared.dismiss()
                print("PASS \(mode) ScreenCaptureKit window pixels, native resolution, private staging, and preview")
            }
        }
        if ProcessInfo.processInfo.environment["BETTERSHOT_CHECK_CONTROL_CAPTURE"] == "1" {
            UserDefaults.standard.set("notch", forKey: AppPreferences.presentationModeKey)
            UserDefaults.standard.set(true, forKey: NotchVoiceCapture.controlKey)
            UserDefaults.standard.set(0, forKey: "bs_selfTimerDelay")
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            AppPreferences.lastRegionRect = CGRect(x: 230, y: 230, width: 160, height: 100)
            if let baseline = try await ScreenCapture.shared.captureLastRegion() {
                defer { try? FileManager.default.removeItem(at: baseline) }
                let bitmap = NSBitmapImageRep(data: try Data(contentsOf: baseline))!
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
                guard color.blueComponent > color.redComponent + 0.3 else {
                    throw NSError(domain: "BetterShot.ControlCaptureTest", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The test window is not visible to display capture. Unlock the Mac, dismiss the screen saver, and retry the live check."])
                }
            }
            let before = CaptureOrchestrator.shared.lastCaptureURL
            let gesture = NotchVoiceCapture.shared
            let top = CGDisplayBounds(CGMainDisplayID()).height
            func send(_ type: CGEventType, x: CGFloat, y: CGFloat, flags: CGEventFlags = .maskControl) -> Bool {
                let event = CGEvent(source: nil)!
                event.type = type
                event.flags = flags
                event.location = CGPoint(x: x, y: top - y)
                return gesture.handleControlEvent(type: type, event: event)
            }
            _ = send(.flagsChanged, x: 230, y: 230)
            precondition(gesture.controlGesture.armed)
            precondition(send(.leftMouseDown, x: 230, y: 230))
            precondition(send(.leftMouseDragged, x: 390, y: 330))
            precondition(send(.leftMouseUp, x: 390, y: 330))
            _ = send(.flagsChanged, x: 390, y: 330, flags: [])
            for _ in 0..<60 {
                if CaptureOrchestrator.shared.lastCaptureURL != before { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let result = CaptureOrchestrator.shared.lastCaptureURL, result != before else {
                preconditionFailure("Control drag did not deliver a screenshot")
            }
            let raw = DeckStaging.isStaged(result) ? DeckStaging.rawURL(for: result) : CaptureOrchestrator.resolveRawSource(for: result)
            let bitmap = NSBitmapImageRep(data: try Data(contentsOf: raw))!
            let scale = window.screen!.backingScaleFactor
            precondition(bitmap.pixelsWide == Int(160 * scale) && bitmap.pixelsHigh == Int(100 * scale))
            let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
            precondition(center.blueComponent > center.redComponent + 0.3, "Selection chrome must be absent from the capture")
            precondition(PreviewOverlay.shared.items.contains(result))
            print("PASS Control-drag event handling, selected pixels, native dimensions, private staging, and shelf delivery")
        }
    }
}
