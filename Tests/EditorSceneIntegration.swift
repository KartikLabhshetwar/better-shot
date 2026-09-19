import AppKit
import SwiftUI
@testable import BetterShot

/// NSHostingController windows do not apply SwiftUI's scene behavior after attachment.
@main
struct EditorSceneIntegration: App {
    @Environment(\.openWindow) private var openWindow
    private static var started = false

    init() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        setbuf(stdout, nil)
        UserDefaults.standard.set(CommandLine.arguments[2] == "1", forKey: AppPreferences.editorOpensFullScreenKey)
        UserDefaults.standard.set(false, forKey: AppPreferences.showInDockKey)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        let _ = start()
        WindowGroup("Editor scene check", id: "editor", for: String.self) { kind in
            Group {
                if kind.wrappedValue == "video" {
                    RecordingStudioWindow(url: .constant(fixture("recording-demo.mp4")))
                } else {
                    AnnotationEditorWindow(url: .constant(fixture("screenshot-demo.png")))
                }
            }
            .onWindowChange { window in
                guard let window else { return }
                let events = FullScreenEvents(window: window)
                Task { @MainActor in
                    defer { NotificationCenter.default.removeObserver(events) }
                    let automatic = AppPreferences.editorOpensFullScreen
                    await waitUntil {
                        window.isKeyWindow && NSApp.isActive && (!automatic || events.entered)
                    }
                    precondition(window.collectionBehavior.contains(.fullScreenPrimary))
                    precondition(!window.collectionBehavior.contains(.fullScreenNone),
                                 "SwiftUI must not disable full screen after view attachment")
                    precondition(window.styleMask.contains(.fullScreen) == automatic,
                                 "The actual editor scene must honor automatic full screen")
                    if !automatic {
                        window.toggleFullScreen(nil)
                        await waitUntil { events.entered }
                        precondition(window.styleMask.contains(.fullScreen), "Manual full screen must work")
                    }
                    window.toggleFullScreen(nil)
                    await waitUntil { events.exited }
                    precondition(!window.styleMask.contains(.fullScreen), "Full screen must exit")
                    try await Task.sleep(for: .seconds(1))
                    precondition(!window.styleMask.contains(.fullScreen), "Updates must not re-enter full screen")
                    print("PASS SwiftUI \(CommandLine.arguments[1]) scene, automatic=\(automatic), focus and full-screen entry/exit")
                    exit(0)
                }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 760)
        .defaultLaunchBehavior(.suppressed)
    }

    private func start() {
        guard !Self.started else { return }
        Self.started = true
        DispatchQueue.main.async { openWindow(id: "editor", value: CommandLine.arguments[1]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            preconditionFailure("Editor scene check timed out")
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<150 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        preconditionFailure("Editor activation/full-screen transition did not complete")
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Onboarding/" + name)
    }
}

@MainActor
private final class FullScreenEvents: NSObject {
    var entered = false
    var exited = false

    init(window: NSWindow) {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didEnter),
            name: NSWindow.didEnterFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(didExit),
            name: NSWindow.didExitFullScreenNotification, object: window)
    }

    @objc private func didEnter() { entered = true }
    @objc private func didExit() { exited = true }
}
