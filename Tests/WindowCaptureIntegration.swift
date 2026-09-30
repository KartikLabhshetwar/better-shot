import AppKit
@testable import BetterShot

/// Opt-in interactive check: select the fixture window, then press Escape on the next picker.
@main
struct WindowCaptureIntegration {
    @MainActor static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        setbuf(stdout, nil)
        precondition(CGPreflightScreenCaptureAccess(), "Requires existing Screen Recording permission")
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await checkCapture(); exit(0) }
            catch { print("FAIL native window capture: \(error)"); exit(1) }
        }
        NSApplication.shared.run()
    }

    @MainActor static func checkCapture() async throws {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "BetterShot window capture check"
        window.backgroundColor = .systemBlue
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            PreviewOverlay.shared.clearAll()
            window.close()
            try? FileManager.default.removeItem(at: ScreenshotHistoryStore.applicationSupportDirectory)
        }
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
        print("Select the blue BetterShot window capture check window in the native picker.")
        guard let url = try await ScreenCapture.shared.captureWindow() else { preconditionFailure("Native window selection cancelled") }
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
        let scale = window.screen!.backingScaleFactor
        precondition(bitmap.pixelsWide == Int(window.frame.width * scale), "Select the fixture window; expected width \(window.frame.width * scale), got \(bitmap.pixelsWide)")
        precondition(bitmap.pixelsHigh == Int(window.frame.height * scale), "Window capture must preserve native pixel height")
        let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
        precondition(center.blueComponent > center.redComponent + 0.3 && center.alphaComponent > 0.99)
        AppPreferences.openEditorAfterCapture = false
        AppPreferences.copyAfterSave = false
        UserDefaults.standard.set(false, forKey: "afterCapture.screenshot.save")
        await CaptureOrchestrator.shared.processCapturedImage(url, action: .window)
        precondition(PreviewOverlay.shared.items.contains(CaptureOrchestrator.shared.lastCaptureURL!))
        print("Press Escape to cancel the second native picker.")
        let cancelled = try await ScreenCapture.shared.captureWindow()
        precondition(cancelled == nil && !ScreenCapture.shared.isCapturing)
        print("PASS native window pixels, resolution, private staging, preview, and Escape cancellation")
    }
}
