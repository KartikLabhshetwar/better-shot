import AppKit
@testable import BetterShot

@main
struct CompositionPreview {
    @MainActor static func main() {
        setenv("BETTERSHOT_TESTING", "1", 1)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Resources/Onboarding/screenshot-demo.png")
        ScreenshotCompositionWindowController.shared.open(images: [fixture, fixture])
        app.run()
    }
}
