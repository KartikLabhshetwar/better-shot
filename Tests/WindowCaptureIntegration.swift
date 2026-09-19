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
}
