import AppIntents

/// Surfaces BetterShot's capture, OCR, and recording actions to the Shortcuts app,
/// Spotlight, and Siri. The system discovers this provider automatically once the
/// app has launched — no Info.plist or entitlement changes are required.
struct BetterShotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegionScreenshotIntent(),
            phrases: [
                "Capture a region screenshot with \(.applicationName)",
                "Take a region screenshot in \(.applicationName)"
            ],
            shortTitle: "Region Screenshot",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: FullscreenScreenshotIntent(),
            phrases: [
                "Capture a fullscreen screenshot with \(.applicationName)",
                "Take a fullscreen screenshot in \(.applicationName)"
            ],
            shortTitle: "Fullscreen Screenshot",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: WindowScreenshotIntent(),
            phrases: [
                "Capture a window screenshot with \(.applicationName)",
                "Take a window screenshot in \(.applicationName)"
            ],
            shortTitle: "Window Screenshot",
            systemImageName: "macwindow.on.rectangle"
        )
        AppShortcut(
            intent: ScanTextIntent(),
            phrases: [
                "Scan text with \(.applicationName)",
                "Extract text from screen with \(.applicationName)"
            ],
            shortTitle: "Scan Text",
            systemImageName: "doc.text.viewfinder"
        )
        AppShortcut(
            intent: StartScreenRecordingIntent(),
            phrases: [
                "Start a screen recording with \(.applicationName)",
                "Start recording my screen with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopScreenRecordingIntent(),
            phrases: [
                "Stop the screen recording in \(.applicationName)",
                "Stop recording my screen with \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
    }
}
