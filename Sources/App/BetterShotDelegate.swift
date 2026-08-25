import AppKit

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.applyAppearance()
        NSApp.setActivationPolicy(.accessory)

        MenuBarPopoverController.shared.setup()

        Task {
            await AppUpdater.shared.checkForUpdatesQuietly()
        }

        if ShortcutService.hasAccessibilityPermission {
            ShortcutService.shared.registerAll()

            if !ShortcutService.shared.isRegistered {
                Self.promptRestart()
            }
        } else {
            ShortcutService.requestAccessibilityPermission()
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPollTimer?.invalidate()
        ShortcutService.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func startPermissionPolling() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard ShortcutService.hasAccessibilityPermission else { return }
            timer.invalidate()

            DispatchQueue.main.async {
                self?.permissionPollTimer = nil
                ShortcutService.shared.registerAll()

                if !ShortcutService.shared.isRegistered {
                    Self.promptRestart()
                }
            }
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

/// Single owner of the Dock/menu-bar policy. Each window controller used to decide alone while checking only some of the others, so closing one window could demote the app while another was still on screen.
@MainActor
enum ActivationPolicy {
    static func dropIfNoWindowsLeft() {
        Task { @MainActor in
            guard !EditorWindowController.shared.hasOpenWindows,
                  !VideoEditorWindowController.shared.hasOpenWindow,
                  !SettingsWindowController.shared.hasOpenWindow else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
