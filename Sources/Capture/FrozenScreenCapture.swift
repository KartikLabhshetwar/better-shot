import AppKit
import ScreenCaptureKit

@MainActor
enum FrozenScreenCapture {
    /// Capture before any selector windows become key, preserving transient content.
    static func capture() async throws -> [CGDirectDisplayID: FrozenScreenFrame] {
        let screens = NSScreen.screens
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedIDs = Set(NSApp.windows.filter { $0.sharingType == .none && $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) })
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
        var frames: [CGDirectDisplayID: FrozenScreenFrame] = [:]
        for screen in screens {
            guard let id = ActiveDisplayResolver.displayID(for: screen),
                  let display = content.displays.first(where: { $0.displayID == id }) else {
                throw NSError(domain: "BetterShot.FrozenScreenCapture", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "A display is no longer available. Try capturing again."
                ])
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            frames[id] = FrozenScreenFrame(displayID: id, pointsRect: display.frame, image: image)
        }
        try Task.checkCancellation()
        return frames
    }
}
