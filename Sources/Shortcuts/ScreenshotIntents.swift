import AppIntents
import UniformTypeIdentifiers

/// Shared plumbing for the screenshot intents below: run a capture through the
/// orchestrator (same pipeline as the keyboard shortcuts) and hand back the saved
/// (beautified) image as an `IntentFile` the Shortcuts app can chain into other actions.
@MainActor
private func performScreenshotIntent(_ action: ShortcutService.Action) async throws -> IntentFile {
    guard case let .image(url) = await CaptureOrchestrator.shared.performCapture(action) else {
        throw BetterShotIntentError.captureFailed
    }

    let data = try Data(contentsOf: url)
    let type = UTType(filenameExtension: url.pathExtension) ?? .png
    return IntentFile(data: data, filename: url.lastPathComponent, type: type)
}

struct RegionScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Region Screenshot"
    static var description = IntentDescription(
        "Lets you draw a region and captures it with your default BetterShot effects applied."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let file = try await performScreenshotIntent(.region)
        return .result(value: file)
    }
}

struct FullscreenScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Fullscreen Screenshot"
    static var description = IntentDescription(
        "Captures the entire screen with your default BetterShot effects applied."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let file = try await performScreenshotIntent(.fullscreen)
        return .result(value: file)
    }
}

struct WindowScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Window Screenshot"
    static var description = IntentDescription(
        "Lets you pick a window and captures it with your default BetterShot effects applied."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let file = try await performScreenshotIntent(.window)
        return .result(value: file)
    }
}
