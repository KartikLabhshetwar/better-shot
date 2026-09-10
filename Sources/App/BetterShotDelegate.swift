import AppKit
import UserNotifications
import TipKit

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var pendingURLActions: [CaptureURLAction] = []

    /// The notification delegate has to be in place before launch finishes,
    /// or the system handles clicks on export notifications itself and never
    /// calls back to reveal the file.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = RecordingExportNotificationDelegate.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        DeckStaging.purge()
        AppPreferences.migrateEditorPreferences()
        AppPreferences.applyAppearance()
        AppActivationPolicy.applyVisibility()
        RecordingRecoveryCoordinator.recoverInterruptedRecordings()
        do {
            try Tips.configure([.displayFrequency(.daily)])
        } catch {
            print("BetterShot: Contextual tips unavailable: \(error.localizedDescription)")
        }
        // Present after launch setup; never put permission prompts in the launch path.
        DispatchQueue.main.async {
            if OnboardingState.shouldPresent() {
                OnboardingWindowController.shared.show()
            } else {
                RecordingBarPresenter.shared.showPicker(activate: false)
            }
        }

        Task {
            await AppUpdater.shared.checkForUpdatesQuietly()
        }

        if ShortcutService.hasAccessibilityPermission {
            ShortcutService.shared.registerAll()

            if !ShortcutService.shared.isRegistered {
                Self.promptRestart()
            }
        }
        didFinishLaunching = true
        performPendingURLActions()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLActions.append(contentsOf: urls.compactMap(CaptureURLAction.init(url:)))
        if didFinishLaunching { performPendingURLActions() }
    }

    private func performPendingURLActions() {
        let actions = pendingURLActions
        pendingURLActions.removeAll()
        guard !actions.isEmpty else { return }
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: true)
        Task {
            for action in actions {
                switch action {
                case .region:
                    await CaptureOrchestrator.shared.performCapture(.region, on: screen)
                case .fullscreen:
                    await CaptureOrchestrator.shared.performCapture(.fullscreen, on: screen)
                case .window:
                    await CaptureOrchestrator.shared.performCapture(.window, on: screen)
                case .ocr:
                    await CaptureOrchestrator.shared.performCapture(.ocr, on: screen)
                case .colorPicker:
                    await CaptureOrchestrator.shared.performCapture(.colorPicker, on: screen)
                case .recording:
                    guard !ScreenRecordingManager.shared.isActive else { continue }
                    RecordingBarPresenter.shared.showPicker(on: screen.flatMap { ActiveDisplayResolver.displayID(for: $0) })
                case .settings:
                    SettingsWindowController.shared.open(on: screen)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutService.shared.unregisterAll()
    }

    /// Quitting mid-recording finishes and saves the recording first, and
    /// Studio's debounced autosave is flushed so no edit is lost.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        StudioProjectRegistry.shared.flushDrafts()
        guard ScreenRecordingManager.shared.isActive else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A screen recording is still in progress"
        alert.informativeText = "BetterShot will finish and save the recording before quitting. This can take a moment for a long recording."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Finish Recording and Quit")

        guard alert.runModal() == .alertSecondButtonReturn else {
            return .terminateCancel
        }

        ScreenRecordingManager.shared.finishForTermination { session in
            Task { @MainActor in
                if let session {
                    _ = await ScreenshotHistoryStore.shared.importRecordingSession(session)
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            RecordingBarPresenter.shared.showPicker()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        if ShortcutService.hasAccessibilityPermission {
            if !ShortcutService.shared.isRegistered { ShortcutService.shared.registerAll() }
        } else {
            ShortcutService.shared.unregisterAll()
        }
    }

    private static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "BetterShot needs to restart to activate keyboard shortcut overrides. Restart now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "sleep 0.5; open \"$0\"", Bundle.main.bundlePath]
            try? task.run()
            NSApp.terminate(nil)
        }
    }
}
